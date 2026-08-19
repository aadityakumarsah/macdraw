import SwiftUI
import AppKit

/// The purple accent used across the whole toolbar for active states.
let macdrawAccent = Color(red: 0.45, green: 0.41, blue: 0.92)

let accentGradient = LinearGradient(
    colors: [
        Color(red: 0.48, green: 0.44, blue: 0.96),
        Color(red: 0.36, green: 0.32, blue: 0.86),
    ],
    startPoint: .top,
    endPoint: .bottom
)

struct ToolbarView: View {
    @ObservedObject var state: CanvasState
    @ObservedObject var pages: PagesManager
    @ObservedObject var updater: AppUpdater
    let onClose: () -> Void
    let onUndo: () -> Void
    let onClear: () -> Void
    let onResetView: () -> Void
    let onActivate: () -> Void
    let onDeactivate: () -> Void
    let onToggleCodeBlock: () -> Void
    let onInsertSymbol: (String) -> Void
    let onSwitchPage: (UUID) -> Void
    let onToggleSidebar: () -> Void
    let onToggleAI: () -> Void

    enum ColorTarget {
        case stroke
        case fill
    }

    @State private var showShortcuts = false
    @State private var showShapes = false
    @State private var showPages = false
    @State private var showUpdate = false
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
                        .fill(Color.black.opacity(0.1))
                        .allowsHitTesting(false)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
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
            Button(action: onToggleSidebar) {
                Image(systemName: state.sidebarVisible ? "sidebar.left" : "sidebar.left")
                    .frame(width: 30, height: 30)
                    .background(
                        state.sidebarVisible ? Color.white.opacity(0.14) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(state.sidebarVisible ? "Hide sidebar" : "Show sidebar")

            pagesButton

            Button(action: onToggleAI) {
                Image(systemName: "sparkles")
                    .frame(width: 30, height: 30)
                    .background(Color.purple.opacity(0.32), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Text to diagram — generate editable flowcharts with AI")

            Divider().frame(height: 22)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Tool.allCases.filter { !Tool.shapePalette.contains($0) }, id: \.self) { tool in
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

                    shapesPaletteButton

                    Divider().frame(height: 22)

                    drawToggle

                    pressureControl

                    Toggle(isOn: codeBlockBinding) {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Code")
                                .font(.system(size: 10, weight: .semibold))
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(macdrawAccent)
                    .help("Code mode — on: new text is typed as syntax-highlighted code; off: plain text")

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

                    Button(action: onResetView) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .frame(width: 32, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Reset view — zoom 100%, recenter (⌘0)")
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

            updateButton

            Text("v\(appVersion)")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.trailing, 2)
                .help("macdraw v\(appVersion)")
        }
    }

    // MARK: - pages

    /// Opens the pages popover — add, rename, delete and switch pages. Every
    /// page is its own drawing, saved forever until deleted.
    private var pagesButton: some View {
        Button {
            showPages.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(pages.currentPageName)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                showPages ? Color.white.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Pages — each page keeps its own drawing, saved forever")
        .popover(isPresented: $showPages, arrowEdge: .bottom) {
            PagesView(
                pages: pages,
                onSwitch: { id in
                    showPages = false
                    onSwitchPage(id)
                }
            )
        }
    }

    // MARK: - updates

    /// Downloads a new build when one is available on GitHub. Shows a badge
    /// while there's a newer version, and the popover reports progress while
    /// downloading. Also lets the user check manually.
    private var updateButton: some View {
        Button {
            if updater.isUpdateAvailable || updater.errorMessage != nil || updater.latestVersion != nil {
                showUpdate.toggle()
            } else {
                updater.checkNow()
            }
        } label: {
            Image(systemName: updater.checking ? "arrow.triangle.2.circlepath" : "arrow.down.circle")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
                .overlay(alignment: .topTrailing) {
                    if updater.isUpdateAvailable {
                        Circle()
                            .fill(Color(nsColor: .systemRed))
                            .frame(width: 7, height: 7)
                            .offset(x: 2, y: -2)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(updater.isUpdateAvailable
            ? "Update available: v\(appVersion) → v\(updater.latestLabel)"
            : "Check for updates")
        .popover(isPresented: $showUpdate, arrowEdge: .bottom) {
            UpdateView(updater: updater)
        }
        .onChange(of: updater.isUpdateAvailable) { _, available in
            if available {
                showUpdate = true
            }
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
                state.drawingMode
                    ? AnyShapeStyle(accentGradient)
                    : AnyShapeStyle(Color.primary.opacity(0.08)),
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
                        ? AnyShapeStyle(accentGradient)
                        : AnyShapeStyle(Color.clear),
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

    /// Two-way binding for the code-mode switch: flips the mode flag and
    /// converts any selected text annotations to / from code blocks.
    private var codeBlockBinding: Binding<Bool> {
        Binding(
            get: { state.codeBlockMode },
            set: { newValue in
                state.codeBlockMode = newValue
                onToggleCodeBlock()
            }
        )
    }

    /// Opens the shape palette popover. Always shows a recognizable icon plus
    /// a label — the active shape's icon when one is selected, otherwise a
    /// generic grid glyph — so the navbar never hides the shapes.
    private var shapesPaletteButton: some View {
        Button {
            showShapes.toggle()
        } label: {
            let activeShape = Tool.shapePalette.contains(state.tool) ? state.tool : nil
            HStack(spacing: 5) {
                Group {
                    if let s = activeShape {
                        Image(nsImage: SVGIconRenderer.image(named: s.iconName, tint: .white, target: 18))
                            .resizable()
                            .frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                Text(activeShape?.label ?? "Shapes")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                activeShape != nil
                    ? RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.28), lineWidth: 1)
                    : nil
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Shape palette — \(Tool.shapePalette.count) standardized shapes + symbols")
        .popover(isPresented: $showShapes, arrowEdge: .bottom) {
            ShapesPaletteView(state: state, onPick: {
                showShapes = false
            }, onInsertSymbol: { symbol in
                showShapes = false
                onInsertSymbol(symbol)
            })
        }
    }

    private var shapesBackground: Color {
        (Tool.shapePalette.contains(state.tool) || showShapes)
            ? macdrawAccent.opacity(0.4)
            : Color.clear
    }

    private var background: Color {
        showShapes
            ? Color.white.opacity(0.12)
            : shapesBackground
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
            strokeStyleMenu
            arrowheadMenu(title: "Start", selection: $state.arrowStart)
            arrowheadMenu(title: "End", selection: $state.arrowEnd)
            opacityControl
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

    private var strokeStyleMenu: some View {
        Menu {
            ForEach(StrokeStyle.allCases, id: \.self) { style in
                Button {
                    state.strokeStyle = style
                } label: {
                    Label(style.label, systemImage: style.iconName)
                }
            }
        } label: {
            Image(systemName: state.strokeStyle.iconName)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .help("Stroke style: \(state.strokeStyle.label)")
    }

    private func arrowheadMenu(title: String, selection: Binding<ArrowheadStyle>) -> some View {
        Menu {
            ForEach(ArrowheadStyle.allCases, id: \.self) { style in
                Button {
                    selection.wrappedValue = style
                } label: {
                    Text(style.label)
                }
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: selection.wrappedValue.iconName)
                Text(title)
                    .font(.system(size: 9, weight: .medium))
            }
            .frame(height: 22)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .help("\(title) arrowhead: \(selection.wrappedValue.label)")
    }

    private var opacityControl: some View {
        HStack(spacing: 3) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 11))
            Slider(value: $state.elementOpacity, in: 0.1...1, step: 0.1)
                .frame(width: 46)
        }
        .help("Element opacity")
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

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(nsImage: SVGIconRenderer.image(named: tool.iconName, tint: .white, target: 22))
                .resizable()
                .frame(width: 22, height: 22)
                .frame(width: 34, height: 30)
                .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    active
                        ? RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.28), lineWidth: 1)
                        : nil
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(shortcutHelp(tool))
    }

    private var background: AnyShapeStyle {
        if active {
            return AnyShapeStyle(accentGradient)
        }
        return AnyShapeStyle(hovering ? Color.white.opacity(0.12) : Color.clear)
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
            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: 8) {
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
                        ("Pan canvas", "Minimap / Space + drag / scroll"),
                        ("Zoom canvas", "Pinch / ⌘ + scroll"),
                        ("Reset view", "⌘0"),
                        ("Undo", "⌘Z"),
                        ("Copy selection", "⌘C"),
                        ("Paste", "⌘V"),
                        ("Select all", "⌘A"),
                        ("Delete selection", "⌫"),
                        ("Bend a line/arrow", "Drag its middle handle"),
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
                .padding(.trailing, 4)
            }
            .frame(height: 300)
        }
        .padding(14)
        .frame(width: 250)
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

/// Grid palette of all the standardized shapes plus the "/" symbol icons,
/// grouped into categories with a search bar on top. Picking a shape
/// activates it as the current drawing tool; picking a symbol inserts it at
/// the mouse position (like the "/" palette).
struct ShapesPaletteView: View {
    @ObservedObject var state: CanvasState
    let onPick: () -> Void
    let onInsertSymbol: (String) -> Void

    @State private var hovering: Tool?
    @State private var query = ""

    private struct ShapeGroup {
        let title: String
        let tools: [Tool]
    }

    private let groups: [ShapeGroup] = [
        ShapeGroup(title: "Basic", tools: [.rectangle, .diamond, .ellipse, .triangle, .rightTriangle, .line, .arrow]),
        ShapeGroup(title: "Polygons", tools: [.parallelogram, .trapezoid, .pentagon, .hexagon, .octagon, .star, .star6, .cross]),
        ShapeGroup(title: "Flowchart", tools: [.process, .predefinedProcess, .delay, .manualInput, .display]),
        ShapeGroup(title: "Architecture", tools: [.cloud, .serverStack, .queue, .firewall, .cube]),
        ShapeGroup(title: "Communication", tools: [.callout, .note]),
        ShapeGroup(title: "Connectors", tools: [.doubleArrow, .curvedConnector, .orthogonal, .connector]),
        ShapeGroup(title: "Data structures", tools: [.linkedList, .stack, .heap, .graph, .set]),
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)

    private var visibleGroups: [ShapeGroup] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return groups }
        return groups.compactMap { group in
            let tools = group.tools.filter { $0.label.lowercased().contains(q) }
            return tools.isEmpty ? nil : ShapeGroup(title: group.title, tools: tools)
        }
    }

    private var visibleSymbols: [LogoItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return LogoCatalog.items }
        return LogoCatalog.items.filter {
            $0.name.lowercased().contains(q) || $0.symbol.contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Search shapes or symbols…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(visibleGroups, id: \.title) { group in
                        Section {
                            ForEach(group.tools, id: \.self) { tool in
                                shapeCell(for: tool)
                            }
                        } header: {
                            Text(group.title.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 2)
                        }
                    }
                    if !visibleSymbols.isEmpty {
                        Section {
                            ForEach(visibleSymbols, id: \.id) { item in
                                symbolCell(for: item)
                            }
                        } header: {
                            Text("SYMBOLS")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 2)
                        }
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 356, height: 330)
    }

    private func shapeCell(for tool: Tool) -> some View {
        Button {
            if tool != .text {
                state.lastNonTextTool = tool
            }
            state.tool = tool
            onPick()
        } label: {
            VStack(spacing: 3) {
                Image(nsImage: SVGIconRenderer.image(named: tool.iconName, tint: .white, target: 20))
                    .resizable()
                    .frame(width: 20, height: 20)
                    .frame(width: 46, height: 32)
                    .background(
                        state.tool == tool
                            ? AnyShapeStyle(accentGradient)
                            : AnyShapeStyle(hovering == tool ? Color.primary.opacity(0.1) : Color.clear),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay(
                        state.tool == tool
                            ? RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.28), lineWidth: 1)
                            : nil
                    )
                Text(tool.label)
                    .font(.system(size: 8.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .foregroundStyle(state.tool == tool ? Color.primary : .secondary)
            }
            .frame(width: 62)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 ? tool : nil }
        .help(tool.label)
    }

    private func symbolCell(for item: LogoItem) -> some View {
        Button {
            onInsertSymbol(item.symbol)
        } label: {
            VStack(spacing: 3) {
                if let img = tintedSymbolImage(named: item.symbol, pointSize: 20, color: .white) {
                    Image(nsImage: img)
                        .resizable()
                        .frame(width: 20, height: 20)
                        .frame(width: 46, height: 32)
                        .background(
                            Color.primary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 46, height: 32)
                }
                Text(item.name)
                    .font(.system(size: 8.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 62)
        }
        .buttonStyle(.plain)
        .help("\(item.name) — inserts at the pointer")
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


// MARK: - pages popover

/// Lists every page with its name (inline rename) and description (inline
/// edit), a delete button, and a "New page" action at the bottom. Clicking a
/// row switches to that page.
struct PagesView: View {
    @ObservedObject var pages: PagesManager
    let onSwitch: (UUID) -> Void
    @State private var newPageName = ""
    @State private var newPageNote = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pages")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(pages.pages) { page in
                        PageRow(
                            page: page,
                            isCurrent: page.id == pages.currentPageID,
                            canDelete: pages.pages.count > 1,
                            onSwitch: { onSwitch(page.id) },
                            onRename: { pages.renamePage(id: page.id, to: $0) },
                            onSetNote: { pages.setNote(id: page.id, to: $0) },
                            onDelete: { pages.deletePage(id: page.id) }
                        )
                    }
                }
            }
            .frame(maxHeight: 220)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    TextField("Page name", text: $newPageName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

                    Button {
                        addPage()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 24, height: 22)
                            .background(macdrawAccent.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(.white)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Add a new page")
                }

                TextField("Description (optional)", text: $newPageNote)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    .onSubmit {
                        addPage()
                    }
            }
        }
        .padding(12)
        .frame(width: 260)
    }

    private func addPage() {
        let name = newPageName.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = pages.addPage(
            named: name.isEmpty ? "New page" : name,
            description: newPageNote
        )
        newPageName = ""
        newPageNote = ""
        onSwitch(id)
    }
}

private struct PageRow: View {
    let page: CanvasPage
    let isCurrent: Bool
    let canDelete: Bool
    let onSwitch: () -> Void
    let onRename: (String) -> Void
    let onSetNote: (String) -> Void
    let onDelete: () -> Void
    @State private var editing = false
    @State private var draft = ""
    @State private var editingNote = false
    @State private var noteDraft = ""

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isCurrent ? "doc.fill" : "doc")
                .font(.system(size: 11))
                .foregroundStyle(isCurrent ? macdrawAccent : .secondary)

            VStack(alignment: .leading, spacing: 1) {
                if editing {
                    TextField("Name", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .onSubmit {
                            onRename(draft)
                            editing = false
                        }
                        .onExitCommand {
                            editing = false
                        }
                } else {
                    Text(page.name)
                        .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                        .lineLimit(1)
                        .onTapGesture(count: 2) {
                            draft = page.name
                            editing = true
                        }
                }

                if editingNote {
                    TextField("Description", text: $noteDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10))
                        .onSubmit {
                            onSetNote(noteDraft)
                            editingNote = false
                        }
                        .onExitCommand {
                            editingNote = false
                        }
                } else if !page.note.isEmpty {
                    Text(page.note)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .onTapGesture(count: 2) {
                            noteDraft = page.note
                            editingNote = true
                        }
                } else {
                    Text("Add description…")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .onTapGesture {
                            noteDraft = ""
                            editingNote = true
                        }
                }
            }

            Spacer(minLength: 0)

            if !isCurrent {
                Button(action: onSwitch) {
                    Text("Open")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(macdrawAccent.opacity(0.85), in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(.white)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Switch to this page")
            }

            Button {
                draft = page.name
                editing = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 10))
                    .frame(width: 22, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Rename page (or double-click the name)")

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .frame(width: 22, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(canDelete ? Color.secondary : Color.secondary.opacity(0.35))
            .disabled(!canDelete)
            .help(canDelete ? "Delete this page" : "Keep at least one page")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            isCurrent ? macdrawAccent.opacity(0.16) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isCurrent {
                onSwitch()
            }
        }
    }
}

// MARK: - update popover

/// Status + action panel for the auto-updater: shows whether this build is
/// current, and lets the user download and install a newer release with
/// live progress.
struct UpdateView: View {
    @ObservedObject var updater: AppUpdater

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: statusIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(statusColor)
                Text(statusTitle)
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                if updater.checking {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(statusSubtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if updater.isUpdateAvailable, let notes = updater.releaseNotes, !notes.isEmpty {
                ScrollView {
                    Text(notes)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 90)
                .padding(6)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }

            if let error = updater.errorMessage {
                Text(error)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if updater.downloading {
                VStack(spacing: 4) {
                    ProgressView(value: updater.downloadProgress)
                        .progressViewStyle(.linear)
                        .tint(macdrawAccent)
                    Text("Downloading update… \(Int(updater.downloadProgress * 100))%")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            if updater.isUpdateAvailable, !updater.downloading {
                Button {
                    updater.downloadAndInstall()
                } label: {
                    Text("Download & Update")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            accentGradient,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)
            } else if !updater.downloading {
                Button {
                    updater.checkNow()
                } label: {
                    Text("Check again")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(macdrawAccent)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    private var statusIcon: String {
        if updater.downloading { return "arrow.down.circle.fill" }
        if updater.isUpdateAvailable { return "exclamationmark.circle.fill" }
        if updater.checking { return "arrow.triangle.2.circlepath" }
        return "checkmark.circle.fill"
    }

    private var statusColor: Color {
        if updater.isUpdateAvailable || updater.downloading { return macdrawAccent }
        if updater.errorMessage != nil { return Color(nsColor: .systemRed) }
        return Color(nsColor: .systemGreen)
    }

    private var statusTitle: String {
        if updater.downloading { return "Updating…" }
        if updater.isUpdateAvailable { return "Update available" }
        if updater.checking { return "Checking…" }
        if updater.errorMessage != nil { return "Update check failed" }
        return "You're up to date"
    }

    private var statusSubtitle: String {
        if updater.isUpdateAvailable {
            return "macdraw v\(appVersion) → v\(updater.latestLabel). The app downloads the new build, replaces itself and relaunches."
        }
        if updater.errorMessage != nil {
            return "The update server could not be reached. Check your connection and try again."
        }
        return "You're running v\(appVersion), the latest release."
    }
}
