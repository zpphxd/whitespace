import AppKit
import CoreGraphics
import Foundation

/// Paste-to-table: render a parsed grid of cells as a native hand-drawn table —
/// one rectangle per cell (header row lightly filled) plus a text label, all
/// grouped so it moves and resizes as a unit. Complements `ChartMaker`.
enum TableMaker {
    private static let rowH = 34.0
    private static let pad = 12.0
    private static let fontSize = 16.0

    /// Build a table centered on `center` (scene coordinates) from a cell grid.
    static func elements(_ cells: [[String]], center: CGPoint) -> [Element] {
        guard !cells.isEmpty else { return [] }
        let cols = cells.map(\.count).max() ?? 0
        guard cols > 0 else { return [] }

        let font = Fonts.font(family: 1, size: CGFloat(fontSize))
        var colW = [Double](repeating: 48, count: cols)
        for row in cells {
            for (j, c) in row.enumerated() where j < cols {
                let w = Double((c as NSString).size(withAttributes: [.font: font]).width) + pad * 2
                colW[j] = max(colW[j], w)
            }
        }

        let totalW = colW.reduce(0, +)
        let totalH = Double(cells.count) * rowH
        let x0 = center.x - totalW / 2, y0 = center.y - totalH / 2
        let now = Date().timeIntervalSince1970 * 1000
        let gid = UUID().uuidString
        var out: [Element] = []

        var y = y0
        for (i, row) in cells.enumerated() {
            var x = x0
            for j in 0..<cols {
                let w = colW[j]
                // Cell box — header row gets a light fill; crisper (low-roughness)
                // strokes read as a table rather than a sketch.
                let cell = Element(
                    type: "rectangle", x: x, y: y, width: w, height: rowH,
                    strokeColor: "#1e1e1e",
                    backgroundColor: i == 0 ? "#e9ecef" : "transparent",
                    fillStyle: .solid, strokeWidth: 1, roughness: 0.5,
                    seed: Int.random(in: 1...2_000_000_000),
                    groupIds: [gid], updated: now)
                out.append(cell)

                let text = j < row.count ? row[j] : ""
                if !text.isEmpty {
                    let label = Element(
                        type: "text", x: x + pad, y: y + (rowH - 20) / 2,
                        width: w - pad * 2, height: 20,
                        strokeColor: "#1e1e1e",
                        seed: Int.random(in: 1...2_000_000_000),
                        groupIds: [gid], updated: now,
                        text: text, fontSize: fontSize, fontFamily: 1,
                        textAlign: "left", verticalAlign: "middle")
                    out.append(label)
                }
                x += w
            }
            y += rowH
        }
        return out
    }
}
