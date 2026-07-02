import CoreGraphics
import Foundation

/// Paste-to-chart: parse tabular clipboard text (TSV/CSV) into a spreadsheet,
/// then generate a bar or line chart as native grouped elements — a port of
/// Excalidraw's `tryParseSpreadsheet` + `renderSpreadsheet`.
enum ChartMaker {

    struct Spreadsheet {
        var title: String?
        var labels: [String]?
        var values: [Double]
    }

    // MARK: Parsing

    /// A number with optional currency symbol, percent, and thousands commas.
    static func parseNumber(_ s: String) -> Double? {
        var t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        for c in ["$", "€", "£", "¥", "₩", "%", ","] { t = t.replacingOccurrences(of: c, with: "") }
        return Double(t)
    }

    /// Split tabular text into a rectangular grid of trimmed cells, choosing the
    /// delimiter (tab > comma > semicolon) that yields the widest consistent rows.
    /// Nil if it isn't at least a 2-row table.
    static func cells(_ text: String) -> [[String]]? {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
                             .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2 else { return nil }

        var best: [[String]]?
        var bestCols = 1
        for d in ["\t", ",", ";"] {
            let grid = lines.map { line in
                line.components(separatedBy: d).map { $0.trimmingCharacters(in: .whitespaces) }
            }
            let cols = grid[0].count
            if cols > bestCols && grid.allSatisfy({ $0.count == cols }) {
                best = grid; bestCols = cols
            }
        }
        return best ?? lines.map { [$0.trimmingCharacters(in: .whitespaces)] }
    }

    /// Parse clipboard text into a spreadsheet, or nil if it isn't tabular data.
    static func parse(_ text: String) -> Spreadsheet? {
        guard let grid = cells(text) else { return nil }
        return parseCells(grid)
    }

    private static func parseCells(_ cells: [[String]]) -> Spreadsheet? {
        let numCols = cells[0].count

        if numCols == 1 {
            let hasHeader = parseNumber(cells[0][0]) == nil
            let rows = hasHeader ? Array(cells.dropFirst()) : cells
            let values = rows.compactMap { parseNumber($0[0]) }
            guard values.count == rows.count, values.count >= 2 else { return nil }
            return Spreadsheet(title: hasHeader ? cells[0][0] : nil, labels: nil, values: values)
        }

        // ≥2 columns: a header row is one where no cell is a number.
        let hasHeader = cells[0].allSatisfy { parseNumber($0) == nil }
        let rows = hasHeader ? Array(cells.dropFirst()) : cells
        guard rows.count >= 2 else { return nil }

        // Value column: prefer column 1, else the first all-numeric column.
        let order = [1] + (0..<numCols).filter { $0 != 1 }
        guard let valueCol = order.first(where: { idx in
            idx < numCols && rows.allSatisfy { idx < $0.count && parseNumber($0[idx]) != nil }
        }) else { return nil }

        let labelCol = valueCol == 0 ? 1 : 0
        let values = rows.map { parseNumber($0[valueCol]) ?? 0 }
        let labels = labelCol < numCols && labelCol != valueCol ? rows.map { $0[labelCol] } : nil
        return Spreadsheet(title: hasHeader ? cells[0][valueCol] : nil, labels: labels, values: values)
    }

    // MARK: Generation

    private static let barWidth = 32.0
    private static let barGap = 12.0
    private static let barHeight = 256.0
    private static let gridOpacity = 50.0
    private static let pastels = ["#a5d8ff", "#b2f2bb", "#ffc9c9", "#ffec99", "#d0bfff", "#99e9f2"]

    // The chart types offered in the paste wheel (order = wheel order).
    static let types = ["bar", "line", "hbar", "step", "scatter", "lollipop"]

    /// Build the chosen chart type centered on `center` (scene coordinates).
    static func elements(_ s: Spreadsheet, type: String, center: CGPoint) -> [Element] {
        guard !s.values.isEmpty else { return [] }
        return type == "hbar" ? horizontalBar(s, center: center)
                              : cartesian(s, type: type, center: center)
    }

    // MARK: Element factories

    private static func mkLine(_ x: Double, _ y: Double, _ pts: [[Double]], gid: String, color: String,
                               dotted: Bool = false, opacity: Double = 100, width: Double = 1) -> Element {
        Element(type: "line", x: x, y: y, backgroundColor: color, strokeWidth: width,
                strokeStyle: dotted ? .dotted : .solid, opacity: opacity, groupIds: [gid],
                points: pts, startArrowhead: nil, endArrowhead: nil)
    }
    private static func mkRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double,
                               gid: String, color: String) -> Element {
        Element(type: "rectangle", x: x, y: y, width: w, height: h, backgroundColor: color,
                fillStyle: .hachure, strokeWidth: 1, groupIds: [gid])
    }
    private static func mkDot(_ cx: Double, _ cy: Double, _ d: Double, gid: String, color: String) -> Element {
        var e = Element(type: "ellipse", x: cx - d / 2, y: cy - d / 2, width: d, height: d,
                        backgroundColor: color, fillStyle: .solid, strokeWidth: 2, groupIds: [gid])
        e.roundness = nil
        return e
    }
    private static func mkText(_ str: String, _ x: Double, _ y: Double, size: Double,
                               gid: String, color: String) -> Element {
        var t = Element(type: "text", x: x, y: y,
                        width: Double(str.count) * size * 0.75 + 16, height: size * 1.25,
                        backgroundColor: color, groupIds: [gid])
        t.text = str; t.fontSize = size; t.fontFamily = 1
        return t
    }

    // MARK: Vertical (bar / line / step / scatter / lollipop)

    private static func cartesian(_ s: Spreadsheet, type: String, center: CGPoint) -> [Element] {
        let n = s.values.count
        let chartWidth = (barWidth + barGap) * Double(n) + barGap
        let chartHeight = barHeight + barGap * 2
        let ox = Double(center.x) - chartWidth / 2
        let oy = Double(center.y) + chartHeight / 2   // x-axis
        let base = oy - barGap                        // marks sit a gap above the axis
        let maxV = Swift.max(s.values.max() ?? 1, 0.000001)
        let gid = UUID().uuidString
        let color = pastels.randomElement() ?? "#a5d8ff"

        func centerX(_ i: Int) -> Double { ox + Double(i) * (barWidth + barGap) + barGap + barWidth / 2 }
        func topY(_ v: Double) -> Double { base - (v / maxV) * barHeight }

        var els: [Element] = []

        switch type {
        case "line", "step":
            var pts: [[Double]] = []
            for (i, v) in s.values.enumerated() {
                let cx = Double(i) * (barWidth + barGap)
                if type == "step" && i > 0 {
                    pts.append([cx, -(s.values[i - 1] / maxV) * barHeight])   // horizontal tread
                }
                pts.append([cx, -(v / maxV) * barHeight])
            }
            els.append(mkLine(ox + barGap + barWidth / 2, base, pts, gid: gid, color: color, width: 2))
            for (i, v) in s.values.enumerated() { els.append(mkDot(centerX(i), topY(v), barGap, gid: gid, color: color)) }
        case "scatter":
            for (i, v) in s.values.enumerated() { els.append(mkDot(centerX(i), topY(v), barGap * 1.5, gid: gid, color: color)) }
        case "lollipop":
            for (i, v) in s.values.enumerated() {
                els.append(mkLine(centerX(i), base, [[0, 0], [0, -(v / maxV) * barHeight]], gid: gid, color: color, width: 2))
                els.append(mkDot(centerX(i), topY(v), barGap * 1.3, gid: gid, color: color))
            }
        default: // bar
            for (i, v) in s.values.enumerated() {
                let h = (v / maxV) * barHeight
                els.append(mkRect(ox + Double(i) * (barWidth + barGap) + barGap, base - h, barWidth, h, gid: gid, color: color))
            }
        }

        // Axes + dotted max gridline.
        els.append(mkLine(ox, oy, [[0, 0], [chartWidth, 0]], gid: gid, color: color))
        els.append(mkLine(ox, oy, [[0, 0], [0, -chartHeight]], gid: gid, color: color))
        els.append(mkLine(ox, oy - barHeight - barGap, [[0, 0], [chartWidth, 0]], gid: gid, color: color, dotted: true, opacity: gridOpacity))

        // Y labels.
        els.append(mkText("0", ox - barGap - 10, oy - 10, size: 16, gid: gid, color: color))
        els.append(mkText(format(maxV), ox - barGap - Double(format(maxV).count) * 9, oy - barHeight - barGap - 8, size: 16, gid: gid, color: color))
        // X labels.
        if let labels = s.labels {
            for (i, raw) in labels.enumerated() {
                let lbl = raw.count > 8 ? String(raw.prefix(5)) + "…" : raw
                els.append(mkText(lbl, centerX(i) - Double(lbl.count) * 12 * 0.3, oy + 6, size: 12, gid: gid, color: color))
            }
        }
        if let title = s.title, !title.isEmpty {
            els.append(mkText(title, ox + chartWidth / 2 - Double(title.count) * 20 * 0.3, oy - chartHeight - 24, size: 20, gid: gid, color: color))
        }
        return els
    }

    // MARK: Horizontal bar

    private static func horizontalBar(_ s: Spreadsheet, center: CGPoint) -> [Element] {
        let n = s.values.count
        let thick = barWidth
        let maxLen = barHeight
        let chartH = (thick + barGap) * Double(n) + barGap
        let chartW = maxLen + barGap * 2
        let ox = Double(center.x) - chartW / 2       // y-axis
        let top = Double(center.y) - chartH / 2
        let bottom = top + chartH                     // value axis
        let maxV = Swift.max(s.values.max() ?? 1, 0.000001)
        let gid = UUID().uuidString
        let color = pastels.randomElement() ?? "#a5d8ff"

        var els: [Element] = []
        for (i, v) in s.values.enumerated() {
            let len = (v / maxV) * maxLen
            let y = top + Double(i) * (thick + barGap) + barGap
            els.append(mkRect(ox, y, len, thick, gid: gid, color: color))
            if let labels = s.labels {
                let lbl = labels[i].count > 8 ? String(labels[i].prefix(5)) + "…" : labels[i]
                els.append(mkText(lbl, ox - 12 - Double(lbl.count) * 12 * 0.6, y + thick / 2 - 8, size: 12, gid: gid, color: color))
            }
        }
        els.append(mkLine(ox, top, [[0, 0], [0, chartH]], gid: gid, color: color))            // y-axis
        els.append(mkLine(ox, bottom, [[0, 0], [maxLen, 0]], gid: gid, color: color))         // value axis
        els.append(mkText("0", ox - 4, bottom + 4, size: 14, gid: gid, color: color))
        els.append(mkText(format(maxV), ox + maxLen - 10, bottom + 4, size: 14, gid: gid, color: color))
        if let title = s.title, !title.isEmpty {
            els.append(mkText(title, ox + chartW / 2 - Double(title.count) * 20 * 0.3, top - 28, size: 20, gid: gid, color: color))
        }
        return els
    }

    private static func format(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}
