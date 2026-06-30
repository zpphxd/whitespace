import Foundation

enum Tool: String, CaseIterable {
    case hand, select, rectangle, ellipse, diamond, arrow, line, freedraw, text, eraser

    var creates: Bool { self != .select && self != .hand && self != .eraser }

    /// Keyboard shortcut (Excalidraw-style single keys).
    var key: Character {
        switch self {
        case .hand: return "h"
        case .select: return "v"
        case .rectangle: return "r"
        case .ellipse: return "o"
        case .diamond: return "d"
        case .arrow: return "a"
        case .line: return "l"
        case .freedraw: return "p"
        case .text: return "t"
        case .eraser: return "e"
        }
    }

    var symbol: String {
        switch self {
        case .hand: return "hand.raised"
        case .select: return "cursorarrow"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .diamond: return "diamond"
        case .arrow: return "arrow.right"
        case .line: return "line.diagonal"
        case .freedraw: return "pencil"
        case .text: return "textformat"
        case .eraser: return "eraser"
        }
    }
}

/// The active drawing style applied to newly created elements (the inspector
/// edits this and the current selection).
struct CurrentStyle {
    var strokeColor = "#1e1e1e"
    var backgroundColor = "transparent"
    var fillStyle: FillStyle = .hachure
    var strokeWidth: Double = 2
    var strokeStyle: StrokeStyle = .solid
    var roughness: Double = 1
    var opacity: Double = 100
    var fontSize: Double = 20
    var fontFamily: Int = 1             // 1 hand-drawn, 2 normal, 3 code, 5 fancy
    var rounded: Bool = true            // edges: rounded vs sharp
    var elbowArrow: Bool = false        // arrow type: elbow vs straight
    var startArrowhead: String = "none"
    var endArrowhead: String = "arrow"
}
