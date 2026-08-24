import AppKit
import Combine

/// The version this build reports. The GitHub release must be tagged
/// `v<appVersion>` (e.g. `v1.9.0`) for the update check to work.
let appVersion = "1.11.4"

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
                self.downloading = false
                if let error {
                    self.errorMessage = "Download failed: \(error.localizedDescription)"
                    return
                }
                guard let tmpURL else {
                    self.errorMessage = "Download failed."
                    return
                }
                self.install(zip: tmpURL)
            }
        }
        // Observe the download so the popover can show a progress bar.
        downloadTask?.addObserver(self, forKeyPath: "countOfBytesReceived", options: .new, context: nil)
        downloadTask?.addObserver(self, forKeyPath: "countOfBytesExpectedToReceive", options: .new, context: nil)
        downloadTask?.resume()
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard let task = downloadTask else { return }
        let expected = task.countOfBytesExpectedToReceive
        guard expected > 0 else { return }
        DispatchQueue.main.async { [weak self] in
            self?.downloadProgress = min(1, Double(task.countOfBytesReceived) / Double(expected))
        }
    }

    private func install(zip: URL) {
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
            unzip.waitUntilExit()
        } catch {
            errorMessage = "Could not unzip the update: \(error.localizedDescription)"
            return
        }
        guard unzip.terminationStatus == 0,
              let newApp = findApp(in: work) else {
            errorMessage = "The downloaded package does not contain macdraw.app."
            return
        }
        let current = Bundle.main.bundleURL
        do {
            try replaceBundle(current: current, with: newApp)
        } catch {
            errorMessage = "Could not install the update: \(error.localizedDescription)"
            return
        }
        try? fm.removeItem(at: work)
        // Hand over to the new build.
        Process.launchedProcess(launchPath: "/usr/bin/open", arguments: [current.path])
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
