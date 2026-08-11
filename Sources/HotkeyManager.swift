import AppKit

/// Fires when the user presses-and-holds Control + Option anywhere in macOS.
///
/// Uses BOTH a global and a local monitor: global monitors are not called for
/// events that are sent to our own app, so once the user activates the app
/// (e.g. by clicking "Draw"), the global monitor goes blind. The local monitor
/// covers that case.
final class HotkeyManager {
    var onTrigger: (() -> Void)?
    private var monitors: [Any] = []

    func start() {
        // App inactive: overlay closed, or open without the app being active.
        let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
        }
        if let global {
            monitors.append(global)
        }

        // App active: global monitors don't see our own app's events.
        let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            return event
        }
        if let local {
            monitors.append(local)
        }
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.control, .option, .command, .shift])
        let combo = flags.contains(.control) && flags.contains(.option)
            && !flags.contains(.command) && !flags.contains(.shift)
        if combo {
            // Dispatch async so toggling (which may remove monitors) never
            // happens from inside a monitor handler.
            DispatchQueue.main.async {
                self.onTrigger?()
            }
        }
    }

    func stop() {
        for m in monitors {
            NSEvent.removeMonitor(m)
        }
        monitors = []
    }
}
