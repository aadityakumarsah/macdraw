import AppKit
import Combine

private func + (l: CGPoint, r: CGPoint) -> CGPoint {
    CGPoint(x: l.x + r.x, y: l.y + r.y)
}

private func - (l: CGPoint, r: CGPoint) -> CGPoint {
    CGPoint(x: l.x - r.x, y: l.y - r.y)
}

private extension NSBezierPath {
    /// Quadratic curve segment — AppKit only ships cubic `curve(to:)`, so the
    /// quadratic is converted using the standard cubic representation.
    func quadCurve(to endPoint: NSPoint, controlPoint: NSPoint) {
        let p0 = currentPoint
        let c1 = NSPoint(
            x: p0.x + 2.0 / 3.0 * (controlPoint.x - p0.x),
            y: p0.y + 2.0 / 3.0 * (controlPoint.y - p0.y)
        )
        let c2 = NSPoint(
            x: endPoint.x + 2.0 / 3.0 * (controlPoint.x - endPoint.x),
            y: endPoint.y + 2.0 / 3.0 * (controlPoint.y - endPoint.y)
        )
        curve(to: endPoint, controlPoint1: c1, controlPoint2: c2)
    }
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
    var strokeStyle: String?
    var sloppiness: CGFloat?
    var edgeRoughness: CGFloat?
    var rx: CGFloat?
    var ry: CGFloat?
    var textInside: Bool?
    var textAnchor: String?
    var dynamicWidth: Bool?
    var symbol: String?
    var isCode: Bool?
    var normalFontFamily: String?
    var normalFontSize: CGFloat?
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
            zIndex: zIndex,
            strokeStyle: strokeStyle.rawValue,
            sloppiness: sloppiness,
            edgeRoughness: edgeRoughness,
            rx: rx,
            ry: ry,
            textInside: textInside,
            textAnchor: textAnchor.rawValue,
            dynamicWidth: dynamicWidth,
            symbol: symbol,
            isCode: isCode,
            normalFontFamily: normalFontFamily,
            normalFontSize: normalFontSize
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

        // Legacy frames/embeddable shapes were stored with a plain `rounded`
        // flag — map that onto the new corner-radius fields so they render the
        // same as before.
        var rx = p.rx ?? 0
        var ry = p.ry ?? 0
        if p.rounded && rx == 0 && ry == 0 {
            rx = 12
            ry = 12
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
            zIndex: p.zIndex,
            strokeStyle: StrokeStyle(rawValue: p.strokeStyle ?? "") ?? .solid,
            sloppiness: p.sloppiness ?? 0,
            edgeRoughness: p.edgeRoughness ?? 0,
            rx: rx,
            ry: ry,
            textInside: p.textInside ?? false,
            textAnchor: TextAnchor(rawValue: p.textAnchor ?? "") ?? .center,
            dynamicWidth: p.dynamicWidth ?? false,
            symbol: p.symbol,
            isCode: p.isCode ?? false,
            normalFontFamily: p.normalFontFamily,
            normalFontSize: p.normalFontSize
        )
    }
}

/// Full-screen transparent overlay where the user draws annotations on top of
/// whatever is on screen.
final class CanvasView: NSView, NSTextViewDelegate {
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
    private var marqueeStart: CGPoint?
    private var marqueeRect: CGRect = .zero
    private var eraseStroke: [CGPoint] = []
    /// Shape whose edge connection dots are shown (connector tools only).
    private var hoverShapeIndex: Int?
    private var hoverSide: Int?
    private var editingView: NSTextView?
    private var editingIndex: Int?
    private var editingFontFamily: String?
    /// The font this text used before code mode replaced it (used when
    /// committing a brand-new code block so toggling it back restores it).
    private var editingNormalFontFamily: String?
    private var editingNormalFontSize: CGFloat?
    /// True when the current edit pushed its undo snapshot up front (code
    /// edits mutate the annotation live while typing, so the snapshot must
    /// be taken before the first keystroke, not at commit).
    private var editingUndoPushed = false
    /// Guards live syntax highlighting against re-entrancy (setting the text
    /// storage notifies the delegate again).
    private var isHighlightingCode = false
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

    var isEditingText: Bool { editingView != nil }

    init(state: CanvasState) {
        self.state = state
        super.init(frame: .zero)
        wantsLayer = true
        // Live font updates while a text field is open (size slider / font menu).
        Publishers.CombineLatest(state.$fontSize, state.$fontFamily)
            .dropFirst()
            .sink { [weak self] size, family in
                guard let self, let tv = self.editingView, !self.isCodeEditingContext else { return }
                tv.font = Fonts.nsFont(for: family, size: size)
                self.editingFontFamily = family
            }
            .store(in: &cancellables)
        // Live color updates while a text field is open
        state.$strokeColor
            .dropFirst()
            .sink { [weak self] color in
                guard let self, let tv = self.editingView, !self.isCodeEditingContext else { return }
                tv.textColor = color
            }
            .store(in: &cancellables)
        // Picking a stroke color while shapes/text are selected recolors them
        // immediately (and stays undoable). Icon annotations are re-rendered
        // with the new tint.
        state.$strokeColor
            .dropFirst()
            .sink { [weak self] color in
                guard let self, !self.selected.isEmpty else { return }
                self.pushUndo()
                for i in self.selected where self.annotations.indices.contains(i) {
                    let a = self.annotations[i]
                    if a.kind == .laser { continue }
                    if a.kind == .image, let symbol = a.symbol {
                        self.annotations[i].image = tintedSymbolImage(
                            named: symbol,
                            pointSize: 44,
                            color: color
                        )
                    }
                    self.annotations[i].strokeColor = color
                }
                self.needsDisplay = true
            }
            .store(in: &cancellables)
        // Style sliders update the selected shapes live so tweaks are instant.
        let applyStyle: (CGFloat, WritableKeyPath<Annotation, CGFloat>) -> Void = { [weak self] value, keyPath in
            guard let self, !self.selected.isEmpty else { return }
            for i in self.selected where self.annotations.indices.contains(i) {
                let a = self.annotations[i]
                guard a.kind != .text, a.kind != .image, a.kind != .laser else { continue }
                self.annotations[i][keyPath: keyPath] = value
            }
            self.needsDisplay = true
        }
        state.$cornerRadius.dropFirst().sink { applyStyle($0, \.rx) }.store(in: &cancellables)
        state.$cornerRadiusY.dropFirst().sink { applyStyle($0, \.ry) }.store(in: &cancellables)
        // Switching pressure mode updates the selected strokes live.
        state.$pressureMode.dropFirst().sink { [weak self] mode in
            guard let self, !self.selected.isEmpty else { return }
            for i in self.selected where self.annotations.indices.contains(i) {
                let a = self.annotations[i]
                guard a.kind != .text, a.kind != .image, a.kind != .laser else { continue }
                self.annotations[i].dynamicWidth = (mode == .dynamic)
            }
            self.needsDisplay = true
        }.store(in: &cancellables)
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
            if isConnectorTool(state.tool) {
                if let (i, s) = connectionDot(at: adjustedP) {
                    hoverShapeIndex = i
                    hoverSide = s
                    NSCursor.pointingHand.set()
                } else {
                    hoverShapeIndex = nil
                    hoverSide = nil
                    NSCursor.crosshair.set()
                }
            } else {
                hoverShapeIndex = nil
                hoverSide = nil
                NSCursor.crosshair.set()
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    // MARK: - mouse

    override func mouseDown(with event: NSEvent) {
        if state.tool != .text {
            editingView?.resignFirstResponder()
        }
        let p = convert(event.locationInWindow, from: nil)
        switch state.tool {
        case .selection:
            // Adjust for canvas offset in selection tool
            let adjustedP = CGPoint(x: p.x - canvasOffset.x, y: p.y - canvasOffset.y)
            dragStart = adjustedP
            if event.clickCount >= 2, let i = hitIndex(adjustedP),
               annotations[i].kind == .text || isClosed(annotations[i].kind) {
                // Double-click an existing text, or a polygon, to re-edit /
                // type inside it.
                selected = [i]
                marqueeStart = nil
                marqueeRect = .zero
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
                    if selected.contains(i) {
                        // Grabbing any selected element moves the whole
                        // selection together.
                        movingOriginals = Dictionary(uniqueKeysWithValues: selected.compactMap { s in
                            annotations.indices.contains(s) ? (s, annotations[s]) : nil
                        })
                    } else if event.modifierFlags.contains(.shift) {
                        selected.insert(i)
                        movingOriginals = [i: annotations[i]]
                    } else {
                        selected = [i]
                        movingOriginals = [i: annotations[i]]
                    }
                } else {
                    // Clicking empty space starts a marquee (box) selection.
                    if !event.modifierFlags.contains(.shift) {
                        selected = []
                    }
                    marqueeStart = adjustedP
                    marqueeRect = .zero
                }
            } else if let i = hitIndex(adjustedP) {
                if selected.contains(i) {
                    // Grabbing any selected element moves the whole
                    // selection together.
                    movingOriginals = Dictionary(uniqueKeysWithValues: selected.compactMap { s in
                        annotations.indices.contains(s) ? (s, annotations[s]) : nil
                    })
                } else if event.modifierFlags.contains(.shift) {
                    selected.insert(i)
                    movingOriginals = [i: annotations[i]]
                } else {
                    selected = [i]
                    movingOriginals = [i: annotations[i]]
                }
            } else {
                // Clicking empty space starts a marquee (box) selection.
                if !event.modifierFlags.contains(.shift) {
                    selected = []
                }
                marqueeStart = adjustedP
                marqueeRect = .zero
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
            } else if let i = hitIndex(adjustedP), isClosed(annotations[i].kind) {
                // Clicking a polygon with the text tool types inside it.
                selected = [i]
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
                dashed: state.tool == .frame,
                strokeStyle: state.tool == .frame ? .dashed : .solid,
                sloppiness: 0,
                edgeRoughness: 0,
                rx: state.cornerRadius,
                ry: state.cornerRadiusY,
                dynamicWidth: state.pressureMode == .dynamic
            )
            // Connector tools grab the connection dot under the cursor, so
            // the line starts glued to that box's edge.
            if isConnectorTool(state.tool), let (i, s) = connectionDot(at: adjustedP) {
                current?.connectionStart = ShapeConnection(annotationIndex: i, side: s, fraction: 0.5)
                if var c = current {
                    c.points = [connectionPoint(for: c.connectionStart, fallback: adjustedP)]
                    current = c
                }
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        switch state.tool {
        case .selection:
            // Adjust for canvas offset in selection tool
            let adjustedP = CGPoint(x: p.x - canvasOffset.x, y: p.y - canvasOffset.y)
            if let ms = marqueeStart {
                marqueeRect = normalizedRect(from: ms, to: adjustedP)
            } else if let i = rotateIndex {
                let a = annotations[i]
                let center = CGPoint(x: a.rect.midX, y: a.rect.midY)
                let startAngle = atan2(rotateStartPoint.y - center.y, rotateStartPoint.x - center.x)
                let currentAngle = atan2(adjustedP.y - center.y, adjustedP.x - center.x)
                annotations[i].rotation = rotateBaseRotation + (currentAngle - startAngle)
            } else if let i = resizeIndex, let h = resizeHandle, let orig = resizeOriginal {
                annotations[i] = resizedAnnotation(orig, handle: h, p: adjustedP, selfIndex: i)
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
            case .rect, .diamond, .ellipse, .frame,
                 .triangle, .rightTriangle, .parallelogram, .trapezoid,
                 .pentagon, .hexagon, .octagon, .star, .star6, .cross,
                 .process, .predefinedProcess, .delay, .manualInput, .display,
                 .cloud, .serverStack, .queue, .firewall, .cube,
                 .callout, .note:
                c.rect = normalizedRect(from: dragStart, to: adjustedP)
            case .arrow, .line, .doubleArrow, .curvedConnector, .orthogonal, .connector:
                var startP: CGPoint
                if let cs = c.connectionStart, annotations.indices.contains(cs.annotationIndex) {
                    startP = connectionPoint(for: cs, fallback: dragStart)
                } else {
                    startP = snappedBoundaryPoint(dragStart)
                }
                var endP: CGPoint
                if let (i, s) = connectionDot(at: adjustedP) {
                    c.connectionEnd = ShapeConnection(annotationIndex: i, side: s, fraction: 0.5)
                    endP = connectionPoint(for: c.connectionEnd, fallback: adjustedP)
                } else {
                    c.connectionEnd = nil
                    endP = snappedBoundaryPoint(adjustedP)
                }
                c.points = [startP, endP]
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
            if marqueeStart != nil {
                // Box selection: pick up every annotation that intersects the
                // dragged rectangle. A plain click without drag just clears.
                let r = marqueeRect
                marqueeStart = nil
                marqueeRect = .zero
                if r.width > 4 || r.height > 4 {
                    let inBox = Set(annotations.indices.filter { i in
                        annotations[i].kind != .laser && annotations[i].rect.intersects(r)
                    })
                    if event.modifierFlags.contains(.shift) {
                        selected.formUnion(inBox)
                    } else {
                        selected = inBox
                    }
                    needsDisplay = true
                } else if !event.modifierFlags.contains(.shift) {
                    selected = []
                    needsDisplay = true
                }
            } else if rotateIndex != nil {
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
                // Switch to the selection tool and drop the current selection.
                state.tool = .selection
                selected = []
                movingOriginals = [:]
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
        case .rect, .diamond, .ellipse, .frame,
             .triangle, .rightTriangle, .parallelogram, .trapezoid,
             .pentagon, .hexagon, .octagon, .star, .star6, .cross,
             .process, .predefinedProcess, .delay, .manualInput, .display,
             .cloud, .serverStack, .queue, .firewall, .cube,
             .callout, .note:
            guard c.rect.width > 2 || c.rect.height > 2 else { return }
        case .arrow, .line, .doubleArrow, .curvedConnector, .orthogonal, .connector:
            c.rect = normalizedRect(from: c.points.first ?? dragStart, to: c.points.last ?? dragStart)
            // Re-check the release point: glued only if it landed on a dot.
            if let end = c.points.last, let (i, s) = connectionDot(at: end) {
                c.connectionEnd = ShapeConnection(annotationIndex: i, side: s, fraction: 0.5)
                c.points[c.points.count - 1] = connectionPoint(for: c.connectionEnd, fallback: end)
            } else {
                c.connectionEnd = nil
            }
            guard distance(c.points.first ?? .zero, c.points.last ?? .zero) > 2 else { return }
        case .freedraw:
            // Trackpad signature support: smooth the points for better handwriting
            c.points = smooth(c.points)
            c.rect = boundingRect(of: c.points)
            guard c.points.count > 1 else { return }
            // Auto-fill if shape is closed and fill mode is enabled
            if state.fillEnabled && isClosedShape(c.points) {
                c.fillColor = state.fillColor
                c.fillOpacity = state.fillOpacity
            }
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
        guard editingView == nil else { return }
        let existing: Annotation? = editingIndex.flatMap { idx in
            annotations.indices.contains(idx) ? annotations[idx] : nil
        }
        let code = isCodeEditingContext
        var family = existing?.fontFamily ?? state.fontFamily
        var size = existing?.fontSize ?? state.fontSize
        editingNormalFontFamily = family
        editingNormalFontSize = size
        if editingIndex == nil, code {
            // New text in code-block mode starts monospaced and compact.
            family = "Cascadia Code"
            size = 15
        }
        editingFontFamily = family
        self.editingIndex = editingIndex
        let editingPolygon = existing.map { $0.kind != .text } ?? false
        let codeWidth: CGFloat = (editingIndex == nil && code) ? 460 : 260
        let rect = existing.map { a in
            if a.kind == .text {
                // Overlay the view exactly on the existing text so re-editing
                // never moves or misaligns it.
                return CGRect(
                    x: a.rect.minX,
                    y: a.rect.minY,
                    width: max(160, a.rect.width),
                    height: max(34, a.rect.height)
                )
            }
            // Typing inside a polygon: the view sits centered in the shape
            // with a little padding, so the text never spills out.
            let pad: CGFloat = 10
            return CGRect(
                x: a.rect.minX + pad,
                y: a.rect.minY + pad,
                width: max(60, a.rect.width - pad * 2),
                height: max(28, a.rect.height - pad * 2)
            )
        } ?? CGRect(x: p.x, y: p.y, width: codeWidth, height: 34)

        if code {
            // Code edits update the annotation live while typing, so the undo
            // snapshot must be taken up front — before the first keystroke —
            // and the commit must not push another (polluted) one.
            pushUndo()
            editingUndoPushed = true
        }
        if editingIndex == nil, code {
            // Eagerly create the code block on the canvas so it renders and
            // grows live while typing — no need to wait for Esc.
            annotations.append(Annotation(
                kind: .text,
                rect: rect,
                strokeColor: state.strokeColor,
                fillColor: nil,
                fillOpacity: state.fillOpacity,
                strokeWidth: 2,
                points: [],
                pointTimes: [],
                text: "",
                fontFamily: family,
                fontSize: size,
                image: nil,
                rounded: false,
                dashed: false,
                rotation: 0,
                createdAt: Date(),
                locked: false,
                zIndex: 0,
                strokeStyle: .solid,
                sloppiness: 0,
                edgeRoughness: 0,
                rx: state.cornerRadius,
                ry: state.cornerRadiusY,
                textInside: false,
                textAnchor: .center,
                dynamicWidth: false,
                symbol: nil,
                isCode: true,
                normalFontFamily: editingNormalFontFamily,
                normalFontSize: editingNormalFontSize
            ))
            self.editingIndex = annotations.count - 1
        }

        let tv = NSTextView(frame: rect)
        tv.isRichText = false
        tv.isEditable = true
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.font = Fonts.nsFont(for: family, size: size)
        tv.textColor = existing?.strokeColor ?? state.strokeColor
        tv.allowsUndo = true
        // Plain, predictable editing: no autocorrect, quotes or dashes.
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.textContainer?.widthTracksTextView = true
        tv.alignment = editingPolygon ? .center : .left
        tv.wantsLayer = true
        if code {
            // The code "editor" look: translucent rounded block that stays
            // readable on any backdrop, matching the committed code block.
            let dark = state.canvasBackground == .black
            tv.textContainerInset = NSSize(width: 8, height: 6)
            tv.layer?.cornerRadius = 8
            tv.layer?.backgroundColor = (dark
                ? NSColor.white.withAlphaComponent(0.15)
                : NSColor.black.withAlphaComponent(0.10)).cgColor
            tv.layer?.borderWidth = 1
            tv.layer?.borderColor = (dark
                ? NSColor.white.withAlphaComponent(0.35)
                : NSColor.black.withAlphaComponent(0.22)).cgColor
        } else {
            tv.layer?.cornerRadius = 4
            tv.layer?.borderWidth = 1
            tv.layer?.borderColor = NSColor(calibratedRed: 0.42, green: 0.4, blue: 0.86, alpha: 1).cgColor
        }
        if let existing, !existing.text.isEmpty {
            tv.string = existing.text
            // Fit the view's height to the existing text right away.
            let attrs: [NSAttributedString.Key: Any] = [.font: tv.font ?? Fonts.nsFont(for: family, size: size)]
            let bounds = (existing.text as NSString).boundingRect(
                with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs
            )
            var f = tv.frame
            f.size.height = max(f.height, ceil(bounds.height) + 8)
            tv.frame = f
        }
        tv.delegate = self
        addSubview(tv)
        editingView = tv
        // Redraw now so the old text underneath the field disappears at once.
        needsDisplay = true
        window?.makeFirstResponder(tv)
        if code, !tv.string.isEmpty {
            highlightCode(in: tv)
        }
    }

    /// True while the open editing view belongs to a code block (either a new
    /// one being typed in code mode, or a re-edit of an existing code block).
    private var isCodeEditingContext: Bool {
        if state.codeBlockMode { return true }
        if let i = editingIndex, annotations.indices.contains(i) {
            return annotations[i].isCode
        }
        return false
    }

    /// Re-applies syntax colors to the editing view (live highlighting while
    /// typing in a code block).
    private func highlightCode(in tv: NSTextView) {
        guard !isHighlightingCode else { return }
        isHighlightingCode = true
        defer { isHighlightingCode = false }
        let dark = state.canvasBackground == .black
        let font = tv.font ?? Fonts.nsFont(for: "Cascadia Code", size: 15)
        let styled = syntaxHighlighted(tv.string, font: font, dark: dark)
        let sel = tv.selectedRange()
        tv.textStorage?.setAttributedString(styled)
        tv.setSelectedRange(sel)
    }

    /// Keeps the edit view tall enough to show everything being typed — it
    /// grows downward (the canvas is flipped) so nothing scrolls out of view.
    func textDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView, tv === editingView else { return }
        if isCodeEditingContext {
            highlightCode(in: tv)
            // Mirror the text onto the canvas annotation in real time so the
            // code block updates while typing, not only on Esc.
            syncCodeAnnotation(tv)
        }
        guard let layoutManager = tv.layoutManager, let container = tv.textContainer else { return }
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        var f = tv.frame
        let target = max(34, ceil(used.height) + 10)
        if abs(target - f.height) > 0.5 {
            f.size.height = target
            tv.frame = f
            if isCodeEditingContext, let idx = editingIndex, annotations.indices.contains(idx) {
                annotations[idx].rect.size.height = target
                needsDisplay = true
            }
        }
    }

    /// Pushes the editing view's text onto its canvas annotation (code edits
    /// render live while typing).
    private func syncCodeAnnotation(_ tv: NSTextView) {
        guard let idx = editingIndex, annotations.indices.contains(idx) else { return }
        annotations[idx].text = tv.string
        needsDisplay = true
    }

    func textDidEndEditing(_ notification: Notification) {
        commitTextEditing()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if isCodeEditingContext {
                let text = textView.string
                let range = textView.selectedRange()
                let ns = text as NSString
                let prefix = ns.substring(to: range.location)
                let lineStart = (prefix as NSString).range(of: "\n", options: .backwards).location
                let line = lineStart == NSNotFound ? prefix : (prefix as NSString).substring(from: lineStart + 1)
                var indent = String(line.prefix { $0 == " " || $0 == "\t" })
                if line.trimmingCharacters(in: .whitespaces).hasSuffix("{") {
                    indent += "    "
                }
                textView.insertText("\n" + indent, replacementRange: range)
                return true
            }
            // Normal text: Enter just starts a new line — Esc or clicking
            // away finishes the text.
            return false
        }
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            if isCodeEditingContext {
                // Tab indents code instead of moving focus.
                textView.insertText("\t", replacementRange: textView.selectedRange())
                return true
            }
            return false
        }
        return false
    }

    /// Auto-closes code pairs while typing in a code block: `{` → `{}`,
    /// `[` → `[]`, `(` → `()`, `"` → `""`, `'` → `''`, leaving the cursor
    /// between the pair. Typing a closer that's already there just steps past
    /// it, and typing an opener with a selection wraps that selection.
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard isCodeEditingContext, let replacement = replacementString, replacement.count == 1,
              let c = replacement.first, autoPairChars.contains(c) else {
            return true
        }
        let ns = textView.string as NSString
        let insertAt = affectedCharRange.location
        let next = insertAt + affectedCharRange.length
        if next < ns.length, ns.substring(with: NSRange(location: next, length: 1)) == String(c) {
            // The closer is already in place (typing `}` after `{}`) — just
            // move the cursor past it instead of inserting a duplicate.
            textView.setSelectedRange(NSRange(location: next + 1, length: 0))
            return false
        }
        guard let closer = closingPair(for: c) else { return true }
        if affectedCharRange.length > 0 {
            let selectedText = ns.substring(with: affectedCharRange)
            textView.insertText(String(c) + selectedText + String(closer), replacementRange: affectedCharRange)
            textView.setSelectedRange(NSRange(location: insertAt + 1, length: selectedText.count))
        } else {
            textView.insertText(String(c) + String(closer), replacementRange: affectedCharRange)
            textView.setSelectedRange(NSRange(location: insertAt + 1, length: 0))
        }
        return false
    }

    private var autoPairChars: Set<Character> { ["{", "}", "[", "]", "(", ")", "\"", "'"] }

    private func closingPair(for opener: Character) -> Character? {
        switch opener {
        case "{": return "}"
        case "[": return "]"
        case "(": return ")"
        case "\"": return "\""
        case "'": return "'"
        default: return nil
        }
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

    /// Self-test hook: sets the text of the open editing view.
    func selftestSetText(_ s: String) {
        guard let tv = editingView else { return }
        tv.string = s
        // The string setter doesn't post NSText.didChange, so run the live
        // sync explicitly to match what real typing produces.
        if isCodeEditingContext {
            syncCodeAnnotation(tv)
        }
    }

    /// Self-test hook: moves the cursor in the open editing view.
    func selftestSetCursor(location: Int) {
        editingView?.setSelectedRange(NSRange(location: location, length: 0))
    }

    /// Self-test hook: number of characters selected in the open editing
    /// view (0 when none is open).
    func selftestEditingSelectionLength() -> Int {
        guard let tv = editingView else { return 0 }
        return tv.selectedRange().length
    }

    /// Self-test hook: the current text of the open editing view.
    func selftestEditingString() -> String {
        editingView?.string ?? ""
    }

    /// Self-test hook: selects the given annotations (as a click would).
    func selftestSelect(_ indices: [Int]) {
        selected = Set(indices)
        needsDisplay = true
    }

    /// Self-test hook: the drawable path for an annotation (as rendered).
    func selftestPath(for a: Annotation) -> NSBezierPath? {
        bezierPath(for: a)
    }

    /// First point of an annotation's rendered path (selftest hook).
    func selftestPathStart(_ a: Annotation) -> CGPoint? {
        selftestPathPoints(a).first
    }

    /// All vertices of an annotation's rendered path (selftest hook).
    func selftestPathPoints(_ a: Annotation) -> [CGPoint] {
        let path = bezierPath(for: a)
        var pts: [CGPoint] = []
        for i in 0..<path.elementCount {
            let raw = UnsafeMutablePointer<NSPoint>.allocate(capacity: 3)
            defer { raw.deallocate() }
            switch path.element(at: i, associatedPoints: raw) {
            case .moveTo, .lineTo:
                pts.append(raw[0])
            default:
                break
            }
        }
        return pts
    }

    /// Selects all the text in the open editing view (Cmd+A).
    func selectAllInEditingField() {
        editingView?.selectAll(nil)
    }

    /// Commits the open text field. Returns the index of the committed text
    /// annotation (newly created or re-edited), or nil when nothing was
    /// committed (empty new text, or an emptied re-edit deletes the annotation).
    @discardableResult
    private func commitTextEditing() -> Int? {
        guard let tv = editingView else { return nil }
        // Leave text mode on every commit path (Esc, click-away, overlay
        // close) so the next click doesn't open a new text field.
        state.tool = state.lastNonTextTool
        editingView = nil
        window?.makeFirstResponder(self)
        let str = tv.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let family = editingFontFamily ?? state.fontFamily
        let size = tv.font?.pointSize ?? state.fontSize
        // Fresh polygons have no text yet — let the toolbar font size apply.
        let targetSize: CGFloat
        if let idx = editingIndex, annotations.indices.contains(idx),
           annotations[idx].kind != .text, !annotations[idx].textInside {
            targetSize = state.fontSize
        } else {
            targetSize = size
        }
        let idx = editingIndex
        editingIndex = nil
        editingFontFamily = nil
        let undoPushed = editingUndoPushed
        editingUndoPushed = false
        let normalFamily = editingNormalFontFamily
        let normalSize = editingNormalFontSize
        editingNormalFontFamily = nil
        editingNormalFontSize = nil
        tv.removeFromSuperview()

        // Clearing an existing text deletes the annotation; clearing a
        // polygon's text just removes the text from inside it.
        if str.isEmpty {
            if let idx, annotations.indices.contains(idx) {
                if !undoPushed { pushUndo() }
                if annotations[idx].kind == .text {
                    annotations.remove(at: idx)
                    selected = []
                } else {
                    annotations[idx].text = ""
                    annotations[idx].textInside = false
                }
            }
            needsDisplay = true
            return nil
        }

        let font = tv.font ?? Fonts.nsFont(for: family, size: size)
        let width = max(60, tv.frame.width)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let bounds = (str as NSString).boundingRect(
            with: NSSize(width: width, height: 100_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        var r = tv.frame
        r.size = CGSize(width: width, height: max(bounds.height, size * 1.4))
        if !undoPushed { pushUndo() }
        if let idx, annotations.indices.contains(idx) {
            var updated = annotations[idx]
            if updated.kind == .text {
                updated.rect = r
                updated.text = str
                updated.fontFamily = family
                updated.fontSize = size
                updated.fillOpacity = state.fillOpacity
            } else {
                // Text inside a polygon — the shape's geometry is untouched,
                // only the attached text and its fitted size change.
                updated.text = str
                updated.textInside = true
                updated.textAnchor = .center
                updated.fontFamily = family
                updated.fontSize = fittingFontSize(
                    for: str,
                    in: updated.rect,
                    fontFamily: family,
                    maxSize: targetSize
                )
            }
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
            zIndex: 0,
            strokeStyle: .solid,
            sloppiness: 0,
            edgeRoughness: 0,
            rx: state.cornerRadius,
            ry: state.cornerRadiusY,
            textInside: false,
            textAnchor: .center,
            dynamicWidth: false,
            symbol: nil,
            isCode: state.codeBlockMode,
            normalFontFamily: state.codeBlockMode ? normalFamily : nil,
            normalFontSize: state.codeBlockMode ? normalSize : nil
        ))
        // Code blocks start monospaced at a readable size.
        if state.codeBlockMode {
            annotations[annotations.count - 1].fontFamily = "Cascadia Code"
            annotations[annotations.count - 1].fontSize = 15
        }
        needsDisplay = true
        return annotations.count - 1
    }

    /// Converts the selected text annotations into (or back from) syntax-
    /// highlighted code blocks. Used by the "Code block" toolbar button.
    func toggleCodeBlock() {
        let textIdx = selected.filter { idx in
            annotations.indices.contains(idx) && annotations[idx].kind == .text
        }
        guard !textIdx.isEmpty else { return }
        pushUndo()
        for idx in textIdx {
            annotations[idx].isCode.toggle()
            if annotations[idx].isCode {
                // Remember what this text looked like before it became code,
                // so toggling back restores it exactly — never a jump to the
                // toolbar's current font, which makes text "disappear".
                if annotations[idx].normalFontFamily == nil {
                    annotations[idx].normalFontFamily = annotations[idx].fontFamily
                    annotations[idx].normalFontSize = annotations[idx].fontSize
                }
                annotations[idx].fontFamily = "Cascadia Code"
                if annotations[idx].fontSize > 18 {
                    annotations[idx].fontSize = 15
                }
                if annotations[idx].rect.width < 420 {
                    annotations[idx].rect.size.width = 420
                }
            } else {
                annotations[idx].fontFamily = annotations[idx].normalFontFamily ?? state.fontFamily
                annotations[idx].fontSize = annotations[idx].normalFontSize ?? state.fontSize
                annotations[idx].normalFontFamily = nil
                annotations[idx].normalFontSize = nil
            }
        }
        needsDisplay = true
    }

    /// Inserts an SF Symbol icon at the given canvas point (used by the "/"
    /// palette), tinted with the current stroke color.
    func insertSymbol(_ symbol: String, at p: CGPoint) {
        // Adjust for canvas offset
        let adjustedP = CGPoint(x: p.x - canvasOffset.x, y: p.y - canvasOffset.y)
        guard let image = tintedSymbolImage(named: symbol, pointSize: 44, color: state.strokeColor) else { return }
        let size = image.size
        pushUndo()
        annotations.append(Annotation(
            kind: .image,
            rect: CGRect(
                x: adjustedP.x - size.width / 2,
                y: adjustedP.y - size.height / 2,
                width: size.width,
                height: size.height
            ),
            strokeColor: state.strokeColor,
            fillColor: nil,
            fillOpacity: state.fillOpacity,
            strokeWidth: 2,
            points: [],
            pointTimes: [],
            text: "",
            fontFamily: "System",
            fontSize: 44,
            image: image,
            rounded: false,
            dashed: false,
            rotation: 0,
            createdAt: Date(),
            locked: false,
            zIndex: annotations.count,
            strokeStyle: .solid,
            sloppiness: 0,
            edgeRoughness: 0,
            rx: state.cornerRadius,
            ry: state.cornerRadiusY,
            textInside: false,
            textAnchor: .center,
            dynamicWidth: false,
            symbol: symbol,
            isCode: false
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

        // Box/marquee selection rectangle, drawn while dragging.
        if marqueeRect.width > 1 || marqueeRect.height > 1 {
            let path = NSBezierPath(rect: marqueeRect)
            NSColor(calibratedRed: 0.42, green: 0.4, blue: 0.86, alpha: 0.08).setFill()
            path.fill()
            NSColor(calibratedRed: 0.42, green: 0.4, blue: 0.86, alpha: 0.9).setStroke()
            path.lineWidth = 1.5
            path.setLineDash([6, 4], count: 2, phase: 0)
            path.stroke()
        }

        if let sel = selected.first, sel >= 0, sel < annotations.count {
            drawSelectionOverlay(for: annotations[sel])
        }

        // Connection dots on box edges for connector tools — grab one to
        // glue a line to that box. The grabbed dot and the hovered target
        // dot are highlighted.
        if isConnectorTool(state.tool) {
            var dotShapes: Set<Int> = []
            if let i = hoverShapeIndex { dotShapes.insert(i) }
            if let c = current, let cs = c.connectionStart { dotShapes.insert(cs.annotationIndex) }
            for i in dotShapes where annotations.indices.contains(i) {
                let a = annotations[i]
                guard isClosed(a.kind), a.kind != .laser else { continue }
                for (side, p) in connectionDots(for: a) {
                    let isSource = current?.connectionStart?.annotationIndex == i && current?.connectionStart?.side == side
                    let isTarget = hoverShapeIndex == i && hoverSide == side && current != nil
                    if isSource || isTarget {
                        NSColor(calibratedRed: 0.42, green: 0.4, blue: 0.86, alpha: 1).setFill()
                        NSBezierPath(ovalIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)).fill()
                        NSColor.white.setStroke()
                        let ring = NSBezierPath(ovalIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
                        ring.lineWidth = 1.5
                        ring.stroke()
                    } else {
                        NSColor(calibratedRed: 0.42, green: 0.4, blue: 0.86, alpha: 0.55).setFill()
                        NSBezierPath(ovalIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)).fill()
                    }
                }
            }
        }

        ctx.restoreGraphicsState()
    }

    private func draw(annotation a: Annotation, index: Int) {
        // While its edit field is open, don't draw the annotation's old
        // content underneath it — the field replaces the text until commit.
        if editingView != nil, editingIndex == index {
            if a.kind == .text { return }
        }
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
            if a.dynamicWidth && (a.kind == .freedraw || a.kind == .line) {
                // Pressure stroke: variable width, filled outline.
                drawDynamicStroke(a)
            } else {
                switch a.strokeStyle {
                case .solid:
                    path.stroke()
                case .dashed:
                    path.setLineDash([12, 8], count: 2, phase: 0)
                    path.stroke()
                case .dotted:
                    strokeDotted(path: path, color: a.strokeColor, width: a.strokeWidth)
                }
            }
            if a.kind == .arrow || a.kind == .doubleArrow || a.kind == .curvedConnector || a.kind == .orthogonal || a.kind == .connector {
                if let seg = lastSegment(of: path) {
                    drawArrowhead(at: seg.end, from: seg.start, color: a.strokeColor, width: a.strokeWidth)
                }
                if a.kind == .doubleArrow, let seg = firstSegment(of: path) {
                    drawArrowhead(at: seg.start, from: seg.end, color: a.strokeColor, width: a.strokeWidth)
                }
            }
            // Connection dots — show where the elbow connector is pinned to
            // its boxes (one on each box edge).
            if a.kind == .connector, a.points.count > 1 {
                let r = max(2.5, a.strokeWidth / 2 + 1)
                a.strokeColor.setFill()
                for p in [a.points[0], a.points[a.points.count - 1]] {
                    NSBezierPath(ovalIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)).fill()
                }
            }
            // Text attached to a polygon — drawn inside the rotation transform,
            // so it moves / rotates / scales together with the shape. Skipped
            // while its edit field is open (the field shows the text instead).
            if a.textInside, !a.text.isEmpty, isClosed(a.kind),
               !(editingView != nil && editingIndex == index) {
                drawTextInShape(a)
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

    // MARK: - pressure (dynamic width) strokes

    /// Renders a stroke with variable width: moving fast draws thin, moving
    /// slowly draws thick, and both ends taper to a fine tail like a
    /// calligraphy pen. Straight lines get a classic swell in the middle.
    private func drawDynamicStroke(_ a: Annotation) {
        var pts = a.points
        guard pts.count > 1 else {
            let r = a.strokeWidth / 2
            a.strokeColor.setFill()
            NSBezierPath(ovalIn: CGRect(x: pts[0].x - r, y: pts[0].y - r, width: r * 2, height: r * 2)).fill()
            return
        }
        if a.kind == .line {
            // Resample straight lines so the calligraphic swell has room to breathe.
            var resampled: [CGPoint] = []
            let count = 10
            for k in 0..<count {
                let t = CGFloat(k) / CGFloat(count - 1)
                resampled.append(CGPoint(
                    x: pts[0].x + (pts[pts.count - 1].x - pts[0].x) * t,
                    y: pts[0].y + (pts[pts.count - 1].y - pts[0].y) * t
                ))
            }
            pts = resampled
        }
        // Drop ultra-dense points so normals stay stable on long strokes.
        if pts.count > 80 {
            var kept = [pts[0]]
            for p in pts.dropFirst().dropLast() where distance(kept.last!, p) > 1.4 {
                kept.append(p)
            }
            kept.append(pts[pts.count - 1])
            pts = kept
        }
        let n = pts.count
        guard n > 1 else { return }
        let base = max(1, a.strokeWidth)

        // Width profile per point.
        var widths = [CGFloat](repeating: base, count: n)
        if a.kind == .line {
            for i in 0..<n {
                let t = CGFloat(i) / CGFloat(n - 1)
                widths[i] = base * (0.18 + 0.82 * sin(.pi * t))
            }
        } else {
            // Freehand: velocity (point spacing) drives thickness — slow is thick.
            var spacing = [CGFloat](repeating: 0, count: n)
            for i in 1..<n { spacing[i] = distance(pts[i - 1], pts[i]) }
            let fast = max(7, spacing.max() ?? 7)
            let slow = max(1.5, fast * 0.14)
            for i in 0..<n {
                var s = spacing[i]
                if i + 1 < n { s = max(s, spacing[i + 1]) }
                let t = min(1, max(0, (s - slow) / (fast - slow)))
                widths[i] = base * (1.35 - 0.9 * t)
            }
            // Smooth the profile so width changes feel fluid, not spiky.
            var smoothed = widths
            for i in 0..<n {
                var acc: CGFloat = 0, cnt: CGFloat = 0
                for j in max(0, i - 2)...min(n - 1, i + 2) {
                    acc += widths[j]
                    cnt += 1
                }
                smoothed[i] = acc / cnt
            }
            widths = smoothed
        }
        // Taper the very ends down to a thin tail.
        let taper = max(3, n / 4)
        for i in 0..<n {
            let fromStart = CGFloat(i) / CGFloat(taper)
            let fromEnd = CGFloat(n - 1 - i) / CGFloat(taper)
            widths[i] *= 0.12 + 0.88 * min(1, min(fromStart, fromEnd))
        }
        // Lightly smooth the polyline so normals don't wobble on jittery input.
        var smoothPts = pts
        if n > 4 {
            for i in 1..<(n - 1) {
                smoothPts[i] = CGPoint(
                    x: (pts[i - 1].x + pts[i].x * 2 + pts[i + 1].x) / 4,
                    y: (pts[i - 1].y + pts[i].y * 2 + pts[i + 1].y) / 4
                )
            }
        }
        func normal(_ i: Int) -> CGPoint {
            let prev = i > 0 ? smoothPts[i - 1] : smoothPts[0]
            let next = i < n - 1 ? smoothPts[i + 1] : smoothPts[n - 1]
            let dx = next.x - prev.x
            let dy = next.y - prev.y
            let len = max(0.0001, sqrt(dx * dx + dy * dy))
            return CGPoint(x: -dy / len, y: dx / len)
        }
        // Filled outline: left side forward, round cap at the end, right side
        // back, round cap at the start.
        let path = NSBezierPath()
        path.move(to: CGPoint(
            x: smoothPts[0].x + normal(0).x * widths[0] / 2,
            y: smoothPts[0].y + normal(0).y * widths[0] / 2
        ))
        for i in 1..<n {
            path.line(to: CGPoint(
                x: smoothPts[i].x + normal(i).x * widths[i] / 2,
                y: smoothPts[i].y + normal(i).y * widths[i] / 2
            ))
        }
        path.appendArc(
            withCenter: smoothPts[n - 1],
            radius: max(0.3, widths[n - 1] / 2),
            startAngle: 0,
            endAngle: 360
        )
        for i in stride(from: n - 1, through: 0, by: -1) {
            path.line(to: CGPoint(
                x: smoothPts[i].x - normal(i).x * widths[i] / 2,
                y: smoothPts[i].y - normal(i).y * widths[i] / 2
            ))
        }
        path.appendArc(
            withCenter: smoothPts[0],
            radius: max(0.3, widths[0] / 2),
            startAngle: 0,
            endAngle: 360
        )
        path.close()
        a.strokeColor.setFill()
        path.fill()
        // Crisp center core keeps overlapping segments from showing seams.
        let core = NSBezierPath()
        core.move(to: smoothPts[0])
        for p in smoothPts.dropFirst() { core.line(to: p) }
        core.lineCapStyle = .round
        core.lineJoinStyle = .round
        a.strokeColor.setStroke()
        core.lineWidth = max(0.8, min(1.6, base * 0.35))
        core.stroke()
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

    private func resizedAnnotation(_ a: Annotation, handle: ResizeHandle, p: CGPoint, selfIndex: Int? = nil) -> Annotation {
        var a = a
        let orig = a.rect

        // Lines and arrows resize from their two endpoint handles.
        if handle == .startPoint || handle == .endPoint {
            guard !a.points.isEmpty else { return a }
            var pts = a.points
            if handle == .startPoint {
                pts[0] = snappedBoundaryPoint(p, selfIndex: selfIndex)
                a.connectionStart = nil
            } else {
                pts[pts.count - 1] = snappedBoundaryPoint(p, selfIndex: selfIndex)
                a.connectionEnd = nil
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
        case .freedraw, .autoshape, .laser, .arrow, .line, .doubleArrow, .curvedConnector, .orthogonal, .connector:
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
            // Resizing a polygon with attached text scales the text with it.
            if a.textInside, !a.text.isEmpty {
                let sx = newRect.width / max(1, orig.width)
                let sy = newRect.height / max(1, orig.height)
                a.fontSize = max(6, min(300, a.fontSize * max(0.4, (sx + sy) / 2)))
            }
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
        if a.isCode {
            drawCodeBlock(a)
            return
        }
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

    /// Code blocks: translucent rounded background (visible on white and
    /// black backdrops) with syntax-highlighted monospaced text.
    private func drawCodeBlock(_ a: Annotation) {
        let dark = state.canvasBackground == .black
        let pad: CGFloat = 14
        let bgRect = a.rect.insetBy(dx: -pad, dy: -pad)
        let bg = NSBezierPath(roundedRect: bgRect, xRadius: 8, yRadius: 8)
        let fill = dark
            ? NSColor.white.withAlphaComponent(0.12)
            : NSColor.black.withAlphaComponent(0.08)
        fill.setFill()
        bg.fill()
        let border = dark
            ? NSColor.white.withAlphaComponent(0.3)
            : NSColor.black.withAlphaComponent(0.18)
        border.setStroke()
        bg.lineWidth = 1
        bg.stroke()

        let font = Fonts.nsFont(for: "Cascadia Code", size: a.fontSize)
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        let styled = syntaxHighlighted(a.text, font: font, dark: dark)
        styled.draw(
            with: a.rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
    }

    /// Lightweight tokenizer that colors keywords, types, functions, strings,
    /// comments and numbers — with palettes tuned for light and dark backdrops.
    private func syntaxHighlighted(_ text: String, font: NSFont, dark: Bool) -> NSAttributedString {
        struct Palette {
            let plain: NSColor
            let keyword: NSColor
            let type: NSColor
            let function: NSColor
            let string: NSColor
            let number: NSColor
            let comment: NSColor
        }
        let palette = dark
            ? Palette(
                plain: NSColor(calibratedWhite: 0.93, alpha: 1),
                keyword: NSColor(calibratedRed: 0.36, green: 0.62, blue: 0.9, alpha: 1),
                type: NSColor(calibratedRed: 0.32, green: 0.78, blue: 0.7, alpha: 1),
                function: NSColor(calibratedRed: 0.86, green: 0.86, blue: 0.63, alpha: 1),
                string: NSColor(calibratedRed: 0.82, green: 0.56, blue: 0.47, alpha: 1),
                number: NSColor(calibratedRed: 0.71, green: 0.82, blue: 0.65, alpha: 1),
                comment: NSColor(calibratedRed: 0.45, green: 0.6, blue: 0.36, alpha: 1)
            )
            : Palette(
                plain: NSColor(calibratedWhite: 0.12, alpha: 1),
                keyword: NSColor(calibratedRed: 0.65, green: 0.1, blue: 0.82, alpha: 1),
                type: NSColor(calibratedRed: 0.1, green: 0.48, blue: 0.6, alpha: 1),
                function: NSColor(calibratedRed: 0.45, green: 0.33, blue: 0.13, alpha: 1),
                string: NSColor(calibratedRed: 0.62, green: 0.13, blue: 0.13, alpha: 1),
                number: NSColor(calibratedRed: 0.04, green: 0.47, blue: 0.3, alpha: 1),
                comment: NSColor(calibratedRed: 0.29, green: 0.52, blue: 0.3, alpha: 1)
            )
        let keywords: Set<String> = [
            "fn", "func", "function", "def", "let", "var", "const", "if", "else",
            "for", "while", "do", "return", "import", "from", "class", "struct",
            "enum", "public", "private", "static", "new", "try", "catch", "throw",
            "throws", "async", "await", "switch", "case", "break", "continue",
            "default", "in", "of", "type", "interface", "extends", "implements",
            "super", "this", "self", "nil", "null", "true", "false", "and", "or",
            "not", "with", "as", "guard", "defer", "init", "deinit", "override",
            "mutating", "protocol", "extension", "where", "yield", "print", "export",
        ]
        let types: Set<String> = [
            "int", "float", "double", "string", "str", "bool", "boolean", "char",
            "void", "any", "never", "number", "object", "array", "list", "dict",
            "map", "set", "tuple", "byte", "short", "long", "uint", "i8", "i16",
            "i32", "i64", "u8", "u16", "u32", "u64", "f32", "f64", "Date", "Data",
            "URL", "UUID", "Error", "Result", "Promise", "Vec", "Option",
        ]
        let chars = Array(text)
        let result = NSMutableAttributedString()
        var i = 0
        let n = chars.count
        func appendPlain(_ s: Substring) {
            if s.isEmpty { return }
            result.append(NSAttributedString(string: String(s), attributes: [
                .font: font, .foregroundColor: palette.plain,
            ]))
        }
        while i < n {
            let c = chars[i]
            // Line comment
            if c == "/", i + 1 < n, chars[i + 1] == "/" {
                var j = i
                while j < n, chars[j] != "\n" { j += 1 }
                result.append(NSAttributedString(string: String(chars[i..<j]), attributes: [
                    .font: font, .foregroundColor: palette.comment,
                ]))
                i = j
                continue
            }
            // String literal
            if c == "\"" || c == "'" {
                let quote = c
                var j = i + 1
                while j < n {
                    if chars[j] == "\\" { j += 2; continue }
                    if chars[j] == quote { j += 1; break }
                    j += 1
                }
                result.append(NSAttributedString(string: String(chars[i..<j]), attributes: [
                    .font: font, .foregroundColor: palette.string,
                ]))
                i = j
                continue
            }
            // Number
            if c.isNumber || (c == "." && i + 1 < n && chars[i + 1].isNumber) {
                var j = i
                while j < n, chars[j].isNumber || chars[j] == "." || chars[j] == "_"
                    || "xXbB".contains(chars[j]) {
                    j += 1
                }
                result.append(NSAttributedString(string: String(chars[i..<j]), attributes: [
                    .font: font, .foregroundColor: palette.number,
                ]))
                i = j
                continue
            }
            // Identifier
            if c.isLetter || c == "_" {
                var j = i
                while j < n, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" { j += 1 }
                let word = String(chars[i..<j])
                let color: NSColor
                if keywords.contains(word) {
                    color = palette.keyword
                } else if types.contains(word) {
                    color = palette.type
                } else if j < n, chars[j] == "(" {
                    color = palette.function
                } else {
                    color = palette.plain
                }
                result.append(NSAttributedString(string: word, attributes: [
                    .font: font, .foregroundColor: color,
                ]))
                i = j
                continue
            }
            // Whitespace + punctuation run
            var j = i
            while j < n {
                let ch = chars[j]
                if ch.isLetter || ch.isNumber || ch == "_" || ch == "\"" || ch == "'" { break }
                if ch == "/", j + 1 < n, chars[j + 1] == "/" { break }
                j += 1
            }
            appendPlain(text[text.index(text.startIndex, offsetBy: i)..<text.index(text.startIndex, offsetBy: j)])
            i = j
        }
        return result
    }

    /// Text anchored inside a polygon: centered, wrapped to the shape's width,
    /// vertically centered so it never spills out of the boundary.
    private func drawTextInShape(_ a: Annotation) {
        let pad: CGFloat = 8
        let textRect = a.rect.insetBy(dx: pad, dy: pad)
        guard textRect.width > 10, textRect.height > 6 else { return }
        let font = Fonts.nsFont(for: a.fontFamily, size: a.fontSize)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: a.strokeColor,
            .paragraphStyle: para,
        ]
        let bounds = (a.text as NSString).boundingRect(
            with: CGSize(width: textRect.width, height: 100_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        let drawRect = CGRect(
            x: textRect.minX,
            y: textRect.midY - bounds.height / 2,
            width: textRect.width,
            height: min(bounds.height, textRect.height)
        )
        (a.text as NSString).draw(
            with: drawRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
    }

    /// Shrinks the font until the text fits inside the polygon with padding.
    private func fittingFontSize(for text: String, in rect: CGRect, fontFamily: String, maxSize: CGFloat) -> CGFloat {
        let pad: CGFloat = 8
        let w = max(20, rect.width - pad * 2)
        let h = max(16, rect.height - pad * 2)
        var size = max(6, maxSize)
        for _ in 0..<24 {
            let font = Fonts.nsFont(for: fontFamily, size: size)
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            para.lineBreakMode = .byWordWrapping
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: para]
            let b = (text as NSString).boundingRect(
                with: CGSize(width: w, height: 100_000),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs
            )
            if b.height <= h + 1, b.width <= w + 1 { return size }
            let scale = min(w / max(b.width, 1), h / max(b.height, 1))
            let next = size * min(scale, 0.9)
            if next < 6 || abs(next - size) < 0.5 { return max(6, next) }
            size = next
        }
        return 6
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

    /// Deterministic seed so a shape's hand-drawn wobble is stable across
    /// redraws (derived from its creation time).
    private func roughSeed(for a: Annotation) -> UInt64 {
        UInt64(bitPattern: Int64(a.createdAt.timeIntervalSince1970 * 1000))
    }

    /// Small deterministic PRNG (xorshift) — Rough.js-style wobble must be
    /// reproducible, never flickering between frames.
    private struct SeededRandom {
        private var state: UInt64
        init(seed: UInt64) {
            state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
        }
        mutating func next() -> CGFloat {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return CGFloat((state & 0xFFFFFF) % 1_000_000) / 1_000_000
        }
    }

    private func bezierPath(for a: Annotation) -> NSBezierPath {
        let r = a.rect
        let slop = a.sloppiness
        let edge = a.edgeRoughness
        let rough = slop > 0.02 || edge > 0.02
        let seed = roughSeed(for: a)
        switch a.kind {
        case .rect:
            if rough {
                return roughRoundedRect(r, rx: a.rx, ry: a.ry, slop: slop, edge: edge, seed: seed)
            }
            let path = NSBezierPath()
            if a.rx > 0.5 || a.ry > 0.5 {
                path.appendRoundedRect(
                    r,
                    xRadius: min(a.rx, r.width / 2),
                    yRadius: min(a.ry, r.height / 2)
                )
            } else {
                path.appendRect(r)
            }
            return path
        case .frame:
            if rough {
                return roughRoundedRect(r, rx: a.rx, ry: a.ry, slop: slop, edge: edge, seed: seed)
            }
            let path = NSBezierPath()
            if a.rx > 0.5 || a.ry > 0.5 {
                path.appendRoundedRect(
                    r,
                    xRadius: min(a.rx, r.width / 2),
                    yRadius: min(a.ry, r.height / 2)
                )
            } else {
                path.appendRect(r)
            }
            return path
        case .diamond:
            if rough {
                return roughDiamond(r, slop: slop, edge: edge, seed: seed)
            }
            let c = CGPoint(x: r.midX, y: r.midY)
            let path = NSBezierPath()
            path.move(to: CGPoint(x: c.x, y: r.maxY))
            path.line(to: CGPoint(x: r.maxX, y: c.y))
            path.line(to: CGPoint(x: c.x, y: r.minY))
            path.line(to: CGPoint(x: r.minX, y: c.y))
            path.close()
            return path
        case .ellipse:
            if rough {
                return roughEllipse(r, slop: slop, edge: edge, seed: seed)
            }
            let path = NSBezierPath()
            path.appendOval(in: r)
            return path
        case .arrow, .line:
            let pts = a.points
            guard pts.count > 1 else { return NSBezierPath() }
            let s = connectionPoint(for: a.connectionStart, fallback: pts[0])
            let e = connectionPoint(for: a.connectionEnd, fallback: pts[pts.count - 1])
            let sOwner = connectionNormal(for: a.connectionStart).map { ConnectorOwner(normal: $0) } ?? connectorOwner(at: s)
            let eOwner = connectionNormal(for: a.connectionEnd).map { ConnectorOwner(normal: $0) } ?? connectorOwner(at: e)
            let margin = 8 + a.strokeWidth / 2
            let obstacles = connectorObstacles(for: a, margin: margin)
            if straightIsBlocked(s, e, obstacles: obstacles),
               let route = connectorRoute(
                   from: s, to: e,
                   startOwner: sOwner,
                   endOwner: eOwner,
                   obstacles: obstacles
               ) {
                let path = NSBezierPath()
                path.move(to: route[0])
                for p in route.dropFirst() {
                    path.line(to: p)
                }
                return path
            }
            if rough {
                return roughLine(from: s, to: e, slop: slop, edge: edge, seed: seed)
            }
            let path = NSBezierPath()
            path.move(to: s)
            path.line(to: e)
            return path
        case .freedraw, .laser:
            let pts = a.points
            guard pts.count > 1 else { return NSBezierPath() }
            let path = NSBezierPath()
            path.move(to: pts[0])
            for p in pts.dropFirst() {
                path.line(to: p)
            }
            return path
        case .autoshape:
            let pts = a.points
            guard pts.count > 2 else { return NSBezierPath() }
            let path = NSBezierPath()
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
            return path
        case .doubleArrow, .curvedConnector, .orthogonal, .connector:
            let pts = a.points
            guard pts.count > 1 else { return NSBezierPath() }
            let s = connectionPoint(for: a.connectionStart, fallback: pts[0])
            let e = connectionPoint(for: a.connectionEnd, fallback: pts[pts.count - 1])
            let sOwner = connectionNormal(for: a.connectionStart).map { ConnectorOwner(normal: $0) } ?? connectorOwner(at: s)
            let eOwner = connectionNormal(for: a.connectionEnd).map { ConnectorOwner(normal: $0) } ?? connectorOwner(at: e)
            let margin = 8 + a.strokeWidth / 2
            let obstacles = connectorObstacles(for: a, margin: margin)
            var blocked = false
            switch a.kind {
            case .doubleArrow:
                blocked = straightIsBlocked(s, e, obstacles: obstacles)
            case .orthogonal, .connector:
                blocked = straightIsBlocked(s, e, obstacles: obstacles)
                    || straightIsBlocked(s, CGPoint(x: e.x, y: s.y), obstacles: obstacles)
                    || straightIsBlocked(CGPoint(x: e.x, y: s.y), e, obstacles: obstacles)
            default:
                let p0 = s
                let p1 = e
                let mid = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
                let dx = p1.x - p0.x
                let dy = p1.y - p0.y
                let len = max(1, sqrt(dx * dx + dy * dy))
                let n = CGPoint(x: -dy / len, y: dx / len)
                let c1 = CGPoint(
                    x: p0.x + (mid.x - p0.x) * 0.55 + n.x * len * 0.22,
                    y: p0.y + (mid.y - p0.y) * 0.55 + n.y * len * 0.22
                )
                let c2 = CGPoint(
                    x: p1.x + (mid.x - p1.x) * 0.55 - n.x * len * 0.22,
                    y: p1.y + (mid.y - p1.y) * 0.55 - n.y * len * 0.22
                )
                blocked = curveIsBlocked(p0, c1, c2, p1, obstacles: obstacles)
            }
            if blocked,
               let route = connectorRoute(
                   from: s, to: e,
                   startOwner: sOwner,
                   endOwner: eOwner,
                   obstacles: obstacles
               ) {
                let path = NSBezierPath()
                path.move(to: route[0])
                for p in route.dropFirst() {
                    path.line(to: p)
                }
                return path
            }
            switch a.kind {
            case .doubleArrow, .orthogonal, .connector:
                let path = NSBezierPath()
                path.move(to: s)
                var prev = s
                for p in pts.dropFirst() {
                    if a.kind == .orthogonal || a.kind == .connector {
                        path.line(to: CGPoint(x: p.x, y: prev.y))
                        path.line(to: p)
                    } else {
                        path.line(to: p)
                    }
                    prev = p
                }
                return path
            default:
                // S-curve connector between the first and last point.
                let p0 = pts[0]
                let p1 = pts[pts.count - 1]
                let mid = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
                let dx = p1.x - p0.x
                let dy = p1.y - p0.y
                let len = max(1, sqrt(dx * dx + dy * dy))
                let n = CGPoint(x: -dy / len, y: dx / len)
                let off = n.x * len * 0.22
                let offY = n.y * len * 0.22
                let c1 = CGPoint(
                    x: p0.x + (mid.x - p0.x) * 0.55 + off,
                    y: p0.y + (mid.y - p0.y) * 0.55 + offY
                )
                let c2 = CGPoint(
                    x: p1.x + (mid.x - p1.x) * 0.55 - off,
                    y: p1.y + (mid.y - p1.y) * 0.55 - offY
                )
                let path = NSBezierPath()
                path.move(to: p0)
                path.curve(to: p1, controlPoint1: c1, controlPoint2: c2)
                return path
            }
        case .triangle:
            let path = NSBezierPath()
            path.move(to: CGPoint(x: r.midX, y: r.minY))
            path.line(to: CGPoint(x: r.maxX, y: r.maxY))
            path.line(to: CGPoint(x: r.minX, y: r.maxY))
            path.close()
            return path
        case .rightTriangle:
            let path = NSBezierPath()
            path.move(to: CGPoint(x: r.minX, y: r.minY))
            path.line(to: CGPoint(x: r.maxX, y: r.maxY))
            path.line(to: CGPoint(x: r.minX, y: r.maxY))
            path.close()
            return path
        case .parallelogram, .manualInput:
            let s = r.width * 0.22
            let path = NSBezierPath()
            path.move(to: CGPoint(x: r.minX + s, y: r.maxY))
            path.line(to: CGPoint(x: r.minX, y: r.minY))
            path.line(to: CGPoint(x: r.maxX - s, y: r.minY))
            path.line(to: CGPoint(x: r.maxX, y: r.maxY))
            path.close()
            return path
        case .trapezoid:
            let s = r.width * 0.18
            let path = NSBezierPath()
            path.move(to: CGPoint(x: r.minX, y: r.maxY))
            path.line(to: CGPoint(x: r.minX + s, y: r.minY))
            path.line(to: CGPoint(x: r.maxX - s, y: r.minY))
            path.line(to: CGPoint(x: r.maxX, y: r.maxY))
            path.close()
            return path
        case .display:
            let s = r.width * 0.18
            let path = NSBezierPath()
            path.move(to: CGPoint(x: r.minX, y: r.minY))
            path.line(to: CGPoint(x: r.maxX, y: r.minY))
            path.line(to: CGPoint(x: r.maxX - s, y: r.maxY))
            path.line(to: CGPoint(x: r.minX, y: r.maxY))
            path.close()
            return path
        case .pentagon, .hexagon, .octagon, .star, .star6:
            let c = CGPoint(x: r.midX, y: r.midY)
            let radius = min(r.width, r.height) / 2
            let sides: Int
            switch a.kind {
            case .pentagon: sides = 5
            case .hexagon: sides = 6
            case .octagon: sides = 8
            case .star: sides = 10
            default: sides = 12
            }
            let inner = a.kind == .star || a.kind == .star6 ? radius * (a.kind == .star ? 0.4 : 0.5) : radius
            let path = NSBezierPath()
            let startAngle: CGFloat = a.kind == .star || a.kind == .star6 ? -90 : 90
            for i in 0..<sides {
                let angle = startAngle + CGFloat(i) * 360 / CGFloat(sides)
                let rad = (i % 2 == 1 && (a.kind == .star || a.kind == .star6)) ? inner : radius
                let radian = angle * .pi / 180
                let p = CGPoint(x: c.x + rad * cos(radian), y: c.y + rad * sin(radian))
                if i == 0 { path.move(to: p) } else { path.line(to: p) }
            }
            path.close()
            return path
        case .cross:
            let t = min(r.width, r.height) * 0.34
            let c = CGPoint(x: r.midX, y: r.midY)
            let path = NSBezierPath()
            path.move(to: CGPoint(x: c.x - t / 2, y: r.minY))
            path.line(to: CGPoint(x: c.x + t / 2, y: r.minY))
            path.line(to: CGPoint(x: c.x + t / 2, y: c.y - t / 2))
            path.line(to: CGPoint(x: r.maxX, y: c.y - t / 2))
            path.line(to: CGPoint(x: r.maxX, y: c.y + t / 2))
            path.line(to: CGPoint(x: c.x + t / 2, y: c.y + t / 2))
            path.line(to: CGPoint(x: c.x + t / 2, y: r.maxY))
            path.line(to: CGPoint(x: c.x - t / 2, y: r.maxY))
            path.line(to: CGPoint(x: c.x - t / 2, y: c.y + t / 2))
            path.line(to: CGPoint(x: r.minX, y: c.y + t / 2))
            path.line(to: CGPoint(x: r.minX, y: c.y - t / 2))
            path.line(to: CGPoint(x: c.x - t / 2, y: c.y - t / 2))
            path.close()
            return path
        case .process:
            let path = NSBezierPath()
            let rad = min(r.width, r.height) * 0.15
            path.appendRoundedRect(r, xRadius: rad, yRadius: rad)
            return path
        case .predefinedProcess:
            let path = NSBezierPath()
            path.appendRect(r)
            let bx = r.width * 0.11
            path.move(to: CGPoint(x: r.minX + bx, y: r.minY))
            path.line(to: CGPoint(x: r.minX + bx, y: r.maxY))
            path.move(to: CGPoint(x: r.maxX - bx, y: r.minY))
            path.line(to: CGPoint(x: r.maxX - bx, y: r.maxY))
            return path
        case .delay:
            let rad = min(r.height / 2, r.width * 0.42)
            let path = NSBezierPath()
            path.move(to: CGPoint(x: r.minX, y: r.maxY))
            path.line(to: CGPoint(x: r.maxX, y: r.maxY))
            path.line(to: CGPoint(x: r.maxX, y: r.minY))
            path.line(to: CGPoint(x: r.minX, y: r.minY))
            path.quadCurve(
                to: CGPoint(x: r.minX, y: r.maxY),
                controlPoint: CGPoint(x: r.minX - rad, y: r.midY)
            )
            return path
        case .cloud:
            let c = CGPoint(x: r.midX, y: r.midY)
            let s = min(r.width, r.height) * 0.5
            let path = NSBezierPath()
            path.move(to: CGPoint(x: c.x - 0.85 * s, y: c.y - 0.1 * s))
            path.quadCurve(
                to: CGPoint(x: c.x - 0.6 * s, y: c.y - 0.6 * s),
                controlPoint: CGPoint(x: c.x - 1.25 * s, y: c.y - 0.4 * s)
            )
            path.quadCurve(
                to: CGPoint(x: c.x + 0.05 * s, y: c.y - 0.7 * s),
                controlPoint: CGPoint(x: c.x - 0.3 * s, y: c.y - 1.05 * s)
            )
            path.quadCurve(
                to: CGPoint(x: c.x + 0.55 * s, y: c.y - 0.55 * s),
                controlPoint: CGPoint(x: c.x + 0.3 * s, y: c.y - 1.0 * s)
            )
            path.quadCurve(
                to: CGPoint(x: c.x + 0.8 * s, y: c.y - 0.05 * s),
                controlPoint: CGPoint(x: c.x + 1.0 * s, y: c.y - 0.7 * s)
            )
            path.quadCurve(
                to: CGPoint(x: c.x + 0.4 * s, y: c.y + 0.5 * s),
                controlPoint: CGPoint(x: c.x + 1.15 * s, y: c.y + 0.25 * s)
            )
            path.quadCurve(
                to: CGPoint(x: c.x - 0.35 * s, y: c.y + 0.55 * s),
                controlPoint: CGPoint(x: c.x + 0.1 * s, y: c.y + 0.9 * s)
            )
            path.quadCurve(
                to: CGPoint(x: c.x - 0.85 * s, y: c.y + 0.1 * s),
                controlPoint: CGPoint(x: c.x - 0.65 * s, y: c.y + 0.8 * s)
            )
            path.close()
            return path
        case .serverStack:
            let path = NSBezierPath()
            let slot = r.height / 3
            let inset = min(r.width * 0.06, slot * 0.3)
            let rad = min(r.width, slot) * 0.08
            for k in 0..<3 {
                let y = r.minY + slot * CGFloat(k)
                let rect = CGRect(x: r.minX + inset, y: y + inset * 0.5, width: r.width - inset * 2, height: slot - inset)
                path.appendRoundedRect(rect, xRadius: rad, yRadius: rad)
                let midX = r.midX
                path.move(to: CGPoint(x: midX - r.width * 0.18, y: rect.midY))
                path.line(to: CGPoint(x: midX + r.width * 0.18, y: rect.midY))
            }
            return path
        case .queue:
            let path = NSBezierPath()
            let rad = min(r.height * 0.12, r.width * 0.14)
            path.appendRoundedRect(r, xRadius: rad, yRadius: rad)
            let gap = r.height / 4
            for k in 0..<3 {
                let center = CGPoint(x: r.minX - rad * 2.4, y: r.minY + gap + gap * CGFloat(k))
                path.appendOval(in: CGRect(
                    x: center.x - rad, y: center.y - rad,
                    width: rad * 2, height: rad * 2
                ))
            }
            return path
        case .firewall:
            let path = NSBezierPath()
            path.appendRect(r)
            let brickH = r.height / 2
            path.move(to: CGPoint(x: r.minX, y: r.minY + brickH))
            path.line(to: CGPoint(x: r.maxX, y: r.minY + brickH))
            let brickW = r.width / 3
            path.move(to: CGPoint(x: r.minX + brickW, y: r.minY))
            path.line(to: CGPoint(x: r.minX + brickW, y: r.minY + brickH))
            path.move(to: CGPoint(x: r.minX + brickW / 2, y: r.minY + brickH))
            path.line(to: CGPoint(x: r.minX + brickW / 2, y: r.maxY))
            path.move(to: CGPoint(x: r.minX + brickW * 1.5, y: r.minY + brickH))
            path.line(to: CGPoint(x: r.minX + brickW * 1.5, y: r.maxY))
            return path
        case .cube:
            let d = r.width * 0.16
            let path = NSBezierPath()
            path.move(to: CGPoint(x: r.minX, y: r.minY))
            path.line(to: CGPoint(x: r.maxX, y: r.minY))
            path.line(to: CGPoint(x: r.maxX, y: r.maxY))
            path.line(to: CGPoint(x: r.minX, y: r.maxY))
            path.close()
            path.move(to: CGPoint(x: r.minX, y: r.minY))
            path.line(to: CGPoint(x: r.minX + d, y: r.minY - d))
            path.line(to: CGPoint(x: r.maxX + d, y: r.minY - d))
            path.line(to: CGPoint(x: r.maxX, y: r.minY))
            path.move(to: CGPoint(x: r.maxX, y: r.minY))
            path.line(to: CGPoint(x: r.maxX + d, y: r.minY - d))
            path.line(to: CGPoint(x: r.maxX + d, y: r.maxY - d))
            path.line(to: CGPoint(x: r.maxX, y: r.maxY))
            return path
        case .callout:
            let path = NSBezierPath()
            let rad = min(r.width, r.height) * 0.1
            let tailY = r.maxY - r.height * 0.28
            path.move(to: CGPoint(x: r.minX + rad, y: r.minY))
            path.line(to: CGPoint(x: r.maxX - rad, y: r.minY))
            path.line(to: CGPoint(x: r.maxX, y: r.minY + rad))
            path.line(to: CGPoint(x: r.maxX, y: r.maxY - rad))
            path.line(to: CGPoint(x: r.maxX - rad, y: r.maxY))
            path.line(to: CGPoint(x: r.minX + r.width * 0.22, y: r.maxY))
            path.line(to: CGPoint(x: r.minX + r.width * 0.1, y: r.maxY + r.height * 0.32))
            path.line(to: CGPoint(x: r.minX + r.width * 0.04, y: tailY))
            path.line(to: CGPoint(x: r.minX, y: tailY))
            path.line(to: CGPoint(x: r.minX, y: r.minY + rad))
            path.close()
            return path
        case .note:
            let fold = min(r.width, r.height) * 0.22
            let path = NSBezierPath()
            path.move(to: CGPoint(x: r.minX, y: r.maxY))
            path.line(to: CGPoint(x: r.minX, y: r.minY))
            path.line(to: CGPoint(x: r.maxX, y: r.minY))
            path.line(to: CGPoint(x: r.maxX, y: r.minY + fold))
            path.line(to: CGPoint(x: r.maxX - fold, y: r.minY + fold))
            path.line(to: CGPoint(x: r.maxX - fold, y: r.maxY))
            path.close()
            return path
        default:
            return NSBezierPath()
        }
    }

    // MARK: - rough (hand-drawn) path generators

    private func roughRect(_ r: CGRect, slop: CGFloat, edge: CGFloat, seed: UInt64) -> NSBezierPath {
        var rnd = SeededRandom(seed: seed)
        let jit = slop * max(3, min(r.width, r.height) * 0.14)
        let over = edge * 5 + 1
        let corners = [
            CGPoint(x: r.minX, y: r.minY),
            CGPoint(x: r.maxX, y: r.minY),
            CGPoint(x: r.maxX, y: r.maxY),
            CGPoint(x: r.minX, y: r.maxY),
        ]
        let path = NSBezierPath()
        for k in 0..<4 {
            let a = corners[k]
            let b = corners[(k + 1) % 4]
            let d = norm(b - a)
            let n = CGPoint(x: -d.y, y: d.x)
            let overA = over * (0.6 + rnd.next())
            let overB = over * (0.6 + rnd.next())
            let start = CGPoint(x: a.x - d.x * overA, y: a.y - d.y * overA)
            let end = CGPoint(x: b.x + d.x * overB, y: b.y + d.y * overB)
            let mid = CGPoint(
                x: (start.x + end.x) / 2 + n.x * (rnd.next() * 2 - 1) * jit,
                y: (start.y + end.y) / 2 + n.y * (rnd.next() * 2 - 1) * jit
            )
            if k == 0 {
                path.move(to: start)
            }
            path.quadCurve(to: end, controlPoint: mid)
            // Sketchy corner: loop back around the corner toward the next edge.
            let d2 = norm(corners[(k + 2) % 4] - corners[(k + 1) % 4])
            let nextStart = CGPoint(x: b.x - d2.x * overB, y: b.y - d2.y * overB)
            let ctrl = CGPoint(
                x: b.x + (rnd.next() * 2 - 1) * jit * 0.9,
                y: b.y + (rnd.next() * 2 - 1) * jit * 0.9
            )
            path.quadCurve(to: nextStart, controlPoint: ctrl)
        }
        return path
    }

    private func roughRoundedRect(_ r: CGRect, rx: CGFloat, ry: CGFloat, slop: CGFloat, edge: CGFloat, seed: UInt64) -> NSBezierPath {
        let rxE = min(rx, r.width / 2)
        let ryE = min(ry, r.height / 2)
        if rxE < 1 && ryE < 1 {
            return roughRect(r, slop: slop, edge: edge, seed: seed)
        }
        var rnd = SeededRandom(seed: seed)
        let jit = slop * max(3, min(r.width, r.height) * 0.14)
        let x0 = r.minX, x1 = r.maxX, y0 = r.minY, y1 = r.maxY
        // 8 anchor points tracing the rounded-rect outline clockwise.
        let pts = [
            CGPoint(x: x0 + rxE, y: y0),
            CGPoint(x: x1 - rxE, y: y0),
            CGPoint(x: x1, y: y0 + ryE),
            CGPoint(x: x1, y: y1 - ryE),
            CGPoint(x: x1 - rxE, y: y1),
            CGPoint(x: x0 + rxE, y: y1),
            CGPoint(x: x0, y: y1 - ryE),
            CGPoint(x: x0, y: y0 + ryE),
        ]
        let corners = [
            CGPoint(x: x0, y: y0),
            CGPoint(x: x1, y: y0),
            CGPoint(x: x1, y: y1),
            CGPoint(x: x0, y: y1),
        ]
        let path = NSBezierPath()
        var firstPoint: CGPoint?
        for i in 0..<8 {
            let a = pts[i]
            let b = pts[(i + 1) % 8]
            if i % 2 == 0 {
                // Straight edge — wobble it perpendicular to its direction.
                let d = norm(b - a)
                let n = CGPoint(x: -d.y, y: d.x)
                let mid = CGPoint(
                    x: (a.x + b.x) / 2 + n.x * (rnd.next() * 2 - 1) * jit,
                    y: (a.y + b.y) / 2 + n.y * (rnd.next() * 2 - 1) * jit
                )
                let wobbleB = CGPoint(
                    x: b.x + (rnd.next() * 2 - 1) * jit * 0.35,
                    y: b.y + (rnd.next() * 2 - 1) * jit * 0.35
                )
                if firstPoint == nil {
                    path.move(to: a)
                    firstPoint = a
                }
                path.quadCurve(to: wobbleB, controlPoint: mid)
            } else {
                // Corner arc — quadratic through a wobbled corner point.
                let c = corners[i / 2]
                let ctrl = CGPoint(
                    x: c.x + (rnd.next() * 2 - 1) * jit * 1.1,
                    y: c.y + (rnd.next() * 2 - 1) * jit * 1.1
                )
                let wobbleB = CGPoint(
                    x: b.x + (rnd.next() * 2 - 1) * jit * 0.35,
                    y: b.y + (rnd.next() * 2 - 1) * jit * 0.35
                )
                path.quadCurve(to: wobbleB, controlPoint: ctrl)
            }
        }
        return path
    }

    private func roughEllipse(_ r: CGRect, slop: CGFloat, edge: CGFloat, seed: UInt64) -> NSBezierPath {
        var rnd = SeededRandom(seed: seed)
        let jit = slop * max(3, min(r.width, r.height) * 0.12)
        let left = CGPoint(x: r.minX, y: r.midY)
        let right = CGPoint(x: r.maxX, y: r.midY)
        let top = CGPoint(x: r.midX, y: r.minY)
        let bottom = CGPoint(x: r.midX, y: r.maxY)
        let path = NSBezierPath()
        path.move(to: left)
        // Top arc (left → right via top), bottom arc (right → left via bottom).
        let ctrlTop = CGPoint(
            x: top.x + (rnd.next() * 2 - 1) * jit,
            y: top.y + (rnd.next() * 2 - 1) * jit
        )
        path.quadCurve(to: right, controlPoint: ctrlTop)
        let ctrlBottom = CGPoint(
            x: bottom.x + (rnd.next() * 2 - 1) * jit,
            y: bottom.y + (rnd.next() * 2 - 1) * jit
        )
        path.quadCurve(to: left, controlPoint: ctrlBottom)
        path.close()
        return path
    }

    private func roughDiamond(_ r: CGRect, slop: CGFloat, edge: CGFloat, seed: UInt64) -> NSBezierPath {
        var rnd = SeededRandom(seed: seed)
        let jit = slop * max(3, min(r.width, r.height) * 0.14)
        let over = edge * 5 + 1
        let corners = [
            CGPoint(x: r.midX, y: r.maxY),
            CGPoint(x: r.maxX, y: r.midY),
            CGPoint(x: r.midX, y: r.minY),
            CGPoint(x: r.minX, y: r.midY),
        ]
        let path = NSBezierPath()
        for k in 0..<4 {
            let a = corners[k]
            let b = corners[(k + 1) % 4]
            let d = norm(b - a)
            let n = CGPoint(x: -d.y, y: d.x)
            let overA = over * (0.6 + rnd.next())
            let overB = over * (0.6 + rnd.next())
            let start = CGPoint(x: a.x - d.x * overA, y: a.y - d.y * overA)
            let end = CGPoint(x: b.x + d.x * overB, y: b.y + d.y * overB)
            let mid = CGPoint(
                x: (start.x + end.x) / 2 + n.x * (rnd.next() * 2 - 1) * jit,
                y: (start.y + end.y) / 2 + n.y * (rnd.next() * 2 - 1) * jit
            )
            if k == 0 {
                path.move(to: start)
            }
            path.quadCurve(to: end, controlPoint: mid)
            let d2 = norm(corners[(k + 2) % 4] - corners[(k + 1) % 4])
            let nextStart = CGPoint(x: b.x - d2.x * overB, y: b.y - d2.y * overB)
            let ctrl = CGPoint(
                x: b.x + (rnd.next() * 2 - 1) * jit * 0.9,
                y: b.y + (rnd.next() * 2 - 1) * jit * 0.9
            )
            path.quadCurve(to: nextStart, controlPoint: ctrl)
        }
        return path
    }

    private func roughLine(from p0: CGPoint, to p1: CGPoint, slop: CGFloat, edge: CGFloat, seed: UInt64) -> NSBezierPath {
        var rnd = SeededRandom(seed: seed)
        let len = max(1, distance(p0, p1))
        let ux = (p1.x - p0.x) / len
        let uy = (p1.y - p0.y) / len
        let over = edge * 6 * (0.5 + rnd.next())
        let start = CGPoint(x: p0.x - ux * over, y: p0.y - uy * over)
        let end = CGPoint(x: p1.x + ux * over, y: p1.y + uy * over)
        let jit = slop * max(2, len * 0.12)
        let mid = CGPoint(
            x: (start.x + end.x) / 2 - uy * (rnd.next() * 2 - 1) * jit,
            y: (start.y + end.y) / 2 + ux * (rnd.next() * 2 - 1) * jit
        )
        let path = NSBezierPath()
        path.move(to: start)
        path.quadCurve(to: end, controlPoint: mid)
        return path
    }

    private func norm(_ v: CGPoint) -> CGPoint {
        let len = max(0.0001, sqrt(v.x * v.x + v.y * v.y))
        return CGPoint(x: v.x / len, y: v.y / len)
    }

    /// Dotted stroke — dots sampled along the flattened path, spaced by the
    /// stroke width like a real pen.
    private func strokeDotted(path: NSBezierPath, color: NSColor, width: CGFloat) {
        let pts = flattenedPoints(path, step: max(1, width * 1.2))
        guard !pts.isEmpty else { return }
        let spacing = max(3, width * 2.4)
        let dotR = max(1.5, width * 0.55)
        color.setFill()
        var last: CGPoint?
        for p in pts {
            if let l = last, distance(l, p) < spacing { continue }
            NSBezierPath(ovalIn: CGRect(x: p.x - dotR, y: p.y - dotR, width: dotR * 2, height: dotR * 2)).fill()
            last = p
        }
    }

    /// Flattens any bezier path into evenly-sampled points (used for dotted
    /// strokes, boundary snapping and distance checks).
    private func flattenedPoints(_ path: NSBezierPath, step: CGFloat) -> [CGPoint] {
        var out: [CGPoint] = []
        var last = CGPoint.zero
        var first = CGPoint.zero
        var haveLast = false
        var haveFirst = false
        for i in 0..<path.elementCount {
            let pts = UnsafeMutablePointer<NSPoint>.allocate(capacity: 3)
            defer { pts.deallocate() }
            let kind = path.element(at: i, associatedPoints: pts)
            switch kind {
            case .moveTo:
                last = pts[0]
                first = pts[0]
                haveLast = true
                haveFirst = true
            case .lineTo:
                if haveLast {
                    out.append(contentsOf: sampleSegment(last, pts[0], step: step))
                }
                last = pts[0]
            case .curveTo, .cubicCurveTo:
                if haveLast {
                    var prev = last
                    for k in 1...20 {
                        let f = CGFloat(k) / 20
                        let q = cubicPoint(prev, pts[0], pts[1], pts[2], t: f)
                        out.append(contentsOf: sampleSegment(prev, q, step: step))
                        prev = q
                    }
                }
                last = pts[2]
            case .quadraticCurveTo:
                if haveLast {
                    var prev = last
                    for k in 1...20 {
                        let f = CGFloat(k) / 20
                        let q = quadPoint(prev, pts[0], pts[1], t: f)
                        out.append(contentsOf: sampleSegment(prev, q, step: step))
                        prev = q
                    }
                }
                last = pts[1]
            case .closePath:
                if haveLast, haveFirst {
                    out.append(contentsOf: sampleSegment(last, first, step: step))
                    last = first
                }
            @unknown default:
                break
            }
        }
        return out
    }

    private func sampleSegment(_ a: CGPoint, _ b: CGPoint, step: CGFloat) -> [CGPoint] {
        let len = distance(a, b)
        let count = max(1, Int(len / max(1, step)))
        var pts: [CGPoint] = []
        for k in 1...count {
            let f = CGFloat(k) / CGFloat(count)
            pts.append(CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f))
        }
        return pts
    }

    // MARK: - shape attachment (arrow/line snapping)

    /// Snaps a point to the boundary of the nearest shape when it's close
    /// enough — lets arrows and lines attach to shape edges while drawing or
    /// dragging their endpoints. `selfIndex` excludes the shape being edited.
    private let snapThreshold: CGFloat = 10

    // MARK: - connector routing

    private func isConnectorTool(_ tool: Tool) -> Bool {
        switch tool {
        case .arrow, .line, .doubleArrow, .curvedConnector, .orthogonal, .connector:
            return true
        default:
            return false
        }
    }

    /// The four edge-midpoint connection dots of a shape (in canvas space).
    private func connectionDots(for a: Annotation) -> [(side: Int, point: CGPoint)] {
        let r = a.rect
        let center = CGPoint(x: r.midX, y: r.midY)
        let local: [(Int, CGPoint)] = [
            (0, CGPoint(x: r.minX + r.width * 0.5, y: r.maxY)), // top
            (1, CGPoint(x: r.maxX, y: r.minY + r.height * 0.5)), // right
            (2, CGPoint(x: r.minX + r.width * 0.5, y: r.minY)), // bottom
            (3, CGPoint(x: r.minX, y: r.minY + r.height * 0.5)), // left
        ]
        return local.map { ($0.0, rotatedPoint($0.1, around: center, by: a.rotation)) }
    }

    /// The connection dot under `p`, if any (connector tools snap to these).
    private func connectionDot(at p: CGPoint) -> (index: Int, side: Int)? {
        let threshold: CGFloat = 9
        for (i, a) in annotations.enumerated() {
            guard isClosed(a.kind), a.kind != .laser else { continue }
            for (side, dot) in connectionDots(for: a) where distance(p, dot) < threshold {
                return (i, side)
            }
        }
        return nil
    }

    /// Resolves a glued connector end against the shape's *current* rect, so
    /// the line follows the box when it moves, resizes or rotates.
    private func connectionPoint(for c: ShapeConnection?, fallback: CGPoint) -> CGPoint {
        guard let c, annotations.indices.contains(c.annotationIndex) else { return fallback }
        let a = annotations[c.annotationIndex]
        let r = a.rect
        let fx = r.minX + r.width * c.fraction
        let fy = r.minY + r.height * c.fraction
        let local: CGPoint
        switch c.side {
        case 0: local = CGPoint(x: fx, y: r.maxY)
        case 1: local = CGPoint(x: r.maxX, y: fy)
        case 2: local = CGPoint(x: fx, y: r.minY)
        default: local = CGPoint(x: r.minX, y: fy)
        }
        return rotatedPoint(local, around: CGPoint(x: r.midX, y: r.midY), by: a.rotation)
    }

    /// The outward edge normal at a glued connector end — the connector must
    /// leave / enter the shape perpendicular to that edge.
    private func connectionNormal(for c: ShapeConnection?) -> CGPoint? {
        guard let c, annotations.indices.contains(c.annotationIndex) else { return nil }
        let a = annotations[c.annotationIndex]
        let base: CGPoint
        switch c.side {
        case 0: base = CGPoint(x: 0, y: 1)
        case 1: base = CGPoint(x: 1, y: 0)
        case 2: base = CGPoint(x: 0, y: -1)
        default: base = CGPoint(x: -1, y: 0)
        }
        return rotatedPoint(base, around: .zero, by: a.rotation)
    }

    /// The closed shape a connector end is attached to (within snap distance),
    /// with the outward-facing normal at the attachment point. The connector
    /// must leave / enter its shape perpendicular to the shape's edge.
    private struct ConnectorOwner {
        var normal: CGPoint
    }

    private func connectorOwner(at p: CGPoint) -> ConnectorOwner? {
        var bestIndex: Int?
        var bestDist = CGFloat.greatestFiniteMagnitude
        for (i, a) in annotations.enumerated() {
            guard isClosed(a.kind), a.kind != .laser, a.rect.width > 0, a.rect.height > 0 else { continue }
            let center = CGPoint(x: a.rect.midX, y: a.rect.midY)
            let local = rotatedPoint(p, around: center, by: -a.rotation)
            let d = distancePointToRect(local, a.rect)
            if d < snapThreshold && d < bestDist {
                bestDist = d
                bestIndex = i
            }
        }
        guard let bestIndex else { return nil }
        let a = annotations[bestIndex]
        let center = CGPoint(x: a.rect.midX, y: a.rect.midY)
        let local = rotatedPoint(p, around: center, by: -a.rotation)
        let boundary = flattenedPoints(bezierPath(for: a), step: 3)
        guard !boundary.isEmpty else { return nil }
        var bestPt = boundary[0]
        var bestD = distance(local, bestPt)
        for q in boundary.dropFirst() {
            let d = distance(local, q)
            if d < bestD {
                bestD = d
                bestPt = q
            }
        }
        var tangent = CGPoint.zero
        if let qi = boundary.firstIndex(of: bestPt) {
            let prev = boundary[(qi - 1 + boundary.count) % boundary.count]
            let next = boundary[(qi + 1) % boundary.count]
            tangent = CGPoint(x: next.x - prev.x, y: next.y - prev.y)
        }
        let len = max(0.001, sqrt(tangent.x * tangent.x + tangent.y * tangent.y))
        var normal = CGPoint(x: -tangent.y / len, y: tangent.x / len)
        let toCenter = CGPoint(x: center.x - local.x, y: center.y - local.y)
        if normal.x * toCenter.x + normal.y * toCenter.y < 0 {
            normal = CGPoint(x: -normal.x, y: -normal.y)
        }
        return ConnectorOwner(normal: rotatedPoint(normal, around: .zero, by: a.rotation))
    }

    /// Rects that block a connector's straight path: every closed shape plus
    /// text/image blocks, inflated by a clearance margin. The connector
    /// itself is never its own obstacle.
    private func connectorObstacles(for a: Annotation, margin: CGFloat) -> [CGRect] {
        var out: [CGRect] = []
        let startIdx = a.connectionStart?.annotationIndex
        let endIdx = a.connectionEnd?.annotationIndex
        for (i, other) in annotations.enumerated() {
            // The connector's glued owner shapes are not obstacles — their
            // inflated rects would swallow the connector's own endpoints.
            if i == startIdx || i == endIdx { continue }
            if other.kind == a.kind,
               other.rect == a.rect,
               other.points == a.points,
               other.rotation == a.rotation,
               other.strokeWidth == a.strokeWidth {
                continue
            }
            guard (isClosed(other.kind) || other.kind == .text || other.kind == .image), other.kind != .laser else { continue }
            out.append(other.rect.insetBy(dx: -margin, dy: -margin))
        }
        return out
    }

    private func straightIsBlocked(_ from: CGPoint, _ to: CGPoint, obstacles: [CGRect]) -> Bool {
        let mnX = min(from.x, to.x), mxX = max(from.x, to.x)
        let mnY = min(from.y, to.y), mxY = max(from.y, to.y)
        for ob in obstacles where mxX >= ob.minX && mnX <= ob.maxX && mxY >= ob.minY && mnY <= ob.maxY {
            return true
        }
        return false
    }

    private func curveIsBlocked(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p1: CGPoint, obstacles: [CGRect]) -> Bool {
        for k in 1...12 {
            let f = CGFloat(k) / 12
            let q = cubicPoint(p0, c1, c2, p1, t: f)
            for ob in obstacles where q.x >= ob.minX && q.x <= ob.maxX && q.y >= ob.minY && q.y <= ob.maxY {
                return true
            }
        }
        return false
    }

    private func routeCollides(_ pts: [CGPoint], obstacles: [CGRect]) -> Bool {
        for k in 0..<(pts.count - 1) {
            if straightIsBlocked(pts[k], pts[k + 1], obstacles: obstacles) { return true }
        }
        return false
    }

    /// Finds an orthogonal path from `start` to `end` that clears every
    /// obstacle, leaving both ends perpendicular to the edge of the shape
    /// they are attached to. Returns nil when no clean route exists.
    private func connectorRoute(
        from start: CGPoint,
        to end: CGPoint,
        startOwner: ConnectorOwner?,
        endOwner: ConnectorOwner?,
        obstacles: [CGRect]
    ) -> [CGPoint]? {
        let legLengths: [CGFloat] = [32, 56, 88, 128, 176]
        for leg in legLengths {
            let a = startOwner.map { CGPoint(x: start.x + $0.normal.x * leg, y: start.y + $0.normal.y * leg) } ?? start
            let b = endOwner.map { CGPoint(x: end.x + $0.normal.x * leg, y: end.y + $0.normal.y * leg) } ?? end
            var candidates: [[CGPoint]] = []
            let mx = (a.x + b.x) / 2
            let my = (a.y + b.y) / 2
            // Horizontal-first and vertical-first bends, plus parallel
            // offsets so routes can dodge obstacles sitting beside the
            // direct line. Clearance lines are derived from the obstacles'
            // own bounds too, so a tall mid-box is always dodged instead of
            // pierced, and the wider ladder covers very large shapes.
            var yLines: [CGFloat] = [a.y, b.y, my, my - 60, my + 60, my - 120, my + 120, my - 180, my + 180]
            var xLines: [CGFloat] = [a.x, b.x, mx, mx - 60, mx + 60, mx - 120, mx + 120, mx - 180, mx + 180]
            // Clear columns/lines derived from the obstacles themselves, so a
            // tall mid-box is always dodged instead of pierced, even when it
            // reaches right up to the connected shapes.
            var columns = Set<CGFloat>([a.x, b.x, end.x])
            var dodgeYs = Set<CGFloat>([my - 120, my + 120, my - 60, my + 60])
            for ob in obstacles {
                yLines.append(ob.maxY + 14)
                yLines.append(ob.minY - 14)
                xLines.append(ob.maxX + 14)
                xLines.append(ob.minX - 14)
                if ob.maxX >= a.x && ob.minX <= b.x {
                    columns.insert(ob.maxX + 14)
                    columns.insert(ob.minX - 14)
                    dodgeYs.insert(ob.maxY + 14)
                    dodgeYs.insert(ob.minY - 14)
                }
            }
            for y in yLines {
                candidates.append([a, CGPoint(x: a.x, y: y), CGPoint(x: b.x, y: y), b, end])
            }
            for x in xLines {
                candidates.append([a, CGPoint(x: x, y: b.y), CGPoint(x: x, y: a.y), b, end])
            }
            // Full 4-bend dodges: climb at a clear column, cross at a clear
            // line, descend at a clear column, then approach the end shape.
            let cols = columns.sorted()
            for y in dodgeYs.sorted() {
                for c in cols {
                    for x in cols {
                        candidates.append([
                            a,
                            CGPoint(x: c, y: a.y),
                            CGPoint(x: c, y: y),
                            CGPoint(x: x, y: y),
                            CGPoint(x: x, y: end.y),
                            end
                        ])
                    }
                }
            }
            // Shortest clean route wins, but dodge routes that cross above the
            // endpoints' mid-line are preferred over equally-cheap bottom
            // routes (within a small length band), so connectors go over
            // obstacles by default.
            candidates.sort {
                let l1 = pathLength($0), l2 = pathLength($1)
                if abs(l1 - l2) > 40 { return l1 < l2 }
                return $0.count > 2 ? $0[2].y > $1[2].y : l1 < l2
            }
            for cand in candidates {
                var full: [CGPoint] = [start]
                for q in cand where distance(full.last!, q) > 0.5 {
                    full.append(q)
                }
                if distance(full.last!, end) > 0.5 { full.append(end) }
                if !routeCollides(full, obstacles: obstacles) {
                    return full
                }
            }
        }
        return nil
    }

    private func pathLength(_ pts: [CGPoint]) -> CGFloat {
        var len: CGFloat = 0
        for k in 0..<(pts.count - 1) {
            len += distance(pts[k], pts[k + 1])
        }
        return len
    }

    /// Direction of the path's final segment — follows curves along their end
    /// tangent so arrowheads stay glued to the line.
    private func lastSegment(of path: NSBezierPath) -> (start: CGPoint, end: CGPoint)? {
        var prev = CGPoint.zero
        var havePrev = false
        var last: (start: CGPoint, end: CGPoint)?
        for i in 0..<path.elementCount {
            let pts = UnsafeMutablePointer<NSPoint>.allocate(capacity: 3)
            defer { pts.deallocate() }
            switch path.element(at: i, associatedPoints: pts) {
            case .moveTo:
                prev = pts[0]
                havePrev = true
            case .lineTo:
                if havePrev { last = (prev, pts[0]) }
                prev = pts[0]
            case .curveTo, .cubicCurveTo:
                if havePrev {
                    let tangent = CGPoint(x: pts[2].x - pts[1].x, y: pts[2].y - pts[1].y)
                    last = (CGPoint(x: pts[2].x - tangent.x, y: pts[2].y - tangent.y), pts[2])
                }
                prev = pts[2]
            case .quadraticCurveTo:
                if havePrev {
                    let tangent = CGPoint(x: pts[1].x - pts[0].x, y: pts[1].y - pts[0].y)
                    last = (CGPoint(x: pts[1].x - tangent.x, y: pts[1].y - tangent.y), pts[1])
                }
                prev = pts[1]
            default:
                break
            }
        }
        return last
    }

    /// Direction of the path's first segment.
    private func firstSegment(of path: NSBezierPath) -> (start: CGPoint, end: CGPoint)? {
        var prev = CGPoint.zero
        var havePrev = false
        for i in 0..<path.elementCount {
            let pts = UnsafeMutablePointer<NSPoint>.allocate(capacity: 3)
            defer { pts.deallocate() }
            switch path.element(at: i, associatedPoints: pts) {
            case .moveTo:
                prev = pts[0]
                havePrev = true
            case .lineTo:
                if havePrev { return (prev, pts[0]) }
            case .curveTo, .cubicCurveTo:
                if havePrev { return (prev, pts[2]) }
            case .quadraticCurveTo:
                if havePrev { return (prev, pts[1]) }
            default:
                break
            }
        }
        return nil
    }

    private func distancePointToRect(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return sqrt(dx * dx + dy * dy)
    }

    private func snappedBoundaryPoint(_ p: CGPoint, selfIndex: Int? = nil) -> CGPoint {
        var bestDist = CGFloat.greatestFiniteMagnitude
        var bestPoint = p
        var bestRotation: CGFloat = 0
        var bestCenter: CGPoint?
        for (i, a) in annotations.enumerated() {
            if i == selfIndex { continue }
            guard isClosed(a.kind), a.kind != .laser, a.rect.width > 0, a.rect.height > 0 else { continue }
            let center = CGPoint(x: a.rect.midX, y: a.rect.midY)
            let local = rotatedPoint(p, around: center, by: -a.rotation)
            for q in flattenedPoints(bezierPath(for: a), step: 3) {
                let d = distance(local, q)
                if d < bestDist {
                    bestDist = d
                    bestPoint = q
                    bestRotation = a.rotation
                    bestCenter = center
                }
            }
        }
        guard bestDist < snapThreshold, let center = bestCenter else { return p }
        return rotatedPoint(bestPoint, around: center, by: bestRotation)
    }

    private func isClosed(_ kind: ShapeKind) -> Bool {
        switch kind {
        case .rect, .diamond, .ellipse, .frame, .autoshape,
             .triangle, .rightTriangle, .parallelogram, .trapezoid,
             .pentagon, .hexagon, .octagon, .star, .star6, .cross,
             .process, .predefinedProcess, .delay, .manualInput, .display,
             .cloud, .serverStack, .queue, .firewall, .cube,
             .callout, .note:
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

    /// Detects if a shape is closed (initial point meets final point or completes a boundary)
    private func isClosedShape(_ pts: [CGPoint]) -> Bool {
        guard pts.count >= 3 else { return false }
        
        let first = pts.first!
        let last = pts.last!
        
        // Check if the first and last points are close enough
        let threshold: CGFloat = 20.0
        let distance = sqrt(pow(first.x - last.x, 2) + pow(first.y - last.y, 2))
        
        if distance < threshold {
            return true
        }
        
        // Additional check: if the shape forms a closed loop by checking if any point
        // is close to the first point (meaning it completed a boundary)
        for i in 1..<(pts.count - 1) {
            let checkDistance = sqrt(pow(first.x - pts[i].x, 2) + pow(first.y - pts[i].y, 2))
            if checkDistance < threshold {
                return true
            }
        }
        
        return false
    }
}
