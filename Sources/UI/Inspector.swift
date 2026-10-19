import AppKit
import SwiftUI

/// The property controls that sit in the second row of the toolbar: colors,
/// fill, stroke, sloppiness, edges, opacity and fonts.
///
/// They are modelled on Excalidraw's left-hand panel — the same controls, the
/// same palette, the same five shades per color — but packed into popovers so
/// the floating toolbar stays one compact bar instead of a row of sliders
/// wide enough to run off the screen.

// MARK: - swatches

/// A single color chip. `nil` means transparent, drawn as the usual
/// checkerboard rather than an empty hole.
struct ColorSwatch: View {
    let color: NSColor?
    var size: CGFloat = 20
    var selected: Bool = false
    var corner: CGFloat = 5

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(color.map { Color(nsColor: $0) } ?? Color.clear)
            .background(
                Group {
                    if color == nil {
                        Checkerboard()
                            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Color.primary.opacity(0.28), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner + 2, style: .continuous)
                    .stroke(macdrawAccent, lineWidth: selected ? 2 : 0)
                    .padding(-2.5)
            )
            .frame(width: size, height: size)
    }
}

/// The transparency checkerboard, so "no fill" reads as transparent instead
/// of as white or as a missing swatch.
struct Checkerboard: View {
    var square: CGFloat = 5

    var body: some View {
        Canvas { context, size in
            let cols = Int(ceil(size.width / square))
            let rows = Int(ceil(size.height / square))
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            for r in 0..<max(rows, 1) {
                for c in 0..<max(cols, 1) where (r + c).isMultiple(of: 2) {
                    let rect = CGRect(
                        x: CGFloat(c) * square, y: CGFloat(r) * square,
                        width: square, height: square
                    )
                    context.fill(Path(rect), with: .color(Color(white: 0.78)))
                }
            }
        }
    }
}

// MARK: - color picker

/// The full Excalidraw palette: a five-slot quick strip, the 5x3 grid of
/// named colors, the five shades of whichever color is active, and a hex
/// field for anything else.
struct ColorPickerPopover: View {
    let title: String
    /// Which shade of each color the grid shows (4 for strokes, 1 for fills).
    let shadeIndex: Int
    /// Quick picks shown across the top.
    let topPicks: [NSColor?]
    /// Whether "transparent" is offered at all (fills: yes, strokes: no).
    let allowsTransparent: Bool
    let selection: NSColor?
    let onPick: (NSColor?) -> Void

    @State private var hex: String = ""
    @State private var activeEntry: Int?

    private let columns = Array(repeating: GridItem(.fixed(26), spacing: 6), count: 5)

    private var entries: [Palette.Entry] {
        allowsTransparent
            ? Palette.pickerGrid
            : Palette.pickerGrid.filter { $0.name != "transparent" }
    }

    /// The grid row whose shades are on show: whatever the user last touched,
    /// otherwise whichever color the selection belongs to.
    private var shadeRow: [NSColor] {
        if let i = activeEntry, entries.indices.contains(i), !entries[i].shades.isEmpty {
            return entries[i].shades
        }
        if let found = Palette.locate(selection), Palette.pickerGrid.indices.contains(found.entry) {
            return Palette.pickerGrid[found.entry].shades
        }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(Array(topPicks.enumerated()), id: \.offset) { _, c in
                    Button { pick(c) } label: {
                        ColorSwatch(color: c, size: 22, selected: matches(c))
                    }
                    .buttonStyle(.plain)
                    .help(c?.hexDescription ?? "Transparent")
                }
            }

            Divider()

            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    Button {
                        activeEntry = index
                        pick(entry.swatch(at: shadeIndex))
                    } label: {
                        ColorSwatch(
                            color: entry.swatch(at: shadeIndex),
                            size: 26,
                            selected: matches(entry.swatch(at: shadeIndex))
                        )
                    }
                    .buttonStyle(.plain)
                    .help(entry.name.capitalized)
                }
            }

            if !shadeRow.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SHADES")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(Array(shadeRow.enumerated()), id: \.offset) { _, c in
                            Button { pick(c) } label: {
                                ColorSwatch(color: c, size: 22, selected: matches(c))
                            }
                            .buttonStyle(.plain)
                            .help(c.hexDescription)
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 6) {
                Text("#")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("1e1e1e", text: $hex)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit { commitHex() }
                Button("Set") { commitHex() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(macdrawAccent)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .padding(14)
        .frame(width: 210)
        .onAppear {
            hex = selection?.hexDescription.replacingOccurrences(of: "#", with: "") ?? ""
        }
    }

    private func matches(_ c: NSColor?) -> Bool {
        guard let c else { return selection == nil }
        guard let selection else { return false }
        return c.hexDescription == selection.hexDescription
    }

    private func pick(_ c: NSColor?) {
        onPick(c)
        hex = c?.hexDescription.replacingOccurrences(of: "#", with: "") ?? ""
    }

    /// Accepts `rrggbb` / `#rrggbb` / `rgb`, ignoring anything else so a
    /// half-typed value never clears the color.
    private func commitHex() {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if raw.hasPrefix("#") { raw.removeFirst() }
        if raw.count == 3 {
            raw = raw.map { "\($0)\($0)" }.joined()
        }
        guard raw.count == 6, raw.allSatisfy({ $0.isHexDigit }) else { return }
        onPick(NSColor(hexString: raw))
    }
}

// MARK: - font picker

/// Font family list where every name is drawn in its own typeface, so the
/// font is recognizable before it is applied. A SwiftUI `Menu` cannot do
/// this: its rows become AppKit menu items, which render in the system font
/// however they are styled — the font list used to look identical whichever
/// font you were looking at.
struct FontPickerPopover: View {
    @ObservedObject var state: CanvasState
    let onPick: () -> Void

    /// Excalidraw's four font sizes (FONT_SIZES in
    /// packages/common/src/constants.ts), scaled for this canvas.
    static let sizePresets: [(label: String, size: CGFloat)] = [
        ("S", 16), ("M", 20), ("L", 28), ("XL", 36),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FONT")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Fonts.available, id: \.name) { f in
                        Button {
                            state.fontFamily = f.name
                            onPick()
                        } label: {
                            HStack(spacing: 8) {
                                Text(f.name)
                                    // The whole point: each row is set in the
                                    // font it selects.
                                    .font(Fonts.font(for: f.name, size: 16))
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                if state.fontFamily == f.name {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(macdrawAccent)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                state.fontFamily == f.name
                                    ? Color.primary.opacity(0.1)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Set text in \(f.name)")
                    }
                }
            }
            .frame(height: 260)

            Divider()

            Text("SIZE")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(Self.sizePresets, id: \.label) { preset in
                    Button {
                        state.fontSize = preset.size
                    } label: {
                        Text(preset.label)
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 32, height: 24)
                            .background(
                                abs(state.fontSize - preset.size) < 0.5
                                    ? AnyShapeStyle(accentGradient)
                                    : AnyShapeStyle(Color.primary.opacity(0.08)),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("\(Int(preset.size)) pt")
                }
            }
            HStack(spacing: 6) {
                Slider(value: $state.fontSize, in: 8...160, step: 1)
                Text("\(Int(state.fontSize))")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .frame(width: 26)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 230)
    }
}

// MARK: - stroke & shape properties

/// Stroke width, stroke style, fill style, sloppiness, edges, arrowheads and
/// opacity — Excalidraw's shape properties, in one popover.
struct ShapePropertiesPopover: View {
    @ObservedObject var state: CanvasState

    /// STROKE_WIDTH in packages/common/src/constants.ts.
    private let widthPresets: [(label: String, icon: String, width: CGFloat)] = [
        ("Thin", "line.horizontal.3", 1),
        ("Bold", "line.horizontal.3", 2),
        ("Extra bold", "line.horizontal.3", 4),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("STROKE WIDTH") {
                HStack(spacing: 4) {
                    ForEach(widthPresets, id: \.label) { preset in
                        chip(
                            selected: abs(state.strokeWidth - preset.width) < 0.01,
                            help: "\(preset.label) stroke"
                        ) {
                            state.strokeWidth = preset.width
                        } label: {
                            Capsule()
                                .fill(Color.primary.opacity(0.85))
                                .frame(width: 18, height: max(1, preset.width))
                        }
                    }
                    Slider(value: $state.strokeWidth, in: 1...32, step: 1)
                        .frame(width: 72)
                        .help("Stroke width")
                    Text("\(Int(state.strokeWidth))")
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .frame(width: 20)
                        .foregroundStyle(.secondary)
                }
            }

            section("STROKE STYLE") {
                HStack(spacing: 4) {
                    ForEach(StrokeStyle.allCases, id: \.self) { style in
                        chip(selected: state.strokeStyle == style, help: style.label) {
                            state.strokeStyle = style
                        } label: {
                            StrokeStylePreview(style: style)
                        }
                    }
                }
            }

            section("FILL") {
                HStack(spacing: 4) {
                    ForEach(FillStyle.allCases, id: \.self) { style in
                        chip(selected: state.fillStyle == style, help: style.label) {
                            state.fillStyle = style
                            state.fillEnabled = true
                        } label: {
                            FillStylePreview(style: style)
                        }
                    }
                    Slider(value: $state.fillOpacity, in: 0.1...1, step: 0.05)
                        .frame(width: 70)
                        .help("Fill opacity")
                }
            }

            section("SLOPPINESS") {
                HStack(spacing: 4) {
                    ForEach(Sloppiness.allCases, id: \.self) { value in
                        chip(selected: state.sloppiness == value, help: value.label) {
                            state.sloppiness = value
                        } label: {
                            SloppinessPreview(sloppiness: value)
                        }
                    }
                }
            }

            section("EDGES") {
                HStack(spacing: 4) {
                    ForEach(EdgeStyle.allCases, id: \.self) { value in
                        chip(selected: state.edgeStyle == value, help: "\(value.label) corners") {
                            state.edgeStyle = value
                        } label: {
                            CornerPreview(style: value)
                        }
                    }
                    if state.edgeStyle != .sharp {
                        Slider(value: $state.cornerRadiusAmount, in: 1...64, step: 1)
                            .frame(width: 74)
                            .help("Corner radius")
                        Text("\(Int(state.cornerRadiusAmount))")
                            .font(.system(size: 10, weight: .semibold))
                            .monospacedDigit()
                            .frame(width: 20)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            section("ARROWHEADS") {
                HStack(spacing: 6) {
                    arrowheadRow("Start", selection: $state.arrowStart)
                    arrowheadRow("End", selection: $state.arrowEnd)
                }
            }

            section("OPACITY") {
                HStack(spacing: 6) {
                    Slider(value: $state.elementOpacity, in: 0.1...1, step: 0.1)
                    Text("\(Int(state.elementOpacity * 100))%")
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .frame(width: 34)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(width: 268)
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func chip<Label: View>(
        selected: Bool,
        help: String,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            label()
                .frame(width: 30, height: 24)
                .background(
                    selected
                        ? AnyShapeStyle(accentGradient)
                        : AnyShapeStyle(Color.primary.opacity(0.08)),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func arrowheadRow(_ title: String, selection: Binding<ArrowheadStyle>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            HStack(spacing: 3) {
                ForEach(ArrowheadStyle.allCases, id: \.self) { style in
                    Button {
                        selection.wrappedValue = style
                    } label: {
                        Image(systemName: style.iconName)
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 24, height: 20)
                            .background(
                                selection.wrappedValue == style
                                    ? AnyShapeStyle(accentGradient)
                                    : AnyShapeStyle(Color.primary.opacity(0.08)),
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("\(title): \(style.label)")
                }
            }
        }
    }
}

// MARK: - previews

/// Miniature of a stroke style, drawn the same way the canvas draws it.
struct StrokeStylePreview: View {
    let style: StrokeStyle

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 3, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width - 3, y: size.height / 2))
            let dash: [CGFloat]
            switch style {
            case .solid: dash = []
            case .dashed: dash = [4, 3]
            case .dotted: dash = [0.1, 3]
            }
            context.stroke(
                path,
                with: .color(.primary),
                style: StrokeStyleShim.make(lineWidth: 1.8, dash: dash)
            )
        }
        .frame(width: 20, height: 14)
    }
}

/// Miniature of a fill style — the real hatch angle and spacing, shrunk.
struct FillStylePreview: View {
    let style: FillStyle

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let box = Path(roundedRect: rect, cornerRadius: 2)
            context.stroke(box, with: .color(.primary.opacity(0.7)), lineWidth: 1)
            context.clip(to: box)
            switch style {
            case .solid:
                context.fill(box, with: .color(.primary.opacity(0.75)))
            case .hachure:
                context.stroke(hatch(rect, angle: -41), with: .color(.primary.opacity(0.8)), lineWidth: 1)
            case .crossHatch:
                context.stroke(hatch(rect, angle: -41), with: .color(.primary.opacity(0.8)), lineWidth: 1)
                context.stroke(hatch(rect, angle: 49), with: .color(.primary.opacity(0.8)), lineWidth: 1)
            case .zigzag:
                context.stroke(zigzag(rect), with: .color(.primary.opacity(0.8)), lineWidth: 1)
            }
        }
        .frame(width: 20, height: 16)
    }

    private func hatch(_ rect: CGRect, angle: CGFloat) -> Path {
        var path = Path()
        let radians = angle * .pi / 180
        let c = cos(radians), s = sin(radians)
        let span = sqrt(rect.width * rect.width + rect.height * rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var offset = -span / 2
        while offset <= span / 2 {
            let base = CGPoint(x: center.x - s * offset, y: center.y + c * offset)
            path.move(to: CGPoint(x: base.x - c * span, y: base.y - s * span))
            path.addLine(to: CGPoint(x: base.x + c * span, y: base.y + s * span))
            offset += 4
        }
        return path
    }

    private func zigzag(_ rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        var y = rect.minY
        var toRight = true
        while y <= rect.maxY {
            path.addLine(to: CGPoint(x: toRight ? rect.maxX : rect.minX, y: y))
            y += 4
            path.addLine(to: CGPoint(x: toRight ? rect.maxX : rect.minX, y: y))
            toRight.toggle()
        }
        return path
    }
}

/// Miniature of a corner treatment: square, a circular arc, or the
/// superellipse the Smooth option draws.
struct CornerPreview: View {
    let style: EdgeStyle

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
            var path = Path()
            switch style {
            case .sharp:
                path = Path(rect)
            case .round:
                path = Path(roundedRect: rect, cornerRadius: 5)
            case .squircle:
                // Same construction as the canvas, including the explicit
                // per-corner start and end — deriving them from one shared
                // table is what put a spur on the first corner.
                let r: CGFloat = 7
                let power: CGFloat = 0.5
                func corner(_ cx: CGFloat, _ cy: CGFloat, _ dx: CGFloat, _ dy: CGFloat, _ swapped: Bool) -> [CGPoint] {
                    (0...8).map { step in
                        let t = CGFloat(step) / 8 * (.pi / 2)
                        let a = pow(cos(t), power) * r
                        let b = pow(sin(t), power) * r
                        return swapped
                            ? CGPoint(x: cx + dx * b, y: cy + dy * a)
                            : CGPoint(x: cx + dx * a, y: cy + dy * b)
                    }
                }
                path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
                for p in corner(rect.maxX - r, rect.minY + r, 1, -1, true) { path.addLine(to: p) }
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
                for p in corner(rect.maxX - r, rect.maxY - r, 1, 1, false) { path.addLine(to: p) }
                path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
                for p in corner(rect.minX + r, rect.maxY - r, -1, 1, true) { path.addLine(to: p) }
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
                for p in corner(rect.minX + r, rect.minY + r, -1, -1, false) { path.addLine(to: p) }
                path.closeSubpath()
            }
            context.stroke(path, with: .color(.primary.opacity(0.85)), lineWidth: 1.6)
        }
        .frame(width: 20, height: 16)
    }
}

/// Miniature of the three sloppiness levels — the same line, drawn
/// progressively more by hand.
struct SloppinessPreview: View {
    let sloppiness: Sloppiness

    var body: some View {
        Canvas { context, size in
            var path = Path()
            let midY = size.height / 2
            let wobble: CGFloat
            switch sloppiness {
            case .architect: wobble = 0
            case .artist: wobble = 1.2
            case .cartoonist: wobble = 2.4
            }
            path.move(to: CGPoint(x: 2, y: midY))
            let steps = 6
            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let x = 2 + (size.width - 4) * t
                let y = midY + sin(t * 9) * wobble
                path.addLine(to: CGPoint(x: x, y: y))
            }
            context.stroke(path, with: .color(.primary), lineWidth: 1.6)
        }
        .frame(width: 20, height: 14)
    }
}

/// `SwiftUI.StrokeStyle` collides with this app's own `StrokeStyle` enum, so
/// it is reached through this shim.
enum StrokeStyleShim {
    static func make(lineWidth: CGFloat, dash: [CGFloat]) -> SwiftUI.StrokeStyle {
        SwiftUI.StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: dash)
    }
}
