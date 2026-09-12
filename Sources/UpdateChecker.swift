import AppKit
import Combine

/// The version this build reports. The GitHub release must be tagged
/// `v<appVersion>` (e.g. `v1.9.0`) for the update check to work.
let appVersion = "1.20.0"

/// The GitHub repository the update check talks to. Releases should attach a
/// `macdraw-v<version>.zip` (produced by build.sh) containing macdraw.app.
let updateRepo = "aadityakumarsah/macdraw"

/// Parses dotted version strings ("1.9", "v1.9.0", "1.9.0-beta") and compares
/// numerically: -1 when a < b, 0 when equal, 1 when a > b. Non-numeric
/// suffixes are ignored.
func compareVersions(_ a: String, _ b: String) -> Int {
    func parts(_ s: String) -> [Int] {
        s.split(separator: ".").compactMap { Int($0.prefix(while: { $0.isNumber })) }
    }
    let pa = parts(a), pb = parts(b)
    for i in 0..<max(pa.count, pb.count) {
        let x = i < pa.count ? pa[i] : 0
        let y = i < pb.count ? pb[i] : 0
        if x != y { return x < y ? -1 : 1 }
    }
    return 0
}

struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case assets
    }
}

/// Checks the GitHub releases feed for a newer version and, when the user
/// clicks update, downloads the release zip and swaps the app bundle in
/// place, then relaunches.
final class AppUpdater: NSObject, ObservableObject {
    @Published private(set) var checking = false
    @Published private(set) var latestVersion: String?
    @Published private(set) var releaseNotes: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var downloading = false
    @Published private(set) var downloadProgress: Double = 0
    private var assetURL: URL?
    private var downloadTask: URLSessionDownloadTask?
    /// Block-based KVO observations on the active download task. Replacing the
    /// task invalidates these automatically, so no observer is ever left
    /// registered on a deallocated object (deallocating a task while a legacy
    /// `addObserver` is still on it crashes the app).
    private var progressObservations: [NSKeyValueObservation] = []

    /// Called on the main thread just before the running bundle is swapped
    /// out for the update, so the app can hide its full-screen overlay and
    /// release its input monitors first.
    var onInstallStarting: (() -> Void)?

    /// True when a strictly newer version has been found.
    var isUpdateAvailable: Bool {
        guard let latest = latestVersion else { return false }
        return compareVersions(latest, appVersion) > 0
    }

    var latestLabel: String { latestVersion ?? appVersion }

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    func checkNow() {
        guard !checking else { return }
        checking = true
        errorMessage = nil
        let url = URL(string: "https://api.github.com/repos/\(updateRepo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("macdraw-update-check", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.checking = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                guard let data,
                      let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
                    self.errorMessage = "Could not read the update feed."
                    return
                }
                let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
                self.latestVersion = version
                self.releaseNotes = release.body
                self.assetURL = release.assets.first {
                    $0.name.lowercased().hasPrefix("macdraw") && $0.name.lowercased().hasSuffix(".zip")
                }.flatMap { URL(string: $0.browserDownloadURL) }
            }
        }.resume()
    }

    /// Downloads the latest release and installs it over the running app,
    /// then relaunches the new build.
    func downloadAndInstall() {
        guard !downloading, let url = assetURL else { return }
        downloading = true
        downloadProgress = 0
        downloadTask = session.downloadTask(with: url) { [weak self] tmpURL, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.downloading = false
                    self.errorMessage = "Download failed: \(error.localizedDescription)"
                    return
                }
                guard let tmpURL else {
                    self.downloading = false
                    self.errorMessage = "Download failed."
                    return
                }
                // Keep `downloading` set during install so the UI shows
                // "Updating…" until the app relaunches. Install runs OFF the
                // main thread (see install) — the overlay is a full-screen
                // panel that swallows every click, so blocking the main thread
                // here froze the entire Mac.
                self.install(zip: tmpURL)
            }
        }
        guard let task = downloadTask else { return }
        // Observe the download so the popover can show a progress bar.
        // Block-based KVO cleans itself up; never leave AddObserver KVO on a
        // task that gets released.
        progressObservations = [
            task.observe(\.countOfBytesReceived) { [weak self] task, _ in
                let expected = task.countOfBytesExpectedToReceive
                guard expected > 0 else { return }
                DispatchQueue.main.async {
                    self?.downloadProgress = min(1, Double(task.countOfBytesReceived) / Double(expected))
                }
            },
            task.observe(\.countOfBytesExpectedToReceive) { [weak self] task, _ in
                let received = task.countOfBytesReceived
                guard received > 0 else { return }
                DispatchQueue.main.async {
                    self?.downloadProgress = min(1, Double(received) / Double(task.countOfBytesExpectedToReceive))
                }
            },
        ]
        task.resume()
    }

    private func install(zip: URL) {
        // Everything below is file/process heavy and MUST NOT run on the main
        // thread: the overlay is a full-screen borderless panel that eats every
        // click, so blocking the main thread while this works froze the whole
        // Mac. Do it on a utility queue and hop back to main only to relaunch.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("macdraw-update-\(UUID().uuidString)")
            try? fm.createDirectory(at: work, withIntermediateDirectories: true)

            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzip.arguments = ["-x", "-k", zip.path, work.path]
            unzip.standardOutput = FileHandle.nullDevice
            unzip.standardError = FileHandle.nullDevice
            do {
                try unzip.run()
            } catch {
                DispatchQueue.main.async {
                    self.downloading = false
                    self.errorMessage = "Could not unzip the update: \(error.localizedDescription)"
                }
                return
            }
            // Watchdog: never block forever on a corrupt/hung ditto. Wait up to
            // 120s (generous for any real release zip), then kill it.
            let deadline = Date().addingTimeInterval(120)
            while unzip.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if unzip.isRunning {
                unzip.terminate()
                DispatchQueue.main.async {
                    self.downloading = false
                    self.errorMessage = "Unzipping the update timed out."
                }
                return
            }
            guard unzip.terminationStatus == 0,
                  let newApp = findApp(in: work) else {
                DispatchQueue.main.async {
                    self.downloading = false
                    self.errorMessage = "The downloaded package does not contain macdraw.app."
                }
                return
            }
            let current = Bundle.main.bundleURL

            // Hide the overlay + release input monitors before the swap, so no
            // invisible full-screen panel is left capturing input while the
            // bundle is replaced underneath a running process.
            DispatchQueue.main.sync {
                self.onInstallStarting?()
            }

            do {
                try replaceBundle(current: current, with: newApp)
            } catch {
                DispatchQueue.main.async {
                    self.downloading = false
                    self.errorMessage = "Could not install the update: \(error.localizedDescription)"
                }
                return
            }
            try? fm.removeItem(at: work)

            // Hand over to the new build. The helper below sleeps first so this
            // process has fully exited before `open` runs — otherwise Launch
            // Services sees a live instance with the same bundle id and the
            // update silently never relaunches.
            DispatchQueue.main.async {
                self.relaunchAfterExit(at: current)
            }
        }
    }

    /// Spawns a detached helper that waits for this process to die, then opens
    /// the freshly installed app, and terminates ourselves.
    private func relaunchAfterExit(at appURL: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let helper = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; \
        /usr/bin/open "\(appURL.path)"
        """
        let sh = Process()
        sh.executableURL = URL(fileURLWithPath: "/bin/bash")
        sh.arguments = ["-c", helper]
        sh.standardOutput = FileHandle.nullDevice
        sh.standardError = FileHandle.nullDevice
        try? sh.run()
        NSApp.terminate(nil)
    }

    /// Finds macdraw.app anywhere under the unzipped directory.
    private func findApp(in dir: URL) -> URL? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        for e in entries {
            if e.pathExtension == "app" && e.lastPathComponent.hasPrefix("macdraw") { return e }
            if e.hasDirectoryPath, let nested = findApp(in: e) { return nested }
        }
        return nil
    }

    /// Swaps the running app bundle for the new one. Renames the old bundle
    /// aside first (the running process keeps its file handles), moves the
    /// new one in, then relaunches — so an interrupted update always leaves a
    /// launchable copy behind.
    private func replaceBundle(current: URL, with newApp: URL) throws {
        let fm = FileManager.default
        let backup = current.deletingLastPathComponent()
            .appendingPathComponent("macdraw-old.app")
        try? fm.removeItem(at: backup)
        try fm.moveItem(at: current, to: backup)
        do {
            try fm.moveItem(at: newApp, to: current)
        } catch {
            // Roll the previous build back so the app is never left broken.
            try? fm.moveItem(at: backup, to: current)
            throw error
        }
    }
}
