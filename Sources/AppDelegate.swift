import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkey: HotkeyManager!
    private var island: IslandManager!
    private var state: CanvasState!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Fonts.register()

        state = CanvasState()
        island = IslandManager(state: state)

        hotkey = HotkeyManager()
        hotkey.onTrigger = { [weak self] in
            self?.island.toggle()
        }
        hotkey.start()

        setupStatusItem()

        // First launch: open the overlay so it's obvious the app is running
        // (macdraw is a background agent — no Dock icon, and otherwise users
        // see nothing and think the launch failed).
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "macdrawHasLaunchedBefore") {
            defaults.set(true, forKey: "macdrawHasLaunchedBefore")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.island.show()
            }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "pencil.and.scribble", accessibilityDescription: "macdraw")
        }
        let menu = NSMenu()
        let toggle = NSMenuItem(title: "Draw on Screen (hold ⌃⌥)", action: #selector(toggleIsland), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        let shortcuts = NSMenuItem(title: "Keyboard shortcuts", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for s in Shortcuts.all {
            let item = NSMenuItem(title: "\(s.key.uppercased()) — \(s.tool.label)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            sub.addItem(item)
        }
        sub.addItem(.separator())
        for (name, key) in [
            ("Undo", "⌘Z"), ("Copy selection", "⌘C"), ("Paste", "⌘V"),
            ("Delete selection", "⌫"), ("Close overlay", "Esc"),
        ] {
            let item = NSMenuItem(title: "\(name) — \(key)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            sub.addItem(item)
        }
        shortcuts.submenu = sub
        menu.addItem(shortcuts)
        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit macdraw",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func toggleIsland() {
        island.toggle()
    }

    /// Scripted smoke test (launch with --selftest): opens the overlay, starts
    /// text editing, presses Esc, and verifies the app stays alive and the
    /// text editing ends. Prints progress to stdout.
    func runSelfTest() {
        let log: (String) -> Void = { print("[selftest] \($0)") }
        island.runSelfTest(log: log)
    }
}
