import CoreGraphics
import Foundation

extension Element {
    var isLinear: Bool { type == "line" || type == "arrow" || type == "freedraw" }

    /// Icon prefix for a link node: 🔗 for URLs, 📁 for folders, 📄 for files.
    var linkDisplayIcon: String {
        guard let link = link else { return "📄 " }
        if link.contains("://") { return "🔗 " }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: (link as NSString).expandingTildeInPath, isDirectory: &isDir)
        return isDir.boolValue ? "📁 " : "📄 "
    }

    /// Normalized rect (positive size) for dimension-based elements.
    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height).standardized
    }

    /// Absolute points for linear/freedraw elements (points are relative to x,y).
    var absolutePoints: [CGPoint] {
        (points ?? []).map { CGPoint(x: x + ($0.first ?? 0), y: y + ($0.count > 1 ? $0[1] : 0)) }
    }

    /// Axis-aligned bounding box in scene coordinates.
    var boundingRect: CGRect {
        if isLinear {
            let pts = absolutePoints
            guard let first = pts.first else { return rect }
            var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
            for p in pts {
                minX = min(minX, p.x); minY = min(minY, p.y)
                maxX = max(maxX, p.x); maxY = max(maxY, p.y)
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
        return rect
    }

    /// Hit test in scene space, with tolerance for thin strokes/lines.
    func hitTest(_ rawPoint: CGPoint, tolerance: CGFloat = 8) -> Bool {
        // Map the point into the element's unrotated frame.
        let p: CGPoint
        if abs(angle) > 0.0001 {
            let bb = boundingRect
            let c = CGPoint(x: bb.midX, y: bb.midY)
            let s = sin(-angle), co = cos(-angle)
            let dx = rawPoint.x - c.x, dy = rawPoint.y - c.y
            p = CGPoint(x: c.x + dx * co - dy * s, y: c.y + dx * s + dy * co)
        } else {
            p = rawPoint
        }
        let box = boundingRect.insetBy(dx: -tolerance, dy: -tolerance)
        guard box.contains(p) else { return false }
        switch type {
        case "rectangle", "diamond", "text", "image":
            // Filled/box-like: bounding box hit is good enough.
            return true
        case "ellipse":
            let r = rect
            guard r.width > 0, r.height > 0 else { return true }
            let dx = (p.x - r.midX) / (r.width / 2 + tolerance)
            let dy = (p.y - r.midY) / (r.height / 2 + tolerance)
            return dx * dx + dy * dy <= 1
        default: // line, arrow, freedraw — distance to polyline
            let pts = absolutePoints
            guard pts.count > 1 else { return box.contains(p) }
            for i in 0..<(pts.count - 1) {
                if distance(from: p, toSegment: pts[i], pts[i + 1]) <= tolerance { return true }
            }
            return false
        }
    }

    private func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        if lenSq == 0 { return hypot(p.x - a.x, p.y - a.y) }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq
        t = max(0, min(1, t))
        let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(p.x - proj.x, p.y - proj.y)
    }
}
