import AppKit
import SwiftUI

/// Borderless panel that sits above everything and hosts the drawing surface.
final class OverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
    }
}

/// Full-screen container. When drawing mode is off, only the toolbar strip is
/// hit-testable; clicks anywhere else fall through to the apps below.
private final class ContainerView: NSView {
    weak var toolbarHost: NSView?
    var isDrawingMode: (() -> Bool)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        if isDrawingMode?() == false {
            guard let toolbar = toolbarHost else { return nil }
            guard toolbar.frame.contains(point) else { return nil }
            return toolbar.hitTest(convert(point, to: toolbar))
        }
        return super.hitTest(point)
    }
}

/// Animates the overlay in/out from the top-center "dynamic island" pill.
final class IslandManager {
    private let window = OverlayWindow()
    private let state: CanvasState
    private weak var canvas: CanvasView?
    private var toolbarHost: NSView?
    private var undoMonitor: Any?
    private var gestureMonitor: Any?
    private var isShowing = false
    private var isAnimating = false
    private var logoPalette: LogoPaletteView?

    var isLogoPaletteVisible: Bool { logoPalette?.superview != nil }

    /// The "/" quick-search palette, positioned near the cursor.
    func showLogoPalette() {
        guard let container = window.contentView else { return }
        let palette: LogoPaletteView
        if let existing = logoPalette {
            palette = existing
        } else {
            let p = LogoPaletteView()
            p.delegate = self
            logoPalette = p
            palette = p
        }
        palette.reload()
        if palette.superview == nil {
            container.addSubview(palette)
        }
        let cursor = container.convert(
            window.convertPoint(fromScreen: NSEvent.mouseLocation),
            from: nil
        )
        let w = palette.frame.width
        let h = palette.frame.height
        var origin = CGPoint(x: cursor.x + 12, y: cursor.y - h - 12)
        origin.x = max(12, min(origin.x, container.bounds.width - w - 12))
        origin.y = max(12, min(origin.y, container.bounds.height - h - 12))
        palette.frame.origin = origin
        palette.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            palette.animator().alphaValue = 1
        }
        window.makeFirstResponder(palette.searchField)
    }

    func closeLogoPalette() {
        guard let palette = logoPalette, palette.superview != nil else { return }
        palette.removeFromSuperview()
        window.makeFirstResponder(canvas)
    }

    init(state: CanvasState) {
        self.state = state
    }

    func toggle() {
        if isShowing && isAnimating {
            // Opening animation still running — hide once it's done.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                self?.hide()
            }
            return
        }
        isShowing ? hide() : show()
    }

    /// Test hook.
    var isOverlayVisible: Bool { isShowing }

    /// Called when the user turns drawing mode on — the app needs to be
    /// active + the window key for keyboard shortcuts and text input.
    func activate() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
    }

    /// Called when the user turns drawing mode off — give focus back.
    func deactivate() {
        window.resignKey()
    }

    func show() {
        guard !isShowing, !isAnimating else { return }
        isShowing = true
        isAnimating = true

        let screen = screenForMouse() ?? NSScreen.main ?? NSScreen.screens[0]
        let pill = pillRect(on: screen)

        window.setFrame(pill, display: false)
        window.contentView = makePillView(frame: pill)
        window.alphaValue = 0
        window.orderFrontRegardless()
        window.animator().alphaValue = 1

        animateCornerRadius(of: window.contentView, from: pill.height / 2, to: 0, duration: 0.5)

        // Opening means ready to draw — the user pressed the combo to draw.
        // Activating also makes keyboard shortcuts (E eraser, T text, ...) work.
        state.drawingMode = true
        activate()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.5
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(screen.frame, display: true)
        } completionHandler: { [weak self] in
            self?.finishShow(on: screen)
        }

        // Watchdog: if the frame animation never completes for any reason,
        // install the content anyway so the overlay can't get stuck.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.isAnimating else { return }
            self.finishShow(on: screen)
        }
    }

    private func finishShow(on screen: NSScreen) {
        guard isAnimating else { return }
        installContent(on: screen)
        isAnimating = false
    }

    func hide() {
        guard isShowing, !isAnimating else { return }
        isShowing = false
        isAnimating = true

        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens[0]

        if let cv = contentView() {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                cv.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                guard let self else { return }
                self.canvas?.commitPendingText()
                self.teardownContent()
                self.collapseToPill(on: screen)
            }
        } else {
            collapseToPill(on: screen)
        }
    }

    private func collapseToPill(on screen: NSScreen) {
        let pill = pillRect(on: screen)
        window.contentView = makePillView(frame: pill)
        window.alphaValue = 1
        animateCornerRadius(of: window.contentView, from: 0, to: pill.height / 2, duration: 0.3)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(pill, display: true)
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.window.orderOut(nil)
            self.window.alphaValue = 1
            self.isAnimating = false
        }
    }

    // MARK: - content

    private func installContent(on screen: NSScreen) {
        let container = ContainerView(frame: screen.frame)
        container.wantsLayer = true

        let canvas = CanvasView(state: state)
        canvas.frame = screen.frame
        container.addSubview(canvas)
        self.canvas = canvas

        let toolbar = NSHostingView(
            rootView: ToolbarView(
                state: state,
                onClose: { [weak self] in self?.hide() },
                onUndo: { [weak canvas] in canvas?.undo() },
                onClear: { [weak canvas] in canvas?.clearAll() },
                onResetView: { [weak canvas] in canvas?.resetView() },
                onActivate: { [weak self] in self?.activate() },
                onDeactivate: { [weak self] in self?.deactivate() },
                onToggleCodeBlock: { [weak canvas] in canvas?.toggleCodeBlock() },
                onInsertSymbol: { [weak self] symbol in
                    guard let self, let canvas = self.canvas else { return }
                    let p = canvas.convert(self.window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
                    canvas.insertSymbol(symbol, at: p)
                }
            )
        )
        toolbar.frame = CGRect(
            x: 12,
            y: screen.frame.maxY - 112,
            width: max(0, screen.frame.width - 24),
            height: 92
        )
        toolbar.alphaValue = 0
        // The toolbar is a floating HUD — pin it to dark so the white icon
        // set stays visible on any wallpaper and in any system theme.
        toolbar.appearance = NSAppearance(named: .darkAqua)
        container.addSubview(toolbar)
        toolbarHost = toolbar
        container.toolbarHost = toolbar
        container.isDrawingMode = { [weak self] in self?.state.drawingMode ?? false }

        window.contentView = container
        window.setFrame(screen.frame, display: true)
        window.makeFirstResponder(canvas)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            toolbar.animator().alphaValue = 1
        }

        undoMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let canvas = self.canvas else { return event }
            let mods = event.modifierFlags.intersection([.command, .control, .option])

            // While the "/" palette is open, every key belongs to its search
            // field (including Esc, which closes it).
            if self.isLogoPaletteVisible { return event }

            // While a text block is being edited every key belongs to it —
            // Esc commits it, Cmd+A selects all its text (this app has no
            // menu bar, so the ⌘A key equivalent never reaches the field),
            // and everything else goes to the editor.
            if canvas.isEditingText {
                if self.handleEditingKey(event, canvas: canvas) { return nil }
                return event
            }

            // While a search field is focused (the "/" palette or the shapes
            // palette search), keys belong to it — never trigger tools from
            // typing a shortcut letter into a search box.
            if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView {
                return event
            }

            if event.keyCode == 53 { // Esc — the canvas clears its selection
                return event
            }
            if !mods.isEmpty {
                if mods.contains(.command), event.charactersIgnoringModifiers == "z" {
                    canvas.undo()
                    return nil
                }
                return event
            }
            if event.charactersIgnoringModifiers == "/", !mods.contains(.command) {
                if self.state.drawingMode { self.showLogoPalette() }
                return nil
            }
            if !self.state.drawingMode { return event }
            if event.keyCode == 51 { // delete
                canvas.deleteSelected()
                return nil
            }
            if let key = event.charactersIgnoringModifiers?.lowercased(),
               let tool = Shortcuts.tool(for: key) {
                if tool != .text {
                    self.state.lastNonTextTool = tool
                }
                self.state.tool = tool
                return nil
            }
            return event
        }

        // Two-finger scroll + pinch can be eaten by SwiftUI scroll views in
        // the toolbar, or never reach the canvas depending on window routing.
        // Catch every gesture for our overlay window and hand it to the
        // canvas directly, so panning/zooming always responds.
        gestureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
            guard let self, let canvas = self.canvas else { return event }
            guard event.window === self.window else { return event }
            guard self.state.drawingMode else { return event }
            // Cursor over the toolbar? Let its own scroll views keep working.
            if let toolbar = self.toolbarHost {
                let p = toolbar.convert(event.locationInWindow, from: nil)
                if toolbar.bounds.contains(p) { return event }
            }
            return canvas.handleGesture(event) ? nil : event
        }
    }

    private func teardownContent() {
        if let m = undoMonitor {
            NSEvent.removeMonitor(m)
            undoMonitor = nil
        }
        if let m = gestureMonitor {
            NSEvent.removeMonitor(m)
            gestureMonitor = nil
        }
        canvas = nil
        toolbarHost = nil
        window.contentView = nil
    }

    private func contentView() -> NSView? {
        window.contentView
    }

    // MARK: - visuals

    private func pillRect(on screen: NSScreen) -> CGRect {
        let w: CGFloat = 150
        let h: CGFloat = 34
        return CGRect(
            x: screen.frame.midX - w / 2,
            y: screen.frame.maxY - 26 - h,
            width: w,
            height: h
        )
    }

    private func makePillView(frame: CGRect) -> NSView {
        let v = NSView(frame: frame)
        v.wantsLayer = true
        v.layer?.cornerRadius = frame.height / 2
        v.layer?.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 0.96).cgColor
        return v
    }

    private func animateCornerRadius(of view: NSView?, from: CGFloat, to: CGFloat, duration: TimeInterval) {
        guard let layer = view?.layer else { return }
        let anim = CABasicAnimation(keyPath: "cornerRadius")
        anim.fromValue = from
        anim.toValue = to
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(anim, forKey: "islandRadius")
        layer.cornerRadius = to
    }

    private func screenForMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }

    // MARK: - self test

    func runSelfTest(log: @escaping (String) -> Void) {
        log("showing overlay")
        show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self else {
                log("FAIL: overlay not installed")
                exit(1)
            }
            log("open: visible=\(self.isOverlayVisible) drawingMode=\(self.state.drawingMode)")
            guard self.isOverlayVisible, self.state.drawingMode else {
                log("FAIL: overlay should be visible and in drawing mode")
                exit(1)
            }
            log("toggling overlay closed")
            self.toggle()
            self.pollVisibility(log: log, expectVisible: false, until: .now() + 2.0) {
                log("after toggle: visible=\(self.isOverlayVisible)")
                log("waiting for the hide animation to finish")
                self.pollIdle(log: log, until: .now() + 3.0) {
                    log("toggling overlay open again")
                    self.toggle()
                    self.pollVisibility(log: log, expectVisible: true, until: .now() + 2.0) {
                        log("reopen: visible=\(self.isOverlayVisible) drawingMode=\(self.state.drawingMode)")
                        self.pollIdle(log: log, until: .now() + 3.0) {
                            guard self.isOverlayVisible, self.state.drawingMode, self.canvas != nil else {
                                log("FAIL: overlay did not reopen in drawing mode")
                                exit(1)
                            }
                            self.textEditingTest(log: log)
                        }
                    }
                }
            }
        }
    }

    private func textEditingTest(log: @escaping (String) -> Void) {
        guard self.canvas != nil else { return }
        self.state.tool = .text
        self.state.lastNonTextTool = .rectangle
        self.activate()
        log("activating + clicking canvas")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, let canvas = self.canvas else { return }
            let w = self.window.windowNumber
            let ev = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: CGPoint(x: 500, y: 400),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: w,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )!
            canvas.mouseDown(with: ev)
            log("isEditingText = \(canvas.isEditingText)")
            guard canvas.isEditingText else {
                log("FAIL: text editing did not start")
                exit(1)
            }
            canvas.selftestSetText("hello")
            log("before esc: editing=\(canvas.selftestEditingString().debugDescription)")
            self.postKeyDown(keyCode: 53)
            log("after post: editing=\(canvas.isEditingText) string=\(canvas.selftestEditingString().debugDescription)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, let canvas = self.canvas else { return }
                log("after Esc: editing=\(canvas.isEditingText) annotations=\(canvas.annotations.count) tool=\(self.state.tool.rawValue)")
                if canvas.isEditingText {
                    log("FAIL: Esc did not exit text editing")
                    exit(1)
                }
                if canvas.annotations.count != 1 {
                    log("FAIL: expected 1 annotation, got \(canvas.annotations.count)")
                    exit(1)
                }
                if self.state.tool != .selection {
                    log("FAIL: expected selection tool after Esc, got \(self.state.tool.rawValue)")
                    exit(1)
                }
                let orig = canvas.annotations[0]
                if canvas.selected != [0] {
                    log("FAIL: text should be selected after Esc")
                    exit(1)
                }
                log("pressing Esc again (not editing)")
                self.postKeyDown(keyCode: 53)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    guard let self, let canvas = self.canvas else { return }
                    log("still alive after 2nd Esc")

                    log("resize test: selecting the text, then dragging right-mid handle +120pt")
                    self.state.tool = .selection
                    let c1 = self.win(CGPoint(x: orig.rect.midX, y: orig.rect.midY))
                    canvas.mouseDown(with: self.mouseEvent(at: c1, type: .leftMouseDown))
                    canvas.mouseUp(with: self.mouseEvent(at: c1, type: .leftMouseUp))
                    let handleP = self.win(CGPoint(x: orig.rect.maxX, y: orig.rect.midY))
                    let endP = self.win(CGPoint(x: orig.rect.maxX + 120, y: orig.rect.midY))
                    canvas.mouseDown(with: self.mouseEvent(at: handleP, type: .leftMouseDown))
                    canvas.mouseDragged(with: self.mouseEvent(at: endP, type: .leftMouseDragged))
                    canvas.mouseUp(with: self.mouseEvent(at: endP, type: .leftMouseUp))
                    let afterResize = canvas.annotations[0]
                    log("after resize: width \(orig.rect.width) -> \(afterResize.rect.width), fontSize \(orig.fontSize) -> \(afterResize.fontSize)")
                    // Mid-right handle stretches the text box; the font stays.
                    if afterResize.rect.width <= orig.rect.width {
                        log("FAIL: resize did not grow the text")
                        exit(1)
                    }

                    log("move test: dragging selection +80pt")
                    let from = self.win(CGPoint(x: afterResize.rect.midX, y: afterResize.rect.midY))
                    let to = self.win(CGPoint(x: afterResize.rect.midX + 80, y: afterResize.rect.midY + 40))
                    canvas.mouseDown(with: self.mouseEvent(at: from, type: .leftMouseDown))
                    canvas.mouseDragged(with: self.mouseEvent(at: to, type: .leftMouseDragged))
                    canvas.mouseUp(with: self.mouseEvent(at: to, type: .leftMouseUp))
                    let afterMove = canvas.annotations[0]
                    log("after move: origin \(afterResize.rect.origin) -> \(afterMove.rect.origin)")
                    if afterMove.rect.origin == afterResize.rect.origin {
                        log("FAIL: move did not change position")
                        exit(1)
                    }

                    log("draw test: rectangle should stay the active tool")
                    self.state.tool = .rectangle
                    let d1 = self.win(CGPoint(x: 300, y: 500))
                    let d2 = self.win(CGPoint(x: 400, y: 650))
                    canvas.mouseDown(with: self.mouseEvent(at: d1, type: .leftMouseDown))
                    canvas.mouseDragged(with: self.mouseEvent(at: d2, type: .leftMouseDragged))
                    canvas.mouseUp(with: self.mouseEvent(at: d2, type: .leftMouseUp))
                    log("after rect: tool=\(self.state.tool.rawValue) annotations=\(canvas.annotations.count) selected=\(canvas.selected)")
                    if self.state.tool != .rectangle {
                        log("FAIL: tool should stay rectangle after drawing")
                        exit(1)
                    }
                    if canvas.selected != [1] {
                        log("FAIL: drawn rectangle should be selected")
                        exit(1)
                    }

                    log("rotate test: dragging the rotate handle above the rect")
                    self.state.tool = .selection
                    let r = canvas.annotations[1].rect
                    let rh = self.win(CGPoint(x: r.midX, y: r.minY - 28))
                    let rt = self.win(CGPoint(x: r.midX + 120, y: r.minY - 88))
                    canvas.mouseDown(with: self.mouseEvent(at: rh, type: .leftMouseDown))
                    canvas.mouseDragged(with: self.mouseEvent(at: rt, type: .leftMouseDragged))
                    canvas.mouseUp(with: self.mouseEvent(at: rt, type: .leftMouseUp))
                    log("after rotate: rotation=\(canvas.annotations[1].rotation)")
                    if abs(canvas.annotations[1].rotation) < 0.1 {
                        log("FAIL: rotation should have changed")
                        exit(1)
                    }
                    log("esc deselect test: Esc should clear the selection and enable free edit mode")
                    self.state.tool = .freedraw
                    self.sendKeyToWindow(keyCode: 53)
                    log("after esc: selected=\(canvas.selected) tool=\(self.state.tool.rawValue)")
                    if !canvas.selected.isEmpty {
                        log("FAIL: Esc should clear the selection")
                        exit(1)
                    }
                    if self.state.tool != .selection {
                        log("FAIL: Esc should switch to the selection tool")
                        exit(1)
                    }

                    log("text re-edit test: double-click the existing text")
                    self.state.tool = .selection
                    self.state.lastNonTextTool = .selection
                    let tr = canvas.annotations[0].rect
                    let tc = self.win(CGPoint(x: tr.midX, y: tr.midY))
                    canvas.mouseDown(with: self.mouseEvent(at: tc, type: .leftMouseDown, clickCount: 2))
                    log("re-edit open: isEditingText=\(canvas.isEditingText)")
                    if !canvas.isEditingText {
                        log("FAIL: double-click should open the text editor")
                        exit(1)
                    }
                    canvas.selftestSetText("edited text")
                    self.postKeyDown(keyCode: 53)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        guard let self, let canvas = self.canvas else { return }
                        log("re-edit after esc: annotations=\(canvas.annotations.count) text=\(canvas.annotations[0].text)")
                        if canvas.annotations.count != 2 {
                            log("FAIL: re-editing should update in place, not create a new annotation")
                            exit(1)
                        }
                        if canvas.annotations[0].text != "edited text" {
                            log("FAIL: re-edited text was not saved")
                            exit(1)
                        }
                        log("re-edit drift check: origin \(tr.origin) -> \(canvas.annotations[0].rect.origin)")
                        if canvas.annotations[0].rect.origin != tr.origin {
                            log("FAIL: re-editing moved the text")
                            exit(1)
                        }

                        log("cursor test: hovering the mid-right resize handle")
                        let hr = self.win(CGPoint(x: tr.maxX, y: tr.midY))
                        canvas.mouseMoved(with: self.mouseEvent(at: hr, type: .mouseMoved))
                        if NSCursor.current !== NSCursor.resizeLeftRight {
                            log("FAIL: expected left/right resize cursor, got \(NSCursor.current)")
                            exit(1)
                        }
                        log("cursor test: hovering the top-left corner handle")
                        let hc = self.win(CGPoint(x: tr.minX, y: tr.minY))
                        canvas.mouseMoved(with: self.mouseEvent(at: hc, type: .mouseMoved))
                        if NSCursor.current !== canvas.cursorTopLeft {
                            log("FAIL: expected diagonal resize cursor, got \(NSCursor.current)")
                            exit(1)
                        }

                        log("click-away commit test: tool must not stay on text")
                        self.state.tool = .text
                        self.state.lastNonTextTool = .selection
                        let nw = self.win(CGPoint(x: 120, y: 120))
                        canvas.mouseDown(with: self.mouseEvent(at: nw, type: .leftMouseDown))
                        log("click-away: isEditingText=\(canvas.isEditingText)")
                        if !canvas.isEditingText {
                            log("FAIL: text editing did not start")
                            exit(1)
                        }
                        canvas.selftestSetText("second")
                        self.window.makeFirstResponder(canvas)
                        log("click-away after resign: tool=\(self.state.tool.rawValue) isEditingText=\(canvas.isEditingText)")
                        if self.state.tool != .selection {
                            log("FAIL: tool should restore to selection after committing by click-away")
                            exit(1)
                        }
                        if canvas.isEditingText {
                            log("FAIL: text editing should have committed on click-away")
                            exit(1)
                        }
                        log("click-away: clicking empty canvas must not open a text field")
                        canvas.mouseDown(with: self.mouseEvent(at: nw, type: .leftMouseDown))
                        canvas.mouseUp(with: self.mouseEvent(at: nw, type: .leftMouseUp))
                        if canvas.isEditingText {
                            log("FAIL: clicking should not open a text field after commit")
                            exit(1)
                        }

                        log("shape text test: double-clicking the rectangle opens inline text editing")
                        self.state.tool = .selection
                        self.state.lastNonTextTool = .selection
                        let sr = canvas.annotations[1].rect
                        let sc = self.win(CGPoint(x: sr.midX, y: sr.midY))
                        canvas.mouseDown(with: self.mouseEvent(at: sc, type: .leftMouseDown, clickCount: 2))
                        log("shape edit open: isEditingText=\(canvas.isEditingText)")
                        if !canvas.isEditingText {
                            log("FAIL: double-clicking a polygon should open text editing")
                            exit(1)
                        }
                        canvas.selftestSetText("inside shape")
                        self.postKeyDown(keyCode: 53)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                            guard let self, let canvas = self.canvas else { return }
                            log("shape text after esc: count=\(canvas.annotations.count) text=\(canvas.annotations[1].text) inside=\(canvas.annotations[1].textInside) fontSize=\(canvas.annotations[1].fontSize)")
                            if canvas.annotations.count != 3 {
                                log("FAIL: shape text should edit in place, not add an annotation")
                                exit(1)
                            }
                            if !canvas.annotations[1].textInside || canvas.annotations[1].text != "inside shape" {
                                log("FAIL: shape text was not stored")
                                exit(1)
                            }
                            log("shape drift check: origin \(sr.origin) -> \(canvas.annotations[1].rect.origin)")
                            if canvas.annotations[1].rect.origin != sr.origin {
                                log("FAIL: editing shape text moved the shape")
                                exit(1)
                            }

                            log("marquee move test: box-select both rectangles, drag one, both must move")
                            self.state.tool = .rectangle
                            self.state.lastNonTextTool = .rectangle
                            let q1 = self.win(CGPoint(x: 500, y: 700))
                            let q2 = self.win(CGPoint(x: 560, y: 760))
                            canvas.mouseDown(with: self.mouseEvent(at: q1, type: .leftMouseDown))
                            canvas.mouseDragged(with: self.mouseEvent(at: q2, type: .leftMouseDragged))
                            canvas.mouseUp(with: self.mouseEvent(at: q2, type: .leftMouseUp))
                            self.state.tool = .selection
                            self.state.lastNonTextTool = .selection
                            let r1 = canvas.annotations[1].rect
                            let r3 = canvas.annotations[3].rect
                            let m1 = self.win(CGPoint(x: min(r1.minX, r3.minX) - 20, y: min(r1.minY, r3.minY) - 20))
                            let m2 = self.win(CGPoint(x: max(r1.maxX, r3.maxX) + 20, y: max(r1.maxY, r3.maxY) + 20))
                            canvas.mouseDown(with: self.mouseEvent(at: m1, type: .leftMouseDown))
                            canvas.mouseDragged(with: self.mouseEvent(at: m2, type: .leftMouseDragged))
                            canvas.mouseUp(with: self.mouseEvent(at: m2, type: .leftMouseUp))
                            log("after marquee: selected=\(canvas.selected.sorted())")
                            if canvas.selected.count != 2 {
                                log("FAIL: marquee should select both rectangles")
                                exit(1)
                            }
                            let grab = self.win(CGPoint(x: r1.midX, y: r1.midY))
                            let dest = self.win(CGPoint(x: r1.midX + 60, y: r1.midY + 30))
                            canvas.mouseDown(with: self.mouseEvent(at: grab, type: .leftMouseDown))
                            canvas.mouseDragged(with: self.mouseEvent(at: dest, type: .leftMouseDragged))
                            canvas.mouseUp(with: self.mouseEvent(at: dest, type: .leftMouseUp))
                            let moved1 = canvas.annotations[1].rect
                            let moved3 = canvas.annotations[3].rect
                            log("after drag: rect1 \(r1.origin) -> \(moved1.origin), rect3 \(r3.origin) -> \(moved3.origin)")
                            if moved1.origin == r1.origin || moved3.origin == r3.origin {
                                log("FAIL: both rectangles should move together")
                                exit(1)
                            }
                            let dx = moved1.minX - r1.minX
                            if abs((moved3.minX - r3.minX) - dx) > 0.5
                                || abs((moved1.minY - r1.minY) - (moved3.minY - r3.minY)) > 0.5 {
                                log("FAIL: rectangles should move by the same delta")
                                exit(1)
                            }
                            log("post-marquee draw test: a new rect must start exactly at the drag start")
                            self.state.tool = .rectangle
                            let dp1 = self.win(CGPoint(x: 150, y: 150))
                            let dp2 = self.win(CGPoint(x: 260, y: 220))
                            canvas.mouseDown(with: self.mouseEvent(at: dp1, type: .leftMouseDown))
                            canvas.mouseDragged(with: self.mouseEvent(at: dp2, type: .leftMouseDragged))
                            canvas.mouseUp(with: self.mouseEvent(at: dp2, type: .leftMouseUp))
                            let drawn = canvas.annotations.last!
                            log("drawn rect: origin \(drawn.rect.origin) size \(drawn.rect.size)")
                            if drawn.rect.minX != 150 || drawn.rect.minY != 150 {
                                log("FAIL: drawn rect should start at the drag start, got \(drawn.rect.origin)")
                                exit(1)
                            }

                            log("slash palette test: opening the logo palette")
                        self.showLogoPalette()
                        log("palette open: \(self.isLogoPaletteVisible)")
                        guard self.isLogoPaletteVisible, let palette = self.logoPalette else {
                            log("FAIL: palette should open")
                            exit(1)
                        }
                        let total = palette.selftestResults.count
                        log("palette total items: \(total)")
                        if total < 100 {
                            log("FAIL: expected the full tech icon set, got \(total)")
                            exit(1)
                        }
                        palette.selftestSetQuery("chat")
                        log("palette query 'chat': \(palette.selftestResults.count)/\(total) results")
                        if palette.selftestResults.isEmpty {
                            log("FAIL: expected results for query 'chat'")
                            exit(1)
                        }
                        palette.selftestSetQuery("server")
                        if palette.selftestResults.isEmpty {
                            log("FAIL: expected results for tech query 'server'")
                            exit(1)
                        }
                        palette.selftestSetQuery("chat")
                        palette.selftestPickRow(0)
                        log("palette pick: annotations=\(canvas.annotations.count) last=\(canvas.annotations.last?.kind.rawValue ?? "?")")
                        if canvas.annotations.count != 6 {
                            log("FAIL: picking a logo should insert an annotation")
                            exit(1)
                        }
                        if canvas.annotations.last?.kind != .image || canvas.annotations.last?.image == nil {
                            log("FAIL: inserted logo should be an image annotation")
                            exit(1)
                        }
                        log("icon recolor test: changing color must re-tint the selected icon")
                        let redColor = NSColor.systemRed
                        self.state.strokeColor = redColor
                        if let img = canvas.annotations.last {
                            log("icon after recolor: strokeColor=\(img.strokeColor) image=\(img.image != nil)")
                            if img.image == nil || img.strokeColor != redColor {
                                log("FAIL: selected icon should recolor")
                                exit(1)
                            }
                        }
                        log("palette reopen + Esc close test")
                        self.showLogoPalette()
                        if !self.isLogoPaletteVisible {
                            log("FAIL: palette should reopen")
                            exit(1)
                        }
                        self.sendKeyToWindow(keyCode: 53)
                        log("palette open after esc: \(self.isLogoPaletteVisible)")
                        if self.isLogoPaletteVisible {
                            log("FAIL: Esc should close the logo palette")
                            exit(1)
                        }

                        log("pressure stroke test: dynamic mode must mark new strokes")
                        self.state.pressureMode = .dynamic
                        self.state.tool = .freedraw
                        self.state.lastNonTextTool = .freedraw
                        let f1 = self.win(CGPoint(x: 620, y: 260))
                        let f2 = self.win(CGPoint(x: 680, y: 320))
                        let f3 = self.win(CGPoint(x: 740, y: 280))
                        canvas.mouseDown(with: self.mouseEvent(at: f1, type: .leftMouseDown))
                        canvas.mouseDragged(with: self.mouseEvent(at: f2, type: .leftMouseDragged))
                        canvas.mouseDragged(with: self.mouseEvent(at: f3, type: .leftMouseDragged))
                        canvas.mouseUp(with: self.mouseEvent(at: f3, type: .leftMouseUp))
                        if let fs = canvas.annotations.last, fs.kind == .freedraw {
                            log("freedraw: dynamicWidth=\(fs.dynamicWidth) points=\(fs.points.count)")
                            if fs.dynamicWidth != true || fs.points.count < 3 {
                                log("FAIL: freedraw should be marked dynamic with collected points")
                                exit(1)
                            }
                        } else {
                            log("FAIL: no freedraw annotation was created")
                            exit(1)
                        }
                        log("pressure stroke test: light mode must mark strokes uniform")
                        self.state.pressureMode = .light
                        let f4 = self.win(CGPoint(x: 620, y: 160))
                        let f5 = self.win(CGPoint(x: 700, y: 120))
                        canvas.mouseDown(with: self.mouseEvent(at: f4, type: .leftMouseDown))
                        canvas.mouseDragged(with: self.mouseEvent(at: f5, type: .leftMouseDragged))
                        canvas.mouseUp(with: self.mouseEvent(at: f5, type: .leftMouseUp))
                        if let fs = canvas.annotations.last, fs.kind == .freedraw {
                            log("light freedraw: dynamicWidth=\(fs.dynamicWidth)")
                            if fs.dynamicWidth != false {
                                log("FAIL: light mode stroke should be uniform")
                                exit(1)
                            }
                        } else {
                            log("FAIL: no light freedraw annotation was created")
                            exit(1)
                        }

                        log("shape library test: new shapes draw from a drag like any tool")
                        for (tool, kind) in [
                            (Tool.hexagon, ShapeKind.hexagon),
                            (Tool.process, ShapeKind.process),
                            (Tool.parallelogram, ShapeKind.parallelogram),
                            (Tool.star, ShapeKind.star),
                            (Tool.cross, ShapeKind.cross),
                            (Tool.cloud, ShapeKind.cloud),
                            (Tool.callout, ShapeKind.callout),
                            (Tool.note, ShapeKind.note),
                            (Tool.cube, ShapeKind.cube),
                        ] {
                            self.state.tool = tool
                            self.state.lastNonTextTool = tool
                            let s1 = self.win(CGPoint(x: 850, y: 200))
                            let s2 = self.win(CGPoint(x: 930, y: 260))
                            canvas.mouseDown(with: self.mouseEvent(at: s1, type: .leftMouseDown))
                            canvas.mouseDragged(with: self.mouseEvent(at: s2, type: .leftMouseDragged))
                            canvas.mouseUp(with: self.mouseEvent(at: s2, type: .leftMouseUp))
                            guard let s = canvas.annotations.last, s.kind == kind else {
                                log("FAIL: \(tool.label) should produce a \(kind.rawValue) annotation, got \(canvas.annotations.last?.kind.rawValue ?? "nil")")
                                exit(1)
                            }
                            log("shape \(kind.rawValue): rect=\(Int(s.rect.width))x\(Int(s.rect.height))")
                            if s.rect.width < 5 || s.rect.height < 5 {
                                log("FAIL: \(kind.rawValue) should have a sized rect")
                                exit(1)
                            }
                            guard let path = canvas.selftestPath(for: s) else {
                                log("FAIL: \(kind.rawValue) should have a drawable path")
                                exit(1)
                            }
                            if path.elementCount < 2 {
                                log("FAIL: \(kind.rawValue) path should have elements, got \(path.elementCount)")
                                exit(1)
                            }
                        }
                        log("shape library test: connectors draw like arrows")
                        for (tool, kind) in [
                            (Tool.orthogonal, ShapeKind.orthogonal),
                            (Tool.connector, ShapeKind.connector),
                            (Tool.doubleArrow, ShapeKind.doubleArrow),
                            (Tool.curvedConnector, ShapeKind.curvedConnector),
                        ] {
                            self.state.tool = tool
                            self.state.lastNonTextTool = tool
                            let c1 = self.win(CGPoint(x: 850, y: 330))
                            let c2 = self.win(CGPoint(x: 980, y: 380))
                            canvas.mouseDown(with: self.mouseEvent(at: c1, type: .leftMouseDown))
                            canvas.mouseDragged(with: self.mouseEvent(at: c2, type: .leftMouseDragged))
                            canvas.mouseUp(with: self.mouseEvent(at: c2, type: .leftMouseUp))
                            guard let s = canvas.annotations.last, s.kind == kind, s.points.count == 2 else {
                                log("FAIL: \(tool.label) should produce a \(kind.rawValue) with 2 points, got \(canvas.annotations.last?.kind.rawValue ?? "nil") pts=\(canvas.annotations.last?.points.count ?? -1)")
                                exit(1)
                            }
                            log("connector \(kind.rawValue): points=\(s.points.count)")
                            guard let path = canvas.selftestPath(for: s), path.elementCount >= 1 else {
                                log("FAIL: \(kind.rawValue) should have a drawable path")
                                exit(1)
                            }
                        }
                        log("smart connector test: glued ends follow the box")
                        self.state.tool = .rectangle
                        self.state.lastNonTextTool = .rectangle
                        let a1 = self.win(CGPoint(x: 600, y: 100))
                        let a2 = self.win(CGPoint(x: 680, y: 160))
                        canvas.mouseDown(with: self.mouseEvent(at: a1, type: .leftMouseDown))
                        canvas.mouseDragged(with: self.mouseEvent(at: a2, type: .leftMouseDragged))
                        canvas.mouseUp(with: self.mouseEvent(at: a2, type: .leftMouseUp))
                        let boxA = canvas.annotations.count - 1
                        let b1 = self.win(CGPoint(x: 600, y: 300))
                        let b2 = self.win(CGPoint(x: 680, y: 360))
                        canvas.mouseDown(with: self.mouseEvent(at: b1, type: .leftMouseDown))
                        canvas.mouseDragged(with: self.mouseEvent(at: b2, type: .leftMouseDragged))
                        canvas.mouseUp(with: self.mouseEvent(at: b2, type: .leftMouseUp))
                        let boxB = canvas.annotations.count - 1
                        self.state.tool = .connector
                        self.state.lastNonTextTool = .connector
                        // Grab box A's top-edge dot (640,160) and release on box B's bottom dot (640,300).
                        let c1 = self.win(CGPoint(x: 640, y: 160))
                        let c2 = self.win(CGPoint(x: 640, y: 300))
                        canvas.mouseDown(with: self.mouseEvent(at: c1, type: .leftMouseDown))
                        canvas.mouseDragged(with: self.mouseEvent(at: c2, type: .leftMouseDragged))
                        canvas.mouseUp(with: self.mouseEvent(at: c2, type: .leftMouseUp))
                        guard let link = canvas.annotations.last, link.kind == .connector else {
                            log("FAIL: dot drag should create a connector, got \(canvas.annotations.last?.kind.rawValue ?? "nil")")
                            exit(1)
                        }
                        if link.connectionStart?.annotationIndex != boxA || link.connectionEnd?.annotationIndex != boxB {
                            log("FAIL: connector should be glued to boxA and boxB, got \(String(describing: link.connectionStart)) \(String(describing: link.connectionEnd))")
                            exit(1)
                        }
                        // Move box A right by 60 — the glued end must follow.
                        self.state.tool = .selection
                        let mv1 = self.win(CGPoint(x: 650, y: 120))
                        let mv2 = self.win(CGPoint(x: 710, y: 120))
                        canvas.mouseDown(with: self.mouseEvent(at: mv1, type: .leftMouseDown))
                        canvas.mouseDragged(with: self.mouseEvent(at: mv2, type: .leftMouseDragged))
                        canvas.mouseUp(with: self.mouseEvent(at: mv2, type: .leftMouseUp))
                        let start = canvas.selftestPathStart(link)
                        if let start, abs(start.x - 700) < 0.5, abs(start.y - 160) < 0.5 {
                            log("glue follow: connector start followed the box to (700,160)")
                        } else {
                            log("FAIL: glued connector should follow the moved box, path start = \(String(describing: start))")
                            exit(1)
                        }
                        log("mid-box dodge test: connector routes over a tall box in the way")
                        // boxA (right dot -> (560,430)), boxB (left dot <- (900,430)),
                        // tall mid box spanning the whole corridor.
                        self.state.tool = .rectangle
                        self.state.lastNonTextTool = .rectangle
                        let da1 = self.win(CGPoint(x: 500, y: 400))
                        let da2 = self.win(CGPoint(x: 560, y: 460))
                        canvas.mouseDown(with: self.mouseEvent(at: da1, type: .leftMouseDown))
                        canvas.mouseDragged(with: self.mouseEvent(at: da2, type: .leftMouseDragged))
                        canvas.mouseUp(with: self.mouseEvent(at: da2, type: .leftMouseUp))
                        let boxA2 = canvas.annotations.count - 1
                        let db1 = self.win(CGPoint(x: 900, y: 400))
                        let db2 = self.win(CGPoint(x: 960, y: 460))
                        canvas.mouseDown(with: self.mouseEvent(at: db1, type: .leftMouseDown))
                        canvas.mouseDragged(with: self.mouseEvent(at: db2, type: .leftMouseDragged))
                        canvas.mouseUp(with: self.mouseEvent(at: db2, type: .leftMouseUp))
                        let boxB2 = canvas.annotations.count - 1
                        let dm1 = self.win(CGPoint(x: 640, y: 250))
                        let dm2 = self.win(CGPoint(x: 860, y: 610))
                        canvas.mouseDown(with: self.mouseEvent(at: dm1, type: .leftMouseDown))
                        canvas.mouseDragged(with: self.mouseEvent(at: dm2, type: .leftMouseDragged))
                        canvas.mouseUp(with: self.mouseEvent(at: dm2, type: .leftMouseUp))
                        let mid = canvas.annotations.count - 1
                        self.state.tool = .connector
                        self.state.lastNonTextTool = .connector
                        let cc1 = self.win(CGPoint(x: 560, y: 430))
                        let cc2 = self.win(CGPoint(x: 900, y: 430))
                        canvas.mouseDown(with: self.mouseEvent(at: cc1, type: .leftMouseDown))
                        canvas.mouseDragged(with: self.mouseEvent(at: cc2, type: .leftMouseDragged))
                        canvas.mouseUp(with: self.mouseEvent(at: cc2, type: .leftMouseUp))
                        guard let link2 = canvas.annotations.last, link2.kind == .connector else {
                            log("FAIL: dot drag should create a connector, got \(canvas.annotations.last?.kind.rawValue ?? "nil")")
                            exit(1)
                        }
                        let midRect = canvas.annotations[mid].rect
                        let pathPts = canvas.selftestPathPoints(link2)
                        let inside = pathPts.contains { midRect.contains($0) }
                        let maxY = pathPts.map(\.y).max() ?? 0
                        if inside || maxY < midRect.maxY {
                            log("FAIL: connector should clear the mid box, inside=\(inside) maxY=\(maxY) midTop=\(midRect.maxY) pts=\(pathPts)")
                            exit(1)
                        }
                        log("mid-box dodge: connector cleared the box over the top (maxY=\(maxY))")
                        log("shape library test: palette contents are all drawable tools")
                        if Tool.shapePalette.count < 25 {
                            log("FAIL: shape palette should contain at least 25 shapes, got \(Tool.shapePalette.count)")
                            exit(1)
                        }
                        for t in Tool.shapePalette where t.shapeKind == nil {
                            log("FAIL: palette tool \(t.label) should map to a shape kind")
                            exit(1)
                        }

                        log("code block test: typing in code-block mode makes a highlighted block")
                        self.state.codeBlockMode = true
                        self.state.tool = .text
                        self.state.lastNonTextTool = .text
                        let cp = self.win(CGPoint(x: 1250, y: 156))
                        canvas.mouseDown(with: self.mouseEvent(at: cp, type: .leftMouseDown))
                        log("code edit open: isEditingText=\(canvas.isEditingText)")
                        if !canvas.isEditingText {
                            log("FAIL: code mode should open the text editor")
                            exit(1)
                        }
                        log("select all test: Cmd+A selects everything in the editing view")
                        canvas.selftestSetText("hello world")
                        if let ev = NSEvent.keyEvent(
                            with: .keyDown, location: .zero, modifierFlags: [.command],
                            timestamp: 0, windowNumber: 0, context: nil,
                            characters: "a", charactersIgnoringModifiers: "a",
                            isARepeat: false, keyCode: 0
                        ) {
                            let consumed = self.handleEditingKey(ev, canvas: canvas)
                            log("post cmd+a: consumed=\(consumed) sel=\(canvas.selftestEditingSelectionLength())")
                        }
                        let selLen = canvas.selftestEditingSelectionLength()
                        log("select all: selection length=\(selLen)")
                        if selLen != 11 {
                            log("FAIL: Cmd+A should select the whole text, got \(selLen)")
                            exit(1)
                        }
                        log("auto-close test: openers insert their closing partner")
                        canvas.selftestSetText("")
                        self.sendKeyToWindow(keyCode: 33, characters: "{")
                        self.sendKeyToWindow(keyCode: 33, characters: "{")
                        self.sendKeyToWindow(keyCode: 3, characters: "f")
                        self.sendKeyToWindow(keyCode: 45, characters: "n")
                        let autoClosed = canvas.selftestEditingString()
                        log("auto-close: \(autoClosed.debugDescription)")
                        if autoClosed != "{{fn}}" {
                            log("FAIL: braces should auto-close into {{fn}}: \(autoClosed)")
                            exit(1)
                        }
                        log("auto-close step test: typing the closer skips over it")
                        canvas.selftestSetText("}")
                        canvas.selftestSetCursor(location: 0)
                        self.sendKeyToWindow(keyCode: 42, characters: "}")
                        if canvas.selftestEditingString() != "}" {
                            log("FAIL: typing } when one is next should not duplicate it: \(canvas.selftestEditingString())")
                            exit(1)
                        }
                        log("real-time sync test: canvas code block updates while typing")
                        canvas.selftestSetText("let x = 1")
                        if canvas.annotations.last?.text != "let x = 1" {
                            log("FAIL: code block should mirror typing live: \(canvas.annotations.last?.text ?? "nil")")
                            exit(1)
                        }
                        log("enter newline test: Enter must keep typing on a new line with smart indent")
                        canvas.selftestSetText("fn main() {")
                        self.sendKeyToWindow(keyCode: 36, characters: "\r")
                        canvas.selftestSetText("fn main() {\n    x")
                        canvas.commitPendingText(selectAndPick: true)
                        if let t = canvas.annotations.last?.text, !t.contains("\n    x") {
                            log("FAIL: Enter should indent after an opening brace: \(t)")
                            exit(1)
                        }
                        log("code block test: typing in code-block mode makes a highlighted block")
                        canvas.selftestSetText("fn main() {\n  let x = 42 // answer\n}")
                        canvas.commitPendingText(selectAndPick: true)
                        log("code after esc: isEditingText=\(canvas.isEditingText) count=\(canvas.annotations.count)")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                            guard let self, let canvas = self.canvas else { return }
                            guard let cb = canvas.annotations.last, cb.kind == .text else {
                                log("FAIL: code block annotation missing")
                                exit(1)
                            }
                            log("code block: isCode=\(cb.isCode) font=\(cb.fontFamily) size=\(cb.fontSize)")
                            if !cb.isCode || cb.fontFamily != "Cascadia Code" || cb.fontSize != 15 {
                                log("FAIL: code block should be monospaced, compact and flagged")
                                exit(1)
                            }
                            log("code block toggle test: converting back to plain text")
                            canvas.toggleCodeBlock()
                            if canvas.annotations.last?.isCode != false {
                                log("FAIL: toggle should clear the code flag")
                                exit(1)
                            }
                            log("code block toggle test: converting forward again")
                            canvas.toggleCodeBlock()
                            if canvas.annotations.last?.isCode != true {
                                log("FAIL: toggle should re-apply the code flag")
                                exit(1)
                            }
                            log("code block font restore test: converting existing text back must restore its font")
                            guard let tIdx = canvas.annotations.indices.last(where: {
                                canvas.annotations[$0].kind == .text && !canvas.annotations[$0].isCode
                            }) else {
                                log("FAIL: no plain text annotation to convert")
                                exit(1)
                            }
                            canvas.selftestSelect([tIdx])
                            let origFamily = canvas.annotations[tIdx].fontFamily
                            let origSize = canvas.annotations[tIdx].fontSize
                            canvas.toggleCodeBlock()
                            if !canvas.annotations[tIdx].isCode || canvas.annotations[tIdx].fontFamily != "Cascadia Code" {
                                log("FAIL: existing text should convert to code with Cascadia Code")
                                exit(1)
                            }
                            canvas.toggleCodeBlock()
                            if canvas.annotations[tIdx].isCode
                                || canvas.annotations[tIdx].fontFamily != origFamily
                                || canvas.annotations[tIdx].fontSize != origSize {
                                log("FAIL: converting back should restore \(origFamily)/\(origSize), got \(canvas.annotations[tIdx].fontFamily)/\(canvas.annotations[tIdx].fontSize)")
                                exit(1)
                            }
                            log("SELFTEST PASS")
                            exit(0)
                        }
                        }
                    }
                }
            }
        }
    }

    /// Convert a canvas (flipped) coordinate to window coordinates for
    /// synthetic mouse events.
    private func win(_ p: CGPoint) -> CGPoint {
        guard let canvas = self.canvas else { return p }
        return CGPoint(x: p.x, y: canvas.bounds.height - p.y)
    }

    private func mouseEvent(at p: CGPoint, type: NSEvent.EventType, clickCount: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: p,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: clickCount,
            pressure: 1
        )!
    }

    /// Polls the overlay visibility until it matches `expectVisible`.
    private func pollVisibility(
        log: @escaping (String) -> Void,
        expectVisible: Bool,
        until: DispatchTime,
        then: @escaping () -> Void
    ) {
        if self.isOverlayVisible == expectVisible {
            then()
            return
        }
        if DispatchTime.now() >= until {
            log("FAIL: visibility did not reach \(expectVisible) (got \(self.isOverlayVisible))")
            exit(1)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.pollVisibility(log: log, expectVisible: expectVisible, until: until, then: then)
        }
    }

    /// Polls until the overlay show/hide animation finishes.
    private func pollIdle(
        log: @escaping (String) -> Void,
        until: DispatchTime,
        then: @escaping () -> Void
    ) {
        if !self.isAnimating {
            then()
            return
        }
        if DispatchTime.now() >= until {
            log("FAIL: overlay animation never finished")
            exit(1)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.pollIdle(log: log, until: until, then: then)
        }
    }

    private func postModifierCombo() {
        guard let ev = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { return }
        ev.type = .flagsChanged
        ev.flags = [.maskControl, .maskAlternate]
        ev.post(tap: .cghidEventTap)
    }

    private func postKeyDown(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else { return }
        down.flags = flags
        down.post(tap: .cghidEventTap)
        if let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) {
            up.flags = flags
            up.post(tap: .cghidEventTap)
        }
    }

    /// Handles a key while a text block is being edited. Esc commits the
    /// text, ⌘A selects all of it, everything else is left for the editor.
    /// Returns true when the event was consumed.
    func handleEditingKey(_ event: NSEvent, canvas: CanvasView) -> Bool {
        if event.keyCode == 53 {
            canvas.commitPendingText(selectAndPick: true)
            return true
        }
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        if mods.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "a" {
            canvas.selectAllInEditingField()
            return true
        }
        return false
    }

    /// Delivers a key event straight to the key window (same path the system
    /// uses for real hardware events) — deterministic in self-tests.
    private func sendKeyToWindow(keyCode: CGKeyCode, characters: String = "\u{1b}", flags: NSEvent.ModifierFlags = []) {
        guard let down = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: keyCode
        ) else { return }
        window.sendEvent(down)
    }
}

extension IslandManager: LogoPaletteDelegate {
    func logoPaletteDidPick(_ item: LogoItem) {
        LogoCatalog.bumpFrequency(of: item.id)
        closeLogoPalette()
        guard let canvas else { return }
        let p = canvas.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        canvas.insertSymbol(item.symbol, at: p)
    }

    func logoPaletteDidClose() {
        closeLogoPalette()
    }
}
