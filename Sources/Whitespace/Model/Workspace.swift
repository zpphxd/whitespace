import Foundation

/// One named whiteboard (a tab).
struct BoardDoc: Codable, Identifiable {
    var id: String
    var name: String
    var elements: [Element]

    init(id: String = UUID().uuidString, name: String, elements: [Element] = []) {
        self.id = id; self.name = name; self.elements = elements
    }
}

/// Persisted set of boards (tabs) + which one is active. Stored as a single
/// JSON file alongside the legacy single-document autosave.
struct WorkspaceData: Codable {
    var boards: [BoardDoc]
    var current: Int
}

enum Workspace {
    static var url: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Whitespace", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("workspace.json")
    }

    /// Directory for generated/imported images (QR codes, drops), under the app support folder.
    static var imagesDir: URL {
        let dir = url.deletingLastPathComponent().appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Load boards, migrating the legacy single document if no workspace exists.
    static func load() -> WorkspaceData {
        if let data = try? Data(contentsOf: url),
           let ws = try? JSONDecoder().decode(WorkspaceData.self, from: data),
           !ws.boards.isEmpty {
            return WorkspaceData(boards: ws.boards, current: min(max(ws.current, 0), ws.boards.count - 1))
        }
        // Migrate legacy desktop.excalidraw into the first board.
        let legacy = DocumentStore.load(from: DocumentStore.defaultURL)
        return WorkspaceData(boards: [BoardDoc(name: "Board 1", elements: legacy)], current: 0)
    }

    static func save(_ ws: WorkspaceData) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(ws) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
