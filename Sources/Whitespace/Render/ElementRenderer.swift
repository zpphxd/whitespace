import AppKit
import CoreGraphics
import CoreText

/// Renders scene elements into a context under the camera transform. Rough
/// geometry is generated once per element and cached by `id`+`version`; only an
/// edited element regenerates, so pan/zoom just replays cached paths.
final class ElementRenderer {

    private struct CacheEntry {
        var version: Int
        var drawable: RoughDrawable
    }
    private var cache: [String: CacheEntry] = [:]

    func invalidate(_ id: String) { cache.removeValue(forKey: id) }
    func invalidateAll() { cache.removeAll() }

    func draw(scene: Scene, camera: Camera, in ctx: CGContext) {
        ctx.saveGState()
        // Scene → view: scale by zoom, then shift by camera offset.
        ctx.scaleBy(x: camera.zoom, y: camera.zoom)
        ctx.translateBy(x: -camera.offset.x, y: -camera.offset.y)

        for element in scene.elements where !element.isDeleted {
            draw(element, in: ctx)
        }
        ctx.restoreGState()
    }

    private func draw(_ e: Element, in ctx: CGContext) {
        let opacity = CGFloat(e.opacity / 100)
        let stroke = NSColor.excalidraw(e.strokeColor) ?? NSColor(hex: 0x1e1e1e)
        let fill = NSColor.excalidraw(e.backgroundColor)

        switch e.type {
        case "text":
            drawText(e, color: stroke, opacity: opacity, in: ctx)
        case "freedraw":
            drawFreehand(e, color: stroke, opacity: opacity, in: ctx)
        default:
            let drawable = drawable(for: e)
            RoughRenderer.draw(drawable, stroke: stroke, fill: fill, opacity: opacity, in: ctx)
            if e.type == "arrow" { drawArrowheads(e, color: stroke, opacity: opacity, in: ctx) }
        }
    }

    private func drawable(for e: Element) -> RoughDrawable {
        if let hit = cache[e.id], hit.version == e.version { return hit.drawable }
        let style = RoughStyle(
            strokeWidth: e.strokeWidth,
            roughness: e.roughness,
            fillStyle: e.fillStyle,
            strokeStyle: e.strokeStyle,
            seed: e.seed,
            hasFill: NSColor.excalidraw(e.backgroundColor) != nil
        )
        let drawable: RoughDrawable
        switch e.type {
        case "ellipse": drawable = RoughShapeFactory.ellipse(e.rect, style: style)
        case "diamond": drawable = RoughShapeFactory.diamond(e.rect, style: style)
        case "line", "arrow": drawable = RoughShapeFactory.line(e.absolutePoints, style: style)
        default: drawable = RoughShapeFactory.rectangle(e.rect, style: style)
        }
        cache[e.id] = CacheEntry(version: e.version, drawable: drawable)
        return drawable
    }

    // MARK: Freehand (smooth, variable cap)

    private func drawFreehand(_ e: Element, color: NSColor, opacity: CGFloat, in ctx: CGContext) {
        let pts = e.absolutePoints
        guard pts.count > 1 else { return }
        let path = CGMutablePath()
        path.move(to: pts[0])
        if pts.count == 2 {
            path.addLine(to: pts[1])
        } else {
            // Quadratic smoothing through midpoints for a fluid pen line.
            for i in 1..<(pts.count - 1) {
                let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2,
                                  y: (pts[i].y + pts[i + 1].y) / 2)
                path.addQuadCurve(to: mid, control: pts[i])
            }
            path.addLine(to: pts[pts.count - 1])
        }
        ctx.saveGState()
        ctx.setAlpha(opacity)
        ctx.addPath(path)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(max(e.strokeWidth, 1) * 1.5)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: Arrowheads

    private func drawArrowheads(_ e: Element, color: NSColor, opacity: CGFloat, in ctx: CGContext) {
        let pts = e.absolutePoints
        guard pts.count >= 2 else { return }
        let end = pts[pts.count - 1], prev = pts[pts.count - 2]
        let angle = atan2(end.y - prev.y, end.x - prev.x)
        let len: CGFloat = max(12, e.strokeWidth * 5)
        let spread: CGFloat = .pi / 7
        let p1 = CGPoint(x: end.x - len * cos(angle - spread), y: end.y - len * sin(angle - spread))
        let p2 = CGPoint(x: end.x - len * cos(angle + spread), y: end.y - len * sin(angle + spread))
        ctx.saveGState()
        ctx.setAlpha(opacity)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(e.strokeWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: p1); ctx.addLine(to: end); ctx.addLine(to: p2)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: Text

    private func drawText(_ e: Element, color: NSColor, opacity: CGFloat, in ctx: CGContext) {
        guard let text = e.text, !text.isEmpty else { return }
        let size = CGFloat(e.fontSize ?? 20)
        let font = Fonts.handDrawn(size: size)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color.withAlphaComponent(opacity),
        ]
        let attr = NSAttributedString(string: text, attributes: attrs)

        ctx.saveGState()
        // Core Text draws upward; flip within the element's box so it reads
        // top-down in our flipped scene space.
        let lineHeight = CGFloat(e.lineHeight ?? 1.25) * size
        var ty = e.y + lineHeight - size * 0.2
        for line in text.components(separatedBy: "\n") {
            let lineAttr = NSAttributedString(string: line, attributes: attrs)
            let ctLine = CTLineCreateWithAttributedString(lineAttr)
            ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            ctx.textPosition = CGPoint(x: e.x, y: ty)
            CTLineDraw(ctLine, ctx)
            ty += lineHeight
        }
        _ = attr
        ctx.restoreGState()
    }
}
