import CoreGraphics

/// The eight resize handles around a selection's bounding box.
enum Handle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var movesLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesRight: Bool { self == .topRight || self == .right || self == .bottomRight }
    var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }
    var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }

    /// Center of this handle within a view-space rect.
    func point(in r: CGRect) -> CGPoint {
        let xs: CGFloat = movesLeft ? r.minX : (movesRight ? r.maxX : r.midX)
        let ys: CGFloat = movesTop ? r.minY : (movesBottom ? r.maxY : r.midY)
        return CGPoint(x: xs, y: ys)
    }
}

extension CanvasView {
    func handleRect(_ h: Handle, in r: CGRect) -> CGRect {
        let c = h.point(in: r)
        let s: CGFloat = 8
        return CGRect(x: c.x - s / 2, y: c.y - s / 2, width: s, height: s)
    }
}
