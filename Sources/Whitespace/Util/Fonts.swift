import AppKit

/// Hand-drawn text font. Excalidraw ships only subsetted `.woff2` (which Core
/// Text can't load), so we fall back to a macOS hand-style face. Drop an
/// `Excalifont.ttf` into Resources and register it here to match exactly.
enum Fonts {
    private static let candidates = ["Bradley Hand", "Chalkboard SE", "Noteworthy"]

    static func handDrawn(size: CGFloat) -> NSFont {
        for name in candidates {
            if let font = NSFont(name: name, size: size) { return font }
        }
        return NSFont.systemFont(ofSize: size)
    }

    /// A selectable font, shown by name in its own typeface in the picker.
    struct Option: Identifiable {
        let id: Int
        let name: String
        let psName: String  // PostScript/family name to load
    }

    /// Curated fonts that ship with macOS (so they always render).
    static let options: [Option] = [
        .init(id: 1, name: "Hand-drawn", psName: "Bradley Hand"),
        .init(id: 9, name: "Chalkboard", psName: "Chalkboard SE"),
        .init(id: 7, name: "Noteworthy", psName: "Noteworthy"),
        .init(id: 6, name: "Marker Felt", psName: "Marker Felt"),
        .init(id: 2, name: "Helvetica", psName: "Helvetica Neue"),
        .init(id: 10, name: "Avenir Next", psName: "Avenir Next"),
        .init(id: 11, name: "Georgia", psName: "Georgia"),
        .init(id: 5, name: "Futura", psName: "Futura"),
        .init(id: 8, name: "Snell Roundhand", psName: "SnellRoundhand"),
        .init(id: 3, name: "Menlo (code)", psName: "Menlo"),
    ]

    static func option(_ id: Int) -> Option { options.first { $0.id == id } ?? options[0] }

    static func font(family: Int, size: CGFloat) -> NSFont {
        NSFont(name: option(family).psName, size: size) ?? handDrawn(size: size)
    }

    /// SVG font-family stack for export.
    static func cssFamily(_ family: Int) -> String { "\(option(family).psName), sans-serif" }
}
