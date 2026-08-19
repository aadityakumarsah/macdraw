import AppKit

extension NSColor {
    convenience init(hex: Int) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    convenience init(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(hex: Int(v))
    }

    var hexDescription: String {
        guard let c = usingColorSpace(.sRGB) else { return "" }
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

/// Excalidraw color palette (copied from copy-here/colors/colors.ts)
enum Palette {
    static let black = NSColor(hex: 0x1E1E1E)
    static let white = NSColor(hex: 0xFFFFFF)

    // shades [0, 2, 4, 6, 8] of open-color (weights 50, 200, 400, 600, 800)
    static let gray = ["#f8f9fa", "#e9ecef", "#ced4da", "#868e96", "#343a40"].map { NSColor(hexString: $0) }
    static let red = ["#fff5f5", "#ffc9c9", "#ff8787", "#fa5252", "#e03131"].map { NSColor(hexString: $0) }
    static let pink = ["#fff0f6", "#fcc2d7", "#f783ac", "#e64980", "#c2255c"].map { NSColor(hexString: $0) }
    static let grape = ["#f8f0fc", "#eebefa", "#da77f2", "#be4bdb", "#9c36b5"].map { NSColor(hexString: $0) }
    static let violet = ["#f3f0ff", "#d0bfff", "#9775fa", "#7950f2", "#6741d9"].map { NSColor(hexString: $0) }
    static let blue = ["#e7f5ff", "#a5d8ff", "#4dabf7", "#228be6", "#1971c2"].map { NSColor(hexString: $0) }
    static let cyan = ["#e3fafc", "#99e9f2", "#3bc9db", "#15aabf", "#0c8599"].map { NSColor(hexString: $0) }
    static let teal = ["#e6fcf5", "#96f2d7", "#38d9a9", "#12b886", "#099268"].map { NSColor(hexString: $0) }
    static let green = ["#ebfbee", "#b2f2bb", "#69db7c", "#40c057", "#2f9e44"].map { NSColor(hexString: $0) }
    static let yellow = ["#fff9db", "#ffec99", "#ffd43b", "#fab005", "#f08c00"].map { NSColor(hexString: $0) }
    static let orange = ["#fff4e6", "#ffd8a8", "#ffa94d", "#fd7e14", "#e8590c"].map { NSColor(hexString: $0) }
    static let bronze = ["#f8f1ee", "#eaddd7", "#d2bab0", "#a18072", "#846358"].map { NSColor(hexString: $0) }

    /// (family name, 5 shades) — row order matches the excalidraw picker grid
    static let families: [(String, [NSColor])] = [
        ("gray", gray),
        ("red", red),
        ("pink", pink),
        ("grape", grape),
        ("violet", violet),
        ("blue", blue),
        ("cyan", cyan),
        ("teal", teal),
        ("green", green),
        ("yellow", yellow),
        ("orange", orange),
        ("bronze", bronze),
    ]

    // quick picks (5-slot strips)
    static let strokePicks = [black, red[4], green[4], blue[4], yellow[4]]
    /// Fill quick picks — the "no fill" slot plus a wide set of soft fills
    /// (light shades are used so the shape outline stays readable).
    static let backgroundPicks: [NSColor?] = [
        nil, red[1], red[3], green[1], green[3], blue[1], blue[3],
        yellow[1], yellow[3], violet[1], teal[1], orange[1],
    ]
    static let canvasPicks = [white, NSColor(hexString: "#f8f9fa"), NSColor(hexString: "#f5faff"), NSColor(hexString: "#fffce8"), NSColor(hexString: "#fdf8f6")]
}
