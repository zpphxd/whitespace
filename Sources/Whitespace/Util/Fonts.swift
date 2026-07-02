import AppKit

/// Hand-drawn text font. The real Excalifont (OFL, converted from Excalidraw's
/// woff2) ships in Resources and is registered at launch, so text metrics match
/// Excalidraw exactly; macOS hand-style faces remain as fallbacks.
enum Fonts {
    private static let candidates = ["Excalifont", "Bradley Hand", "Chalkboard SE", "Noteworthy"]

    /// Register the bundled Excalifont with Core Text (process scope). Looks in
    /// the app bundle first, then repo-relative paths so dev-harness CLI runs
    /// (`--render-stencils` etc.) get the same metrics.
    static func registerBundled() {
        guard NSFont(name: "Excalifont", size: 12) == nil else { return }   // already available
        var urls: [URL] = []
        if let u = Bundle.main.url(forResource: "Excalifont", withExtension: "ttf") { urls.append(u) }
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        urls.append(exe.appendingPathComponent("../../Resources/Excalifont.ttf").standardizedFileURL)
        urls.append(URL(fileURLWithPath: "Resources/Excalifont.ttf"))
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) { return }
        }
    }

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
        .init(id: 1, name: "Hand-drawn", psName: "Excalifont"),
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
