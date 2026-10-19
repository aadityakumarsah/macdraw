import AppKit
import CryptoKit
import Foundation

/// Where macdraw keeps everything the user must never lose.
///
/// Everything lives in `~/Library/Application Support/MacDraw`, which is
/// *outside* the app bundle: deleting macdraw.app — or replacing it with a
/// new download — leaves every page, every image and every preference exactly
/// where it was. Drawings disappear only when the user deletes them from
/// inside the app (or wipes the folder by hand).
enum AppStorage {
    /// Root of the on-disk store. `MACDRAW_DATA_DIR` overrides it, which is
    /// how `--selftest` runs against a throwaway folder instead of trampling
    /// real drawings.
    static let root: URL = {
        let fm = FileManager.default
        if let override = ProcessInfo.processInfo.environment["MACDRAW_DATA_DIR"],
           !override.isEmpty {
            let u = URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
            try? fm.createDirectory(at: u, withIntermediateDirectories: true)
            return u
        }
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent("MacDraw", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// A subdirectory of the store, created on first use.
    static func directory(_ name: String) -> URL {
        let dir = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func file(_ name: String) -> URL {
        root.appendingPathComponent(name)
    }

    /// Serial queue every disk write runs on. The main thread hands over a
    /// `Data` and returns immediately, so a save never shows up as a dropped
    /// frame no matter how large the drawing is.
    static let io = DispatchQueue(label: "com.local.macdraw.io", qos: .utility)

    /// Replaces a file in one step (write to a sibling, then rename), so a
    /// crash or a force-quit mid-write can never truncate a drawing.
    static func writeAtomically(_ data: Data, to url: URL) {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            // .atomic needs a writable parent; recreate it and retry once.
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Writes off the main thread. `completion` runs on the io queue.
    static func writeAsync(_ data: Data, to url: URL, completion: (() -> Void)? = nil) {
        io.async {
            writeAtomically(data, to: url)
            completion?()
        }
    }
}

/// Opt-in diagnostics. Off unless the app is launched with `--selftest` or
/// `MACDRAW_DEBUG=1`, so a normal run prints nothing.
enum Diag {
    static let enabled: Bool = {
        ProcessInfo.processInfo.environment["MACDRAW_DEBUG"] == "1"
            || CommandLine.arguments.contains("--selftest")
    }()

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        print("[diag] \(message())")
    }
}

/// Content-addressed store for the binary blobs a drawing references — today
/// images, tomorrow anything else heavy.
///
/// This is the reason a page with a gigabyte of screenshots stays as cheap to
/// edit as an empty one. Previously every image was re-encoded to PNG and
/// base64'd into the page JSON on *every* autosave, and all of it stayed
/// resident in RAM; now each image is written once under the hash of its
/// bytes, the page JSON carries only that id, and decoded bitmaps live in a
/// bounded cache that evicts the least recently drawn.
final class FileStore {
    static let shared = FileStore()

    private let dir: URL
    private let lock = NSLock()

    /// Decoded bitmaps, most recently drawn last. Bounded by pixel budget,
    /// *not* by count: one 8000×6000 photo costs as much as 48 thumbnails.
    private var cache: [String: NSImage] = [:]
    private var order: [String] = []
    private var bytes = 0
    /// ~256 MB of decoded pixels. Everything above this is re-read from disk
    /// the next time it scrolls into view.
    private let budget = 256 * 1024 * 1024

    /// Ids currently being read from disk, so a redraw storm can't queue the
    /// same decode a hundred times.
    private var loading = Set<String>()

    private init() {
        dir = AppStorage.directory("files")
    }

    // MARK: - writing

    /// Stores `data` under the hex SHA-256 of its bytes and returns the id.
    /// Storing the same bytes twice is free and yields the same id, so
    /// duplicating or re-pasting an image never duplicates the file.
    @discardableResult
    func store(data: Data, ext: String) -> String {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let id = "\(digest).\(ext)"
        let url = dir.appendingPathComponent(id)
        if !FileManager.default.fileExists(atPath: url.path) {
            AppStorage.writeAsync(data, to: url)
        }
        return id
    }

    /// Encodes an image once (PNG) and stores it. Returns its id.
    func store(image: NSImage) -> String? {
        guard let data = FileStore.pngData(of: image) else { return nil }
        let id = store(data: data, ext: "png")
        // Seed the cache so the image the user just placed draws from memory
        // instead of waiting for the write to land.
        remember(id, image: image)
        return id
    }

    static func pngData(of image: NSImage) -> Data? {
        if let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - reading

    func data(for id: String) -> Data? {
        try? Data(contentsOf: dir.appendingPathComponent(id))
    }

    /// The decoded image for `id` if it is already in memory.
    ///
    /// Returns nil the first time, and reads the file on the io queue —
    /// calling `onReady` back on the main thread once it can be drawn. The
    /// canvas paints a placeholder for that one frame rather than blocking
    /// the main thread on a multi-megabyte decode, which is what kept image
    /// -heavy pages from opening instantly.
    func image(for id: String, onReady: (() -> Void)? = nil) -> NSImage? {
        lock.lock()
        if let hit = cache[id] {
            touch(id)
            lock.unlock()
            return hit
        }
        if loading.contains(id) {
            lock.unlock()
            return nil
        }
        loading.insert(id)
        lock.unlock()

        let url = dir.appendingPathComponent(id)
        AppStorage.io.async { [weak self] in
            guard let self else { return }
            let img = NSImage(contentsOf: url)
            // Force the decode here, on the io queue, instead of lazily on
            // the main thread at first draw.
            if let img { _ = img.representations.first?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
            self.lock.lock()
            self.loading.remove(id)
            if let img { self.rememberLocked(id, image: img) }
            self.lock.unlock()
            if img != nil, let onReady {
                DispatchQueue.main.async(execute: onReady)
            }
        }
        return nil
    }

    /// Synchronous read — used by export/clipboard paths that must have the
    /// pixels right now and are already off the drawing hot path.
    func imageNow(for id: String) -> NSImage? {
        if let hit = image(for: id) { return hit }
        guard let img = NSImage(contentsOf: dir.appendingPathComponent(id)) else { return nil }
        remember(id, image: img)
        return img
    }

    func remember(_ id: String, image: NSImage) {
        lock.lock()
        rememberLocked(id, image: image)
        lock.unlock()
    }

    private func rememberLocked(_ id: String, image: NSImage) {
        if cache[id] == nil {
            bytes += FileStore.footprint(of: image)
            order.append(id)
        }
        cache[id] = image
        evictLocked()
    }

    private func touch(_ id: String) {
        if let i = order.firstIndex(of: id) {
            order.remove(at: i)
            order.append(id)
        }
    }

    private func evictLocked() {
        while bytes > budget, order.count > 1 {
            let id = order.removeFirst()
            if let img = cache.removeValue(forKey: id) {
                bytes -= FileStore.footprint(of: img)
            }
        }
    }

    /// Decoded size in bytes (4 bytes per pixel), not the file size.
    private static func footprint(of image: NSImage) -> Int {
        var px = 0
        for rep in image.representations {
            px = max(px, rep.pixelsWide * rep.pixelsHigh)
        }
        if px == 0 {
            px = Int(max(1, image.size.width) * max(1, image.size.height))
        }
        return px * 4
    }

    // MARK: - housekeeping

    /// Deletes stored blobs nothing references any more. Runs on the io queue
    /// and is safe to call at launch: ids still referenced by any page are
    /// passed in `keeping`.
    func collectGarbage(keeping keep: Set<String>) {
        AppStorage.io.async { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            let all = (try? fm.contentsOfDirectory(at: self.dir, includingPropertiesForKeys: nil)) ?? []
            for url in all where !keep.contains(url.lastPathComponent) {
                try? fm.removeItem(at: url)
            }
        }
    }

    /// Total bytes on disk — shown in the storage readout.
    func diskUsage() -> Int64 {
        let fm = FileManager.default
        let all = (try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        return all.reduce(0) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}
