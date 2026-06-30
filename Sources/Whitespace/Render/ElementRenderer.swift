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
    private var imageCache: [String: NSImage] = [:]

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

        let rotated = abs(e.angle) > 0.0001
        if rotated {
            let bb = e.boundingRect
            ctx.saveGState()
            ctx.translateBy(x: bb.midX, y: bb.midY)
            ctx.rotate(by: CGFloat(e.angle))
            ctx.translateBy(x: -bb.midX, y: -bb.midY)
        }
        defer { if rotated { ctx.restoreGState() } }

        switch e.type {
        case "text":
            drawText(e, color: stroke, opacity: opacity, in: ctx)
        case "file":
            drawFileNode(e, opacity: opacity, in: ctx)
        case "image":
            drawImage(e, opacity: opacity, in: ctx)
        case "freedraw":
            drawFreehand(e, color: stroke, opacity: opacity, in: ctx)
        default:
            let drawable = drawable(for: e)
            RoughRenderer.draw(drawable, stroke: stroke, fill: fill, opacity: opacity,
                               strokeStyle: e.strokeStyle, in: ctx)
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
        default:
            drawable = e.roundness != nil
                ? RoughShapeFactory.roundedRectangle(e.rect, style: style)
                : RoughShapeFactory.rectangle(e.rect, style: style)
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
        if let end = e.endArrowhead {
            let tip = pts[pts.count - 1], prev = pts[pts.count - 2]
            drawArrowhead(end, at: tip, angle: atan2(tip.y - prev.y, tip.x - prev.x),
                          width: e.strokeWidth, color: color, opacity: opacity, in: ctx)
        }
        if let start = e.startArrowhead {
            let tip = pts[0], next = pts[1]
            drawArrowhead(start, at: tip, angle: atan2(tip.y - next.y, tip.x - next.x),
                          width: e.strokeWidth, color: color, opacity: opacity, in: ctx)
        }
    }

    /// Draw one arrowhead at `tip`, pointing along `angle`.
    private func drawArrowhead(_ type: String, at tip: CGPoint, angle: CGFloat,
                               width: Double, color: NSColor, opacity: CGFloat, in ctx: CGContext) {
        let len: CGFloat = max(12, width * 5)
        let spread: CGFloat = .pi / 7
        ctx.saveGState()
        ctx.setAlpha(opacity)
        ctx.setStrokeColor(color.cgColor)
        ctx.setFillColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let p1 = CGPoint(x: tip.x - len * cos(angle - spread), y: tip.y - len * sin(angle - spread))
        let p2 = CGPoint(x: tip.x - len * cos(angle + spread), y: tip.y - len * sin(angle + spread))
        switch type {
        case "triangle":
            ctx.move(to: tip); ctx.addLine(to: p1); ctx.addLine(to: p2); ctx.closePath(); ctx.fillPath()
        case "dot":
            let r = max(3, width * 1.6)
            ctx.fillEllipse(in: CGRect(x: tip.x - r, y: tip.y - r, width: r * 2, height: r * 2))
        case "bar":
            let b1 = CGPoint(x: tip.x - len * 0.6 * cos(angle + .pi / 2), y: tip.y - len * 0.6 * sin(angle + .pi / 2))
            let b2 = CGPoint(x: tip.x + len * 0.6 * cos(angle + .pi / 2), y: tip.y + len * 0.6 * sin(angle + .pi / 2))
            ctx.move(to: b1); ctx.addLine(to: b2); ctx.strokePath()
        default: // "arrow" — open V
            ctx.move(to: p1); ctx.addLine(to: tip); ctx.addLine(to: p2); ctx.strokePath()
        }
        ctx.restoreGState()
    }

    // MARK: Image

    private func drawImage(_ e: Element, opacity: CGFloat, in ctx: CGContext) {
        guard let path = e.link else { return }
        let image: NSImage
        if let cached = imageCache[path] {
            image = cached
        } else if let loaded = NSImage(contentsOfFile: (path as NSString).expandingTildeInPath) {
            imageCache[path] = loaded; image = loaded
        } else { return }
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        ctx.saveGState()
        ctx.setAlpha(opacity)
        // Flip vertically within the element box (CG images draw bottom-up).
        ctx.translateBy(x: e.rect.minX, y: e.rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: e.rect.width, height: e.rect.height))
        ctx.restoreGState()
    }

    // MARK: File node (a linked box with a filename)

    private func drawFileNode(_ e: Element, opacity: CGFloat, in ctx: CGContext) {
        // Transparent link: an icon (file/folder/URL) + name in the link color.
        let name = e.linkDisplayIcon + (e.text ?? "file")
        let size = CGFloat(e.fontSize ?? 16)
        let font = Fonts.handDrawn(size: size)
        let color = (NSColor.excalidraw(Settings.linkColor) ?? NSColor(hex: 0x6965db))
            .withAlphaComponent(opacity)
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: name, attributes: [.font: font, .foregroundColor: color]))
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: e.x, y: e.y + size)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    // MARK: Text

    private func drawText(_ e: Element, color: NSColor, opacity: CGFloat, in ctx: CGContext) {
        guard let text = e.text, !text.isEmpty else { return }
        let size = CGFloat(e.fontSize ?? 20)
        let font = Fonts.font(family: e.fontFamily ?? 1, size: size)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color.withAlphaComponent(opacity),
        ]
        let lineHeight = CGFloat(e.lineHeight ?? 1.25) * size
        // Bound (container) text is centered in the shape; free text is left/top.
        let centered = e.containerId != nil
        let wrapWidth: CGFloat = e.width > 8 ? max(CGFloat(e.width) - (centered ? 16 : 4), 24) : 100_000

        // Build wrapped lines.
        var lines: [CTLine] = []
        for paragraph in text.components(separatedBy: "\n") {
            if paragraph.isEmpty {
                lines.append(CTLineCreateWithAttributedString(NSAttributedString(string: " ", attributes: attrs)))
                continue
            }
            let attr = NSAttributedString(string: paragraph, attributes: attrs)
            let typesetter = CTTypesetterCreateWithAttributedString(attr)
            let length = (paragraph as NSString).length
            var start = 0
            while start < length {
                let count = CTTypesetterSuggestLineBreak(typesetter, start, Double(wrapWidth))
                if count <= 0 { break }
                lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)))
                start += count
            }
        }

        ctx.saveGState()
        var ty: CGFloat = centered
            ? CGFloat(e.rect.midY) - CGFloat(lines.count) * lineHeight / 2 + size * 0.85
            : CGFloat(e.y) + size
        for line in lines {
            let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            let x: CGFloat = centered ? (CGFloat(e.rect.midX) - lineWidth / 2) : (CGFloat(e.x) + 2)
            ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            ctx.textPosition = CGPoint(x: x, y: ty)
            CTLineDraw(line, ctx)
            ty += lineHeight
        }
        ctx.restoreGState()
    }
}
