import AppKit

/// Sleek installer window shown when MacDraw is launched with `--install`.
/// Presents a big icon, a "Drag to Applications" prompt and a one-click
/// Install button that copies the running bundle to /Applications.
final class InstallerWindowController: NSWindowController, NSWindowDelegate {

    private let progressLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let installButton = NSButton(title: "Install to Applications", target: nil, action: #selector(installClicked))
    private let launchButton = NSButton(title: "Launch MacDraw", target: nil, action: #selector(launchClicked))
    private let statusIcon = NSImageView()
    private let iconView = NSImageView()
    private let appsIconView = NSImageView()
    private let arrowView = NSTextField(labelWithString: "→")

    private var state: InstallerState = .ready
    private var installedAppPath = "/Applications/MacDraw.app"

    enum InstallerState {
        case ready, installing, done
    }

    // MARK: - lifecycle

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 1)
        window.isReleasedWhenClosed = false
        window.center()

        self.init(window: window)
        window.delegate = self

        buildUI()
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - UI construction

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        // Background gradient layer
        let bgLayer = CAGradientLayer()
        bgLayer.colors = [
            NSColor(calibratedWhite: 0.07, alpha: 1).cgColor,
            NSColor(calibratedWhite: 0.03, alpha: 1).cgColor,
        ]
        bgLayer.startPoint = CGPoint(x: 0.5, y: 1)
        bgLayer.endPoint = CGPoint(x: 0.5, y: 0)
        bgLayer.frame = contentView.bounds
        bgLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        contentView.wantsLayer = true
        contentView.layer?.insertSublayer(bgLayer, at: 0)

        // --- Title bar drag handle area (transparent titlebar) ---
        let dragHandle = NSView()
        dragHandle.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(dragHandle)

        // --- App icon ---
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconView)

        // --- Applications folder icon ---
        let appsPath = "/Applications"
        let appsIcon = NSWorkspace.shared.icon(forFile: appsPath)
        appsIconView.image = appsIcon
        appsIconView.imageScaling = .scaleProportionallyUpOrDown
        appsIconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(appsIconView)

        // --- Arrow ---
        arrowView.font = NSFont.systemFont(ofSize: 36, weight: .thin)
        arrowView.textColor = NSColor(calibratedWhite: 0.35, alpha: 1)
        arrowView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(arrowView)

        // --- Title ---
        let title = NSTextField(labelWithString: "Install MacDraw")
        title.font = .systemFont(ofSize: 26, weight: .bold)
        title.textColor = .white
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(title)

        // --- Subtitle ---
        let subtitle = NSTextField(labelWithString: "Click below to copy MacDraw into your Applications folder.")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = NSColor(calibratedWhite: 0.55, alpha: 1)
        subtitle.alignment = .center
        subtitle.maximumNumberOfLines = 2
        subtitle.preferredMaxLayoutWidth = 400
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(subtitle)

        // --- Progress indicator ---
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.doubleValue = 0
        progressIndicator.isHidden = true
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(progressIndicator)

        // --- Progress label ---
        progressLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        progressLabel.textColor = NSColor(calibratedWhite: 0.5, alpha: 1)
        progressLabel.alignment = .center
        progressLabel.isHidden = true
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(progressLabel)

        // --- Status icon (hidden until done) ---
        statusIcon.imageScaling = .scaleProportionallyUpOrDown
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        statusIcon.isHidden = true
        contentView.addSubview(statusIcon)

        // --- Install button ---
        installButton.target = self
        installButton.bezelStyle = .rounded
        installButton.font = .systemFont(ofSize: 15, weight: .semibold)
        installButton.contentTintColor = .white
        installButton.translatesAutoresizingMaskIntoConstraints = false
        installButton.wantsLayer = true
        installButton.layer?.cornerRadius = 12
        installButton.layer?.backgroundColor = NSColor.systemIndigo.cgColor
        installButton.layer?.masksToBounds = true
        installButton.setButtonType(.momentaryChange)
        contentView.addSubview(installButton)

        // --- Launch button (hidden until done) ---
        launchButton.target = self
        launchButton.bezelStyle = .rounded
        launchButton.font = .systemFont(ofSize: 15, weight: .semibold)
        launchButton.contentTintColor = .white
        launchButton.translatesAutoresizingMaskIntoConstraints = false
        launchButton.wantsLayer = true
        launchButton.layer?.cornerRadius = 12
        launchButton.layer?.backgroundColor = NSColor.systemGreen.cgColor
        launchButton.layer?.masksToBounds = true
        launchButton.isHidden = true
        contentView.addSubview(launchButton)

        // --- Layout ---
        NSLayoutConstraint.activate([
            dragHandle.topAnchor.constraint(equalTo: contentView.topAnchor),
            dragHandle.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            dragHandle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            dragHandle.heightAnchor.constraint(equalToConstant: 38),

            // App icon — top center
            iconView.topAnchor.constraint(equalTo: dragHandle.bottomAnchor, constant: 10),
            iconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor, constant: -50),
            iconView.widthAnchor.constraint(equalToConstant: 80),
            iconView.heightAnchor.constraint(equalToConstant: 80),

            // Arrow between icons
            arrowView.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            arrowView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            arrowView.widthAnchor.constraint(equalToConstant: 40),

            // Applications icon
            appsIconView.topAnchor.constraint(equalTo: iconView.topAnchor),
            appsIconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor, constant: 50),
            appsIconView.widthAnchor.constraint(equalToConstant: 80),
            appsIconView.heightAnchor.constraint(equalToConstant: 80),

            // Title
            title.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 20),
            title.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            // Subtitle
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            subtitle.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            subtitle.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 40),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -40),

            // Progress bar
            progressIndicator.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 24),
            progressIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            progressIndicator.widthAnchor.constraint(equalToConstant: 320),
            progressIndicator.heightAnchor.constraint(equalToConstant: 6),

            // Progress label
            progressLabel.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 8),
            progressLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            // Status icon
            statusIcon.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            statusIcon.centerYAnchor.constraint(equalTo: progressIndicator.centerYAnchor, constant: -4),
            statusIcon.widthAnchor.constraint(equalToConstant: 48),
            statusIcon.heightAnchor.constraint(equalToConstant: 48),

            // Install button
            installButton.topAnchor.constraint(equalTo: progressLabel.bottomAnchor, constant: 16),
            installButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            installButton.widthAnchor.constraint(equalToConstant: 240),
            installButton.heightAnchor.constraint(equalToConstant: 48),

            // Launch button (same position as install button)
            launchButton.topAnchor.constraint(equalTo: installButton.topAnchor),
            launchButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            launchButton.widthAnchor.constraint(equalToConstant: 240),
            launchButton.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    // MARK: - actions

    @objc private func installClicked() {
        guard state == .ready else { return }
        state = .installing

        installButton.isHidden = true
        progressIndicator.isHidden = false
        progressIndicator.isIndeterminate = true
        progressIndicator.startAnimation(nil)
        progressLabel.isHidden = false
        progressLabel.stringValue = "Copying MacDraw to Applications…"

        // Perform the copy on a background thread so the UI stays responsive.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.copyToApplications()
        }
    }

    @objc private func launchClicked() {
        // Open the freshly installed copy.
        if let url = URL(string: "file://\(installedAppPath)") {
            NSWorkspace.shared.open(url)
        }
        NSApp.terminate(nil)
    }

    // MARK: - copy logic

    private func copyToApplications() {
        guard let bundlePath = Bundle.main.bundlePath as String? else {
            showError("Could not locate the running app bundle.")
            return
        }

        // If a previously installed copy of MacDraw is already running we
        // can't overwrite — ask the user to quit it first. The installer's
        // own process is excluded so the temporary copy we're running from
        // never triggers this.
        let existing = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.local.macdraw"
        ).filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !existing.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.showError("MacDraw is already running. Quit it first, then try again.")
            }
            return
        }

        let fm = FileManager.default

        // Simulated phased progress so the user sees movement before the
        // (fast) copy completes.
        DispatchQueue.main.async { [weak self] in
            self?.progressIndicator.isIndeterminate = false
        }
        for pct in stride(from: 0.0, through: 0.85, by: 0.05) {
            Thread.sleep(forTimeInterval: 0.04)
            DispatchQueue.main.async { [weak self] in
                self?.progressIndicator.doubleValue = pct
            }
        }

        // Primary destination /Applications, with a fallback to ~/Applications
        // for machines where /Applications isn't user-writable.
        let candidates = ["/Applications/MacDraw.app", NSHomeDirectory() + "/Applications/MacDraw.app"]
        var installedTo: String?
        var lastError: Error?
        for dest in candidates {
            let parent = (dest as NSString).deletingLastPathComponent
            if !fm.fileExists(atPath: parent) {
                try? fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
            }
            if fm.fileExists(atPath: dest) {
                if !fm.isDeletableFile(atPath: dest) {
                    lastError = NSError(domain: "MacDraw", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "\(dest) isn't removable"])
                    continue
                }
                do { try fm.removeItem(atPath: dest) } catch { lastError = error; continue }
            }
            do {
                try fm.copyItem(atPath: bundlePath, toPath: dest)
                installedTo = dest
                break
            } catch {
                lastError = error
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.progressIndicator.doubleValue = 1.0
        }
        Thread.sleep(forTimeInterval: 0.3)

        guard let finalDest = installedTo else {
            let msg = lastError?.localizedDescription ?? "unknown error"
            showError("Could not copy MacDraw — \(msg).")
            return
        }

        // Remember where we installed so "Launch" opens the right copy.
        installedAppPath = finalDest
        DispatchQueue.main.async { [weak self] in
            self?.showDone()
        }
    }

    private func showError(_ msg: String) {
        state = .ready
        progressIndicator.isHidden = true
        progressIndicator.stopAnimation(nil)
        progressLabel.isHidden = false
        progressLabel.textColor = NSColor.systemRed
        progressLabel.stringValue = msg
        installButton.isHidden = false
    }

    private func showDone() {
        state = .done
        progressIndicator.isHidden = true
        progressIndicator.stopAnimation(nil)

        statusIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Installed")
        statusIcon.contentTintColor = .systemGreen
        statusIcon.isHidden = false

        progressLabel.textColor = .white
        progressLabel.stringValue = "MacDraw is ready!"

        installButton.isHidden = true
        launchButton.isHidden = false
    }
}
