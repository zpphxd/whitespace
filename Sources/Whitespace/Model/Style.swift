import Foundation

/// Excalidraw fill patterns.
enum FillStyle: String, Codable, CaseIterable {
    case hachure
    case crossHatch = "cross-hatch"
    case solid
    case zigzag
}

/// Excalidraw stroke patterns.
enum StrokeStyle: String, Codable, CaseIterable {
    case solid
    case dashed
    case dotted
}

/// Roughness presets (Excalidraw: 0 architect, 1 artist, 2 cartoonist).
enum Roughness {
    static let architect = 0.0
    static let artist = 1.0
    static let cartoonist = 2.0
}
