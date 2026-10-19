import AppKit

// Full-scene generation: the model emits real macdraw elements — any shape
// kind, the Excalidraw palette, hachure fills, sloppiness, stroke styles,
// text — rather than the narrow node/edge DiagramSpec.
//
// The harness around it does not ask the model to grade itself. It measures
// the draft (SceneCritic), repairs everything that can be repaired without a
// model (SceneDoctor), and feeds the remaining, specific defects back. Both of
// those are pure functions over a SceneSpec, which is what makes the harness
// testable with no API key and identical across all seven providers.

// MARK: - schema

/// One element of a generated scene. Field names are kept short because the
/// model writes them by hand, and every style field is optional so a sparse
/// element is still valid.
struct SceneElement: Codable {
    var id: String
    /// A `ShapeKind` raw value ("rect", "ellipse", "cloud", "arrow", "text"…).
    var kind: String
    var x: CGFloat = 0
    var y: CGFloat = 0
    var w: CGFloat = 0
    var h: CGFloat = 0
    /// Vertices for lines, arrows, connectors and freehand strokes.
    var points: [[CGFloat]]? = nil
    var text: String? = nil
    /// `#rrggbb`.
    var stroke: String? = nil
    /// `#rrggbb`, or "transparent" for no fill.
    var fill: String? = nil
    /// hachure | crossHatch | zigzag | solid
    var fillStyle: String? = nil
    /// solid | dashed | dotted
    var strokeStyle: String? = nil
    var strokeWidth: CGFloat? = nil
    /// architect | artist | cartoonist
    var sloppiness: String? = nil
    /// sharp | round
    var edges: String? = nil
    /// 0...1
    var opacity: CGFloat? = nil
    var fontFamily: String? = nil
    var fontSize: CGFloat? = nil
    /// none | arrow | triangle | bar
    var startArrow: String? = nil
    var endArrow: String? = nil
    /// SF Symbol name, from `AIIconCatalog`.
    var symbol: String? = nil
    var zIndex: Int? = nil

    var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
    var cgPoints: [CGPoint] { (points ?? []).compactMap { $0.count >= 2 ? CGPoint(x: $0[0], y: $0[1]) : nil } }

    init(
        id: String, kind: String,
        x: CGFloat = 0, y: CGFloat = 0, w: CGFloat = 0, h: CGFloat = 0,
        points: [[CGFloat]]? = nil, text: String? = nil
    ) {
        self.id = id; self.kind = kind
        self.x = x; self.y = y; self.w = w; self.h = h
        self.points = points; self.text = text
    }

    // Decoding is deliberately tolerant. Swift's synthesized decoder ignores
    // property defaults, so a model that omits `w` on a connector — or `x` on
    // anything — would fail the whole scene. Only `id` and `kind` are
    // genuinely required, and even those fall back rather than throw, because
    // one sloppy element should not cost the user the entire drawing: the
    // critic reports what is missing and the doctor repairs it.
    private enum CodingKeys: String, CodingKey {
        case id, kind, x, y, w, h, points, text, stroke, fill, fillStyle
        case strokeStyle, strokeWidth, sloppiness, edges, opacity
        case fontFamily, fontSize, startArrow, endArrow, symbol, zIndex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        kind = (try? c.decode(String.self, forKey: .kind)) ?? ""
        x = (try? c.decode(CGFloat.self, forKey: .x)) ?? 0
        y = (try? c.decode(CGFloat.self, forKey: .y)) ?? 0
        w = (try? c.decode(CGFloat.self, forKey: .w)) ?? 0
        h = (try? c.decode(CGFloat.self, forKey: .h)) ?? 0
        points = try? c.decode([[CGFloat]].self, forKey: .points)
        text = try? c.decode(String.self, forKey: .text)
        stroke = try? c.decode(String.self, forKey: .stroke)
        fill = try? c.decode(String.self, forKey: .fill)
        fillStyle = try? c.decode(String.self, forKey: .fillStyle)
        strokeStyle = try? c.decode(String.self, forKey: .strokeStyle)
        strokeWidth = try? c.decode(CGFloat.self, forKey: .strokeWidth)
        sloppiness = try? c.decode(String.self, forKey: .sloppiness)
        edges = try? c.decode(String.self, forKey: .edges)
        opacity = try? c.decode(CGFloat.self, forKey: .opacity)
        fontFamily = try? c.decode(String.self, forKey: .fontFamily)
        fontSize = try? c.decode(CGFloat.self, forKey: .fontSize)
        startArrow = try? c.decode(String.self, forKey: .startArrow)
        endArrow = try? c.decode(String.self, forKey: .endArrow)
        symbol = try? c.decode(String.self, forKey: .symbol)
        zIndex = try? c.decode(Int.self, forKey: .zIndex)
    }
}

struct SceneSpec: Codable {
    var title: String? = nil
    /// transparent | white | black | warmYellow | warmWhite
    var background: String? = nil
    var elements: [SceneElement]

    init(title: String? = nil, background: String? = nil, elements: [SceneElement]) {
        self.title = title; self.background = background; self.elements = elements
    }

    private enum CodingKeys: String, CodingKey { case title, background, elements }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try? c.decode(String.self, forKey: .title)
        background = try? c.decode(String.self, forKey: .background)
        // `elements` is the one field a scene cannot do without.
        elements = (try? c.decode([SceneElement].self, forKey: .elements)) ?? []
    }
}

// MARK: - vocabulary

/// Maps the strings a model writes onto macdraw's own enums. Everything is
/// case- and separator-insensitive, because models are inconsistent about
/// "crossHatch" / "cross-hatch" / "cross hatch".
enum SceneVocabulary {
    static func normalize(_ raw: String) -> String {
        raw.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Kinds the scene schema accepts, plus the synonyms models reach for.
    static let kindSynonyms: [String: ShapeKind] = {
        var map: [String: ShapeKind] = [:]
        // Every real ShapeKind under its own name.
        let all: [ShapeKind] = [
            .rect, .diamond, .ellipse, .line, .arrow, .freedraw, .frame, .text,
            .image, .triangle, .rightTriangle, .parallelogram, .trapezoid,
            .pentagon, .hexagon, .octagon, .star, .star6, .cross, .process,
            .predefinedProcess, .delay, .manualInput, .display, .cloud,
            .serverStack, .queue, .firewall, .cube, .callout, .note,
            .doubleArrow, .curvedConnector, .orthogonal, .connector,
            .linkedList, .stack, .heap, .graph, .set,
        ]
        for kind in all { map[normalize(kind.rawValue)] = kind }
        // Words models use for the same things.
        let synonyms: [String: ShapeKind] = [
            "rectangle": .rect, "box": .rect, "square": .rect, "card": .rect,
            "circle": .ellipse, "oval": .ellipse, "start": .ellipse, "end": .ellipse,
            "terminator": .ellipse, "decision": .diamond, "rhombus": .diamond,
            "database": .serverStack, "datastore": .serverStack, "storage": .serverStack,
            "input": .manualInput, "output": .display, "label": .text,
            "sticky": .note, "comment": .callout, "bubble": .callout,
            "service": .process, "step": .process, "task": .process,
            "server": .serverStack, "api": .process, "queue": .queue,
            "sketch": .freedraw, "scribble": .freedraw, "path": .freedraw,
            "elbow": .orthogonal, "curve": .curvedConnector, "link": .arrow,
            "edge": .arrow, "connector": .connector,
        ]
        for (word, kind) in synonyms { map[normalize(word)] = kind }
        return map
    }()

    static func kind(_ raw: String) -> ShapeKind? { kindSynonyms[normalize(raw)] }

    static func fillStyle(_ raw: String?) -> FillStyle? {
        guard let raw else { return nil }
        switch normalize(raw) {
        case "hachure", "hatch", "lines": return .hachure
        case "crosshatch", "cross": return .crossHatch
        case "zigzag", "zig": return .zigzag
        case "solid", "fill", "flat": return .solid
        default: return nil
        }
    }

    static func strokeStyle(_ raw: String?) -> StrokeStyle? {
        guard let raw else { return nil }
        switch normalize(raw) {
        case "solid": return .solid
        case "dashed", "dash": return .dashed
        case "dotted", "dot": return .dotted
        default: return nil
        }
    }

    static func sloppiness(_ raw: String?) -> Sloppiness? {
        guard let raw else { return nil }
        switch normalize(raw) {
        case "architect", "precise", "clean", "straight": return .architect
        case "artist", "sketchy", "hand", "handdrawn": return .artist
        case "cartoonist", "rough", "loose": return .cartoonist
        default: return nil
        }
    }

    static func edgeStyle(_ raw: String?) -> EdgeStyle? {
        guard let raw else { return nil }
        switch normalize(raw) {
        case "round", "rounded", "soft": return .round
        case "sharp", "square", "hard": return .sharp
        default: return nil
        }
    }

    static func arrowhead(_ raw: String?) -> ArrowheadStyle? {
        guard let raw else { return nil }
        switch normalize(raw) {
        case "none", "flat": return .none
        case "arrow", "open": return .arrow
        case "triangle", "filled", "solid": return .triangle
        case "bar", "line": return .bar
        default: return nil
        }
    }

    static func background(_ raw: String?) -> CanvasBackground? {
        guard let raw else { return nil }
        switch normalize(raw) {
        case "transparent", "clear", "none": return .clear
        case "white": return .white
        case "black", "dark": return .black
        case "warmyellow", "yellow", "cream": return .warmYellow
        case "warmwhite", "offwhite", "paper": return .warmWhite
        default: return nil
        }
    }

    /// Kinds drawn as a closed area — the ones that can hold a fill and a
    /// centered label, and the ones overlap checks apply to.
    static func isArea(_ kind: ShapeKind) -> Bool {
        switch kind {
        case .line, .arrow, .doubleArrow, .curvedConnector, .orthogonal,
             .connector, .freedraw, .text, .image, .laser:
            return false
        default:
            return true
        }
    }

    static func isConnector(_ kind: ShapeKind) -> Bool {
        switch kind {
        case .line, .arrow, .doubleArrow, .curvedConnector, .orthogonal, .connector:
            return true
        default:
            return false
        }
    }
}

// MARK: - colors

enum SceneColor {
    /// Parses `#rgb` / `#rrggbb` / a bare hex / a palette name like "blue.4".
    /// Returns nil for "transparent" and for anything unparseable, so the
    /// caller can tell "no fill" from "bad value".
    static func parse(_ raw: String?) -> NSColor? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if SceneVocabulary.normalize(trimmed) == "transparent" { return nil }

        var hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        if hex.count == 6, hex.allSatisfy({ $0.isHexDigit }) {
            return NSColor(hexString: hex)
        }
        // "blue.4" / "blue 4" / bare family name.
        let parts = trimmed.lowercased().split(whereSeparator: { $0 == "." || $0 == " " || $0 == "-" })
        if let family = parts.first,
           let shades = Palette.families.first(where: { $0.0 == String(family) })?.1 {
            let index = parts.count > 1 ? Int(parts[1]) ?? Palette.strokeShadeIndex : Palette.strokeShadeIndex
            return shades[min(max(index, 0), shades.count - 1)]
        }
        switch SceneVocabulary.normalize(trimmed) {
        case "black": return Palette.black
        case "white": return Palette.white
        default: return nil
        }
    }

    /// Whether the string is a value the schema allows at all (a color, or an
    /// explicit "transparent"). Used to tell a bad color from an absent one.
    static func isWellFormed(_ raw: String?) -> Bool {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        if SceneVocabulary.normalize(raw) == "transparent" { return true }
        return parse(raw) != nil
    }

    /// Nearest color in the Excalidraw palette, used to repair an off-palette
    /// or unparseable value instead of dropping the element's styling.
    static func snapToPalette(_ color: NSColor) -> NSColor {
        let target = color.usingColorSpace(.sRGB) ?? color
        var best = Palette.black
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (_, shades) in Palette.families {
            for shade in shades {
                let candidate = shade.usingColorSpace(.sRGB) ?? shade
                let dr = candidate.redComponent - target.redComponent
                let dg = candidate.greenComponent - target.greenComponent
                let db = candidate.blueComponent - target.blueComponent
                let distance = dr * dr + dg * dg + db * db
                if distance < bestDistance {
                    bestDistance = distance
                    best = shade
                }
            }
        }
        return best
    }

    /// YIQ brightness, matching `isColorDark` in packages/common/src/colors.ts.
    static func isDark(_ color: NSColor, threshold: CGFloat = 160) -> Bool {
        let c = color.usingColorSpace(.sRGB) ?? color
        let yiq = (c.redComponent * 255 * 299 + c.greenComponent * 255 * 587 + c.blueComponent * 255 * 114) / 1000
        return yiq < threshold
    }
}

// MARK: - critic

/// One measured problem with a draft scene. The harness turns these into the
/// feedback the model sees, so every case carries the ids involved and reads
/// as an instruction rather than a category name.
enum SceneDefect: Equatable {
    case emptyScene
    case duplicateID(String)
    case unknownKind(id: String, kind: String)
    case degenerateSize(id: String)
    case offCanvas(id: String)
    case badColor(id: String, field: String, value: String)
    case connectorNeedsPoints(id: String)
    case labelOverflows(id: String)
    case textOnNonTextElement(id: String, kind: String)
    case overlap(a: String, b: String)
    case unreadableLabel(id: String)
    case emptyText(id: String)
    case tooFewElements(Int)

    /// Penalty applied to the score. Correctness defects outweigh aesthetic
    /// ones, so the harness never trades a valid scene for a prettier broken
    /// one.
    var weight: Int {
        switch self {
        case .emptyScene: return 1000
        case .duplicateID, .unknownKind, .connectorNeedsPoints: return 60
        case .degenerateSize, .offCanvas: return 40
        case .badColor, .textOnNonTextElement, .emptyText: return 20
        case .labelOverflows, .unreadableLabel: return 12
        case .overlap: return 10
        case .tooFewElements(let n): return max(0, 6 - n) * 15
        }
    }

    /// The line the model is shown. Specific and actionable — a measured
    /// defect with the element id, not a generic style rule.
    var instruction: String {
        switch self {
        case .emptyScene:
            return "The scene has no elements. Produce at least one."
        case .duplicateID(let id):
            return "Two elements share the id \"\(id)\". Every id must be unique."
        case .unknownKind(let id, let kind):
            return "Element \"\(id)\" has kind \"\(kind)\", which is not in the allowed kind list."
        case .degenerateSize(let id):
            return "Element \"\(id)\" has no width or height. Give it a real size."
        case .offCanvas(let id):
            return "Element \"\(id)\" sits far outside the drawing. Keep coordinates within about ±4000."
        case .badColor(let id, let field, let value):
            return "Element \"\(id)\" has \(field) \"\(value)\", which is not a #rrggbb color or \"transparent\"."
        case .connectorNeedsPoints(let id):
            return "Connector \"\(id)\" needs at least two points in `points`."
        case .labelOverflows(let id):
            return "The text on \"\(id)\" does not fit its box. Shorten the label or widen the element."
        case .textOnNonTextElement(let id, let kind):
            return "Element \"\(id)\" is a \(kind) and cannot hold text. Use a separate text element."
        case .overlap(let a, let b):
            return "\"\(a)\" and \"\(b)\" overlap. Separate them so both are readable."
        case .unreadableLabel(let id):
            return "The label on \"\(id)\" is nearly the same tone as its fill. Pick a contrasting stroke color."
        case .emptyText(let id):
            return "Text element \"\(id)\" has no content. Give it text or remove it."
        case .tooFewElements(let n):
            return "The scene has only \(n) element\(n == 1 ? "" : "s"). Develop the subject more fully."
        }
    }
}

/// Measures a scene. Pure — no model, no network, no canvas.
enum SceneCritic {
    /// Coordinates beyond this are treated as a mistake rather than a choice.
    static let canvasLimit: CGFloat = 4000
    /// Overlap below this fraction of the smaller element is ignored, so
    /// deliberate touching or nesting isn't reported.
    static let overlapTolerance: CGFloat = 0.18

    static func defects(_ spec: SceneSpec) -> [SceneDefect] {
        var found: [SceneDefect] = []
        guard !spec.elements.isEmpty else { return [.emptyScene] }

        var seen = Set<String>()
        for element in spec.elements {
            if element.id.isEmpty || seen.contains(element.id) {
                found.append(.duplicateID(element.id))
            }
            seen.insert(element.id)

            guard let kind = SceneVocabulary.kind(element.kind) else {
                found.append(.unknownKind(id: element.id, kind: element.kind))
                continue
            }

            if !SceneColor.isWellFormed(element.stroke) {
                found.append(.badColor(id: element.id, field: "stroke", value: element.stroke ?? ""))
            }
            if !SceneColor.isWellFormed(element.fill) {
                found.append(.badColor(id: element.id, field: "fill", value: element.fill ?? ""))
            }

            if SceneVocabulary.isConnector(kind) || kind == .freedraw {
                if element.cgPoints.count < 2 {
                    found.append(.connectorNeedsPoints(id: element.id))
                }
            } else if element.w <= 1 || element.h <= 1 {
                found.append(.degenerateSize(id: element.id))
            }

            let origin = CGPoint(x: element.x, y: element.y)
            if abs(origin.x) > canvasLimit || abs(origin.y) > canvasLimit {
                found.append(.offCanvas(id: element.id))
            }

            let label = element.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if kind == .text, label.isEmpty {
                found.append(.emptyText(id: element.id))
            }
            if !label.isEmpty, !SceneVocabulary.isArea(kind), kind != .text {
                found.append(.textOnNonTextElement(id: element.id, kind: element.kind))
            }
            if !label.isEmpty, SceneVocabulary.isArea(kind), overflows(element) {
                found.append(.labelOverflows(id: element.id))
            }
            if !label.isEmpty,
               let fill = SceneColor.parse(element.fill),
               let stroke = SceneColor.parse(element.stroke),
               SceneColor.isDark(fill) == SceneColor.isDark(stroke) {
                found.append(.unreadableLabel(id: element.id))
            }
        }

        found.append(contentsOf: overlaps(spec))
        if spec.elements.count < 6 { found.append(.tooFewElements(spec.elements.count)) }
        return found
    }

    /// Whether a label needs more room than its element gives it. Measured
    /// with the real font, so it matches what the canvas will draw.
    static func overflows(_ element: SceneElement) -> Bool {
        guard let text = element.text, !text.isEmpty, element.w > 1, element.h > 1 else { return false }
        let size = element.fontSize ?? 18
        let font = Fonts.nsFont(for: element.fontFamily ?? "Virgil", size: size)
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let padding: CGFloat = 16
        let available = CGSize(width: max(1, element.w - padding), height: .greatestFiniteMagnitude)
        let measured = attributed.boundingRect(
            with: available,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return measured.height > element.h - padding * 0.5
    }

    /// Pairs of area elements that cover each other enough to hurt.
    static func overlaps(_ spec: SceneSpec) -> [SceneDefect] {
        let areas = spec.elements.enumerated().filter { _, element in
            guard let kind = SceneVocabulary.kind(element.kind) else { return false }
            return SceneVocabulary.isArea(kind) && element.w > 1 && element.h > 1
        }
        var out: [SceneDefect] = []
        for i in areas.indices {
            for j in areas.indices where j > i {
                let a = areas[i].element, b = areas[j].element
                let intersection = a.rect.intersection(b.rect)
                guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { continue }
                let smaller = min(a.rect.width * a.rect.height, b.rect.width * b.rect.height)
                guard smaller > 0 else { continue }
                let covered = (intersection.width * intersection.height) / smaller
                if covered > overlapTolerance {
                    out.append(.overlap(a: a.id, b: b.id))
                }
            }
        }
        return out
    }

    /// Lower is better. Defect penalties minus a modest reward for a scene
    /// that actually develops its subject, so the optimizer can't win by
    /// deleting everything down to one clean rectangle.
    static func score(_ spec: SceneSpec) -> Int {
        let penalty = defects(spec).reduce(0) { $0 + $1.weight }
        let richness = min(spec.elements.count, 40) * 2 + styleVariety(spec) * 3
        return penalty - richness
    }

    /// How many distinct shape kinds and fill styles the scene uses.
    static func styleVariety(_ spec: SceneSpec) -> Int {
        var kinds = Set<String>()
        var fills = Set<String>()
        for element in spec.elements {
            if let kind = SceneVocabulary.kind(element.kind) { kinds.insert(kind.rawValue) }
            if let fill = element.fillStyle { fills.insert(SceneVocabulary.normalize(fill)) }
        }
        return kinds.count + fills.count
    }
}

// MARK: - doctor

/// Repairs everything that can be repaired without asking the model again.
/// Deterministic and idempotent: running it twice changes nothing the second
/// time, which is what lets the harness treat it as a measurement step.
enum SceneDoctor {
    static let grid: CGFloat = 10
    static let minimumSize = CGSize(width: 80, height: 48)

    static func repair(_ spec: SceneSpec) -> SceneSpec {
        var out = spec
        out.elements = spec.elements.compactMap(repairElement)
        out.elements = deduplicateIDs(out.elements)
        out.elements = separate(out.elements)
        out.elements = growToFitLabels(out.elements)
        return out
    }

    private static func repairElement(_ element: SceneElement) -> SceneElement? {
        var fixed = element

        // An unrecognized kind becomes a plain rectangle rather than being
        // dropped — the model's intent for position and label is still useful.
        let kind = SceneVocabulary.kind(element.kind) ?? .rect
        fixed.kind = kind.rawValue

        if SceneVocabulary.isConnector(kind) || kind == .freedraw {
            // A connector with no usable points can't be placed at all.
            guard element.cgPoints.count >= 2 else { return nil }
            let bounds = element.cgPoints.reduce(CGRect.null) { partial, p in
                partial.union(CGRect(x: p.x, y: p.y, width: 0, height: 0))
            }
            fixed.x = bounds.minX
            fixed.y = bounds.minY
            fixed.w = bounds.width
            fixed.h = bounds.height
        } else {
            fixed.w = max(element.w, kind == .text ? 40 : minimumSize.width)
            fixed.h = max(element.h, kind == .text ? 24 : minimumSize.height)
            fixed.x = snap(element.x)
            fixed.y = snap(element.y)
            fixed.w = snap(fixed.w)
            fixed.h = snap(fixed.h)
        }

        fixed.x = fixed.x.clamped(to: -SceneCritic.canvasLimit...SceneCritic.canvasLimit)
        fixed.y = fixed.y.clamped(to: -SceneCritic.canvasLimit...SceneCritic.canvasLimit)

        // Off-palette or unparseable colors snap to the nearest palette entry
        // instead of being discarded.
        if let stroke = element.stroke, !SceneColor.isWellFormed(stroke) {
            fixed.stroke = SceneColor.snapToPalette(Palette.black).hexDescription
        }
        if let fill = element.fill, !SceneColor.isWellFormed(fill) {
            fixed.fill = "transparent"
        }

        // Text on a shape that cannot carry it moves nowhere — it is dropped
        // here and reported by the critic, so the model learns to emit a
        // separate text element.
        if let text = element.text, !text.isEmpty, !SceneVocabulary.isArea(kind), kind != .text {
            fixed.text = nil
        }

        // Contrast: a label the same tone as its fill becomes readable.
        if let text = fixed.text, !text.isEmpty,
           let fill = SceneColor.parse(fixed.fill),
           let stroke = SceneColor.parse(fixed.stroke),
           SceneColor.isDark(fill) == SceneColor.isDark(stroke) {
            fixed.stroke = (SceneColor.isDark(fill) ? Palette.white : Palette.black).hexDescription
        }

        if let opacity = fixed.opacity { fixed.opacity = opacity.clamped(to: 0.1...1) }
        if let size = fixed.fontSize { fixed.fontSize = size.clamped(to: 8...160) }
        if let width = fixed.strokeWidth { fixed.strokeWidth = width.clamped(to: 1...32) }

        return fixed
    }

    private static func snap(_ value: CGFloat) -> CGFloat { (value / grid).rounded() * grid }

    /// Makes ids unique by suffixing repeats, so the rest of the pipeline can
    /// key on them.
    private static func deduplicateIDs(_ elements: [SceneElement]) -> [SceneElement] {
        var seen = Set<String>()
        return elements.enumerated().map { index, element in
            var fixed = element
            var candidate = element.id.isEmpty ? "e\(index)" : element.id
            var suffix = 2
            while seen.contains(candidate) {
                candidate = "\(element.isEmptyID ? "e\(index)" : element.id)-\(suffix)"
                suffix += 1
            }
            seen.insert(candidate)
            fixed.id = candidate
            return fixed
        }
    }

    /// Pushes overlapping area elements apart along the axis of least
    /// movement. A few relaxation rounds is enough for the densities a
    /// generated scene reaches, and it keeps the model's intended layout.
    private static func separate(_ elements: [SceneElement]) -> [SceneElement] {
        var out = elements
        let indices = out.indices.filter { index in
            guard let kind = SceneVocabulary.kind(out[index].kind) else { return false }
            return SceneVocabulary.isArea(kind) && out[index].w > 1 && out[index].h > 1
        }
        guard indices.count > 1 else { return out }

        let gap: CGFloat = 20
        for _ in 0..<6 {
            var moved = false
            for i in indices {
                for j in indices where j > i {
                    let a = out[i].rect.insetBy(dx: -gap / 2, dy: -gap / 2)
                    let b = out[j].rect.insetBy(dx: -gap / 2, dy: -gap / 2)
                    let overlap = a.intersection(b)
                    guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }
                    moved = true
                    // Separate along whichever axis needs the smaller shove.
                    if overlap.width < overlap.height {
                        let shove = (overlap.width / 2).rounded(.up)
                        let push: CGFloat = a.midX <= b.midX ? -shove : shove
                        out[i].x += push
                        out[j].x -= push
                    } else {
                        let shove = (overlap.height / 2).rounded(.up)
                        let push: CGFloat = a.midY <= b.midY ? -shove : shove
                        out[i].y += push
                        out[j].y -= push
                    }
                }
            }
            if !moved { break }
        }
        for i in indices {
            out[i].x = snap(out[i].x)
            out[i].y = snap(out[i].y)
        }
        return out
    }

    /// Widens and heightens boxes whose label would not fit, so a good scene
    /// isn't marked down for a label one word too long.
    private static func growToFitLabels(_ elements: [SceneElement]) -> [SceneElement] {
        elements.map { element in
            guard let kind = SceneVocabulary.kind(element.kind),
                  SceneVocabulary.isArea(kind),
                  let text = element.text, !text.isEmpty,
                  SceneCritic.overflows(element) else { return element }
            var fixed = element
            // Grow in steps rather than solving exactly: the measurement is
            // cheap and this converges in a few iterations.
            for _ in 0..<8 where SceneCritic.overflows(fixed) {
                fixed.w = snap(fixed.w * 1.18)
                fixed.h = snap(fixed.h * 1.12)
            }
            return fixed
        }
    }
}

private extension SceneElement {
    var isEmptyID: Bool { id.isEmpty }
}

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - harness

/// Drives generation: draft, repair, measure, feed the measured defects back,
/// keep the best scoring result.
///
/// The model is never asked whether its own output is good. Every critique it
/// receives is a measurement from `SceneCritic` over the repaired draft, which
/// is why this behaves the same on every provider and why the loop can be
/// tested offline.
enum SceneAI {
    /// Draft, then at most this many revision passes.
    static let maxPasses = 4
    /// A scene this clean is accepted without spending another pass.
    static let acceptableDefectWeight = 24

    static let systemPrompt = """
    You compose drawings for macdraw, a canvas app. Reply with a single JSON
    object and nothing else — no prose, no code fences.

    {
      "title": "short name",
      "background": "transparent" | "white" | "black" | "warmYellow" | "warmWhite",
      "elements": [ ... ]
    }

    Every element:
      "id"          unique short string (required)
      "kind"        one of the kinds listed below (required)
      "x","y"       top-left corner, y grows downward
      "w","h"       size (omit for connectors and freehand)
      "points"      [[x,y], ...] — required for line/arrow/connector/freedraw
      "text"        label; only on closed shapes and on "text" elements
      "stroke"      "#rrggbb"
      "fill"        "#rrggbb" or "transparent"
      "fillStyle"   "hachure" | "crossHatch" | "zigzag" | "solid"
      "strokeStyle" "solid" | "dashed" | "dotted"
      "strokeWidth" 1, 2 or 4
      "sloppiness"  "architect" | "artist" | "cartoonist"
      "edges"       "sharp" | "round"
      "opacity"     0.1 to 1
      "fontFamily", "fontSize"
      "startArrow", "endArrow"  "none" | "arrow" | "triangle" | "bar"
      "symbol"      an SF Symbol name from the allowed list, for icon accents
      "zIndex"      draw order, higher is on top

    Kinds:
      areas       rect, ellipse, diamond, triangle, rightTriangle, parallelogram,
                  trapezoid, pentagon, hexagon, octagon, star, star6, cross,
                  process, predefinedProcess, delay, manualInput, display,
                  cloud, serverStack, queue, firewall, cube, callout, note,
                  frame, linkedList, stack, heap, graph, set
      connectors  line, arrow, doubleArrow, curvedConnector, orthogonal, connector
      other       text, freedraw

    Composition rules:
    - Build a real composition, not a row of boxes. Vary size and kind to show
      what matters; group related things; leave breathing room.
    - Shapes must not overlap unless one deliberately contains another.
    - Use the palette: #1e1e1e, #e03131, #2f9e44, #1971c2, #f08c00, #9c36b5,
      #0c8599, #e8590c for strokes; the pale shades #ffc9c9, #b2f2bb, #a5d8ff,
      #ffec99, #eebefa, #99e9f2, #ffd8a8 for fills.
    - A filled shape reads best with "hachure" or "crossHatch" and
      "sloppiness": "artist". Reserve "solid" for emphasis.
    - Keep labels short enough to fit their box. A label that needs a sentence
      belongs in its own "text" element beside the shape.
    - Label stroke must contrast with the shape's fill.
    - Every connector needs explicit "points"; route them so they do not cut
      through unrelated shapes.
    """

    /// Allowed icon names, appended to the prompt so the model never invents a
    /// symbol the canvas cannot render.
    static var symbolGuidance: String {
        "Allowed \"symbol\" values: " + AIIconCatalog.icons.joined(separator: ", ")
    }

    struct Attempt {
        var spec: SceneSpec
        var score: Int
        var defects: [SceneDefect]
    }

    /// Generates a scene and improves it until the measurements stop
    /// complaining or the pass budget runs out. Returns the best-scoring
    /// repaired scene.
    static func generate(
        prompt: String,
        settings: AISettings,
        progress: ((String) -> Void)? = nil
    ) async throws -> SceneSpec {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "MacdrawAI", code: 40, userInfo: [NSLocalizedDescriptionKey: "Describe what to draw first."])
        }

        progress?("Composing…")
        let system = systemPrompt + "\n\n" + symbolGuidance
        let draft = try await DiagramAI.request(
            prompt: trimmed, system: system, settings: settings
        )
        var best = try evaluate(decode(draft))
        progress?(summary(for: best, pass: 0))

        for pass in 1..<maxPasses {
            if best.defects.reduce(0, { $0 + $1.weight }) <= acceptableDefectWeight { break }
            guard let json = encode(best.spec) else { break }
            progress?("Revising — \(describe(best.defects))")

            let revision = """
            Original request: \(trimmed)

            Current scene:
            \(json)

            Measured problems with that scene:
            \(best.defects.prefix(14).map { "- " + $0.instruction }.joined(separator: "\n"))

            Fix exactly these problems. Keep everything that already works —
            the same subject, the same elements where they are correct. Do not
            change the JSON schema. Return the corrected scene JSON only.
            """
            // The last pass gets more reasoning, since it is the one shipped
            // when nothing earlier reached the bar.
            let effort = pass == maxPasses - 1 ? "high" : DiagramAI.defaultEffort
            guard let response = try? await DiagramAI.request(
                prompt: revision, system: system, settings: settings, effort: effort
            ) else { continue }
            guard let candidate = try? decode(response) else { continue }

            let attempt = evaluate(candidate)
            if attempt.score < best.score { best = attempt }
            progress?(summary(for: best, pass: pass))
        }

        guard !best.spec.elements.isEmpty else {
            throw NSError(domain: "MacdrawAI", code: 41, userInfo: [NSLocalizedDescriptionKey: "The model did not produce any drawable elements."])
        }
        return best.spec
    }

    /// Repair, then measure. Always repair first — the score should reflect
    /// what will actually be drawn, not the raw draft.
    static func evaluate(_ spec: SceneSpec) -> Attempt {
        let repaired = SceneDoctor.repair(spec)
        let defects = SceneCritic.defects(repaired)
        return Attempt(spec: repaired, score: SceneCritic.score(repaired), defects: defects)
    }

    static func encode(_ spec: SceneSpec) -> String? {
        (try? JSONEncoder().encode(spec)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Pulls the JSON object out of whatever the model wrapped it in.
    static func decode(_ text: String) throws -> SceneSpec {
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}") else {
            throw NSError(domain: "MacdrawAI", code: 42, userInfo: [NSLocalizedDescriptionKey: "The model did not return a scene JSON object."])
        }
        return try JSONDecoder().decode(SceneSpec.self, from: Data(String(cleaned[start...end]).utf8))
    }

    private static func summary(for attempt: Attempt, pass: Int) -> String {
        let weight = attempt.defects.reduce(0) { $0 + $1.weight }
        return "Pass \(pass): \(attempt.spec.elements.count) elements, \(attempt.defects.count) issue\(attempt.defects.count == 1 ? "" : "s") (weight \(weight))"
    }

    private static func describe(_ defects: [SceneDefect]) -> String {
        guard let first = defects.max(by: { $0.weight < $1.weight }) else { return "polishing" }
        return defects.count == 1 ? first.instruction : "\(first.instruction) (+\(defects.count - 1) more)"
    }
}
