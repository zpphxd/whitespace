import AppKit
import CoreGraphics

/// Draws a `RoughDrawable` into a Core Graphics context: paint the fill first
/// (solid region or sketchy hachure strokes), then the outline on top.
enum RoughRenderer {
    static func draw(_ d: RoughDrawable, stroke: NSColor, fill: NSColor?,
                     opacity: CGFloat = 1, strokeStyle: StrokeStyle = .solid,
                     in ctx: CGContext) {
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
        // Dash the outline per stroke style (fill stays solid).
        switch strokeStyle {
        case .solid:
            ctx.setLineCap(.round)
        case .dashed:
            ctx.setLineCap(.butt)
            ctx.setLineDash(phase: 0, lengths: [d.strokeWidth * 3 + 2, d.strokeWidth * 2.5 + 2])
        case .dotted:
            ctx.setLineCap(.round)
            ctx.setLineDash(phase: 0, lengths: [0.01, d.strokeWidth * 2])
        }
        ctx.strokePath()

        ctx.restoreGState()
    }
}
