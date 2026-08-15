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
    /// True when this stroke renders with variable width — velocity-driven
    /// calligraphic swell and taper — instead of uniform thickness.
    var dynamicWidth: Bool = false
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
    @Published var fillOpacity: CGFloat = 0.3
    @Published var strokeWidth: CGFloat = 3
    @Published var fontFamily: String = "Virgil"
    @Published var fontSize: CGFloat = 28
    @Published var canvasBackground: CanvasBackground = .clear

    // Stroke appearance — new shapes pick these up, selected shapes update live.
    // Pressure mode drives line dynamics; rectangles keep slightly curved corners.
    @Published var pressureMode: PressureMode = .dynamic
    @Published var cornerRadius: CGFloat = 10
    @Published var cornerRadiusY: CGFloat = 10

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
