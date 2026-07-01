import CoreGraphics
import Foundation

/// Round-trips the canvas's code cells with the Jupyter `.ipynb` format. Export
/// flattens cells (reading order) into a notebook; import lays a notebook's code
/// cells out vertically on the canvas.
enum Notebook {

    // MARK: Export (spatial → linear)

    static func exportIPYNB(_ elements: [Element]) -> Data? {
        let cells = elements.filter { $0.type == "cell" && !$0.isDeleted }
            .sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        guard !cells.isEmpty else { return nil }

        let nbCells: [[String: Any]] = cells.map { c in
            var outputs: [[String: Any]] = []
            if c.cellOutputType == "image/png", let d = c.cellOutputData {
                outputs.append(["output_type": "display_data", "data": ["image/png": d], "metadata": [:]])
            } else if let out = c.cellOutput, !out.isEmpty, out != "(no output)" {
                outputs.append(["output_type": "stream", "name": "stdout", "text": out])
            }
            return [
                "cell_type": "code",
                "source": c.text ?? "",
                "outputs": outputs,
                "execution_count": c.cellExecCount.map { $0 as Any } ?? NSNull(),
                "metadata": ["whitespace": ["language": c.cellLanguage ?? "shell", "kind": c.cellKind ?? "code"]],
            ]
        }
        let nb: [String: Any] = [
            "cells": nbCells,
            "metadata": [
                "kernelspec": ["name": "python3", "display_name": "Python 3"],
                "language_info": ["name": "python"],
            ],
            "nbformat": 4, "nbformat_minor": 5,
        ]
        return try? JSONSerialization.data(withJSONObject: nb, options: [.prettyPrinted])
    }

    // MARK: Import (linear → spatial)

    static func importIPYNB(_ data: Data, at origin: CGPoint) -> [Element] {
        guard let nb = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cells = nb["cells"] as? [[String: Any]] else { return [] }
        var elements: [Element] = []
        var y = Double(origin.y)
        for c in cells where (c["cell_type"] as? String) == "code" {
            let source = joinText(c["source"])
            var e = Element(type: "cell", x: Double(origin.x), y: y, width: 460, height: 200,
                            backgroundColor: "transparent")
            let meta = (c["metadata"] as? [String: Any])?["whitespace"] as? [String: Any]
            e.cellLanguage = meta?["language"] as? String ?? "python"
            e.cellKind = meta?["kind"] as? String
            e.text = source
            e.cellExecCount = c["execution_count"] as? Int

            var text = ""
            for o in (c["outputs"] as? [[String: Any]]) ?? [] {
                switch o["output_type"] as? String {
                case "stream":
                    text += joinText(o["text"])
                case "display_data", "execute_result":
                    if let d = o["data"] as? [String: Any] {
                        if let img = d["image/png"] as? String {
                            e.cellOutputType = "image/png"; e.cellOutputData = img
                        } else if d["text/plain"] != nil {
                            text += joinText(d["text/plain"])
                        }
                    }
                case "error":
                    text += (o["traceback"] as? [String])?.joined(separator: "\n") ?? ""
                    e.cellFailed = true
                default: break
                }
            }
            if !text.isEmpty { e.cellOutput = text }
            elements.append(e)
            y += 220
        }
        return elements
    }

    /// nbformat's `source`/`text` may be a String or an array of line-Strings.
    private static func joinText(_ any: Any?) -> String {
        if let s = any as? String { return s }
        if let arr = any as? [String] { return arr.joined() }
        return ""
    }
}
