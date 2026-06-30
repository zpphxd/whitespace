import AppKit
import CoreGraphics

/// Draws a `RoughDrawable` into a Core Graphics context: paint the fill first
/// (solid region or sketchy hachure strokes), then the outline on top.
enum RoughRenderer {
    static func draw(_ d: RoughDrawable, stroke: NSColor, fill: NSColor?,
                     opacity: CGFloat = 1, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setAlpha(opacity)

        if let fillPath = d.fill, let fillColor = fill {
            ctx.addPath(fillPath)
            if d.fillIsSolid {
                ctx.setFillColor(fillColor.cgColor)
                ctx.fillPath()
            } else {
                ctx.setStrokeColor(fillColor.cgColor)
                ctx.setLineWidth(d.fillWeight)
                ctx.setLineCap(.round)
                ctx.strokePath()
            }
        }

        ctx.addPath(d.outline)
        ctx.setStrokeColor(stroke.cgColor)
        ctx.setLineWidth(d.strokeWidth)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.strokePath()

        ctx.restoreGState()
    }
}
