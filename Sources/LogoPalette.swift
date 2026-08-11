import AppKit

protocol LogoPaletteDelegate: AnyObject {
    func logoPaletteDidPick(_ item: LogoItem)
    func logoPaletteDidClose()
}

struct LogoItem {
    let id: String
    let emoji: String
    let name: String
}

/// The catalog of searchable logos: a few friendly aliases for common terms
/// plus every emoji in Unicode (named via its Unicode name). Results are
/// ordered by how often the user has picked each one (persisted in
/// UserDefaults).
enum LogoCatalog {
    static let curated: [LogoItem] = [
        LogoItem(id: "user", emoji: "👤", name: "User"),
        LogoItem(id: "server", emoji: "🖥️", name: "Server"),
        LogoItem(id: "chatgpt", emoji: "🤖", name: "ChatGPT / AI"),
        LogoItem(id: "llm", emoji: "🧠", name: "LLM / Model"),
        LogoItem(id: "chat", emoji: "💬", name: "Chat"),
        LogoItem(id: "database", emoji: "🗄️", name: "Database"),
        LogoItem(id: "cloud", emoji: "☁️", name: "Cloud"),
        LogoItem(id: "web", emoji: "🌐", name: "Web / Browser"),
        LogoItem(id: "security", emoji: "🔒", name: "Security"),
        LogoItem(id: "api", emoji: "🔑", name: "API Key"),
        LogoItem(id: "analytics", emoji: "📊", name: "Analytics"),
        LogoItem(id: "email", emoji: "📧", name: "Email"),
        LogoItem(id: "settings", emoji: "⚙️", name: "Settings"),
        LogoItem(id: "notification", emoji: "🔔", name: "Notifications"),
        LogoItem(id: "payment", emoji: "💳", name: "Payment"),
        LogoItem(id: "growth", emoji: "📈", name: "Growth"),
        LogoItem(id: "code", emoji: "👩‍💻", name: "Developer"),
        LogoItem(id: "design", emoji: "🎨", name: "Design"),
        LogoItem(id: "bug", emoji: "🐛", name: "Bug"),
        LogoItem(id: "deploy", emoji: "🚀", name: "Launch / Deploy"),
    ]

    /// Every single-scalar emoji in Unicode, searched by its Unicode name
    /// (e.g. "GRINNING FACE", "BUST IN SILHOUETTE").
    static let allEmoji: [LogoItem] = {
        var result: [LogoItem] = []
        for value in UInt32(0x1)..<UInt32(0x110000) {
            guard let scalar = UnicodeScalar(value) else { continue }
            let p = scalar.properties
            guard p.isEmoji, !p.isEmojiModifier else { continue }
            var emoji = String(scalar)
            if !p.isEmojiPresentation {
                // Force color emoji rendering for characters that can also
                // be drawn as plain text (©, ♥, ⚠, …).
                emoji += "\u{FE0F}"
            }
            guard let name = unicodeName(emoji) else { continue }
            result.append(LogoItem(id: emoji, emoji: emoji, name: name))
        }
        return result
    }()

    /// Curated aliases first, then the full emoji set.
    static var items: [LogoItem] { curated + allEmoji }

    /// "\N{GRINNING FACE}" → "Grinning Face"
    private static func unicodeName(_ s: String) -> String? {
        let mutable = NSMutableString(string: s)
        CFStringTransform(mutable, nil, kCFStringTransformToUnicodeName, false)
        guard mutable.hasPrefix("\\N{"), mutable.hasSuffix("}") else { return nil }
        let inner = String(mutable).dropFirst(3).dropLast(1)
        guard !inner.isEmpty, !inner.hasPrefix("<") else { return nil }
        return inner.replacingOccurrences(of: "_", with: " ").capitalized
    }

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
                item.name.lowercased().contains(q) || item.emoji.contains(q)
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
            let title = NSMutableAttributedString(string: "\(item.emoji)  \(item.name)")
            title.addAttribute(
                .font,
                value: NSFont.systemFont(ofSize: 15),
                range: NSRange(location: 0, length: title.length)
            )
            button.attributedTitle = title
            button.contentTintColor = .white
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
