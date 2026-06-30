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
        case "frame":
            drawFrame(e, in: ctx)
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

    // MARK: Frame & embed

    private func drawFrame(_ e: Element, in ctx: CGContext) {
        let r = e.rect
        let path = CGPath(roundedRect: r, cornerWidth: 8, cornerHeight: 8, transform: nil)
        ctx.addPath(path); ctx.setFillColor(NSColor.gray.withAlphaComponent(0.04).cgColor); ctx.fillPath()
        ctx.addPath(path); ctx.setStrokeColor(NSColor.gray.withAlphaComponent(0.55).cgColor)
        ctx.setLineWidth(1.5); ctx.strokePath()
        // Name label above the top-left corner.
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: e.text ?? "Frame", attributes: attrs))
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: r.minX + 2, y: r.minY - 5)
        CTLineDraw(line, ctx)
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

    private static let modifiedFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()

    private func drawFileNode(_ e: Element, opacity: CGFloat, in ctx: CGContext) {
        let link = e.link ?? ""
        let isFilePath = !link.isEmpty && !link.contains("://")
        // "preview" renders real files as a QuickLook card; everything else is a
        // compact label (icon + name, or just colored text).
        if Settings.linkStyle == "preview" && isFilePath {
            drawFileCard(e, path: link, opacity: opacity, in: ctx)
            return
        }
        let textOnly = Settings.linkStyle == "text"
        let name = (textOnly ? "" : e.linkDisplayIcon) + (e.text ?? "file")
        let size = CGFloat(e.fontSize ?? 16)
        let font = e.fontFamily.map { Fonts.font(family: $0, size: size) } ?? Fonts.handDrawn(size: size)
        let color = (NSColor.excalidraw(Settings.linkColor) ?? NSColor(hex: 0x6965db))
            .withAlphaComponent(opacity)
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: name, attributes: [.font: font, .foregroundColor: color]))
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: e.x, y: e.y + size)
        CTLineDraw(line, ctx)
        // Underline in text mode to read like a hyperlink.
        if textOnly {
            let w = (name as NSString).size(withAttributes: [.font: font]).width
            ctx.textMatrix = .identity
            ctx.setStrokeColor(color.cgColor); ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: e.x, y: e.y + size + 2))
            ctx.addLine(to: CGPoint(x: e.x + w, y: e.y + size + 2))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// A Finder-style card: QuickLook thumbnail + filename + modified date.
    private func drawFileCard(_ e: Element, path: String, opacity: CGFloat, in ctx: CGContext) {
        let r = e.rect
        let expanded = (path as NSString).expandingTildeInPath
        let exists = FileManager.default.fileExists(atPath: expanded)
        let captionH: CGFloat = 36

        ctx.saveGState()
        ctx.setAlpha(opacity)
        let card = CGPath(roundedRect: r, cornerWidth: 8, cornerHeight: 8, transform: nil)
        ctx.addPath(card); ctx.setFillColor(NSColor.white.cgColor); ctx.fillPath()
        ctx.addPath(card); ctx.setStrokeColor(NSColor(white: 0, alpha: 0.14).cgColor)
        ctx.setLineWidth(1); ctx.strokePath()

        // Thumbnail, aspect-fit and centered in the top region.
        let thumbRect = CGRect(x: r.minX + 10, y: r.minY + 10,
                               width: r.width - 20, height: r.height - captionH - 14)
        if thumbRect.width > 4, thumbRect.height > 4,
           let thumb = ThumbnailCache.shared.image(for: path,
                            pixelSize: CGSize(width: thumbRect.width * 2, height: thumbRect.height * 2)),
           let cg = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let iw = CGFloat(cg.width), ih = CGFloat(cg.height)
            let scale = min(thumbRect.width / iw, thumbRect.height / ih)
            let w = iw * scale, h = ih * scale
            let x = thumbRect.midX - w / 2, y = thumbRect.minY + (thumbRect.height - h) / 2
            ctx.saveGState()
            ctx.translateBy(x: x, y: y + h); ctx.scaleBy(x: 1, y: -1)
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            ctx.restoreGState()
        }

        // Filename. Fixed dark colors (not dynamic system colors, which can
        // resolve to nothing without an active appearance) on the white card.
        let name = e.text ?? (expanded as NSString).lastPathComponent
        let nameFont = e.fontFamily.map { Fonts.font(family: $0, size: CGFloat(e.fontSize ?? 12)) }
            ?? .systemFont(ofSize: 12, weight: .medium)
        drawCaption(name, at: CGPoint(x: r.minX + 10, y: r.maxY - 21), maxWidth: r.width - 20,
                    font: nameFont, color: NSColor(white: 0.12, alpha: opacity), in: ctx)
        // Subtitle: modified date, or a red "Missing" badge.
        let subtitle = exists ? modifiedDate(expanded) : "Missing"
        let subColor = exists ? NSColor(white: 0.5, alpha: opacity)
                              : NSColor(hex: 0xe03131).withAlphaComponent(opacity)
        drawCaption(subtitle, at: CGPoint(x: r.minX + 10, y: r.maxY - 7), maxWidth: r.width - 20,
                    font: .systemFont(ofSize: 10), color: subColor, in: ctx)
        ctx.restoreGState()
    }

    private func drawCaption(_ s: String, at baseline: CGPoint, maxWidth: CGFloat,
                             font: NSFont, color: NSColor, in ctx: CGContext) {
        guard !s.isEmpty else { return }
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color]))
        ctx.saveGState()
        ctx.clip(to: CGRect(x: baseline.x, y: baseline.y - 12, width: maxWidth, height: 16))
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = baseline
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    private func modifiedDate(_ path: String) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let date = attrs[.modificationDate] as? Date else { return "" }
        return Self.modifiedFormatter.string(from: date)
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
