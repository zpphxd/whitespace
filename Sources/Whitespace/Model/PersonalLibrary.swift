import Foundation

/// A user-created reusable stencil: a named group of elements captured from the
/// canvas. Elements are stored normalized (bounding box centered on the origin),
/// exactly like the bundled `StencilComponent`s, so `dropComponent` can place a
/// fresh, centered copy.
struct CustomStencil: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    let elements: [Element]
}

/// Loads and saves the user's personal stencil library to Application Support,
/// alongside the board document.
enum PersonalLibraryStore {
    static var url: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Whitespace", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }

    static func load() -> [CustomStencil] {
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([CustomStencil].self, from: data)
        else { return [] }
        return items
    }

    static func save(_ items: [CustomStencil]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
