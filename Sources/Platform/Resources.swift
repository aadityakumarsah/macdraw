import Foundation

enum Resources {
    private static let fm = FileManager.default

    /// Bundle Resources dir, or a Resources/ folder next to the executable (dev builds).
    static var root: URL {
        if let res = Bundle.main.resourceURL {
            return res
        }
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let cand = exe.appendingPathComponent("Resources")
        return fm.fileExists(atPath: cand.path) ? cand : exe
    }

    static func url(_ sub: String, _ file: String?) -> URL? {
        let base = root.appendingPathComponent(sub)
        if let f = file {
            let u = base.appendingPathComponent(f)
            return fm.fileExists(atPath: u.path) ? u : nil
        }
        return fm.fileExists(atPath: base.path) ? base : nil
    }

    static func files(in sub: String, ext: String) -> [URL] {
        guard let dir = url(sub, nil) else { return [] }
        let all = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return all.filter { $0.pathExtension.lowercased() == ext.lowercased() }
    }
}
