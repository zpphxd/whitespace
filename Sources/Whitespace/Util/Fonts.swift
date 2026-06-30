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
}
