import AppKit
import Combine

enum ShapeKind: String {
    case rect
    case diamond
    case ellipse
    case line
    case arrow
    case freedraw
    case autoshape
    case frame
    case laser
    case text
    case image
    // Polygon library
    case triangle
    case rightTriangle
    case parallelogram
    case trapezoid
    case pentagon
    case hexagon
    case octagon
    case star
    case star6
    case cross
    // Flowchart
    case process
    case predefinedProcess
    case delay
    case manualInput
    case display
    // Architecture
    case cloud
    case serverStack
    case queue
    case firewall
    case cube
    // Communication
    case callout
    case note
    // Connectors
    case doubleArrow
    case curvedConnector
    case orthogonal
    case connector
    // Data structures — multi-node shapes with editable values in every node
    case linkedList
    case stack
    case heap
    case graph
    case set
}

/// How the outline of a shape is stroked.
enum StrokeStyle: String, CaseIterable, Codable {
    case solid
    case dashed
    case dotted
}

/// How the pen responds to movement:
/// - `.light`: uniform, constant-width lines regardless of speed or input.
/// - `.dynamic`: velocity-driven calligraphic strokes that swell when the
///   pen moves slowly and taper to thin tails when it moves fast.
enum PressureMode: String, CaseIterable, Codable {
    case light
    case dynamic
}

/// Where text attached to a shape is anchored inside it.
enum TextAnchor: String, Codable {
    case center
    case top
    case topLeft
}

enum Tool: String, CaseIterable {
    case selection
    case hand
    case rectangle
    case diamond
    case ellipse
    case arrow
    case line
    case freedraw
    case text
    case image
    case eraser
    case frame
    case embeddable
    case autoshape
    case lasso
    case laser
    case bucketFill
    case triangle
    case rightTriangle
    case parallelogram
    case trapezoid
    case pentagon
    case hexagon
    case octagon
    case star
    case star6
    case cross
    case process
    case predefinedProcess
    case delay
    case manualInput
    case display
    case cloud
    case serverStack
    case queue
    case firewall
    case cube
    case callout
    case note
    case doubleArrow
    case curvedConnector
    case orthogonal
    case connector
    case linkedList
    case stack
    case heap
    case graph
    case set

    /// Tools that draw rect-based shapes, shown in the shape palette.
    static let shapePalette: [Tool] = [
        .rectangle, .diamond, .ellipse, .triangle, .rightTriangle,
        .parallelogram, .trapezoid, .pentagon, .hexagon, .octagon,
        .star, .star6, .cross, .process, .predefinedProcess, .delay,
        .manualInput, .display, .cloud, .serverStack, .queue,
        .firewall, .cube, .callout, .note, .arrow, .line,
        .doubleArrow, .curvedConnector, .orthogonal, .connector,
        // Data structures
        .linkedList, .stack, .heap, .graph, .set,
    ]

    var iconName: String {
        switch self {
        case .selection: return "selection"
        case .hand: return "hand"
        case .rectangle: return "rectangle"
        case .diamond: return "diamond"
        case .ellipse: return "ellipse"
        case .arrow: return "arrow"
        case .line: return "line"
        case .freedraw: return "freedraw"
        case .text: return "text"
        case .image: return "image"
        case .eraser: return "eraser"
        case .frame: return "frame"
        case .embeddable: return "embeddable"
        case .autoshape: return "autoshape"
        case .lasso: return "lasso"
        case .laser: return "laser"
        case .bucketFill: return "bucket-fill"
        case .triangle: return "triangle"
        case .rightTriangle: return "right-triangle"
        case .parallelogram: return "parallelogram"
        case .trapezoid: return "trapezoid"
        case .pentagon: return "pentagon"
        case .hexagon: return "hexagon"
        case .octagon: return "octagon"
        case .star: return "star"
        case .star6: return "star6"
        case .cross: return "cross"
        case .process: return "process"
        case .predefinedProcess: return "predefined-process"
        case .delay: return "delay"
        case .manualInput: return "manual-input"
        case .display: return "display"
        case .cloud: return "cloud"
        case .serverStack: return "server-stack"
        case .queue: return "queue"
        case .firewall: return "firewall"
        case .cube: return "cube"
        case .callout: return "callout"
        case .note: return "note"
        case .doubleArrow: return "double-arrow"
        case .curvedConnector: return "curved-connector"
        case .orthogonal: return "orthogonal"
        case .connector: return "connector"
        case .linkedList: return "linked-list"
        case .stack: return "stack"
        case .heap: return "heap"
        case .graph: return "graph"
        case .set: return "set"
        }
    }

    var label: String {
        switch self {
        case .selection: return "Select"
        case .hand: return "Pan"
        case .rectangle: return "Rectangle"
        case .diamond: return "Diamond"
        case .ellipse: return "Ellipse"
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .freedraw: return "Sketch"
        case .text: return "Text"
        case .image: return "Image"
        case .eraser: return "Eraser"
        case .frame: return "Frame"
        case .embeddable: return "Embed"
        case .autoshape: return "Magic shape"
        case .lasso: return "Lasso"
        case .laser: return "Laser"
        case .bucketFill: return "Fill"
        case .triangle: return "Triangle"
        case .rightTriangle: return "Right triangle"
        case .parallelogram: return "Parallelogram"
        case .trapezoid: return "Trapezoid"
        case .pentagon: return "Pentagon"
        case .hexagon: return "Hexagon"
        case .octagon: return "Octagon"
        case .star: return "Star"
        case .star6: return "6-point star"
        case .cross: return "Cross"
        case .process: return "Process"
        case .predefinedProcess: return "Predefined process"
        case .delay: return "Delay"
        case .manualInput: return "Manual input"
        case .display: return "Display"
        case .cloud: return "Cloud"
        case .serverStack: return "Server stack"
        case .queue: return "Queue"
        case .firewall: return "Firewall"
        case .cube: return "Cube"
        case .callout: return "Callout"
        case .note: return "Note"
        case .doubleArrow: return "Double arrow"
        case .curvedConnector: return "Curved connector"
        case .orthogonal: return "Orthogonal line"
        case .connector: return "Connector"
        case .linkedList: return "Linked list"
        case .stack: return "Stack"
        case .heap: return "Heap"
        case .graph: return "Graph"
        case .set: return "Set"
        }
    }

    var shapeKind: ShapeKind? {
        switch self {
        case .rectangle: return .rect
        case .diamond: return .diamond
        case .ellipse: return .ellipse
        case .arrow: return .arrow
        case .line: return .line
        case .freedraw: return .freedraw
        case .autoshape: return .autoshape
        case .frame, .embeddable: return .frame
        case .laser: return .laser
        case .triangle: return .triangle
        case .rightTriangle: return .rightTriangle
        case .parallelogram: return .parallelogram
        case .trapezoid: return .trapezoid
        case .pentagon: return .pentagon
        case .hexagon: return .hexagon
        case .octagon: return .octagon
        case .star: return .star
        case .star6: return .star6
        case .cross: return .cross
        case .process: return .process
        case .predefinedProcess: return .predefinedProcess
        case .delay: return .delay
        case .manualInput: return .manualInput
        case .display: return .display
        case .cloud: return .cloud
        case .serverStack: return .serverStack
        case .queue: return .queue
        case .firewall: return .firewall
        case .cube: return .cube
        case .callout: return .callout
        case .note: return .note
        case .doubleArrow: return .doubleArrow
        case .curvedConnector: return .curvedConnector
        case .orthogonal: return .orthogonal
        case .connector: return .connector
        case .linkedList: return .linkedList
        case .stack: return .stack
        case .heap: return .heap
        case .graph: return .graph
        case .set: return .set
        default: return nil
        }
    }
}

struct Annotation {
    var kind: ShapeKind
    var rect: CGRect = .zero
    var strokeColor: NSColor = Palette.black
    var fillColor: NSColor?
    var fillOpacity: CGFloat = 1.0
    var strokeWidth: CGFloat = 2
    var points: [CGPoint] = []
    var pointTimes: [Date] = []
    var text: String = ""
    var fontFamily: String = "Virgil"
    var fontSize: CGFloat = 24
    var image: NSImage?
    var rounded: Bool = false
    var dashed: Bool = false
    var rotation: CGFloat = 0
    var createdAt: Date = Date()
    var locked: Bool = false
    var zIndex: Int = 0
    /// Stroke rendering style (solid / dashed / dotted).
    var strokeStyle: StrokeStyle = .solid
    /// 0 = perfect vector lines, 1 = heavily hand-drawn wobble (Rough.js style).
    var sloppiness: CGFloat = 0
    /// 0 = clean corners, 1 = sketchy over-drawn corners that stick out.
    var edgeRoughness: CGFloat = 0
    /// Corner radius of rounded rectangles (rx, ry).
    var rx: CGFloat = 0
    var ry: CGFloat = 0
    /// When true, `text` is rendered centered inside this shape (double-click
    /// a polygon to type into it). The text moves/resizes/rotates with it.
    var textInside: Bool = false
    var textAnchor: TextAnchor = .center
    /// Standalone text grows to its measured content while this is true.
    /// Dragging a horizontal text handle turns it off and makes that width a
    /// deliberate wrapping constraint (the same distinction used by modern
    /// canvas editors).
    var textAutoResize: Bool = true
    /// True when this stroke renders with variable width — velocity-driven
    /// calligraphic swell and taper — instead of uniform thickness.
    var dynamicWidth: Bool = false
    /// SF Symbol name for icon annotations (inserted from the "/" palette) —
    /// lets recoloring re-render the tinted icon.
    var symbol: String? = nil
    /// True when this text renders as a syntax-highlighted code block with a
    /// translucent background.
    var isCode: Bool = false
    /// When set, this connector is glued to a shape's edge: its start point
    /// is recomputed from that shape's current rect whenever it moves, so
    /// the line follows the box. nil = plain absolute point.
    var connectionStart: ShapeConnection? = nil
    var connectionEnd: ShapeConnection? = nil
    /// Font this text used before it became a code block — restored exactly
    /// when toggling back to normal text (nil = never converted).
    var normalFontFamily: String? = nil
    var normalFontSize: CGFloat? = nil
    /// RTF data of the markdown-formatted rich text (headings, bullets, code,
    /// bold/italic...) — nil when the text is plain. Rendering and re-editing
    /// use this; the plain `text` is what the user types.
    var richTextData: Data? = nil
    /// Values inside the nodes of a data-structure shape (linked list, stack,
    /// heap, graph, set). One entry per node; missing entries render empty.
    var nodeTexts: [String] = []

    /// The stored rich text, or nil when the annotation is plain.
    func richText() -> NSAttributedString? {
        guard let data = richTextData else { return nil }
        return NSAttributedString(rtf: data, documentAttributes: nil)
    }
}

/// Where a connector is pinned to a shape's edge. The anchor stays glued to
/// the box: moving, resizing or rotating the shape moves the connector end
/// with it (side/fraction are in the shape's local, pre-rotation space).
struct ShapeConnection: Codable, Equatable {
    var annotationIndex: Int
    /// 0 = top, 1 = right, 2 = bottom, 3 = left edge.
    var side: Int
    /// Position along the side, 0...1 (0 = start of the side, 1 = end).
    var fraction: CGFloat
}

/// Solid backdrop behind the drawing — lets the user write on a clean
/// white/black screen instead of whatever is behind the overlay.
enum CanvasBackground: String {
    case clear
    case white
    case black
}

final class CanvasState: ObservableObject {
    @Published var tool: Tool = .rectangle
    @Published var strokeColor: NSColor = Palette.black
    @Published var fillColor: NSColor = Palette.red[1]
    @Published var fillEnabled: Bool = false
    @Published var fillOpacity: CGFloat = 0.5
    @Published var strokeWidth: CGFloat = 3
    @Published var fontFamily: String = "Virgil"
    @Published var fontSize: CGFloat = 28
    @Published var canvasBackground: CanvasBackground = .clear

    // Stroke appearance — new shapes pick these up, selected shapes update live.
    // Pressure mode drives line dynamics; rectangles keep slightly curved corners.
    @Published var pressureMode: PressureMode = .dynamic
    @Published var cornerRadius: CGFloat = 10
    @Published var cornerRadiusY: CGFloat = 10

    /// When on, newly typed text becomes a syntax-highlighted code block
    /// (monospaced font, translucent background).
    @Published var codeBlockMode: Bool = false

    /// When false (default), clicks on the canvas pass through to your other
    /// apps. When true, the canvas captures mouse events for drawing.
    @Published var drawingMode: Bool = false

    /// The tool that was active before text mode — restored when the user
    /// presses Esc to exit text editing.
    var lastNonTextTool: Tool = .selection
}

struct ShortcutInfo {
    let key: String
    let tool: Tool
}

enum Shortcuts {
    static let all: [ShortcutInfo] = [
        ShortcutInfo(key: "v", tool: .selection),
        ShortcutInfo(key: "h", tool: .hand),
        ShortcutInfo(key: "r", tool: .rectangle),
        ShortcutInfo(key: "y", tool: .diamond),
        ShortcutInfo(key: "o", tool: .ellipse),
        ShortcutInfo(key: "a", tool: .arrow),
        ShortcutInfo(key: "l", tool: .line),
        ShortcutInfo(key: "d", tool: .freedraw),
        ShortcutInfo(key: "t", tool: .text),
        ShortcutInfo(key: "i", tool: .image),
        ShortcutInfo(key: "e", tool: .eraser),
        ShortcutInfo(key: "f", tool: .frame),
        ShortcutInfo(key: "g", tool: .autoshape),
        ShortcutInfo(key: "s", tool: .lasso),
        ShortcutInfo(key: "z", tool: .laser),
        ShortcutInfo(key: "b", tool: .bucketFill),
    ]

    static func tool(for key: String) -> Tool? {
        all.first { $0.key == key }?.tool
    }

    static func key(for tool: Tool) -> String? {
        all.first { $0.tool == tool }?.key
    }
}
