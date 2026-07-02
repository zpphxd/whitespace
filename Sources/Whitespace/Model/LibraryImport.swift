import Foundation
import CoreGraphics

/// Imports Excalidraw library files (`.excalidrawlib`, v1 or v2) — and whole
/// `.excalidraw` drawings — into the personal library as reusable stencils.
/// Embedded image files are materialized to disk so image-based packs render.
enum LibraryImport {
    private struct Lib: Decodable {
        var libraryItems: [Item]?     // v2
        var library: [[Element]]?     // v1 (array of element groups)
        var elements: [Element]?      // a plain .excalidraw drawing
        var files: [String: FileEntry]?
        struct Item: Decodable {
            var name: String?
            var elements: [Element]
            var files: [String: FileEntry]?
        }
        struct FileEntry: Decodable { var dataURL: String?; var mimeType: String? }
    }

    /// Parse a library/drawing file into normalized custom stencils.
    static func stencils(from url: URL) -> [CustomStencil] {
        guard let data = try? Data(contentsOf: url),
              let lib = try? JSONDecoder().decode(Lib.self, from: data) else { return [] }

        var groups: [(name: String?, elements: [Element], files: [String: Lib.FileEntry])] = []
        if let items = lib.libraryItems {
            for it in items { groups.append((it.name, it.elements, it.files ?? [:])) }
        } else if let v1 = lib.library {
            for els in v1 { groups.append((nil, els, [:])) }
        } else if let els = lib.elements {   // a whole drawing → one stencil
            groups.append((url.deletingPathExtension().lastPathComponent, els, [:]))
        }
        guard !groups.isEmpty else { return [] }

        let base = url.deletingPathExtension().lastPathComponent
        var out: [CustomStencil] = []
        for (i, g) in groups.enumerated() {
            var files = lib.files ?? [:]
            for (k, v) in g.files { files[k] = v }
            let els = materializeImages(g.elements, files: files).filter { !$0.isDeleted }
            let name = g.name ?? derivedName(els) ?? "\(base) \(i + 1)"
            if let s = makeStencil(name: name, from: els) { out.append(s) }
        }
        return out
    }

    /// A stencil's name when the library item didn't provide one: its first text.
    private static func derivedName(_ els: [Element]) -> String? {
        els.first { $0.type == "text" && !($0.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .text?.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n").first.map(String.init)
    }

    /// Center the group's bounding box on the origin (matches bundled stencils).
    private static func makeStencil(name: String, from elements: [Element]) -> CustomStencil? {
        guard let first = elements.first else { return nil }
        let box = elements.dropFirst().reduce(first.boundingRect) { $0.union($1.boundingRect) }
        let cx = box.midX, cy = box.midY
        let norm = elements.map { e -> Element in var c = e; c.x -= cx; c.y -= cy; return c }
        return CustomStencil(id: UUID().uuidString, name: name, elements: norm)
    }

    /// Write each referenced image's dataURL to disk and point its element's
    /// `link` at the file (Whitespace renders images from `link`, not `fileId`).
    private static func materializeImages(_ elements: [Element], files: [String: Lib.FileEntry]) -> [Element] {
        guard elements.contains(where: { $0.type == "image" }), !files.isEmpty else { return elements }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Whitespace/library-assets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var cache: [String: String] = [:]
        func path(for fileId: String) -> String? {
            if let p = cache[fileId] { return p }
            guard let dataURL = files[fileId]?.dataURL,
                  let comma = dataURL.firstIndex(of: ","),
                  let bytes = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])) else { return nil }
            let ext = dataURL.contains("image/png") ? "png"
                    : dataURL.contains("image/jpeg") ? "jpg"
                    : dataURL.contains("svg") ? "svg" : "png"
            let safe = fileId.replacingOccurrences(of: "/", with: "_")
            let file = dir.appendingPathComponent("\(safe).\(ext)")
            if !FileManager.default.fileExists(atPath: file.path) { try? bytes.write(to: file) }
            cache[fileId] = file.path
            return file.path
        }
        return elements.map { e in
            guard e.type == "image", let fid = e.fileId, let p = path(for: fid) else { return e }
            var c = e; c.link = p; return c
        }
    }
}
