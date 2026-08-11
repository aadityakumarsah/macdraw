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
                onActivate: { [weak self] in self?.activate() },
                onDeactivate: { [weak self] in self?.deactivate() }
            )
        )
        toolbar.frame = CGRect(
            x: 12,
            y: screen.frame.maxY - 112,
            width: max(0, screen.frame.width - 24),
            height: 92
        )
        toolbar.alphaValue = 0
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

            if event.keyCode == 53 { // Esc — ends text editing, or lets the canvas clear its selection
                if canvas.isEditingText {
                    canvas.commitPendingText(selectAndPick: true)
                    return nil
                }
                return event
            }
            if !mods.isEmpty {
                if mods.contains(.command), event.charactersIgnoringModifiers == "z" {
                    canvas.undo()
                    return nil
                }
                return event
            }
            if canvas.isEditingText { return event }
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
    }

    private func teardownContent() {
        if let m = undoMonitor {
            NSEvent.removeMonitor(m)
            undoMonitor = nil
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
            log("posting Ctrl+Option to close")
            self.postModifierCombo()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self else { return }
                log("after combo: visible=\(self.isOverlayVisible)")
                guard !self.isOverlayVisible else {
                    log("FAIL: Ctrl+Option did not close the overlay")
                    exit(1)
                }
                log("posting Ctrl+Option to reopen")
                self.postModifierCombo()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                    guard let self else { return }
                    log("reopen: visible=\(self.isOverlayVisible) drawingMode=\(self.state.drawingMode)")
                    guard self.isOverlayVisible, self.state.drawingMode, self.canvas != nil else {
                        log("FAIL: overlay did not reopen in drawing mode")
                        exit(1)
                    }
                    self.textEditingTest(log: log)
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
            self.postKeyDown(keyCode: 53)
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
                    if afterResize.rect.width <= orig.rect.width || afterResize.fontSize <= orig.fontSize {
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

                        log("slash palette test: opening the logo palette")
                        self.showLogoPalette()
                        log("palette open: \(self.isLogoPaletteVisible)")
                        guard self.isLogoPaletteVisible, let palette = self.logoPalette else {
                            log("FAIL: palette should open")
                            exit(1)
                        }
                        let total = palette.selftestResults.count
                        log("palette total items: \(total)")
                        if total <= 500 {
                            log("FAIL: expected the full emoji set, got \(total)")
                            exit(1)
                        }
                        palette.selftestSetQuery("chat")
                        log("palette query 'chat': \(palette.selftestResults.count)/\(total) results")
                        if palette.selftestResults.isEmpty {
                            log("FAIL: expected results for query 'chat'")
                            exit(1)
                        }
                        palette.selftestSetQuery("grinning")
                        if palette.selftestResults.isEmpty {
                            log("FAIL: expected results for unicode-name query 'grinning'")
                            exit(1)
                        }
                        palette.selftestSetQuery("chat")
                        let picked = palette.selftestResults.first!
                        palette.selftestPickRow(0)
                        log("palette pick: annotations=\(canvas.annotations.count) last=\(canvas.annotations.last?.text ?? "?")")
                        if canvas.annotations.count != 4 {
                            log("FAIL: picking a logo should insert an annotation")
                            exit(1)
                        }
                        if canvas.annotations.last?.text != picked.emoji {
                            log("FAIL: inserted logo does not match the picked item")
                            exit(1)
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
                        log("SELFTEST PASS")
                        exit(0)
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

    private func postModifierCombo() {
        guard let ev = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { return }
        ev.type = .flagsChanged
        ev.flags = [.maskControl, .maskAlternate]
        ev.post(tap: .cghidEventTap)
    }

    private func postKeyDown(keyCode: CGKeyCode) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else { return }
        down.post(tap: .cghidEventTap)
        if let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) {
            up.post(tap: .cghidEventTap)
        }
    }

    /// Deliver a key event straight to the key window (same path the system
    /// uses for real hardware events) — deterministic in self-tests.
    private func sendKeyToWindow(keyCode: CGKeyCode) {
        guard let down = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
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
        canvas.insertEmoji(item.emoji, at: p)
    }

    func logoPaletteDidClose() {
        closeLogoPalette()
    }
}
