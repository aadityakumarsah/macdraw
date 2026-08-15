import SwiftUI
import AppKit

struct ToolbarView: View {
    @ObservedObject var state: CanvasState
    let onClose: () -> Void
    let onUndo: () -> Void
    let onClear: () -> Void
    let onActivate: () -> Void
    let onDeactivate: () -> Void

    enum ColorTarget {
        case stroke
        case fill
    }

    @State private var showShortcuts = false
    @State private var colorTarget: ColorTarget = .stroke

    var body: some View {
        VStack(spacing: 6) {
            if state.drawingMode {
                topRow
                bottomRow
            } else {
                Spacer(minLength: 0)
                miniBar
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .if(state.drawingMode) { view in
            view
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 14, y: 5)
        }
        .animation(.easeInOut(duration: 0.18), value: state.drawingMode)
    }

    /// Compact bar shown while drawing is paused — keeps the screen mostly
    /// click-through while leaving a way to resume drawing or close.
    private var miniBar: some View {
        HStack(spacing: 6) {
            drawToggle

            Divider().frame(height: 20)

            Button {
                showShortcuts = true
            } label: {
                Image(systemName: "keyboard")
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Keyboard shortcuts")
            .popover(isPresented: $showShortcuts, arrowEdge: .bottom) {
                ShortcutsView()
            }

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close overlay (press ⌃⌥ again)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    // MARK: - row 1: tools, draw toggle, undo/clear, keyboard, close

    private var topRow: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Tool.allCases, id: \.self) { tool in
                        ToolButton(tool: tool, active: state.tool == tool) {
                            if tool != .text {
                                state.lastNonTextTool = tool
                            }
                            state.tool = tool
                            if !state.drawingMode {
                                state.drawingMode = true
                                onActivate()
                            }
                        }
                    }

                    Divider().frame(height: 22)

                    drawToggle

                    pressureControl

                    Button(action: onUndo) {
                        Image(systemName: "arrow.uturn.backward")
                            .frame(width: 32, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Undo (⌘Z)")

                    Button(action: onClear) {
                        Image(systemName: "trash")
                            .frame(width: 32, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Clear all")
                }
            }

            Divider().frame(height: 22)

            Button {
                showShortcuts = true
            } label: {
                Image(systemName: "keyboard")
                    .frame(width: 32, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Keyboard shortcuts")
            .popover(isPresented: $showShortcuts, arrowEdge: .bottom) {
                ShortcutsView()
            }

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .frame(width: 32, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close overlay (press ⌃⌥ again)")
        }
    }

    private var drawToggle: some View {
        Button {
            if state.drawingMode {
                state.drawingMode = false
                onDeactivate()
            } else {
                state.drawingMode = true
                onActivate()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: state.drawingMode ? "pencil.line" : "pencil.slash")
                Text(state.drawingMode ? "Drawing" : "Draw")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(state.drawingMode ? .white : Color.primary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                state.drawingMode ? Color.accentColor : Color.primary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(state.drawingMode ? "Pause drawing — clicks pass through" : "Start drawing — captures your clicks")
    }

    /// Pressure control: light = uniform constant-width lines, dynamic =
    /// strokes that swell and taper like real ink. The active mode gets a
    /// purple highlight.
    private var pressureControl: some View {
        HStack(spacing: 2) {
            pressureButton(.light) {
                WaveIcon(lineWidth: 1.3, amplitude: 0.5, color: state.pressureMode == .light ? .white : .primary)
            }
            pressureButton(.dynamic) {
                WaveIcon(lineWidth: 3, amplitude: 1, color: state.pressureMode == .dynamic ? .white : .primary)
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func pressureButton(_ mode: PressureMode, @ViewBuilder icon: () -> some View) -> some View {
        Button {
            state.pressureMode = mode
        } label: {
            icon()
                .frame(width: 22, height: 14)
                .frame(width: 30, height: 24)
                .background(
                    state.pressureMode == mode
                        ? Color(red: 0.42, green: 0.4, blue: 0.86)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(
            mode == .light
                ? "Light pressure — uniform, constant-width lines"
                : "Dynamic pressure — strokes swell and taper like real ink"
        )
    }

    // MARK: - row 2: colors, fill, width, palette, font

    private var bottomRow: some View {
        HStack(spacing: 8) {
            targetPicker
            quickPicks
            Divider().frame(height: 24)
            fillToggle
            if state.fillEnabled {
                Slider(value: $state.fillOpacity, in: 0.1...1.0, step: 0.1)
                    .frame(width: 60)
                    .help("Fill opacity")
            }
            Slider(value: $state.strokeWidth, in: 1...16, step: 1)
                .frame(width: 70)
                .help("Stroke width")
            Divider().frame(height: 24)
            fullPalette
            Divider().frame(height: 24)
            backgroundPicker
            Divider().frame(height: 24)
            fontMenu
            Slider(value: $state.fontSize, in: 10...72, step: 1)
                .frame(width: 70)
                .help("Font size")
            Text("\(Int(state.fontSize))")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .frame(width: 22)
                .foregroundStyle(.secondary)
        }
    }

    private var targetPicker: some View {
        HStack(spacing: 2) {
            targetButton(.stroke) {
                Circle().fill(Color(nsColor: state.strokeColor))
            }
            targetButton(.fill) {
                Circle()
                    .fill(state.fillEnabled ? Color(nsColor: state.fillColor) : Color.clear)
                    .overlay(Circle().stroke(Color.primary.opacity(0.5), lineWidth: 1.5))
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func targetButton(_ target: ColorTarget, @ViewBuilder icon: () -> some View) -> some View {
        Button {
            colorTarget = target
        } label: {
            icon()
                .frame(width: 14, height: 14)
                .frame(width: 24, height: 22)
                .background(
                    colorTarget == target ? Color.primary.opacity(0.15) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(target == .stroke ? "Stroke color" : "Fill color")
    }

    private var quickPicks: some View {
        HStack(spacing: 4) {
            if colorTarget == .fill {
                swatch(nil, size: 20)
            }
            ForEach(
                colorTarget == .stroke
                    ? Palette.strokePicks
                    : Palette.backgroundPicks.compactMap { $0 },
                id: \.self
            ) { c in
                swatch(c, size: 20)
            }
        }
    }

    private var fillToggle: some View {
        Button {
            state.fillEnabled.toggle()
        } label: {
            Image(systemName: state.fillEnabled ? "bucket.fill" : "bucket")
                .frame(width: 24, height: 22)
                .background(
                    state.fillEnabled ? Color.primary.opacity(0.15) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Fill shapes (toggle on/off)")
    }

    private var fullPalette: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Palette.families, id: \.0) { name, shades in
                    VStack(spacing: 3) {
                        Text(name)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 3) {
                            ForEach(shades, id: \.self) { c in
                                swatch(c, size: 16)
                            }
                        }
                    }
                }
            }
        }
        .frame(height: 32)
    }

    /// Background mode — transparent, white, or black writing surface.
    private var backgroundPicker: some View {
        HStack(spacing: 2) {
            backgroundButton(.clear) {
                Rectangle()
                    .fill(Color.clear)
                    .overlay(Rectangle().stroke(Color.primary.opacity(0.5), lineWidth: 1.5))
                    .overlay(
                        Image(systemName: "slash")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    )
            }
            backgroundButton(.white) {
                Circle()
                    .fill(.white)
                    .overlay(Circle().stroke(Color.primary.opacity(0.35), lineWidth: 1))
            }
            backgroundButton(.black) {
                Circle()
                    .fill(.black)
                    .overlay(Circle().stroke(Color.primary.opacity(0.35), lineWidth: 1))
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func backgroundButton(_ bg: CanvasBackground, @ViewBuilder icon: () -> some View) -> some View {
        Button {
            state.canvasBackground = bg
        } label: {
            icon()
                .frame(width: 14, height: 14)
                .frame(width: 24, height: 22)
                .background(
                    state.canvasBackground == bg ? Color.primary.opacity(0.15) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(bg == .clear ? "Transparent background" : "\(bg.rawValue.capitalized) screen")
    }

    private func swatch(_ color: NSColor?, size: CGFloat) -> some View {
        Button {
            if let c = color {
                if colorTarget == .stroke {
                    state.strokeColor = c
                } else {
                    state.fillColor = c
                    state.fillEnabled = true
                }
            } else {
                state.fillEnabled = false
            }
        } label: {
            ZStack {
                Rectangle()
                    .fill(color.map { Color(nsColor: $0) } ?? Color.clear)
                Rectangle()
                    .stroke(Color.primary.opacity(0.35), lineWidth: 1)
                if color == nil {
                    Image(systemName: "slash")
                        .font(.system(size: size * 0.55))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(color == nil ? "No fill" : color?.hexDescription ?? "")
    }

    private var fontMenu: some View {
        Menu {
            ForEach(Fonts.available, id: \.name) { f in
                Button(f.name) { state.fontFamily = f.name }
            }
        } label: {
            Text(state.fontFamily)
                .font(.caption)
                .frame(minWidth: 80)
        }
        .fixedSize()
        .help("Text font")
    }
}

struct ToolButton: View {
    let tool: Tool
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(nsImage: SVGIconRenderer.image(named: tool.iconName, tint: .white, target: 20))
                .resizable()
                .frame(width: 20, height: 20)
                .frame(width: 32, height: 28)
                .background(
                    active ? Color.white.opacity(0.2) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(shortcutHelp(tool))
    }

    private func shortcutHelp(_ tool: Tool) -> String {
        if let key = Shortcuts.key(for: tool) {
            return "\(tool.label) — press \(key.uppercased())"
        }
        return tool.label
    }
}

struct ShortcutsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Keyboard shortcuts", systemImage: "keyboard")
                .font(.headline)
            Divider()
            ForEach(Shortcuts.all, id: \.key) { s in
                HStack {
                    Text(s.tool.label)
                        .font(.callout)
                    Spacer()
                    Text(s.key.uppercased())
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .frame(width: 24, height: 22)
                        .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                }
            }
            Divider()
            ForEach([
                ("Draw on / off", "Toolbar button"),
                ("Pause drawing", "Draw button again"),
                ("Undo", "⌘Z"),
                ("Select all", "⌘A"),
                ("Delete selection", "⌫"),
                ("Close overlay", "⌃⌥ again"),
                ("Quit macdraw", "Status bar menu"),
            ], id: \.0) { name, key in
                HStack {
                    Text(name).font(.callout)
                    Spacer()
                    Text(key).font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(width: 240)
    }
}

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

/// Small sine-wave icon used by the pressure toggle — thin for light
/// pressure, thick and taller for dynamic pressure.
struct WaveIcon: View {
    let lineWidth: CGFloat
    let amplitude: CGFloat
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            let midY = size.height / 2
            let amp = size.height * 0.26 * amplitude
            path.move(to: CGPoint(x: 1, y: midY))
            for x in stride(from: 0.0, through: size.width, by: 0.5) {
                let t = x / size.width
                path.addLine(to: CGPoint(
                    x: x,
                    y: midY - sin(t * .pi * 3) * amp
                ))
            }
            ctx.stroke(path, with: .color(color), style: SwiftUI.StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
    }
}

