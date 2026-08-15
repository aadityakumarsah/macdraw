import AppKit

/// Renders an SF Symbol as a tinted bitmap image (retina-crisp), or nil when
/// the symbol doesn't exist on this macOS. The symbol is drawn first, then
/// the tint color is composited over it with `.sourceAtop` so the symbol's
/// shape clips the color (its alpha is preserved).
func tintedSymbolImage(named symbol: String, pointSize: CGFloat, color: NSColor) -> NSImage? {
    guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else { return nil }
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
    guard let sized = base.withSymbolConfiguration(config) else { return nil }
    let size = sized.size
    let px = max(4, Int(size.width * 2))
    let py = max(4, Int(size.height * 2))
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: py,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    sized.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
    color.setFill()
    NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
    NSGraphicsContext.restoreGraphicsState()
    let out = NSImage(size: size)
    out.addRepresentation(rep)
    return out
}

/// A text-attachment version of `tintedSymbolImage` for attributed strings.
func tintedSymbolAttachment(_ symbol: String, pointSize: CGFloat, color: NSColor) -> NSTextAttachment? {
    guard let image = tintedSymbolImage(named: symbol, pointSize: pointSize, color: color) else { return nil }
    let attach = NSTextAttachment()
    attach.image = image
    attach.bounds = CGRect(x: 0, y: -3, width: pointSize, height: pointSize)
    return attach
}

protocol LogoPaletteDelegate: AnyObject {
    func logoPaletteDidPick(_ item: LogoItem)
    func logoPaletteDidClose()
}

struct LogoItem {
    let id: String
    let symbol: String
    let name: String
}

/// The catalog of searchable tech icons: curated SF Symbols for common
/// architecture terms plus a large catalog of developer-focused symbols.
/// Results are ordered by how often the user has picked each one (persisted
/// in UserDefaults).
enum LogoCatalog {
    static let curated: [LogoItem] = [
        LogoItem(id: "user", symbol: "person.crop.circle", name: "User"),
        LogoItem(id: "server", symbol: "server.rack", name: "Server"),
        LogoItem(id: "chatgpt", symbol: "sparkles", name: "ChatGPT / AI"),
        LogoItem(id: "llm", symbol: "brain", name: "LLM / Model"),
        LogoItem(id: "chat", symbol: "bubble.left.and.bubble.right", name: "Chat"),
        LogoItem(id: "database", symbol: "cylinder.split.1x2", name: "Database"),
        LogoItem(id: "cloud", symbol: "cloud", name: "Cloud"),
        LogoItem(id: "web", symbol: "globe", name: "Web / Browser"),
        LogoItem(id: "security", symbol: "lock.shield", name: "Security"),
        LogoItem(id: "api", symbol: "key", name: "API Key"),
        LogoItem(id: "analytics", symbol: "chart.bar.xaxis", name: "Analytics"),
        LogoItem(id: "email", symbol: "envelope", name: "Email"),
        LogoItem(id: "settings", symbol: "gearshape", name: "Settings"),
        LogoItem(id: "notification", symbol: "bell", name: "Notifications"),
        LogoItem(id: "payment", symbol: "creditcard", name: "Payment"),
        LogoItem(id: "growth", symbol: "chart.line.uptrend.xyaxis", name: "Growth"),
        LogoItem(id: "code", symbol: "chevron.left.forwardslash.chevron.right", name: "Code"),
        LogoItem(id: "design", symbol: "paintpalette", name: "Design"),
        LogoItem(id: "bug", symbol: "ladybug", name: "Bug"),
        LogoItem(id: "deploy", symbol: "rocket", name: "Launch / Deploy"),
        LogoItem(id: "terminal", symbol: "terminal", name: "Terminal"),
        LogoItem(id: "git", symbol: "arrow.triangle.branch", name: "Git / Branch"),
        LogoItem(id: "wifi", symbol: "wifi", name: "Wi-Fi"),
        LogoItem(id: "mobile", symbol: "iphone", name: "Mobile"),
        LogoItem(id: "docs", symbol: "doc.text", name: "Docs"),
        LogoItem(id: "storage", symbol: "externaldrive", name: "Storage"),
        LogoItem(id: "network", symbol: "network", name: "Network"),
        LogoItem(id: "cpu", symbol: "cpu", name: "CPU"),
        LogoItem(id: "memory", symbol: "memorychip", name: "Memory"),
    ]

    /// A broad catalog of developer / tech icons (SF Symbols), each named for
    /// searching. Symbols that don't exist on this macOS are dropped at load.
    static let allSymbols: [LogoItem] = {
        let raw: [(String, String)] = [
            // Hardware & devices
            ("desktopcomputer", "Desktop Computer"), ("laptopcomputer", "Laptop"),
            ("pc", "PC"), ("macmini", "Mac Mini"), ("macpro.gen3", "Mac Pro"),
            ("display", "Display"), ("tv", "TV"), ("server.rack", "Server Rack"),
            ("internaldrive", "Internal Drive"), ("externaldrive", "External Drive"),
            ("externaldrive.connected.to.line.below", "Drive Connected"),
            ("opticaldiscdrive", "Optical Drive"), ("floppy", "Floppy Disk"),
            ("memorychip", "Memory Chip"), ("cpu", "CPU"), ("keyboard", "Keyboard"),
            ("mouse", "Mouse"), ("printer", "Printer"), ("scanner", "Scanner"),
            ("web.camera", "Webcam"), ("camera", "Camera"), ("camera.aperture", "Aperture"),
            ("microphone", "Microphone"), ("headphones", "Headphones"),
            ("speaker.wave.2", "Speaker"), ("gamecontroller", "Game Controller"),
            ("iphone", "iPhone"), ("ipad", "iPad"), ("applewatch", "Apple Watch"),
            ("simcard", "SIM Card"), ("creditcard", "Credit Card"),
            ("clock", "Clock"), ("timer", "Timer"), ("stopwatch", "Stopwatch"),
            ("hourglass", "Hourglass"), ("alarm", "Alarm"),
            // Network
            ("network", "Network"), ("network.badge.shield.half.filled", "Protected Network"),
            ("wifi", "Wi-Fi"), ("wifi.exclamationmark", "Wi-Fi Issue"),
            ("antenna.radiowaves.left.and.right", "Antenna"),
            ("dot.radiowaves.left.and.right", "Signal"),
            ("arrow.triangle.branch", "Branch / Fork"), ("arrow.triangle.merge", "Merge"),
            ("arrow.triangle.pull", "Pull Request"), ("arrow.triangle.swap", "Swap"),
            ("point.3.connected.trianglepath.dotted", "Mesh Network"),
            ("point.3.filled.connected.trianglepath.dotted", "Mesh Network Filled"),
            ("globe", "Globe"), ("globe.americas", "Globe Americas"),
            ("globe.europe.africa", "Globe Europe"), ("globe.asia.australia", "Globe Asia"),
            ("globe.badge.chevron.backward", "Globe with Arrow"),
            ("cable.connector", "Cable Connector"), ("bolt.horizontal.circle", "Link / Ethernet"),
            // Cloud & storage
            ("cloud", "Cloud"), ("cloud.fill", "Cloud Filled"), ("cloud.bolt", "Cloud Lightning"),
            ("icloud", "iCloud"), ("icloud.fill", "iCloud Filled"),
            ("icloud.and.arrow.up", "iCloud Upload"), ("icloud.and.arrow.down", "iCloud Download"),
            ("cylinder", "Database Cylinder"), ("cylinder.fill", "Database Cylinder Filled"),
            ("cylinder.split.1x2", "Database"), ("cylinder.split.1x2.fill", "Database Filled"),
            ("archivebox", "Archive"), ("archivebox.fill", "Archive Filled"),
            ("tray", "Tray"), ("tray.fill", "Tray Filled"),
            ("tray.and.arrow.up", "Upload to Server"), ("tray.and.arrow.down", "Download from Server"),
            ("shippingbox", "Package"), ("shippingbox.fill", "Package Filled"),
            ("box.truck", "Delivery"), ("externaldrive.badge.checkmark", "Backup Drive"),
            ("externaldrive.badge.icloud", "Cloud Drive"),
            // Code & development
            ("chevron.left.forwardslash.chevron.right", "Code"),
            ("curlybraces", "Code Braces"),
            ("square.stack.3d.up", "Stack"), ("square.stack.3d.up.fill", "Stack Filled"),
            ("square.stack.3d.down.right", "Layer Stack Down"),
            ("square.stack", "Square Stack"), ("layers", "Layers"), ("layers.fill", "Layers Filled"),
            ("layers.3d", "3D Layers"), ("cube", "Cube"), ("cube.fill", "Cube Filled"),
            ("cube.transparent", "Transparent Cube"),
            ("square.grid.2x2", "Grid 2x2"), ("square.grid.3x3", "Grid 3x3"),
            ("rectangle.grid.2x2", "Grid Rectangles"),
            ("rectangle.3.group", "Group"), ("rectangle.3.group.fill", "Group Filled"),
            ("rectangle.on.rectangle", "Overlay"), ("rectangle.on.rectangle.fill", "Overlay Filled"),
            ("square.on.square", "Combine"), ("square.on.square.fill", "Combine Filled"),
            ("doc", "Document"), ("doc.fill", "Document Filled"),
            ("doc.text", "Document Text"), ("doc.text.fill", "Document Text Filled"),
            ("doc.plaintext", "Plain Text Document"), ("doc.richtext", "Rich Text Document"),
            ("doc.on.doc", "Duplicate Document"), ("doc.on.clipboard", "Clipboard Document"),
            ("doc.viewfinder", "Document Scan"), ("doc.badge.plus", "New Document"),
            ("folder", "Folder"), ("folder.fill", "Folder Filled"),
            ("folder.badge.plus", "New Folder"),
            ("terminal", "Terminal"), ("terminal.fill", "Terminal Filled"),
            ("hammer", "Build / Hammer"), ("hammer.fill", "Build Filled"),
            ("wrench", "Fix"), ("wrench.fill", "Fix Filled"),
            ("wrench.and.screwdriver", "Tools"), ("screwdriver", "Screwdriver"),
            ("gearshape", "Settings"), ("gearshape.fill", "Settings Filled"),
            ("slider.horizontal.3", "Filter Sliders"),
            ("power", "Power"), ("power.circle", "Power Circle"),
            ("bolt", "Lightning / Fast"), ("bolt.fill", "Lightning Filled"),
            ("bolt.badge.a", "Accelerate"), ("bolt.horizontal", "Fast Energy"),
            ("flame", "Flame"), ("flame.fill", "Flame Filled"),
            // AI / ML / data science
            ("brain", "AI Brain"), ("brain.head.profile", "AI Head"),
            ("sparkles", "AI Sparkles"), ("sparkles.tv", "AI TV"),
            ("scope", "AI Scope"), ("scope.fill", "AI Scope Filled"),
            ("viewfinder", "Target"), ("viewfinder.circle", "Target Circle"),
            ("gyroscope", "Gyroscope"), ("barcode", "Barcode"), ("qrcode", "QR Code"),
            ("barcode.viewfinder", "Scan Barcode"), ("qrcode.viewfinder", "Scan QR Code"),
            ("wave.3.right", "Sound Wave"), ("waveform.path", "Waveform"),
            ("waveform.path.ecg", "ECG Waveform"), ("waveform.path.ecg.rectangle", "ECG Monitor"),
            ("chart.xyaxis.line", "Data Line"), ("function", "Function"),
            ("x.squareroot", "Square Root"), ("sum", "Summation"), ("infinity", "Infinity"),
            ("infinity.circle", "Infinity Circle"), ("number", "Number"), ("percent", "Percent"),
            ("plusminus", "Plus Minus"), ("equal.circle", "Equal"), ("divide.circle", "Divide"),
            ("multiply.circle", "Multiply"), ("minus.circle", "Minus"), ("plus.circle", "Plus"),
            // Security & identity
            ("lock", "Lock"), ("lock.fill", "Lock Filled"),
            ("lock.shield", "Locked Shield"), ("lock.shield.fill", "Locked Shield Filled"),
            ("lock.open", "Unlock"), ("lock.rotation", "Rotate Lock"),
            ("shield", "Shield"), ("shield.fill", "Shield Filled"),
            ("shield.lefthalf.filled", "Shield Half"),
            ("checkmark.shield", "Verified Shield"), ("exclamationmark.shield", "Warning Shield"),
            ("xmark.shield", "Blocked Shield"),
            ("key", "API Key"), ("key.fill", "API Key Filled"),
            ("key.horizontal", "Key Horizontal"), ("key.icloud", "iCloud Keychain"),
            ("key.viewfinder", "Key Scan"),
            ("faceid", "Face ID"), ("touchid", "Touch ID"), ("fingerprint", "Fingerprint"),
            ("hand.raised", "Block User"), ("hand.raised.fill", "Block User Filled"),
            ("person.badge.key", "User with Key"), ("person.badge.shield.checkmark", "Verified User"),
            ("person.badge.clock", "User with Clock"), ("person.badge.gearshape", "User Settings"),
            ("person.crop.circle.badge.checkmark", "Verified Account"),
            ("person.crop.circle.badge.exclamationmark", "Account Issue"),
            ("checkmark.seal", "Certified"), ("checkmark.seal.fill", "Certified Filled"),
            ("xmark.seal", "Not Certified"),
            ("exclamationmark.octagon", "Critical Error"),
            ("exclamationmark.triangle", "Warning"), ("exclamationmark.triangle.fill", "Warning Filled"),
            ("exclamationmark.bubble", "Alert Message"),
            ("questionmark.circle", "Question"), ("questionmark.circle.fill", "Question Filled"),
            ("info.circle", "Info"), ("info.circle.fill", "Info Filled"),
            ("checkmark.circle", "Success"), ("checkmark.circle.fill", "Success Filled"),
            ("xmark.circle", "Error"), ("xmark.circle.fill", "Error Filled"),
            // Communication & collaboration
            ("bubble.left", "Chat Bubble"), ("bubble.left.fill", "Chat Bubble Filled"),
            ("bubble.left.and.bubble.right", "Chat"), ("bubble.left.and.bubble.right.fill", "Chat Filled"),
            ("bubble.left.and.text.bubble.right", "Chat with Text"),
            ("message", "Message"), ("message.fill", "Message Filled"),
            ("envelope", "Email"), ("envelope.fill", "Email Filled"),
            ("envelope.badge.person.crop", "Email Contact"),
            ("paperplane", "Send"), ("paperplane.fill", "Send Filled"),
            ("phone", "Phone"), ("phone.fill", "Phone Filled"),
            ("video", "Video Call"), ("video.fill", "Video Call Filled"), ("video.badge.plus", "Add to Call"),
            ("mic", "Mic"), ("mic.fill", "Mic Filled"), ("mic.slash", "Mic Muted"),
            ("bell", "Notification"), ("bell.fill", "Notification Filled"),
            ("bell.badge", "Notification Badge"), ("bell.badge.fill", "Notification Badge Filled"),
            ("bell.slash", "Notifications Muted"),
            ("person", "User"), ("person.fill", "User Filled"),
            ("person.2", "Users"), ("person.2.fill", "Users Filled"),
            ("person.3", "Team"), ("person.3.fill", "Team Filled"),
            ("person.crop.circle", "Account"), ("person.crop.circle.fill", "Account Filled"),
            ("person.crop.rectangle", "User Card"),
            ("person.2.wave.2", "Team Call"), ("person.and.arrow.left.and.right", "Transfer User"),
            ("person.bust", "Person Bust"), ("person.bust.fill", "Person Bust Filled"),
            ("person.bust.circle", "Person Bust Circle"),
            ("at", "Mention / At"), ("hashtag", "Hashtag"), ("link", "Link"), ("link.circle", "Link Circle"),
            ("paperclip", "Attachment"),
            ("calendar", "Calendar"), ("calendar.badge.clock", "Calendar with Clock"),
            ("calendar.badge.exclamationmark", "Calendar Alert"),
            // Charts & analytics
            ("chart.bar", "Bar Chart"), ("chart.bar.fill", "Bar Chart Filled"),
            ("chart.bar.xaxis", "Bar Chart X-Axis"),
            ("chart.pie", "Pie Chart"), ("chart.pie.fill", "Pie Chart Filled"),
            ("chart.line.uptrend.xyaxis", "Growth Chart"),
            ("chart.line.uptrend.xyaxis.circle", "Growth Chart Circle"),
            ("chart.line.downtrend.xyaxis", "Decline Chart"),
            ("arrow.up.right", "Trend Up"), ("arrow.down.right", "Trend Down"),
            ("arrow.up.right.circle", "Growth"),
            ("arrow.clockwise", "Refresh"), ("arrow.clockwise.circle", "Refresh Circle"),
            ("arrow.counterclockwise", "Undo Arrow"), ("arrow.uturn.backward", "Go Back"),
            ("arrow.triangle.2.circlepath", "Sync"), ("arrow.triangle.2.circlepath.circle", "Sync Circle"),
            ("repeat", "Repeat"), ("repeat.circle", "Repeat Circle"), ("shuffle", "Shuffle"),
            ("switch.2", "Switch"), ("arrow.up.arrow.down", "Sort"), ("arrow.up.arrow.down.circle", "Sort Circle"),
            // DevOps / deploy
            ("rocket", "Deploy"), ("rocket.fill", "Deploy Filled"),
            ("airplane", "Release"), ("airplane.departure", "Takeoff"), ("airplane.arrival", "Landing"),
            ("figure.run", "Runner"), ("figure.walk", "Walkthrough"),
            ("flag", "Flag"), ("flag.fill", "Flag Filled"), ("flag.checkered", "Goal"),
            ("checkmark", "Checkmark"), ("circle.dashed", "Pending"),
            ("circle", "Circle"), ("circle.fill", "Circle Filled"), ("circle.inset.filled", "Status Dot"),
            ("app", "App Icon"), ("app.fill", "App Icon Filled"), ("app.badge", "App Badge"),
            ("square.dashed", "Draft"), ("tray.full", "Full Tray"), ("tray.full.fill", "Full Tray Filled"),
            // Web & search
            ("safari", "Safari Browser"), ("safari.fill", "Safari Filled"),
            ("magnifyingglass", "Search"), ("text.magnifyingglass", "Search Text"),
            ("magnifyingglass.circle", "Search Circle"),
            ("command", "Command Key"), ("option", "Option Key"), ("control", "Control Key"),
            ("shift", "Shift Key"), ("escape", "Esc Key"), ("delete.left", "Backspace"),
            ("return", "Return Key"), ("tab", "Tab Key"), ("space", "Space Bar"), ("capslock", "Caps Lock"),
            // Automation & integration
            ("puzzlepiece", "Integration"), ("puzzlepiece.fill", "Integration Filled"),
            ("puzzlepiece.extension", "Integration Extension"),
            ("puzzlepiece.extension.fill", "Integration Extension Filled"),
            ("plus.square.on.square", "Compose"),
            ("square.and.arrow.up", "Share"), ("square.and.arrow.down", "Download"),
            ("square.and.arrow.up.on.square", "Share Multiple"),
            ("arrow.down.doc", "Import"), ("arrow.up.doc", "Export"),
            ("square.and.pencil", "Edit"), ("pencil", "Pen"), ("pencil.and.outline", "Sketch"),
            ("highlighter", "Highlight"), ("marker", "Marker"), ("eraser", "Eraser"),
            ("textformat", "Formatting"), ("textformat.size", "Font Size"),
            ("textformat.abc", "ABC"), ("character", "Character"),
            ("text.alignleft", "Align Left"), ("text.aligncenter", "Align Center"),
            ("text.alignright", "Align Right"), ("text.justify", "Justify"),
            ("list.bullet", "Bullet List"), ("list.number", "Numbered List"),
            ("list.bullet.rectangle", "Checklist"), ("checklist", "Checklist"),
            ("tablecells", "Table"), ("tablecells.fill", "Table Filled"),
            ("squareshape.split.2x2", "Squares"),
        ]
        return raw.compactMap { symbol, name in
            guard NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil else { return nil }
            return LogoItem(id: symbol, symbol: symbol, name: name)
        }
    }()

    /// Curated aliases first, then the full tech icon set.
    static var items: [LogoItem] { curated + allSymbols }

    static func frequency(of id: String) -> Int {
        UserDefaults.standard.integer(forKey: "logo.freq.\(id)")
    }

    static func bumpFrequency(of id: String) {
        UserDefaults.standard.set(frequency(of: id) + 1, forKey: "logo.freq.\(id)")
    }

    /// Items matching the query, most frequently used first, curated aliases
    /// ahead of the rest.
    static func results(for query: String) -> [LogoItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var filtered = q.isEmpty
            ? items
            : items.filter { item in
                item.name.lowercased().contains(q) || item.symbol.contains(q)
            }
        filtered.sort { a, b in
            let fa = frequency(of: a.id)
            let fb = frequency(of: b.id)
            if fa != fb { return fa > fb }
            let ca = curated.contains { $0.id == a.id }
            let cb = curated.contains { $0.id == b.id }
            if ca != cb { return ca }
            return a.name < b.name
        }
        return filtered
    }
}

/// The "/" search palette: a search field on top and a list of logo results
/// below. ↑/↓ navigate, ↵ inserts, Esc closes.
final class LogoPaletteView: NSView, NSTextFieldDelegate {
    weak var delegate: LogoPaletteDelegate?

    let searchField = NSTextField()
    private let footer = NSTextField(labelWithString: "↑↓ navigate  ·  ↵ insert  ·  Esc close")
    private var rows: [NSButton] = []
    private var currentResults: [LogoItem] = []
    private var highlightedRow = 0

    private static let rowHeight: CGFloat = 38
    private static let maxRows = 8
    private let accent = NSColor(calibratedRed: 0.42, green: 0.4, blue: 0.86, alpha: 1)

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 280, height: 380))
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 0.97).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.14).cgColor

        let search = searchField
        search.frame = CGRect(x: 12, y: 12, width: bounds.width - 24, height: 30)
        search.placeholderString = "Search logos…"
        search.isBordered = false
        search.drawsBackground = true
        search.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.1)
        search.textColor = .white
        search.font = NSFont.systemFont(ofSize: 14)
        search.delegate = self
        search.wantsLayer = true
        search.layer?.cornerRadius = 6
        search.focusRingType = .none
        addSubview(search)

        footer.font = NSFont.systemFont(ofSize: 11)
        footer.textColor = NSColor(calibratedWhite: 1, alpha: 0.45)
        footer.frame = CGRect(x: 12, y: bounds.height - 24, width: bounds.width - 24, height: 16)
        addSubview(footer)

        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        currentResults = LogoCatalog.results(for: searchField.stringValue)
        highlightedRow = 0
        rebuildRows()
    }

    private func rebuildRows() {
        for row in rows {
            row.removeFromSuperview()
        }
        rows = []
        for (i, item) in currentResults.prefix(LogoPaletteView.maxRows).enumerated() {
            let button = NSButton(title: "", target: self, action: #selector(rowClicked(_:)))
            button.tag = i
            button.frame = CGRect(
                x: 8,
                y: 48 + CGFloat(i) * LogoPaletteView.rowHeight,
                width: bounds.width - 16,
                height: 34
            )
            button.isBordered = false
            button.alignment = .left
            button.wantsLayer = true
            button.layer?.cornerRadius = 6
            let title = NSMutableAttributedString()
            if let attach = tintedSymbolAttachment(item.symbol, pointSize: 15, color: .white) {
                title.append(NSAttributedString(attachment: attach))
                title.append(NSAttributedString(string: "  "))
            }
            title.append(NSAttributedString(
                string: item.name,
                attributes: [.font: NSFont.systemFont(ofSize: 14)]
            ))
            button.attributedTitle = title
            addSubview(button)
            rows.append(button)
        }
        updateHighlight()
    }

    private func updateHighlight() {
        for (i, row) in rows.enumerated() {
            row.layer?.backgroundColor = i == highlightedRow
                ? accent.cgColor
                : NSColor.clear.cgColor
        }
    }

    @objc private func rowClicked(_ sender: NSButton) {
        highlightedRow = sender.tag
        pickRow(highlightedRow)
    }

    private func pickRow(_ i: Int) {
        guard i >= 0, i < currentResults.count else { return }
        delegate?.logoPaletteDidPick(currentResults[i])
    }

    // MARK: - search field delegate

    func controlTextDidChange(_ obj: Notification) {
        reload()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            pickRow(highlightedRow)
            return true
        case #selector(NSResponder.moveUp(_:)):
            highlightedRow = max(0, highlightedRow - 1)
            updateHighlight()
            return true
        case #selector(NSResponder.moveDown(_:)):
            highlightedRow = min(rows.count - 1, highlightedRow + 1)
            updateHighlight()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            delegate?.logoPaletteDidClose()
            return true
        default:
            return false
        }
    }

    // MARK: - self-test hooks

    func selftestSetQuery(_ q: String) {
        searchField.stringValue = q
        reload()
    }

    var selftestResults: [LogoItem] { currentResults }

    func selftestPickRow(_ i: Int) {
        pickRow(i)
    }
}
