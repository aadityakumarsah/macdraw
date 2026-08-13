import AppKit
import Combine

private func + (l: CGPoint, r: CGPoint) -> CGPoint {
    CGPoint(x: l.x + r.x, y: l.y + r.y)
}

private func - (l: CGPoint, r: CGPoint) -> CGPoint {
    CGPoint(x: l.x - r.x, y: l.y - r.y)
}

/// Which selection handle the user is dragging.
private enum ResizeHandle {
    case topLeft, topMid, topRight
    case midRight, bottomRight, bottomMid
    case bottomLeft, midLeft
    case startPoint, endPoint
}

/// Codable snapshot of an annotation, used to persist drawings to disk so they
/// survive app relaunches.
private struct PersistedAnnotation: Codable {
    var kind: String
    var x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat
    var stroke: [CGFloat]
    var fill: [CGFloat]?
    var fillOpacity: CGFloat
    var strokeWidth: CGFloat
    var points: [[CGFloat]]
    var text: String
    var fontFamily: String
    var fontSize: CGFloat
    var imagePNG: String?
    var rounded: Bool
    var dashed: Bool
    var rotation: CGFloat
    var createdAt: Date
    var locked: Bool
    var zIndex: Int
}

private func colorComponents(_ c: NSColor) -> [CGFloat] {
    let s = c.usingColorSpace(.sRGB) ?? c
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
    s.getRed(&r, green: &g, blue: &b, alpha: &a)
    return [r, g, b, a]
}

private func color(fromComponents v: [CGFloat]) -> NSColor {
    guard v.count >= 4 else { return .black }
    return NSColor(srgbRed: v[0], green: v[1], blue: v[2], alpha: v[3])
}

private func pngBase64(of img: NSImage) -> String? {
    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])?.base64EncodedString()
}

private func imageFromPNG(_ s: String) -> NSImage? {
    guard let d = Data(base64Encoded: s) else { return nil }
    return NSImage(data: d)
}

private extension Annotation {
    func persisted() -> PersistedAnnotation {
        PersistedAnnotation(
            kind: kind.rawValue,
            x: rect.minX, y: rect.minY, w: rect.width, h: rect.height,
            stroke: colorComponents(strokeColor),
            fill: fillColor.map { colorComponents($0) },
            fillOpacity: fillOpacity,
            strokeWidth: strokeWidth,
            points: points.map { [$0.x, $0.y] },
            text: text,
            fontFamily: fontFamily,
            fontSize: fontSize,
            imagePNG: image.flatMap { pngBase64(of: $0) },
            rounded: rounded,
            dashed: dashed,
            rotation: rotation,
            createdAt: createdAt,
            locked: locked,
            zIndex: zIndex
        )
    }

    static func restored(from p: PersistedAnnotation) -> Annotation {
        var fillColor: NSColor?
        if let fill = p.fill {
            fillColor = color(fromComponents: fill)
            // Apply opacity to the fill color
            if let color = fillColor {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
                color.getRed(&r, green: &g, blue: &b, alpha: &a)
                fillColor = NSColor(calibratedRed: r, green: g, blue: b, alpha: a * p.fillOpacity)
            }
        }
        
        return Annotation(
            kind: ShapeKind(rawValue: p.kind) ?? .rect,
            rect: CGRect(x: p.x, y: p.y, width: p.w, height: p.h),
            strokeColor: color(fromComponents: p.stroke),
            fillColor: fillColor,
            fillOpacity: p.fillOpacity,
            strokeWidth: p.strokeWidth,
            points: p.points.compactMap { pt in
                pt.count >= 2 ? CGPoint(x: pt[0], y: pt[1]) : nil
            },
            text: p.text,
            fontFamily: p.fontFamily,
            fontSize: p.fontSize,
            image: p.imagePNG.flatMap { imageFromPNG($0) },
            rounded: p.rounded,
            dashed: p.dashed,
            rotation: p.rotation,
            createdAt: p.createdAt,
            locked: p.locked,
            zIndex: p.zIndex
        )
    }
}

/// Full-screen transparent overlay where the user draws annotations on top of
/// whatever is on screen.
final class CanvasView: NSView, NSTextFieldDelegate {
    override var isFlipped: Bool { true }

    private let state: CanvasState
    private(set) var annotations: [Annotation] = [] {
        didSet { scheduleSave() }
    }
    private var undoStack: [[Annotation]] = []
    private var saveWorkItem: DispatchWorkItem?
    private var lastSavedData: Data?

    private var canvasOffset: CGPoint = .zero
    private var current: Annotation?
    private var dragStart: CGPoint = .zero
    private var dragOriginOffset: CGPoint = .zero
    private(set) var selected: Set<Int> = []
    private var movingOriginals: [Int: Annotation] = [:]
    private var resizeIndex: Int?
    private var resizeHandle: ResizeHandle?
    private var resizeOriginal: Annotation?
    private var rotateIndex: Int?
    private var rotateStartPoint: CGPoint = .zero
    private var rotateBaseRotation: CGFloat = 0
    private var lassoPoly: [CGPoint] = []
    private var eraseStroke: [CGPoint] = []
    private var editingField: NSTextField?
    private var editingIndex: Int?
    private var editingFontFamily: String?
    private var laserTimer: Timer?
    private var cursorTrackingArea: NSTrackingArea?
    private var cancellables = Set<AnyCancellable>()

    /// Laser strokes stay fully visible for `laserFadeStart` seconds, then fade
    /// out tail-first over `laserFadeDuration` seconds.
    private let laserFadeStart: TimeInterval = 2.0
    private let laserFadeDuration: TimeInterval = 1.5

    /// Diagonal resize cursors (AppKit only ships horizontal/vertical ones).
    let cursorTopLeft = CanvasView.makeDiagonalCursor(angle: -45)   // drag ↘
    let cursorTopRight = CanvasView.makeDiagonalCursor(angle: -135) // drag ↙
    let cursorBottomRight = CanvasView.makeDiagonalCursor(angle: 45) // drag ↗
    let cursorBottomLeft = CanvasView.makeDiagonalCursor(angle: 135) // drag ↖

    static func makeDiagonalCursor(angle: CGFloat) -> NSCursor {
        let px = 32
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        let t = NSAffineTransform()
        t.translateX(by: CGFloat(px) / 2, yBy: CGFloat(px) / 2)
        t.rotate(byDegrees: angle)
        t.translateX(by: -CGFloat(px) / 2, yBy: -CGFloat(px) / 2)
        t.concat()
        // White-outlined arrow pointing right, rotated to the drag direction.
        let shaft = NSBezierPath()
        shaft.move(to: NSPoint(x: 6, y: 16))
        shaft.line(to: NSPoint(x: 24, y: 16))
        shaft.lineWidth = 4
        shaft.lineCapStyle = .round
        NSColor.white.setStroke()
        shaft.stroke()
        let head = NSBezierPath()
        head.move(to: NSPoint(x: 26, y: 16))
        head.line(to: NSPoint(x: 18, y: 10))
        head.line(to: NSPoint(x: 18, y: 22))
        head.close()
        NSColor.white.setFill()
        head.fill()
        NSColor.black.setStroke()
        shaft.lineWidth = 2
        shaft.stroke()
        NSColor.black.setFill()
        head.fill()
        head.lineWidth = 2
        head.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: NSSize(width: px, height: px))
        img.addRepresentation(rep)
        return NSCursor(image: img, hotSpot: NSPoint(x: px / 2, y: px / 2))
    }

    private func setResizeCursor(for h: ResizeHandle, annotation a: Annotation) {
        switch h {
        case .topLeft: cursorTopLeft.set()
        case .topRight: cursorTopRight.set()
        case .bottomRight: cursorBottomRight.set()
        case .bottomLeft: cursorBottomLeft.set()
        case .topMid, .bottomMid: NSCursor.resizeUpDown.set()
        case .midLeft, .midRight: NSCursor.resizeLeftRight.set()
        case .startPoint, .endPoint:
            // Line/arrow endpoints — follow the line's dominant direction.
            if a.points.count >= 2,
               abs(a.points.last!.x - a.points.first!.x) > abs(a.points.last!.y - a.points.first!.y) {
                NSCursor.resizeLeftRight.set()
            } else {
                NSCursor.resizeUpDown.set()
            }
        }
    }

    var isEditingText: Bool { editingField != nil }

    init(state: CanvasState) {
        self.state = state
        super.init(frame: .zero)
        wantsLayer = true
        // Live font updates while a text field is open (size slider / font menu).
        Publishers.CombineLatest(state.$fontSize, state.$fontFamily)
            .dropFirst()
            .sink { [weak self] size, family in
                guard let self, let field = self.editingField else { return }
                field.font = Fonts.nsFont(for: family, size: size)
                self.editingFontFamily = family
            }
            .store(in: &cancellables)
        // Live color updates while a text field is open
        state.$strokeColor
            .dropFirst()
            .sink { [weak self] color in
                guard let self, let field = self.editingField else { return }
                field.textColor = color
            }
            .store(in: &cancellables)
        state.$canvasBackground
            .dropFirst()
            .sink { [weak self] _ in
                self?.needsDisplay = true
            }
            .store(in: &cancellables)
        laserTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.annotations.contains(where: { $0.kind == .laser }) else { return }
            let gone = Date().addingTimeInterval(-(self.laserFadeStart + self.laserFadeDuration))
            self.annotations.removeAll { laser in
                laser.kind == .laser
                    && (laser.pointTimes.last ?? laser.createdAt) < gone
            }
            // Redraw every tick while a laser exists so the fade animates.
            self.needsDisplay = true
        }
        loadAnnotations()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Click-through unless drawing mode is on — lets the user control their
    /// PC while the overlay is open.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard state.drawingMode else { return nil }
        return super.hitTest(point)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let area = cursorTrackingArea {
            removeTrackingArea(area)
        }
        let ta = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(ta)
        cursorTrackingArea = ta
    }

    override func mouseMoved(with event: NSEvent) {
        // In pass-through mode the cursor belongs to the apps below.
        guard state.drawingMode else { return }
        let p = convert(event.locationInWindow, from: nil)
        // Adjust for canvas offset in hit testing
        let adjustedP = CGPoint(x: p.x - canvasOffset.x, y: p.y - canvasOffset.y)
        switch state.tool {
        case .selection:
            if let sel = selected.first, sel < annotations.count {
                let a = annotations[sel]
                if let h = handle(at: adjustedP, for: a) {
                    setResizeCursor(for: h, annotation: a)
                } else if rotateHandle(at: adjustedP, for: a) {
                    NSCursor.arrow.set()
                } else if hitIndex(adjustedP) != nil {
                    NSCursor.openHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            } else if hitIndex(adjustedP) != nil {
                NSCursor.openHand.set()
            } else {
                NSCursor.arrow.set()
            }
        case .hand:
            NSCursor.openHand.set()
        case .text:
            NSCursor.iBeam.set()
        case .eraser, .bucketFill, .image:
            NSCursor.arrow.set()
        default:
            NSCursor.crosshair.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    // MARK: - mouse

    override func mouseDown(with event: NSEvent) {
        if state.tool != .text {
            editingField?.resignFirstResponder()
        }
        let p = convert(event.locationInWindow, from: nil)
        switch state.tool {
        case .selection:
            // Adjust for canvas offset in selection tool
            let adjustedP = CGPoint(x: p.x - canvasOffset.x, y: p.y - canvasOffset.y)
            dragStart = adjustedP
            if event.clickCount >= 2, let i = hitIndex(adjustedP), annotations[i].kind == .text {
                // Double-click an existing text to re-edit it.
                selected = [i]
                beginTextEditing(at: adjustedP, editingIndex: i)
                return
            }
            if let sel = selected.first, sel < annotations.count {
                let a = annotations[sel]
                if rotateHandle(at: adjustedP, for: a) {
                    rotateIndex = sel
                    rotateStartPoint = adjustedP
                    rotateBaseRotation = a.rotation
                    movingOriginals = [:]
                } else if let h = handle(at: adjustedP, for: a) {
                    // Dragging a handle of the currently selected shape resizes it.
                    resizeIndex = sel
                    resizeHandle = h
                    resizeOriginal = annotations[sel]
                    movingOriginals = [:]
                } else if let i = hitIndex(adjustedP) {
                    selected = [i]
                    movingOriginals = [i: annotations[i]]
                } else {
                    selected = []
                }
            } else if let i = hitIndex(adjustedP) {
                selected = [i]
                movingOriginals = [i: annotations[i]]
            } else {
                selected = []
            }
        case .hand:
            NSCursor.closedHand.set()
            dragStart = p
            dragOriginOffset = canvasOffset
        case .lasso:
            // Adjust for canvas offset in lasso tool
            let adjustedP = CGPoint(x: p.x - canvasOffset.x, y: p.y - canvasOffset.y)
            dragStart = adjustedP
            lassoPoly = [adjustedP]
        case .eraser:
            pushUndo()
            // Adjust for canvas offset in eraser tool
            let adjustedP = CGPoint(x: p.x - canvasOffset.x, y: p.y - canvasOffset.y)
            eraseStroke = [adjustedP]
            erase(at: adjustedP)
        case .bucketFill:
            // Adjust for canvas offset in bucket fill tool
            let adjustedP = CGPoint(x: p.x - canvasOffset.x, y: p.y - canvasOffset.y)
            if let i = hitIndex(adjustedP) {
                pushUndo()
                if state.fillEnabled {
                    annotations[i].fillColor = state.fillColor
                    annotations[i].fillOpacity = state.fillOpacity
                } else {
                    annotations[i].fillColor = nil
                }
                needsDisplay = true
                scheduleSave()
            }
        case .text:
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKey()
            // Adjust for canvas offset when hitting text
            let adjustedP = CGPoint(x: p.x - canvasOffset.x, y: p.y - canvasOffset.y)
            if let i = hitIndex(adjustedP), annotations[i].kind == .text {
                // Clicking an existing text edits it instead of creating a new one.
                beginTextEditing(at: adjustedP, editingIndex: i)
            } else {
                beginTextEditing(at: adjustedP)
            }
        case .image:
            // Image tool needs the raw window point (will be converted in pickImage)
            pickImage(at: p)
        default:
            // Adjust coordinates by canvas offset to ensure drawing works correctly after panning
            let adjustedP = CGPoint(x: p.x - canvasOffset.x, y: p.y - canvasOffset.y)
            dragStart = adjustedP
            let kind = state.tool.shapeKind ?? .rect
            current = Annotation(
                kind: kind,
                rect: CGRect(origin: adjustedP, size: .zero),
                strokeColor: state.strokeColor,
                fillColor: state.fillEnabled ? state.fillColor : nil,
                fillOpacity: state.fillOpacity,
                strokeWidth: state.strokeWidth,
                points: [adjustedP],
                pointTimes: [Date()],
                rounded: state.tool == .embeddable,
                dashed: state.tool == .frame
            )
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        switch state.tool {
        case .selection:
            // Adjust for canvas offset in selection tool
            let adjustedP = CGPoint(x: p.x - canvasOffset.x, y: p.y - canvasOffset.y)
            if let i = rotateIndex {
                let a = annotations[i]
                let center = CGPoint(x: a.rect.midX, y: a.rect.midY)
                let startAngle = atan2(rotateStartPoint.y - center.y, rotateStartPoint.x - center.x)
                let currentAngle = atan2(adjustedP.y - center.y, adjustedP.x - center.x)
                annotations[i].rotation = rotateBaseRotation + (currentAngle - startAngle)
            } else if let i = resizeIndex, let h = resizeHandle, let orig = resizeOriginal {
                annotations[i] = resizedAnnotation(orig, handle: h, p: adjustedP)
            } else if !movingOriginals.isEmpty {
                let delta = adjustedP - dragStart
                for (i, orig) in movingOriginals {
                    annotations[i].rect.origin = orig.rect.origin + delta
                    annotations[i].points = orig.points.map { $0 + delta }
                }
            }
        case .hand:
            canvasOffset = dragOriginOffset + (p - dragStart)
        case .lasso:
            // Adjust for canvas offset in lasso tool
            let adjustedP = CGPoint(x: p.x - canvasOffset.x, y: p.y - canvasOffset.y)
            lassoPoly.append(adjustedP)
        case .eraser:
            // Adjust for canvas offset in eraser tool
            let adjustedP = CGPoint(x: p.x - canvasOffset.x, y: p.y - canvasOffset.y)
            eraseStroke.append(adjustedP)
            erase(at: adjustedP)
        case .text:
            break
        default:
            guard var c = current else { return }
            // Adjust point by canvas offset for drawing tools
            let adjustedP = CGPoint(x: p.x - canvasOffset.x, y: p.y - canvasOffset.y)
            switch c.kind {
            case .rect, .diamond, .ellipse, .frame:
                c.rect = normalizedRect(from: dragStart, to: adjustedP)
            case .arrow, .line:
                c.points = [dragStart, adjustedP]
            case .freedraw, .laser, .autoshape:
                c.points.append(adjustedP)
                c.pointTimes.append(Date())
            default:
                break
            }
            current = c
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        // Adjust point by canvas offset for consistency
        let adjustedP = CGPoint(x: p.x - canvasOffset.x, y: p.y - canvasOffset.y)
        switch state.tool {
        case .selection:
            if rotateIndex != nil {
                if distance(dragStart, adjustedP) > 1 {
                    pushUndo()
                }
                rotateIndex = nil
            } else if resizeIndex != nil {
                if distance(dragStart, adjustedP) > 1 {
                    pushUndo()
                }
                resizeIndex = nil
                resizeHandle = nil
                resizeOriginal = nil
            } else if !movingOriginals.isEmpty, distance(dragStart, adjustedP) > 1 {
                pushUndo()
            }
            movingOriginals = [:]
            scheduleSave()
        case .hand:
            NSCursor.openHand.set()
            break
        case .lasso:
            finishLasso()
        case .eraser:
            eraseStroke = []
        case .text, .image, .bucketFill:
            break
        default:
            finalizeCurrent()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc — end text editing, or switch to selection tool
            if isEditingText {
                commitPendingText(selectAndPick: true)
            } else {
                // Switch to selection tool without clearing selection
                state.tool = .selection
                needsDisplay = true
            }
        } else if event.keyCode == 51 { // delete
            if !selected.isEmpty {
                pushUndo()
                // Don't delete locked annotations
                let deletable = selected.filter { !annotations[$0].locked }
                for i in deletable.sorted(by: >) {
                    annotations.remove(at: i)
                }
                selected = Set(deletable)
                needsDisplay = true
            }
        } else if event.modifierFlags.contains(.command),
                  event.charactersIgnoringModifiers?.lowercased() == "a" {
            selectAll()
        } else if event.modifierFlags.contains(.command),
                  event.charactersIgnoringModifiers?.lowercased() == "l" {
            // Lock/unlock selected annotations
            for i in selected {
                if annotations.indices.contains(i) {
                    annotations[i].locked.toggle()
                }
            }
            needsDisplay = true
        } else if event.modifierFlags.contains(.command),
                  event.charactersIgnoringModifiers?.lowercased() == "f" {
            // Bring to front
            bringToFront()
        } else if event.modifierFlags.contains(.command),
                  event.modifierFlags.contains(.shift),
                  event.charactersIgnoringModifiers?.lowercased() == "f" {
            // Send to back
            sendToBack()
        } else {
            super.keyDown(with: event)
        }
    }

    /// Selects every annotation so the user can move/resize or delete them all
    /// with one ⌘A + ⌫. Transient laser strokes are excluded.
    func selectAll() {
        guard !annotations.isEmpty else { return }
        selected = Set(annotations.indices.filter { annotations[$0].kind != .laser })
        needsDisplay = true
    }

    /// Brings selected annotations to the front (highest z-index)
    func bringToFront() {
        guard !selected.isEmpty else { return }
        let maxZ = annotations.map { $0.zIndex }.max() ?? 0
        for i in selected {
            if annotations.indices.contains(i) {
                annotations[i].zIndex = maxZ + 1
            }
        }
        needsDisplay = true
    }

    /// Sends selected annotations to the back (lowest z-index)
    func sendToBack() {
        guard !selected.isEmpty else { return }
        let minZ = annotations.map { $0.zIndex }.min() ?? 0
        for i in selected {
            if annotations.indices.contains(i) {
                annotations[i].zIndex = max(0, minZ - 1)
            }
        }
        needsDisplay = true
    }

    // MARK: - tools

    private func finalizeCurrent() {
        defer { current = nil }
        guard var c = current else { return }

        switch c.kind {
        case .rect, .diamond, .ellipse, .frame:
            guard c.rect.width > 2 || c.rect.height > 2 else { return }
        case .arrow, .line:
            c.rect = normalizedRect(from: c.points.first ?? dragStart, to: c.points.last ?? dragStart)
            guard distance(c.points.first ?? .zero, c.points.last ?? .zero) > 2 else { return }
        case .freedraw:
            c.rect = boundingRect(of: c.points)
            guard c.points.count > 1 else { return }
        case .autoshape:
            guard c.points.count > 2 else { return }
            c.points = smooth(c.points)
            c.rect = boundingRect(of: c.points)
        case .laser:
            c.strokeColor = NSColor(red: 1, green: 0.24, blue: 0.18, alpha: 1)
            c.strokeWidth = 3
            c.rect = boundingRect(of: c.points)
            guard c.points.count > 1 else { return }
        default:
            return
        }

        pushUndo()
        annotations.append(c)
        // Keep the drawn shape selected (so pressing V lets you move/resize it
        // right away) but stay on the current tool — no need to re-press D.
        selected = [annotations.count - 1]
        needsDisplay = true
    }

    private func beginTextEditing(at p: CGPoint, editingIndex: Int? = nil) {
        guard editingField == nil else { return }
        let existing: Annotation? = editingIndex.flatMap { idx in
            annotations.indices.contains(idx) ? annotations[idx] : nil
        }
        let family = existing?.fontFamily ?? state.fontFamily
        let size = existing?.fontSize ?? state.fontSize
        editingFontFamily = family
        self.editingIndex = editingIndex
        let field = NSTextField(
            frame: existing.map {
                CGRect(x: $0.rect.minX, y: $0.rect.minY - 6, width: max(160, $0.rect.width), height: 34)
            } ?? CGRect(x: p.x, y: p.y - 6, width: 260, height: 34)
        )
        field.isBordered = false
        field.drawsBackground = false
        field.font = Fonts.nsFont(for: family, size: size)
        field.textColor = existing?.strokeColor ?? state.strokeColor
        if let existing, !existing.text.isEmpty {
            field.stringValue = existing.text
        }
        field.placeholderString = "Type…"
        field.delegate = self
        field.wantsLayer = true
        field.layer?.borderColor = NSColor(calibratedRed: 0.42, green: 0.4, blue: 0.86, alpha: 1).cgColor
        field.layer?.borderWidth = 1
        field.layer?.cornerRadius = 4
        addSubview(field)
        editingField = field
        window?.makeFirstResponder(field)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitTextEditing()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitPendingText(selectAndPick: true)
            return true
        }
        return false
    }

    /// Commits any open text field (used when the overlay is dismissed).
    /// When `selectAndPick` is true (Esc / Enter), the committed text is
    /// selected and the selection tool is activated so it can be moved/resized.
    func commitPendingText(selectAndPick: Bool = false) {
        let idx = commitTextEditing()
        if selectAndPick, let i = idx {
            selected = [i]
            state.tool = .selection
            needsDisplay = true
        }
    }

    /// Self-test hook: sets the text of the open editing field.
    func selftestSetText(_ s: String) {
        editingField?.stringValue = s
    }

    /// Commits the open text field. Returns the index of the committed text
    /// annotation (newly created or re-edited), or nil when nothing was
    /// committed (empty new text, or an emptied re-edit deletes the annotation).
    @discardableResult
    private func commitTextEditing() -> Int? {
        guard let field = editingField else { return nil }
        // Leave text mode on every commit path (Esc, Enter, click-away,
        // overlay close) so the next click doesn't open a new text field.
        state.tool = state.lastNonTextTool
        editingField = nil
        field.resignFirstResponder()
        window?.makeFirstResponder(self)
        let str = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let family = editingFontFamily ?? state.fontFamily
        let size = field.font?.pointSize ?? state.fontSize
        let idx = editingIndex
        editingIndex = nil
        editingFontFamily = nil
        field.removeFromSuperview()

        // Clearing an existing text deletes the annotation.
        if str.isEmpty {
            if let idx, annotations.indices.contains(idx) {
                pushUndo()
                annotations.remove(at: idx)
                selected = []
            }
            needsDisplay = true
            return nil
        }

        let font = field.font ?? Fonts.nsFont(for: family, size: size)
        let width = max(60, field.frame.width)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let bounds = (str as NSString).boundingRect(
            with: NSSize(width: width, height: 100_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        var r = field.frame
        r.size = CGSize(width: width, height: max(bounds.height, size * 1.4))
        pushUndo()
        if let idx, annotations.indices.contains(idx) {
            var updated = annotations[idx]
            updated.rect = r
            updated.text = str
            updated.fontFamily = family
            updated.fontSize = size
            updated.fillOpacity = state.fillOpacity
            annotations[idx] = updated
            needsDisplay = true
            return idx
        }
        annotations.append(Annotation(
            kind: .text,
            rect: r,
            strokeColor: state.strokeColor,
            fillColor: nil,
            fillOpacity: state.fillOpacity,
            strokeWidth: 2,
            points: [],
            pointTimes: [],
            text: str,
            fontFamily: family,
            fontSize: size,
            image: nil,
            rounded: false,
            dashed: false,
            rotation: 0,
            createdAt: Date(),
            locked: false,
            zIndex: 0
        ))
        needsDisplay = true
        return annotations.count - 1
    }

    /// Inserts an emoji "logo" at the given canvas point (used by the "/" palette).
    func insertEmoji(_ emoji: String, at p: CGPoint) {
        // Adjust for canvas offset
        let adjustedP = CGPoint(x: p.x - canvasOffset.x, y: p.y - canvasOffset.y)
        let size: CGFloat = 48
        let font = NSFont.systemFont(ofSize: size)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let bounds = (emoji as NSString).boundingRect(
            with: NSSize(width: 300, height: 300),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        pushUndo()
        annotations.append(Annotation(
            kind: .text,
            rect: CGRect(
                x: adjustedP.x - bounds.width / 2,
                y: adjustedP.y - bounds.height / 2,
                width: max(bounds.width, 24),
                height: max(bounds.height, 24)
            ),
            strokeColor: .black,
            fillColor: nil,
            fillOpacity: state.fillOpacity,
            strokeWidth: 2,
            points: [],
            pointTimes: [],
            text: emoji,
            fontFamily: "System",
            fontSize: size,
            image: nil,
            rounded: false,
            dashed: false,
            rotation: 0,
            createdAt: Date(),
            locked: false,
            zIndex: 0
        ))
        selected = [annotations.count - 1]
        needsDisplay = true
    }

    private func pickImage(at p: CGPoint) {
        // Store the window point for later conversion
        let windowPoint = p
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.title = "Choose Image"
        panel.prompt = "Choose"
        
        // Run as modal sheet on the main window
        if let window = self.window {
            panel.beginSheetModal(for: window) { [weak self] response in
                guard let self, response == .OK, let url = panel.url,
                      let img = NSImage(contentsOf: url) else { return }
                let maxW: CGFloat = 360
                var s = img.size
                if s.width > maxW {
                    let k = maxW / s.width
                    s = CGSize(width: maxW, height: s.height * k)
                }
                // Convert window point to canvas coordinates at placement time
                let canvasPoint = self.convert(windowPoint, from: nil)
                let adjustedPoint = CGPoint(x: canvasPoint.x - self.canvasOffset.x, y: canvasPoint.y - self.canvasOffset.y)
                self.pushUndo()
                self.annotations.append(Annotation(
                    kind: .image,
                    rect: CGRect(origin: adjustedPoint, size: s),
                    strokeColor: .black,
                    fillColor: nil,
                    fillOpacity: state.fillOpacity,
                    strokeWidth: 2,
                    points: [],
                    pointTimes: [],
                    text: "",
                    fontFamily: "Virgil",
                    fontSize: 24,
                    image: img,
                    rounded: false,
                    dashed: false,
                    rotation: 0,
                    createdAt: Date(),
                    locked: false,
                    zIndex: 0
                ))
                self.needsDisplay = true
            }
        } else {
            // Fallback to non-sheet if no window
            panel.begin { [weak self] response in
                guard let self, response == .OK, let url = panel.url,
                      let img = NSImage(contentsOf: url) else { return }
                let maxW: CGFloat = 360
                var s = img.size
                if s.width > maxW {
                    let k = maxW / s.width
                    s = CGSize(width: maxW, height: s.height * k)
                }
                // Convert window point to canvas coordinates at placement time
                let canvasPoint = self.convert(windowPoint, from: nil)
                let adjustedPoint = CGPoint(x: canvasPoint.x - self.canvasOffset.x, y: canvasPoint.y - self.canvasOffset.y)
                self.pushUndo()
                self.annotations.append(Annotation(
                    kind: .image,
                    rect: CGRect(origin: adjustedPoint, size: s),
                    strokeColor: .black,
                    fillColor: nil,
                    fillOpacity: state.fillOpacity,
                    strokeWidth: 2,
                    points: [],
                    pointTimes: [],
                    text: "",
                    fontFamily: "Virgil",
                    fontSize: 24,
                    image: img,
                    rounded: false,
                    dashed: false,
                    rotation: 0,
                    createdAt: Date(),
                    locked: false,
                    zIndex: 0
                ))
                self.needsDisplay = true
            }
        }
    }

    private func erase(at p: CGPoint) {
        var toRemove: [Int] = []
        for (i, a) in annotations.enumerated() where a.kind != .laser {
            let r = a.rect.insetBy(dx: -16, dy: -16)
            if r.contains(p) {
                toRemove.append(i)
            }
        }
        if !toRemove.isEmpty {
            for i in toRemove.sorted(by: >) {
                annotations.remove(at: i)
            }
            selected = []
            needsDisplay = true
        }
    }

    private func finishLasso() {
        guard lassoPoly.count > 2 else {
            lassoPoly = []
            return
        }
        selected = Set(annotations.indices.filter { i in
            let a = annotations[i]
            let r = a.rect
            let corners = [
                r.origin,
                CGPoint(x: r.maxX, y: r.minY),
                CGPoint(x: r.maxX, y: r.maxY),
                CGPoint(x: r.minX, y: r.maxY),
            ]
            return corners.contains { pointInPolygon($0, lassoPoly) }
                || pointInPolygon(CGPoint(x: r.midX, y: r.midY), lassoPoly)
        })
        lassoPoly = []
        needsDisplay = true
    }

    // MARK: - undo

    private func pushUndo() {
        undoStack.append(annotations)
        if undoStack.count > 50 {
            undoStack.removeFirst()
        }
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        annotations = prev
        selected = []
        movingOriginals = [:]
        needsDisplay = true
    }

    func clearAll() {
        guard !annotations.isEmpty else { return }
        pushUndo()
        annotations = []
        selected = []
        needsDisplay = true
    }

    // MARK: - persistence

    /// JSON file the drawing is saved to, so it survives app relaunches.
    private var persistURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent("MacDraw", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("annotations.json")
    }

    /// Writes the current drawing to disk (laser strokes are transient, so they
    /// are never persisted). Skips the write when nothing changed.
    private func saveAnnotations() {
        let items = annotations.filter { $0.kind != .laser }.map { $0.persisted() }
        guard let data = try? JSONEncoder().encode(items) else { return }
        if data == lastSavedData { return }
        lastSavedData = data
        try? data.write(to: persistURL, options: .atomic)
    }

    /// Coalesces bursts of edits (e.g. drag frames) into a single disk write.
    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveAnnotations() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    /// Restores the drawing saved by a previous session (called on init).
    private func loadAnnotations() {
        guard let data = try? Data(contentsOf: persistURL) else { return }
        let items = (try? JSONDecoder().decode([PersistedAnnotation].self, from: data)) ?? []
        annotations = items.map { .restored(from: $0) }
        needsDisplay = true
    }

    func deleteSelected() {
        guard !selected.isEmpty else { return }
        pushUndo()
        for i in selected.sorted(by: >) {
            annotations.remove(at: i)
        }
        selected = []
        needsDisplay = true
    }

    // MARK: - drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let ctx = NSGraphicsContext.current else { return }

        // Solid backdrop — "writing on a white/black screen" mode.
        switch state.canvasBackground {
        case .white:
            NSColor.white.setFill()
            bounds.fill()
        case .black:
            NSColor.black.setFill()
            bounds.fill()
        case .clear:
            break
        }

        ctx.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: canvasOffset.x, yBy: canvasOffset.y)
        t.concat()

        // Sort annotations by z-index for proper layering
        let sortedAnnotations = annotations.enumerated().sorted { $0.element.zIndex < $1.element.zIndex }
        for (i, a) in sortedAnnotations {
            draw(annotation: a, index: i)
        }

        if let c = current, c.kind != .text, c.kind != .image {
            draw(annotation: c, index: -1)
        }

        if lassoPoly.count > 1 {
            let path = NSBezierPath()
            path.move(to: lassoPoly[0])
            for p in lassoPoly.dropFirst() { path.line(to: p) }
            path.close()
            NSColor(calibratedRed: 0.42, green: 0.4, blue: 0.86, alpha: 0.18).setFill()
            path.fill()
            NSColor(calibratedRed: 0.42, green: 0.4, blue: 0.86, alpha: 0.9).setStroke()
            path.lineWidth = 1.5
            path.setLineDash([6, 4], count: 2, phase: 0)
            path.stroke()
        }

        if let sel = selected.first, sel >= 0, sel < annotations.count {
            drawSelectionOverlay(for: annotations[sel])
        }

        ctx.restoreGraphicsState()
    }

    private func draw(annotation a: Annotation, index: Int) {
        let center = CGPoint(x: a.rect.midX, y: a.rect.midY)
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.rotate(byDegrees: a.rotation * 180 / .pi)
        transform.translateX(by: -center.x, yBy: -center.y)
        transform.concat()
        switch a.kind {
        case .text:
            drawText(a)
        case .image:
            a.image?.draw(in: a.rect)
        case .laser:
            drawLaser(a)
        default:
            let path = bezierPath(for: a)
            if let fill = a.fillColor, isClosed(a.kind) {
                // Apply fill opacity
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a_comp: CGFloat = 1
                fill.getRed(&r, green: &g, blue: &b, alpha: &a_comp)
                let colorWithOpacity = NSColor(calibratedRed: r, green: g, blue: b, alpha: a_comp * a.fillOpacity)
                colorWithOpacity.setFill()
                path.fill()
            }
            a.strokeColor.setStroke()
            path.lineWidth = a.strokeWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            if a.dashed {
                path.setLineDash([12, 8], count: 2, phase: 0)
            }
            path.stroke()
            if a.kind == .arrow, let end = a.points.last {
                let from = a.points.count > 1 ? a.points[a.points.count - 2] : end
                drawArrowhead(at: end, from: from, color: a.strokeColor, width: a.strokeWidth)
            }
        }

        if selected.contains(index) {
            let outline = a.rect.insetBy(dx: -4, dy: -4)
            let sel = NSColor(calibratedRed: 0.42, green: 0.4, blue: 0.86, alpha: 1)
            sel.setStroke()
            let op = NSBezierPath(rect: outline)
            op.lineWidth = 1.5
            op.setLineDash([5, 3], count: 2, phase: 0)
            op.stroke()
        }
    }

    // MARK: - selection handles

    private func handleRects(for a: Annotation) -> [(ResizeHandle, CGRect)] {
        let s: CGFloat = 10
        func rect(at c: CGPoint) -> CGRect {
            CGRect(x: c.x - s / 2, y: c.y - s / 2, width: s, height: s)
        }
        if a.kind == .line || a.kind == .arrow {
            let first = a.points.first ?? .zero
            let last = a.points.last ?? first
            return [(.startPoint, rect(at: first)), (.endPoint, rect(at: last))]
        }
        let b = a.rect
        return [
            (.topLeft, rect(at: CGPoint(x: b.minX, y: b.minY))),
            (.topMid, rect(at: CGPoint(x: b.midX, y: b.minY))),
            (.topRight, rect(at: CGPoint(x: b.maxX, y: b.minY))),
            (.midRight, rect(at: CGPoint(x: b.maxX, y: b.midY))),
            (.bottomRight, rect(at: CGPoint(x: b.maxX, y: b.maxY))),
            (.bottomMid, rect(at: CGPoint(x: b.midX, y: b.maxY))),
            (.bottomLeft, rect(at: CGPoint(x: b.minX, y: b.maxY))),
            (.midLeft, rect(at: CGPoint(x: b.minX, y: b.midY))),
        ]
    }

    private func handle(at p: CGPoint, for a: Annotation) -> ResizeHandle? {
        let localP = rotatedPoint(p, around: CGPoint(x: a.rect.midX, y: a.rect.midY), by: -a.rotation)
        for (h, rect) in handleRects(for: a) where rect.insetBy(dx: -2, dy: -2).contains(localP) {
            return h
        }
        return nil
    }

    /// Selection outline + handles drawn on top of every other annotation,
    /// rotated together with the selected shape.
    private func drawSelectionOverlay(for a: Annotation) {
        let center = CGPoint(x: a.rect.midX, y: a.rect.midY)
        let t = NSAffineTransform()
        t.translateX(by: center.x, yBy: center.y)
        t.rotate(byDegrees: a.rotation * 180 / .pi)
        t.translateX(by: -center.x, yBy: -center.y)
        t.concat()
        drawSelectionHandles(for: a)
        drawRotateHandle(for: a)
        t.invert()
        t.concat()
    }

    private func rotateHandleRects(for a: Annotation) -> [CGRect] {
        guard a.kind != .line, a.kind != .arrow, a.kind != .laser else { return [] }
        let s: CGFloat = 14
        let c = CGPoint(x: a.rect.midX, y: a.rect.minY - 28)
        return [CGRect(x: c.x - s / 2, y: c.y - s / 2, width: s, height: s)]
    }

    private func rotateHandle(at p: CGPoint, for a: Annotation) -> Bool {
        let localP = rotatedPoint(p, around: CGPoint(x: a.rect.midX, y: a.rect.midY), by: -a.rotation)
        return rotateHandleRects(for: a).contains { $0.insetBy(dx: -2, dy: -2).contains(localP) }
    }

    private func drawRotateHandle(for a: Annotation) {
        let s: CGFloat = 14
        let c = CGPoint(x: a.rect.midX, y: a.rect.minY - 28)
        let sel = NSColor(calibratedRed: 0.42, green: 0.4, blue: 0.86, alpha: 1)
        let line = NSBezierPath()
        line.move(to: CGPoint(x: a.rect.midX, y: a.rect.minY))
        line.line(to: c)
        sel.setStroke()
        line.lineWidth = 1.5
        line.stroke()
        let circle = NSBezierPath(ovalIn: CGRect(x: c.x - s / 2, y: c.y - s / 2, width: s, height: s))
        NSColor.white.setFill()
        circle.fill()
        sel.setStroke()
        circle.lineWidth = 1.5
        circle.stroke()
    }

    /// Rotate `p` by `angle` (radians) around `center`.
    private func rotatedPoint(_ p: CGPoint, around center: CGPoint, by angle: CGFloat) -> CGPoint {
        let dx = p.x - center.x
        let dy = p.y - center.y
        let cosA = cos(angle)
        let sinA = sin(angle)
        return CGPoint(x: center.x + dx * cosA - dy * sinA, y: center.y + dx * sinA + dy * cosA)
    }

    private func resizedAnnotation(_ a: Annotation, handle: ResizeHandle, p: CGPoint) -> Annotation {
        var a = a
        let orig = a.rect

        // Lines and arrows resize from their two endpoint handles.
        if handle == .startPoint || handle == .endPoint {
            guard !a.points.isEmpty else { return a }
            var pts = a.points
            if handle == .startPoint {
                pts[0] = p
            } else {
                pts[pts.count - 1] = p
            }
            a.points = pts
            a.rect = boundingRect(of: pts)
            return a
        }

        var minX = orig.minX, maxX = orig.maxX
        var minY = orig.minY, maxY = orig.maxY
        let minSize: CGFloat = 6
        switch handle {
        case .topLeft, .midLeft, .bottomLeft:
            minX = min(p.x, maxX - minSize)
        case .topRight, .midRight, .bottomRight:
            maxX = max(p.x, minX + minSize)
        default:
            break
        }
        switch handle {
        case .topLeft, .topMid, .topRight:
            minY = min(p.y, maxY - minSize)
        case .bottomLeft, .bottomMid, .bottomRight:
            maxY = max(p.y, minY + minSize)
        default:
            break
        }
        let newRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        switch a.kind {
        case .text:
            // Horizontal resize: change width only, keep font size constant
            // Vertical resize: change font size based on height change
            let horizontalHandles: [ResizeHandle] = [.midLeft, .midRight]
            let verticalHandles: [ResizeHandle] = [.topMid, .bottomMid]
            let cornerHandles: [ResizeHandle] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
            
            if horizontalHandles.contains(handle) {
                // Only change width, keep font size
                a.rect = CGRect(x: newRect.minX, y: orig.minY, width: newRect.width, height: orig.height)
            } else if verticalHandles.contains(handle) {
                // Only change font size, keep width
                let sy = newRect.height / max(1, orig.height)
                a.fontSize = max(6, min(300, a.fontSize * sy))
                a.rect = CGRect(x: orig.minX, y: newRect.minY, width: orig.width, height: a.fontSize * 1.4)
            } else if cornerHandles.contains(handle) {
                // Corner handles: change both
                let sx = newRect.width / max(1, orig.width)
                let sy = newRect.height / max(1, orig.height)
                a.fontSize = max(6, min(300, a.fontSize * max(sx, sy)))
                a.rect = CGRect(x: newRect.minX, y: newRect.minY, width: newRect.width, height: a.fontSize * 1.4)
            }
        case .freedraw, .autoshape, .laser:
            let fixedX: CGFloat
            switch handle {
            case .topLeft, .midLeft, .bottomLeft: fixedX = orig.maxX
            default: fixedX = orig.minX
            }
            let fixedY: CGFloat
            switch handle {
            case .topLeft, .topMid, .topRight: fixedY = orig.maxY
            default: fixedY = orig.minY
            }
            let sx = newRect.width / max(1, orig.width)
            let sy = newRect.height / max(1, orig.height)
            a.points = a.points.map { pt in
                CGPoint(x: fixedX + (pt.x - fixedX) * sx, y: fixedY + (pt.y - fixedY) * sy)
            }
            a.rect = newRect
        default:
            a.rect = newRect
        }
        return a
    }

    private func drawSelectionHandles(for a: Annotation) {
        let blue = NSColor(calibratedRed: 0.42, green: 0.4, blue: 0.86, alpha: 1)
        for (_, rect) in handleRects(for: a) {
            NSColor.white.setFill()
            NSBezierPath(rect: rect).fill()
            blue.setStroke()
            let outline = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            outline.lineWidth = 1.5
            outline.stroke()
        }
    }

    /// Laser pointer line: rendered as one continuous path with a blurred
    /// shadow glow (smooth joints, no per-segment blob artifacts) that fades
    /// away tail-first.
    private func drawLaser(_ a: Annotation) {
        let pts = a.points
        guard pts.count > 1 else { return }
        let now = Date()
        let color = NSColor(red: 1, green: 0.24, blue: 0.18, alpha: 1)

        // Tail-first trim: skip points that have fully faded.
        let goneBefore = now.addingTimeInterval(-(laserFadeStart + laserFadeDuration))
        var start = 0
        while start < pts.count - 1,
              laserPointTime(a, index: start) < goneBefore {
            start += 1
        }
        guard start < pts.count - 1 else { return }

        let path = NSBezierPath()
        path.move(to: pts[start])
        for i in (start + 1)..<pts.count {
            path.line(to: pts[i])
        }
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        let glowShadow = NSShadow()
        glowShadow.shadowColor = color.withAlphaComponent(0.85)
        glowShadow.shadowBlurRadius = 14
        glowShadow.shadowOffset = .zero

        NSGraphicsContext.saveGraphicsState()
        glowShadow.set()

        // Wide soft pass — hot center of the glow.
        let soft = path.copy() as! NSBezierPath
        soft.lineWidth = a.strokeWidth * 2.4
        color.withAlphaComponent(0.55).setStroke()
        soft.stroke()

        // Bright thin core.
        color.setStroke()
        path.lineWidth = a.strokeWidth
        path.stroke()

        NSGraphicsContext.restoreGraphicsState()

        // The segment that is currently dissolving — drawn at partial alpha
        // so the tail shrinks smoothly.
        if start > 0 {
            let i = start - 1
            let alpha = laserAlpha(for: now.timeIntervalSince(laserPointTime(a, index: i)))
            guard alpha > 0.02 else { return }
            let seg = NSBezierPath()
            seg.move(to: pts[i])
            seg.line(to: pts[start])
            seg.lineCapStyle = .round

            NSGraphicsContext.saveGraphicsState()
            glowShadow.set()
            let softSeg = seg.copy() as! NSBezierPath
            softSeg.lineWidth = a.strokeWidth * 2.4
            color.withAlphaComponent(0.55 * alpha).setStroke()
            softSeg.stroke()
            color.withAlphaComponent(alpha).setStroke()
            seg.lineWidth = a.strokeWidth
            seg.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func laserPointTime(_ a: Annotation, index: Int) -> Date {
        a.pointTimes.indices.contains(index) ? a.pointTimes[index] : a.createdAt
    }

    private func laserAlpha(for age: TimeInterval) -> CGFloat {
        if age < laserFadeStart { return 1 }
        let t = (age - laserFadeStart) / laserFadeDuration
        return CGFloat(max(0, 1 - t))
    }

    private func drawText(_ a: Annotation) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Fonts.nsFont(for: a.fontFamily, size: a.fontSize),
            .foregroundColor: a.strokeColor,
        ]
        a.text.draw(
            with: a.rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
    }

    private func drawArrowhead(at end: CGPoint, from prev: CGPoint, color: NSColor, width: CGFloat) {
        let dx = end.x - prev.x
        let dy = end.y - prev.y
        let len = max(1, sqrt(dx * dx + dy * dy))
        let ux = dx / len
        let uy = dy / len
        let size = max(10, width * 3)
        let p1 = CGPoint(x: end.x - ux * size + uy * size * 0.5, y: end.y - uy * size - ux * size * 0.5)
        let p2 = CGPoint(x: end.x - ux * size - uy * size * 0.5, y: end.y - uy * size + ux * size * 0.5)
        let path = NSBezierPath()
        path.move(to: p1)
        path.line(to: end)
        path.line(to: p2)
        color.setStroke()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    // MARK: - geometry

    private func bezierPath(for a: Annotation) -> NSBezierPath {
        let r = a.rect
        let path = NSBezierPath()
        switch a.kind {
        case .rect:
            path.appendRect(r)
        case .frame:
            if a.rounded {
                path.appendRoundedRect(r, xRadius: 12, yRadius: 12)
            } else {
                path.appendRect(r)
            }
        case .diamond:
            let c = CGPoint(x: r.midX, y: r.midY)
            path.move(to: CGPoint(x: c.x, y: r.maxY))
            path.line(to: CGPoint(x: r.maxX, y: c.y))
            path.line(to: CGPoint(x: c.x, y: r.minY))
            path.line(to: CGPoint(x: r.minX, y: c.y))
            path.close()
        case .ellipse:
            path.appendOval(in: r)
        case .arrow, .line, .freedraw, .laser:
            let pts = a.points
            guard pts.count > 1 else { return path }
            path.move(to: pts[0])
            for p in pts.dropFirst() {
                path.line(to: p)
            }
        case .autoshape:
            let pts = a.points
            guard pts.count > 2 else { return path }
            path.move(to: pts[0])
            for i in 0..<pts.count {
                let cur = pts[i]
                let next = pts[(i + 1) % pts.count]
                let mid = CGPoint(x: (cur.x + next.x) / 2, y: (cur.y + next.y) / 2)
                path.curve(
                    to: mid,
                    controlPoint1: i == 0 ? pts[pts.count - 1] : pts[i - 1],
                    controlPoint2: cur
                )
            }
            path.close()
        default:
            break
        }
        return path
    }

    private func isClosed(_ kind: ShapeKind) -> Bool {
        switch kind {
        case .rect, .diamond, .ellipse, .frame, .autoshape:
            return true
        default:
            return false
        }
    }

    private func hitIndex(_ p: CGPoint) -> Int? {
        for (i, a) in annotations.enumerated().reversed() {
            if a.kind == .laser { continue }
            let localP = rotatedPoint(p, around: CGPoint(x: a.rect.midX, y: a.rect.midY), by: -a.rotation)
            switch a.kind {
            case .text, .image:
                if a.rect.insetBy(dx: -8, dy: -8).contains(localP) { return i }
            default:
                let path = bezierPath(for: a)
                if path.contains(localP) { return i }
                let threshold = max(10, a.strokeWidth / 2 + 6)
                if distanceToPath(localP, path) < threshold { return i }
            }
        }
        return nil
    }

    private func distanceToPath(_ p: CGPoint, _ path: NSBezierPath) -> CGFloat {
        var minD = CGFloat.greatestFiniteMagnitude
        var last = CGPoint.zero
        var haveLast = false
        for i in 0..<path.elementCount {
            let pts = UnsafeMutablePointer<NSPoint>.allocate(capacity: 3)
            defer { pts.deallocate() }
            let kind = path.element(at: i, associatedPoints: pts)
            switch kind {
            case .moveTo:
                last = pts[0]
                haveLast = true
            case .lineTo:
                if haveLast {
                    minD = min(minD, distancePointToSegment(p, last, pts[0]))
                }
                last = pts[0]
            case .curveTo, .cubicCurveTo:
                if haveLast {
                    var prev = last
                    for k in 1...10 {
                        let f = CGFloat(k) / 10
                        let q = cubicPoint(prev, pts[0], pts[1], pts[2], t: f)
                        minD = min(minD, distancePointToSegment(p, prev, q))
                        prev = q
                    }
                }
                last = pts[2]
            case .quadraticCurveTo:
                if haveLast {
                    var prev = last
                    for k in 1...10 {
                        let f = CGFloat(k) / 10
                        let q = quadPoint(prev, pts[0], pts[1], t: f)
                        minD = min(minD, distancePointToSegment(p, prev, q))
                        prev = q
                    }
                }
                last = pts[1]
            case .closePath:
                break
            @unknown default:
                break
            }
        }
        return minD
    }

    private func cubicPoint(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p1: CGPoint, t: CGFloat) -> CGPoint {
        let mt = 1 - t
        let x = mt * mt * mt * p0.x + 3 * mt * mt * t * c1.x + 3 * mt * t * t * c2.x + t * t * t * p1.x
        let y = mt * mt * mt * p0.y + 3 * mt * mt * t * c1.y + 3 * mt * t * t * c2.y + t * t * t * p1.y
        return CGPoint(x: x, y: y)
    }

    private func quadPoint(_ p0: CGPoint, _ q: CGPoint, _ p1: CGPoint, t: CGFloat) -> CGPoint {
        let mt = 1 - t
        let x = mt * mt * p0.x + 2 * mt * t * q.x + t * t * p1.x
        let y = mt * mt * p0.y + 2 * mt * t * q.y + t * t * p1.y
        return CGPoint(x: x, y: y)
    }

    private func distancePointToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        if len2 == 0 { return distance(p, a) }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2
        t = max(0, min(1, t))
        let q = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return distance(p, q)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    private func pointInPolygon(_ p: CGPoint, _ poly: [CGPoint]) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i]
            let b = poly[j]
            if (a.y > p.y) != (b.y > p.y),
               p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    private func normalizedRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }

    private func boundingRect(of pts: [CGPoint]) -> CGRect {
        guard let first = pts.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in pts.dropFirst() {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func smooth(_ pts: [CGPoint]) -> [CGPoint] {
        var out = pts
        for _ in 0..<2 {
            var next: [CGPoint] = []
            for i in 0..<(out.count - 1) {
                let p0 = out[i]
                let p1 = out[i + 1]
                next.append(CGPoint(x: p0.x * 0.75 + p1.x * 0.25, y: p0.y * 0.75 + p1.y * 0.25))
                next.append(CGPoint(x: p0.x * 0.25 + p1.x * 0.75, y: p0.y * 0.25 + p1.y * 0.75))
            }
            next.append(out.last!)
            out = next
        }
        return out
    }
}
