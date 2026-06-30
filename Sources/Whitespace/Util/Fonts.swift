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

    /// Excalidraw-style font families: 1 hand-drawn, 2 normal, 3 code, 5 fancy.
    static func font(family: Int, size: CGFloat) -> NSFont {
        switch family {
        case 2: // Normal
            return NSFont(name: "Nunito", size: size)
                ?? NSFont(name: "Helvetica Neue", size: size)
                ?? NSFont.systemFont(ofSize: size)
        case 3: // Code / mono
            return NSFont(name: "Comic Shanns Mono", size: size)
                ?? NSFont(name: "Cascadia Code", size: size)
                ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case 5: // Fancy / display
            return NSFont(name: "Lilita One", size: size)
                ?? NSFont(name: "Futura", size: size)
                ?? NSFont.systemFont(ofSize: size, weight: .black)
        default: // 1 Hand-drawn
            return handDrawn(size: size)
        }
    }

    /// SVG font-family stack for export.
    static func cssFamily(_ family: Int) -> String {
        switch family {
        case 2: return "Nunito, Helvetica, sans-serif"
        case 3: return "Comic Shanns Mono, Cascadia Code, monospace"
        case 5: return "Lilita One, Futura, sans-serif"
        default: return "Bradley Hand, Chalkboard SE, cursive"
        }
    }
}
