import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkey: HotkeyManager!
    private var island: IslandManager!
    private var state: CanvasState!
    private var updater: AppUpdater!
    private var updateItem: NSMenuItem!
    private var syncItem: NSMenuItem!
    private var themeItem: NSMenuItem!
    private var cancellables = Set<AnyCancellable>()

    /// The currently installed canvas (if the overlay is showing) so remote
    /// sync updates can refresh the visible page immediately.
    weak var activeCanvas: CanvasView?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // macdraw is a menu-bar background agent (LSUIElement); the overlay is
        // never "closed", only hidden, but some system teardown paths close it
        // and roll the default back to `true` — which silently quits the app.
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Fonts.register()

        state = CanvasState()
        island = IslandManager(state: state)
        updater = island.updater
        updater.onInstallStarting = { [weak self] in
            self?.island.prepareForInstall()
        }

        // Live sync with React Roadmap (Supabase + Prisma). Sign-in with the
        // shared test account happens in the background; offline mode keeps
        // the app fully local if the network or account is unavailable.
        SyncService.shared.pageSink = island.pages
        island.pages.syncHook = SyncService.shared
        SyncService.shared.start()

        hotkey = HotkeyManager()
        hotkey.onTrigger = { [weak self] in
            self?.island.toggle()
        }
        hotkey.start()

        setupStatusItem()

        // Check for updates shortly after launch so users always know
        // whether they're running the latest build.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.updater.checkNow()
        }

        // First launch: open the overlay so it's obvious the app is running
        // (macdraw is a background agent — no Dock icon, and otherwise users
        // see nothing and think the launch failed). Skipped in scripted modes.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "macdrawHasLaunchedBefore") &&
            !CommandLine.arguments.contains("--synctest") {
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

        // Update menu item — shows status and lets the user check/install.
        updateItem = NSMenuItem(
            title: "Check for updates...",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        menu.addItem(updateItem)
        menu.addItem(.separator())

        // Sync + theme live in the status menu too, mirroring the sidebar.
        themeItem = NSMenuItem(
            title: "Appearance: Dark",
            action: #selector(toggleTheme),
            keyEquivalent: ""
        )
        themeItem.target = self
        menu.addItem(themeItem)

        syncItem = NSMenuItem(
            title: "Sync: connecting…",
            action: #selector(toggleSync),
            keyEquivalent: ""
        )
        syncItem.target = self
        menu.addItem(syncItem)
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit macdraw",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)
        statusItem.menu = menu

        // Keep the update + sync + theme menu labels in sync with state.
        updater.$latestVersion
            .combineLatest(updater.$checking, updater.$downloading)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, checking, downloading in
                self?.refreshUpdateMenuItem(
                    available: self?.updater.isUpdateAvailable ?? false,
                    checking: checking,
                    downloading: downloading
                )
            }
            .store(in: &cancellables)

        SyncService.shared.$phase
            .combineLatest(SyncService.shared.$connection)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.refreshSyncMenuItems()
            }
            .store(in: &cancellables)

        ThemeManager.shared.$theme
            .receive(on: DispatchQueue.main)
            .sink { [weak self] theme in
                self?.themeItem.title = theme == .dark ? "Appearance: Dark" : "Appearance: Light"
            }
            .store(in: &cancellables)
    }

    private func refreshSyncMenuItems() {
        let phase = SyncService.shared.phase
        let conn = SyncService.shared.connection
        let online = SyncService.shared.isOnline
        let label: String
        switch phase {
        case .idle:
            label = online ? "Sync: idle" : "Sync: offline — click to enable"
        case .signingIn:
            label = "Sync: signing in…"
        case .ready:
            if conn == .connected { label = "Sync: live — click to go offline" }
            else if conn == .connecting { label = "Sync: connecting…" }
            else { label = "Sync: reconnecting…" }
        case .error:
            label = "Sync: error — click to retry"
        }
        syncItem.title = label
    }

    @objc private func toggleTheme() {
        ThemeManager.shared.toggle()
    }

    @objc private func toggleSync() {
        SyncService.shared.setOnline(!SyncService.shared.isOnline)
        refreshSyncMenuItems()
    }

    private func refreshUpdateMenuItem(available: Bool, checking: Bool, downloading: Bool) {
        guard let item = updateItem else { return }
        if downloading {
            item.title = "Installing update..."
            item.isEnabled = false
        } else if checking {
            item.title = "Checking for updates..."
            item.isEnabled = false
        } else if available {
            item.title = "Update available (v\(updater.latestLabel)) — click to install"
            item.isEnabled = true
        } else {
            item.title = "Check for updates..."
            item.isEnabled = true
        }
    }

    @objc private func checkForUpdates() {
        if updater.isUpdateAvailable {
            updater.downloadAndInstall()
        } else {
            updater.checkNow()
        }
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

    /// Scripted live-sync test (launch with --synctest): waits for the shared
    /// test account to sign in, the workspace to resolve, realtime to connect
    /// and the initial pull to land, then exits PASS/FAIL with the page count.
    func runSyncTest() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            let svc = SyncService.shared
            var attempts = 0
            var lastCount = -1
            var created = false
            let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
                attempts += 1
                let count = self.island.pages.pages.count
                if count != lastCount {
                    print("[synctest] pages=\(count)")
                    lastCount = count
                }
                print("[synctest] phase=\(self.label(svc.phase)) conn=\(self.label(svc.connection)) ws=\(svc.workspaceID ?? "nil")")
                if svc.phase == .ready && svc.connection == .connected && svc.workspaceID != nil, count >= 1 {
                    print("[synctest] SYNCTEST PASS")
                    if !created {
                        created = true
                        let id = self.island.pages.addPage(named: "mac-sync-check-\(Int(Date().timeIntervalSince1970))", description: "")
                        print("[synctest] created page id=\(id)")
                    }
                }
                if attempts >= 30 {
                    print("[synctest] SYNCTEST FAIL (timeout phase=\(self.label(svc.phase)) conn=\(self.label(svc.connection)))")
                    exit(1)
                }
                if created && attempts >= 24 {
                    print("[synctest] push-window elapsed; exiting")
                    exit(0)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func label(_ phase: SyncService.Phase) -> String {
        switch phase {
        case .idle: return "idle"
        case .signingIn: return "signingIn"
        case .ready: return "ready"
        case .error(let msg): return "error(\(msg))"
        }
    }

    private func label(_ conn: SyncService.Connection) -> String {
        switch conn {
        case .offline: return "offline"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .reconnecting: return "reconnecting"
        case .closed: return "closed"
        }
    }
}
