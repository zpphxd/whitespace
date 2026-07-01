import CoreGraphics

/// Geometry for arrows that link shapes: where an arrow should touch a bound
/// shape's edge, and orthogonal ("elbow"/checker) routing between two points.
/// Named `ArrowBinding` (not `Binding`) to avoid colliding with SwiftUI.Binding.
enum ArrowBinding {
    /// Point on `element`'s edge along the ray from its center toward `target`,
    /// pushed out by `gap` so the arrow doesn't overlap the shape.
    static func edgePoint(of element: Element, toward target: CGPoint, gap: CGFloat = 6) -> CGPoint {
        let r = element.boundingRect
        let c = CGPoint(x: r.midX, y: r.midY)
        let dx = target.x - c.x, dy = target.y - c.y
        if dx == 0 && dy == 0 { return c }
        let hw = r.width / 2 + gap, hh = r.height / 2 + gap
        let scale = 1 / max(abs(dx) / max(hw, 0.001), abs(dy) / max(hh, 0.001))
        return CGPoint(x: c.x + dx * scale, y: c.y + dy * scale)
    }

    /// Normalized [u,v] location of `absPoint` within `shape`'s (unrotated) box,
    /// clamped to [0,1]. This is the "fixedPoint" the arrow welds to.
    static func fixedPoint(of shape: Element, at absPoint: CGPoint) -> [Double] {
        let r = shape.rect
        var p = absPoint
        if abs(shape.angle) > 0.0001 {   // map the drop into the shape's local frame
            let c = CGPoint(x: r.midX, y: r.midY)
            let s = sin(-CGFloat(shape.angle)), co = cos(-CGFloat(shape.angle))
            let dx = p.x - c.x, dy = p.y - c.y
            p = CGPoint(x: c.x + dx * co - dy * s, y: c.y + dx * s + dy * co)
        }
        let u = r.width  > 0 ? (p.x - r.minX) / r.width  : 0.5
        let v = r.height > 0 ? (p.y - r.minY) / r.height : 0.5
        return [Double(min(max(u, 0), 1)), Double(min(max(v, 0), 1))]
    }

    /// Absolute point for a stored `fixedPoint`, pushed out from the shape center
    /// by `gap` so the arrowhead clears the shape. Honors the shape's rotation.
    static func anchorPoint(of shape: Element, fixed: [Double], gap: CGFloat = 6) -> CGPoint {
        let r = shape.rect
        let u = CGFloat(fixed.first ?? 0.5), v = CGFloat(fixed.count > 1 ? fixed[1] : 0.5)
        let c = CGPoint(x: r.midX, y: r.midY)
        var anchor = CGPoint(x: r.minX + u * r.width, y: r.minY + v * r.height)
        if abs(shape.angle) > 0.0001 {
            let s = sin(CGFloat(shape.angle)), co = cos(CGFloat(shape.angle))
            let dx = anchor.x - c.x, dy = anchor.y - c.y
            anchor = CGPoint(x: c.x + dx * co - dy * s, y: c.y + dx * s + dy * co)
        }
        let dx = anchor.x - c.x, dy = anchor.y - c.y
        let len = hypot(dx, dy)
        guard len > 0.001 else { return anchor }   // dead-center: no meaningful gap
        return CGPoint(x: anchor.x + dx / len * gap, y: anchor.y + dy / len * gap)
    }

    /// Right-angle route between two points (horizontal-first or vertical-first
    /// depending on the dominant axis), via a midpoint dogleg.
    static func elbowRoute(_ a: CGPoint, _ b: CGPoint) -> [CGPoint] {
        if abs(b.x - a.x) >= abs(b.y - a.y) {
            let mx = (a.x + b.x) / 2
            return [a, CGPoint(x: mx, y: a.y), CGPoint(x: mx, y: b.y), b]
        } else {
            let my = (a.y + b.y) / 2
            return [a, CGPoint(x: a.x, y: my), CGPoint(x: b.x, y: my), b]
        }
    }
}
