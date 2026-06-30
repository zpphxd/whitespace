import Foundation

/// The `.excalidraw` file envelope. Unknown keys (extra appState fields, image
/// `files`) are ignored on decode and omitted on encode — fine for V1 vector
/// content and keeps round-trips clean.
struct ExcalidrawFile: Codable {
    var type: String = "excalidraw"
    var version: Int = 2
    var source: String = "whitespace"
    var elements: [Element]
    var appState: AppStateData = .init()

    struct AppStateData: Codable {
        var viewBackgroundColor: String? = "#ffffff"
        var gridSize: Int? = 20
    }

    enum CodingKeys: String, CodingKey {
        case type, version, source, elements, appState
    }

    init(elements: [Element]) {
        self.elements = elements
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decode(String.self, forKey: .type)) ?? "excalidraw"
        version = (try? c.decode(Int.self, forKey: .version)) ?? 2
        source = (try? c.decode(String.self, forKey: .source)) ?? "unknown"
        elements = (try? c.decode([Element].self, forKey: .elements)) ?? []
        appState = (try? c.decode(AppStateData.self, forKey: .appState)) ?? .init()
    }
}

enum DocumentStore {
    static var defaultURL: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Whitespace", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("desktop.excalidraw")
    }

    static func load(from url: URL) -> [Element] {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ExcalidrawFile.self, from: data)
        else { return [] }
        return file.elements.filter { !$0.isDeleted }
    }

    static func save(_ elements: [Element], to url: URL) {
        let file = ExcalidrawFile(elements: elements)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(file) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
