import AppKit

setbuf(stdout, nil)

let app = NSApplication.shared

// --install mode: show the sleek installer window and nothing else.
if CommandLine.arguments.contains("--install") {
    app.setActivationPolicy(.accessory)
    let delegate = InstallModeDelegate()
    app.delegate = delegate
    app.run()
} else {
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate

    if CommandLine.arguments.contains("--selftest") {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            delegate.runSelfTest()
        }
    }

    if CommandLine.arguments.contains("--synctest") {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            delegate.runSyncTest()
        }
    }

    app.run()
}

/// Minimal delegate used in --install mode — does nothing except keep the
/// run loop alive so the InstallerWindow can display.
final class InstallModeDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { _ = InstallerWindowController() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
