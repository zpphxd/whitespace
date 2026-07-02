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
    /// Cached perfect-freehand outline path, keyed by element id (+ version).
    private var freehandCache: [String: (version: Int, path: CGPath)] = [:]

    /// Marching-ants phase for live data pipes (advanced by the canvas timer).
    var pipePhase: CGFloat = 0
    /// Per-pipe (arrow id → 0…1) progress of a data pulse traveling the pipe.
    var pipePulses: [String: CGFloat] = [:]
    /// Ids of cell elements in the scene being drawn (so arrows can tell when
    /// they connect two cells and should render as a live pipe).
    private var cellIds: Set<String> = []

    func invalidate(_ id: String) { cache.removeValue(forKey: id); freehandCache.removeValue(forKey: id) }
    func invalidateAll() { cache.removeAll(); freehandCache.removeAll() }

    func draw(scene: Scene, camera: Camera, in ctx: CGContext, hiding: Set<String> = []) {
        ctx.saveGState()
        // Scene → view: scale by zoom, then shift by camera offset.
        ctx.scaleBy(x: camera.zoom, y: camera.zoom)
        ctx.translateBy(x: -camera.offset.x, y: -camera.offset.y)

        cellIds = Set(scene.elements.filter { $0.type == "cell" }.map(\.id))
        for element in scene.elements where !element.isDeleted && !hiding.contains(element.id) {
            draw(element, in: ctx)
        }
        ctx.restoreGState()
    }

    /// Overlay pass for transient effects (e.g. the stencil drop pop-in): draws
    /// just `elements` under the camera transform, scaled about `pivot` (scene
    /// space) and composited at `alpha` via a transparency layer.
    func drawOverlay(elements: [Element], camera: Camera, pivot: CGPoint,
                     scale: CGFloat, alpha: CGFloat, in ctx: CGContext) {
        guard !elements.isEmpty else { return }
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.scaleBy(x: camera.zoom, y: camera.zoom)
        ctx.translateBy(x: -camera.offset.x, y: -camera.offset.y)
        // Pop about the group's center, in scene space.
        ctx.translateBy(x: pivot.x, y: pivot.y)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -pivot.x, y: -pivot.y)
        for element in elements where !element.isDeleted {
            draw(element, in: ctx)
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// An arrow whose both ends are bound to cells is a live data pipe.
    private func isLivePipe(_ e: Element) -> Bool {
        guard e.type == "arrow" || e.type == "line",
              let s = e.startBindingId, let t = e.endBindingId else { return false }
        return cellIds.contains(s) && cellIds.contains(t)
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

        if isLivePipe(e) { drawLivePipe(e, opacity: opacity, in: ctx); return }

        switch e.type {
        case "text":
            drawText(e, color: stroke, opacity: opacity, in: ctx)
        case "file":
            drawFileNode(e, opacity: opacity, in: ctx)
        case "image":
            drawImage(e, opacity: opacity, in: ctx)
        case "frame":
            drawFrame(e, opacity: opacity, in: ctx)
        case "cell":
            drawCell(e, opacity: opacity, in: ctx)
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
        case "line", "arrow":
            drawable = RoughShapeFactory.line(e.absolutePoints, style: style, curved: e.roundness != nil)
        default:
            drawable = e.roundness != nil
                ? RoughShapeFactory.roundedRectangle(e.rect, style: style)
                : RoughShapeFactory.rectangle(e.rect, style: style)
        }
        cache[e.id] = CacheEntry(version: e.version, drawable: drawable)
        return drawable
    }

    // MARK: Freehand — perfect-freehand variable-width outline (thick=slow, thin=fast)

    private func drawFreehand(_ e: Element, color: NSColor, opacity: CGFloat, in ctx: CGContext) {
        let pts = e.absolutePoints
        guard !pts.isEmpty else { return }

        let path: CGPath
        if let hit = freehandCache[e.id], hit.version == e.version {
            path = hit.path
        } else {
            let outline = PerfectFreehand.stroke(pts, strokeWidth: e.strokeWidth,
                                                 pressure: e.simulatePressure ?? true)
            path = PerfectFreehand.path(from: outline)
            freehandCache[e.id] = (e.version, path)
        }

        ctx.saveGState()
        ctx.setAlpha(opacity)
        ctx.addPath(path)
        ctx.setFillColor(color.cgColor)   // filled variable-width polygon, not a stroked centerline
        ctx.fillPath()
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

    // MARK: Live data pipe (an arrow connecting two cells)

    private func drawLivePipe(_ e: Element, opacity: CGFloat, in ctx: CGContext) {
        let pts = e.absolutePoints
        guard pts.count >= 2 else { return }
        let accent = NSColor(hex: 0x12b886)
        ctx.saveGState()
        ctx.setAlpha(opacity)
        ctx.setLineCap(.round); ctx.setLineJoin(.round)

        let path = CGMutablePath()
        path.move(to: pts[0]); for p in pts.dropFirst() { path.addLine(to: p) }

        // Soft glow, solid core, then bright marching dashes to read as "flowing".
        ctx.addPath(path); ctx.setStrokeColor(accent.withAlphaComponent(0.16).cgColor)
        ctx.setLineWidth(9); ctx.strokePath()
        ctx.addPath(path); ctx.setStrokeColor(accent.cgColor)
        ctx.setLineWidth(3); ctx.strokePath()
        ctx.addPath(path); ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.92).cgColor)
        ctx.setLineWidth(2)
        ctx.setLineDash(phase: -pipePhase, lengths: [5, 9])   // negative → flows toward the end
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])

        // End ports.
        ctx.setFillColor(accent.cgColor)
        for p in [pts.first!, pts.last!] {
            ctx.fillEllipse(in: CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9))
        }
        // Arrowhead at the end, along the last segment.
        let tip = pts[pts.count - 1], prev = pts[pts.count - 2]
        let a = atan2(tip.y - prev.y, tip.x - prev.x)
        let len: CGFloat = 11, spread: CGFloat = .pi / 7
        let head = CGMutablePath()
        head.move(to: tip)
        head.addLine(to: CGPoint(x: tip.x - len * cos(a - spread), y: tip.y - len * sin(a - spread)))
        head.addLine(to: CGPoint(x: tip.x - len * cos(a + spread), y: tip.y - len * sin(a + spread)))
        head.closeSubpath()
        ctx.addPath(head); ctx.setFillColor(accent.cgColor); ctx.fillPath()

        // Data pulse traveling the pipe while it's carrying output.
        if let prog = pipePulses[e.id], let dot = pointAlong(pts, t: prog) {
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: dot.x - 6, y: dot.y - 6, width: 12, height: 12))
            ctx.setFillColor(accent.withAlphaComponent(0.5).cgColor)
            ctx.fillEllipse(in: CGRect(x: dot.x - 10, y: dot.y - 10, width: 20, height: 20))
        }
        ctx.restoreGState()
    }

    /// Point at fractional length `t` (0…1) along a polyline.
    private func pointAlong(_ pts: [CGPoint], t: CGFloat) -> CGPoint? {
        guard pts.count >= 2 else { return pts.first }
        var total: CGFloat = 0
        var segs: [(CGPoint, CGPoint, CGFloat)] = []
        for i in 0..<(pts.count - 1) {
            let d = hypot(pts[i + 1].x - pts[i].x, pts[i + 1].y - pts[i].y)
            segs.append((pts[i], pts[i + 1], d)); total += d
        }
        guard total > 0 else { return pts.first }
        var target = max(0, min(1, t)) * total
        for (a, b, d) in segs {
            if target <= d {
                let f = d > 0 ? target / d : 0
                return CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
            }
            target -= d
        }
        return pts.last
    }

    // MARK: Live cell (executable code + output)

    private func drawCell(_ e: Element, opacity: CGFloat, in ctx: CGContext) {
        let r = e.rect
        let headerH: CGFloat = 26
        let hasRich = e.cellOutputType != nil && e.cellOutputData != nil
        let hasOutput = hasRich || !(e.cellOutput ?? "").isEmpty
        let outputH: CGFloat = hasOutput
            ? max(hasRich ? 130 : 40, (r.height - headerH) * (hasRich ? 0.55 : 0.42)) : 0
        let codeRect = CGRect(x: r.minX, y: r.minY + headerH, width: r.width,
                              height: r.height - headerH - outputH)

        ctx.saveGState()
        ctx.setAlpha(opacity)
        let card = CGPath(roundedRect: r, cornerWidth: 9, cornerHeight: 9, transform: nil)
        ctx.addPath(card); ctx.setFillColor(NSColor(hex: 0x1e1e2e).cgColor); ctx.fillPath()

        // Header bar.
        ctx.saveGState()
        ctx.addPath(card); ctx.clip()
        ctx.setFillColor(NSColor(hex: 0x2a2a3c).cgColor)
        ctx.fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: headerH))
        ctx.restoreGState()
        let lang = CellRunner.displayName(e.cellLanguage ?? "shell")
        let header = e.cellExecCount.map { "\(lang)   [\($0)]" } ?? lang
        drawMono(header, in: CGRect(x: r.minX + 12, y: r.minY + 6, width: r.width - 60, height: 16),
                 size: 11, color: NSColor(hex: 0x9aa0b4), in: ctx)
        // Test cells show a PASS / FAIL / TEST badge.
        if e.cellKind == "test" {
            let label: String, col: NSColor
            if e.cellExecCount == nil { label = "TEST"; col = NSColor(hex: 0x9aa0b4) }
            else if e.cellFailed == true { label = "FAIL"; col = NSColor(hex: 0xe03131) }
            else { label = "PASS"; col = NSColor(hex: 0x40c057) }
            let pill = CGRect(x: r.maxX - 96, y: r.minY + 6, width: 52, height: 15)
            ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 4, cornerHeight: 4, transform: nil))
            ctx.setFillColor(col.withAlphaComponent(0.18).cgColor); ctx.fillPath()
            drawMono(label, in: pill.insetBy(dx: 8, dy: 1), size: 10, color: col, in: ctx)
        }

        // Run glyph (green triangle) at the right of the header.
        let tri = CGRect(x: r.maxX - 26, y: r.minY + 8, width: 11, height: 11)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: tri.minX, y: tri.minY))
        ctx.addLine(to: CGPoint(x: tri.minX, y: tri.maxY))
        ctx.addLine(to: CGPoint(x: tri.maxX, y: tri.midY))
        ctx.closePath()
        ctx.setFillColor(NSColor(hex: 0x40c057).cgColor); ctx.fillPath()

        // Source.
        drawMonoBlock(e.text ?? "", in: codeRect.insetBy(dx: 12, dy: 8),
                      size: 12.5, color: NSColor(hex: 0xe4e4ef), in: ctx)

        // Output panel.
        if hasOutput {
            let outRect = CGRect(x: r.minX, y: codeRect.maxY, width: r.width, height: outputH)
            ctx.saveGState(); ctx.addPath(card); ctx.clip()
            ctx.setFillColor(NSColor(hex: 0x16161f).cgColor); ctx.fill(outRect)
            ctx.setStrokeColor(NSColor(hex: 0x33334a).cgColor); ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: r.minX, y: outRect.minY)); ctx.addLine(to: CGPoint(x: r.maxX, y: outRect.minY)); ctx.strokePath()
            ctx.restoreGState()
            let inset = outRect.insetBy(dx: 12, dy: 7)
            let rawData = e.cellOutputData.flatMap { Data(base64Encoded: $0) }
            if e.cellOutputType == "image/png", let data = rawData {
                drawCellImage(data, in: inset, in: ctx)
            } else if e.cellOutputType == "table", let data = rawData {
                drawCellTable(data, in: inset, in: ctx)
            } else {
                let outColor = e.cellFailed == true ? NSColor(hex: 0xff6b6b) : NSColor(hex: 0x8de08d)
                drawMonoBlock(e.cellOutput ?? "", in: inset, size: 11.5, color: outColor, in: ctx)
            }
        }

        let border = e.cellFailed == true ? NSColor(hex: 0xe03131) : NSColor(hex: 0x3a3a52)
        ctx.addPath(card); ctx.setStrokeColor(border.cgColor)
        ctx.setLineWidth(e.cellFailed == true ? 1.5 : 1); ctx.strokePath()
        ctx.restoreGState()
    }

    /// A rich image output (e.g. a matplotlib plot), aspect-fit in the panel.
    private func drawCellImage(_ data: Data, in rect: CGRect, in ctx: CGContext) {
        guard rect.width > 4, rect.height > 4, let img = NSImage(data: data),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let iw = CGFloat(cg.width), ih = CGFloat(cg.height)
        let scale = min(rect.width / iw, rect.height / ih)
        let w = iw * scale, h = ih * scale
        let x = rect.midX - w / 2, y = rect.minY + (rect.height - h) / 2
        ctx.saveGState()
        ctx.translateBy(x: x, y: y + h); ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.restoreGState()
    }

    /// A rich table output — a simple grid, header row tinted.
    private func drawCellTable(_ data: Data, in rect: CGRect, in ctx: CGContext) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return }
        var rows: [[String]] = []
        if let arr = obj as? [[Any]] {
            rows = arr.map { $0.map { "\($0)" } }
        } else if let dicts = obj as? [[String: Any]], let first = dicts.first {
            let keys = Array(first.keys)
            rows = [keys] + dicts.map { d in keys.map { "\(d[$0] ?? "")" } }
        }
        guard let cols = rows.map(\.count).max(), cols > 0 else { return }
        let colW = rect.width / CGFloat(cols)
        let rowH: CGFloat = 16
        let maxRows = min(rows.count, max(1, Int(rect.height / rowH)))
        for ri in 0..<maxRows {
            let y = rect.minY + CGFloat(ri) * rowH
            for ci in 0..<min(rows[ri].count, cols) {
                let color = ri == 0 ? NSColor(hex: 0xbfc7ff) : NSColor(hex: 0xd0d0e0)
                drawMono(rows[ri][ci], in: CGRect(x: rect.minX + CGFloat(ci) * colW + 2, y: y,
                                                  width: colW - 4, height: rowH),
                         size: 10.5, color: color, in: ctx)
            }
        }
        ctx.setStrokeColor(NSColor(hex: 0x44445e).cgColor); ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: rect.minX, y: rect.minY + rowH))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rowH)); ctx.strokePath()
    }

    /// One clipped monospaced line.
    private func drawMono(_ s: String, in rect: CGRect, size: CGFloat, color: NSColor, in ctx: CGContext) {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: .regular), .foregroundColor: color]))
        ctx.saveGState(); ctx.clip(to: rect)
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: rect.minX, y: rect.minY + size)
        CTLineDraw(line, ctx); ctx.restoreGState()
    }

    /// Multi-line monospaced text, top-aligned and clipped to `rect`.
    private func drawMonoBlock(_ s: String, in rect: CGRect, size: CGFloat, color: NSColor, in ctx: CGContext) {
        guard rect.height > 4 else { return }
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let lineH = size * 1.35
        ctx.saveGState(); ctx.clip(to: rect)
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        var y = rect.minY + size
        for raw in s.components(separatedBy: "\n") {
            if y - size > rect.maxY { break }
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: raw, attributes: [
                .font: font, .foregroundColor: color]))
            ctx.textPosition = CGPoint(x: rect.minX, y: y)
            CTLineDraw(line, ctx)
            y += lineH
        }
        ctx.restoreGState()
    }

    // MARK: Frame & embed

    private func drawFrame(_ e: Element, opacity: CGFloat, in ctx: CGContext) {
        let r = e.rect
        ctx.saveGState(); ctx.setAlpha(opacity); defer { ctx.restoreGState() }
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
        // Bound (container) text is centered in the shape and wraps to it; free
        // text renders its explicit newlines only — Excalidraw never soft-wraps
        // free text (its width is derived from content), and wrapping it here
        // clipped the last character whenever our font metrics ran a hair wide.
        let centered = e.containerId != nil
        let wrapWidth: CGFloat = (centered && e.width > 8) ? max(CGFloat(e.width) - 16, 24) : 100_000

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
