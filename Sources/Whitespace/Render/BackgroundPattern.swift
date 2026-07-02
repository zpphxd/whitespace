import AppKit
import CoreGraphics

/// Whiteboard dot/grid backdrop, drawn in scene units so it pans and zooms with
/// the canvas. Shared by `CanvasView` (live) and the dev-harness renderer.
enum BackgroundPattern {
    static let spacing: CGFloat = 24

    /// Draw `pattern` ("dots" | "grid" | anything else = nothing) across `bounds`
    /// (view space) under `camera`.
    static func draw(_ pattern: String, bounds: CGRect, camera: Camera, in ctx: CGContext) {
        guard pattern == "dots" || pattern == "grid" else { return }
        let step = spacing * camera.zoom
        guard step >= 8 else { return }   // too dense when zoomed way out

        let topLeft = camera.viewToScene(CGPoint(x: bounds.minX, y: bounds.minY))
        let botRight = camera.viewToScene(CGPoint(x: bounds.maxX, y: bounds.maxY))
        let startX = (topLeft.x / spacing).rounded(.down) * spacing
        let startY = (topLeft.y / spacing).rounded(.down) * spacing

        // A blue-gray line/dot that reads on a white board and still shows over a
        // busy wallpaper (the board can be translucent), with a faint white
        // under-layer so it doesn't vanish on dark backgrounds.
        let ink = NSColor(hex: 0x5b6472)
        ctx.saveGState()
        if pattern == "grid" {
            let path = CGMutablePath()
            var sx = startX
            while sx <= botRight.x {
                let vx = camera.sceneToView(CGPoint(x: sx, y: 0)).x
                path.move(to: CGPoint(x: vx, y: bounds.minY)); path.addLine(to: CGPoint(x: vx, y: bounds.maxY))
                sx += spacing
            }
            var sy = startY
            while sy <= botRight.y {
                let vy = camera.sceneToView(CGPoint(x: 0, y: sy)).y
                path.move(to: CGPoint(x: bounds.minX, y: vy)); path.addLine(to: CGPoint(x: bounds.maxX, y: vy))
                sy += spacing
            }
            ctx.setLineWidth(2)
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
            ctx.addPath(path); ctx.strokePath()          // soft halo
            ctx.setLineWidth(1)
            ctx.setStrokeColor(ink.withAlphaComponent(0.30).cgColor)
            ctx.addPath(path); ctx.strokePath()
        } else {   // dots
            let r = min(2.6, max(1.3, camera.zoom * 1.4))
            var sy = startY
            while sy <= botRight.y {
                let vy = camera.sceneToView(CGPoint(x: 0, y: sy)).y
                var sx = startX
                while sx <= botRight.x {
                    let vx = camera.sceneToView(CGPoint(x: sx, y: 0)).x
                    ctx.setFillColor(NSColor.white.withAlphaComponent(0.4).cgColor)
                    ctx.fillEllipse(in: CGRect(x: vx - r - 0.5, y: vy - r - 0.5, width: r * 2 + 1, height: r * 2 + 1))
                    ctx.setFillColor(ink.withAlphaComponent(0.5).cgColor)
                    ctx.fillEllipse(in: CGRect(x: vx - r, y: vy - r, width: r * 2, height: r * 2))
                    sx += spacing
                }
                sy += spacing
            }
        }
        ctx.restoreGState()
    }
}
