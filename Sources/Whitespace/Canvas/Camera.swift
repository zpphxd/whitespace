import CoreGraphics

/// Maps between scene space (Excalidraw coordinates, y-down) and view space.
/// `offset` is the scene point shown at the view's top-left; `zoom` is scale.
struct Camera {
    var offset: CGPoint = .zero
    var zoom: CGFloat = 1

    static let minZoom: CGFloat = 0.1
    static let maxZoom: CGFloat = 30

    func sceneToView(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - offset.x) * zoom, y: (p.y - offset.y) * zoom)
    }

    func viewToScene(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x / zoom + offset.x, y: p.y / zoom + offset.y)
    }

    /// Zoom while keeping the scene point under `anchor` (view space) fixed.
    mutating func zoom(by factor: CGFloat, around anchor: CGPoint) {
        let scenePt = viewToScene(anchor)
        zoom = max(Self.minZoom, min(Self.maxZoom, zoom * factor))
        offset = CGPoint(x: scenePt.x - anchor.x / zoom, y: scenePt.y - anchor.y / zoom)
    }

    mutating func pan(byViewDelta d: CGSize) {
        offset.x -= d.width / zoom
        offset.y -= d.height / zoom
    }
}
