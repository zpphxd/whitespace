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
