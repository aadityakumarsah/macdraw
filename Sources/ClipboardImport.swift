import AppKit

/// Visual style the paste-from-other-apps path should use for content that has
/// no intrinsic style of its own (plain/rich text copies).
struct PasteStyle {
    var strokeColor: NSColor
    var fontFamily: String
    var fontSize: CGFloat
}

/// Turns content found on the system pasteboard into native macdraw
/// annotations.
///
/// Excalidraw-compatible canvas tools (excalidraw.com and similar editors)
/// write their scene as JSON in the clipboard's "text/plain" slot right next
/// to the PNG bitmap. Decoding that reconstructs real, editable vector shapes
/// instead of a flat screenshot. Everything else that is text — plain or rich
/// — becomes a text annotation.
enum ClipboardImport {

    /// Returns the reconstructed shapes when the clipboard's plain text is an
    /// Excalidraw scene (JSON), nil otherwise so the caller can fall back to
    /// image/text paste.
    static func annotationsFromExcalidrawJSON(_ string: String?) -> [Annotation]? {
        guard let string, !string.isEmpty,
              let data = string.data(using: .utf8),
              let scene = try? JSONDecoder().decode(ExcalidrawScene.self, from: data),
              scene.type == "excalidraw" || (scene.elements?.isEmpty == false)
        else { return nil }
        let items = (scene.elements ?? []).compactMap { map($0) }
        return items.isEmpty ? nil : items
    }

    /// A standalone text annotation for a plain/rich text copy from another
    /// app. The rect is measured from the string so multiline pastes size
    /// themselves; rich text (when present) is kept so its formatting renders.
    static func textAnnotation(from string: String, rtfData: Data?, style: PasteStyle) -> Annotation {
        var a = Annotation(kind: .text)
        a.text = string
        a.fontFamily = style.fontFamily
        a.fontSize = style.fontSize
        a.strokeColor = style.strokeColor
        a.textAutoResize = true
        if let rtfData {
            a.richTextData = rtfData
        }
        let font = Fonts.nsFont(for: style.fontFamily, size: style.fontSize)
        let measured = (string as NSString).boundingRect(
            with: CGSize(width: 640, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        a.rect = CGRect(
            x: 0, y: 0,
            width: ceil(min(640, measured.width)) + 2,
            height: ceil(measured.height) + 2
        )
        return a
    }

    // MARK: - Excalidraw element mapping

    private static func map(_ e: ExcalidrawElement) -> Annotation? {
        let type = e.type ?? ""
        let startHead = e.startArrowhead ?? e.arrowhead?.start
        let endHead = e.endArrowhead ?? e.arrowhead?.end

        let kind: ShapeKind
        switch type {
        case "rectangle": kind = .rect
        case "ellipse": kind = .ellipse
        case "diamond": kind = .diamond
        case "arrow", "line":
            if type == "line" && arrowhead(endHead) == .none {
                kind = .line
            } else {
                kind = .arrow
            }
        case "text": kind = .text
        case "freedraw": kind = .freedraw
        case "frame": kind = .frame
        default:
            return nil  // images, links and embeds carry no pasteable bytes
        }

        var a = Annotation(kind: kind)
        let x = e.x ?? 0, y = e.y ?? 0
        a.rotation = e.angle ?? 0
        a.opacity = CGFloat(min(max(e.opacity ?? 100, 0), 100) / 100.0)
        a.locked = e.locked ?? false
        a.strokeColor = color(e.strokeColor, fallback: Palette.black)
        a.strokeWidth = e.strokeWidth ?? 2
        switch e.strokeStyle {
        case "dashed": a.strokeStyle = .dashed
        case "dotted": a.strokeStyle = .dotted
        default: a.strokeStyle = .solid
        }
        let rough = e.roughness ?? 0
        a.sloppiness = min(1, rough)
        a.edgeRoughness = rough > 0 ? min(1, rough * 0.6) : 0

        if let bg = e.backgroundColor, bg.hasPrefix("#"), bg != "transparent" {
            a.fillColor = NSColor(hexString: bg)
            a.fillOpacity = CGFloat((e.opacity ?? 100) / 100.0)
        }

        if kind == .arrow || kind == .line || kind == .doubleArrow || kind == .freedraw {
            if let pts = e.points, !pts.isEmpty {
                a.points = pts.map { CGPoint(x: x + $0[0], y: y + $0[1]) }
                var r = CGRect.null
                for p in a.points { r = r.union(CGRect(x: p.x, y: p.y, width: 0, height: 0)) }
                a.rect = r.isNull
                    ? CGRect(x: x, y: y, width: max(1, e.width ?? 1), height: max(1, e.height ?? 1))
                    : r.insetBy(dx: -2, dy: -2)
            } else {
                a.rect = CGRect(x: x, y: y, width: max(1, e.width ?? 1), height: max(1, e.height ?? 1))
            }
            if type == "arrow" || type == "line" {
                a.arrowStart = arrowhead(startHead)
                a.arrowEnd = arrowhead(endHead)
            }
        } else {
            a.rect = CGRect(x: x, y: y, width: max(1, e.width ?? 1), height: max(1, e.height ?? 1))
        }

        if kind == .rect, let rv = e.roundness?.value, rv > 0 {
            let radius = min(a.rect.width, a.rect.height) * min(max(rv, 0), 1) / 2
            a.rx = radius
            a.ry = radius
            a.rounded = true
        }

        if kind == .text {
            a.text = e.text ?? ""
            a.textAutoResize = true
            a.fontSize = e.fontSize ?? 28
            a.fontFamily = fontFamilyName(e.fontFamily)
        }

        return a
    }

    private static func arrowhead(_ s: String?) -> ArrowheadStyle {
        guard let s else { return .none }
        switch s {
        case "arrow": return .arrow
        case "triangle": return .triangle
        case "bar": return .bar
        default: return .arrow  // "dot" has no macdraw equivalent; approximate
        }
    }

    private static func color(_ hex: String?, fallback: NSColor) -> NSColor {
        guard let hex, hex.hasPrefix("#"), hex.count >= 7 else { return fallback }
        return NSColor(hexString: hex)
    }

    private static func fontFamilyName(_ code: Int?) -> String {
        switch code {
        case 2: return "System"           // Helvetica
        case 3: return "Cascadia Code"
        case 4: return "Excalifont"
        case 5: return "Comic Shanns"
        case 6: return "Lilita One"
        case 7: return "Nunito"
        default: return "Virgil"
        }
    }

    // MARK: - Decoding shapes

    private struct ExcalidrawScene: Decodable {
        let type: String?
        let elements: [ExcalidrawElement]?
    }

    private struct ExcalidrawElement: Decodable {
        let type: String?
        let x: CGFloat?
        let y: CGFloat?
        let width: CGFloat?
        let height: CGFloat?
        let angle: CGFloat?
        let strokeColor: String?
        let backgroundColor: String?
        let strokeWidth: CGFloat?
        let strokeStyle: String?
        let roughness: CGFloat?
        let opacity: Double?
        let locked: Bool?
        let points: [[CGFloat]]?
        let roundness: Roundness?
        let text: String?
        let fontSize: CGFloat?
        let fontFamily: Int?
        let textAlign: String?
        let startArrowhead: String?
        let endArrowhead: String?
        let arrowhead: OldArrowhead?
    }

    private struct OldArrowhead: Decodable {
        let start: String?
        let end: String?
    }

    /// Excalidraw's `roundness` is an object on new files (`{"type":3,...}`)
    /// but a bare number on old ones — accept both.
    private struct Roundness: Decodable {
        var value: Double

        init(from decoder: Decoder) throws {
            if let n = try? decoder.singleValueContainer().decode(Double.self) {
                value = n
            } else if let n = try? decoder.singleValueContainer().decode(Int.self) {
                value = Double(n)
            } else {
                let obj = try decoder.container(keyedBy: CodingKeys.self)
                value = (try? obj.decode(Double.self, forKey: .value)) ?? 0
            }
        }

        private enum CodingKeys: String, CodingKey { case value, type }
    }
}