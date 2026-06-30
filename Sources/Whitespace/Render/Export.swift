import AppKit
import CoreGraphics

/// Export the scene to PNG (raster) or SVG (vector). Both reuse the same rough
/// geometry and per-element seeds, so an export matches the on-screen drawing.
enum Export {
    private static let pad: CGFloat = 24

    /// Union of all element bounds, or nil if the scene is empty.
    static func contentBounds(_ elements: [Element]) -> CGRect? {
        let live = elements.filter { !$0.isDeleted }
        guard let first = live.first else { return nil }
        return live.dropFirst().reduce(first.boundingRect) { $0.union($1.boundingRect) }
    }

    // MARK: PNG

    static func png(_ elements: [Element], scale: CGFloat = 2) -> Data? {
        guard let bounds = contentBounds(elements) else { return nil }
        let frame = bounds.insetBy(dx: -pad, dy: -pad)
        let w = Int(frame.width * scale), h = Int(frame.height * scale)
        guard w > 0, h > 0,
              let ctx = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // Flip to y-down and apply export scale; camera shifts content to origin.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        let scene = Scene(elements: elements)
        let camera = Camera(offset: frame.origin, zoom: 1)
        ElementRenderer().draw(scene: scene, camera: camera, in: ctx)

        guard let image = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    // MARK: SVG

    static func svg(_ elements: [Element]) -> String? {
        guard let bounds = contentBounds(elements) else { return nil }
        let f = bounds.insetBy(dx: -pad, dy: -pad)
        var out = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(num(f.width))" height="\(num(f.height))" \
        viewBox="\(num(f.minX)) \(num(f.minY)) \(num(f.width)) \(num(f.height))">
        <rect x="\(num(f.minX))" y="\(num(f.minY))" width="\(num(f.width))" height="\(num(f.height))" fill="#ffffff"/>

        """
        for e in elements where !e.isDeleted {
            out += svgElement(e)
        }
        out += "</svg>\n"
        return out
    }

    private static func svgElement(_ e: Element) -> String {
        let stroke = e.strokeColor
        let opacity = e.opacity / 100
        switch e.type {
        case "text":
            let size = e.fontSize ?? 20
            var s = ""
            for (i, line) in (e.text ?? "").components(separatedBy: "\n").enumerated() {
                let y = e.y + size * (1 + Double(i) * 1.25)
                s += "<text x=\"\(num(e.x))\" y=\"\(num(y))\" font-family=\"Bradley Hand, cursive\" "
                s += "font-size=\"\(num(size))\" fill=\"\(stroke)\" opacity=\"\(num(opacity))\">"
                s += line.htmlEscaped + "</text>\n"
            }
            return s
        case "file":
            let size = e.fontSize ?? 16
            let color = Settings.linkColor
            let display = "– " + (e.text ?? "file")
            return "<text x=\"\(num(e.x))\" y=\"\(num(e.y + size))\" font-family=\"Bradley Hand, cursive\" font-size=\"\(num(size))\" fill=\"\(color)\" opacity=\"\(num(opacity))\">\(display.htmlEscaped)</text>\n"
        case "freedraw":
            let d = svgData(freehandPath(e))
            return "<path d=\"\(d)\" stroke=\"\(stroke)\" fill=\"none\" stroke-width=\"\(num(max(e.strokeWidth,1) * 1.5))\" stroke-linecap=\"round\" stroke-linejoin=\"round\" opacity=\"\(num(opacity))\"/>\n"
        default:
            let drawable = makeDrawable(e)
            var s = ""
            if let fill = drawable.fill {
                if drawable.fillIsSolid, e.backgroundColor != "transparent" {
                    s += "<path d=\"\(svgData(fill))\" fill=\"\(e.backgroundColor)\" opacity=\"\(num(opacity))\"/>\n"
                } else if e.backgroundColor != "transparent" {
                    s += "<path d=\"\(svgData(fill))\" stroke=\"\(e.backgroundColor)\" fill=\"none\" stroke-width=\"\(num(drawable.fillWeight))\" stroke-linecap=\"round\" opacity=\"\(num(opacity))\"/>\n"
                }
            }
            s += "<path d=\"\(svgData(drawable.outline))\" stroke=\"\(stroke)\" fill=\"none\" stroke-width=\"\(num(e.strokeWidth))\" stroke-linecap=\"round\" stroke-linejoin=\"round\" opacity=\"\(num(opacity))\"/>\n"
            if e.type == "arrow", let head = arrowheadPath(e) {
                s += "<path d=\"\(svgData(head))\" stroke=\"\(stroke)\" fill=\"none\" stroke-width=\"\(num(e.strokeWidth))\" stroke-linecap=\"round\" stroke-linejoin=\"round\" opacity=\"\(num(opacity))\"/>\n"
            }
            return s
        }
    }

    private static func makeDrawable(_ e: Element) -> RoughDrawable {
        let style = RoughStyle(
            strokeWidth: e.strokeWidth, roughness: e.roughness, fillStyle: e.fillStyle,
            strokeStyle: e.strokeStyle, seed: e.seed,
            hasFill: e.backgroundColor != "transparent")
        switch e.type {
        case "ellipse": return RoughShapeFactory.ellipse(e.rect, style: style)
        case "diamond": return RoughShapeFactory.diamond(e.rect, style: style)
        case "line", "arrow": return RoughShapeFactory.line(e.absolutePoints, style: style)
        default: return RoughShapeFactory.rectangle(e.rect, style: style)
        }
    }

    private static func freehandPath(_ e: Element) -> CGPath {
        let pts = e.absolutePoints
        let path = CGMutablePath()
        guard pts.count > 1 else { return path }
        path.move(to: pts[0])
        for i in 1..<pts.count { path.addLine(to: pts[i]) }
        return path
    }

    private static func arrowheadPath(_ e: Element) -> CGPath? {
        let pts = e.absolutePoints
        guard pts.count >= 2 else { return nil }
        let end = pts[pts.count - 1], prev = pts[pts.count - 2]
        let angle = atan2(end.y - prev.y, end.x - prev.x)
        let len = max(12, e.strokeWidth * 5)
        let spread = CGFloat.pi / 7
        let path = CGMutablePath()
        path.move(to: CGPoint(x: end.x - len * cos(angle - spread), y: end.y - len * sin(angle - spread)))
        path.addLine(to: end)
        path.addLine(to: CGPoint(x: end.x - len * cos(angle + spread), y: end.y - len * sin(angle + spread)))
        return path
    }

    // MARK: CGPath → SVG path data

    private static func svgData(_ path: CGPath) -> String {
        var d = ""
        path.applyWithBlock { elementPtr in
            let el = elementPtr.pointee
            let p = el.points
            switch el.type {
            case .moveToPoint: d += "M\(num(p[0].x)) \(num(p[0].y)) "
            case .addLineToPoint: d += "L\(num(p[0].x)) \(num(p[0].y)) "
            case .addQuadCurveToPoint: d += "Q\(num(p[0].x)) \(num(p[0].y)) \(num(p[1].x)) \(num(p[1].y)) "
            case .addCurveToPoint: d += "C\(num(p[0].x)) \(num(p[0].y)) \(num(p[1].x)) \(num(p[1].y)) \(num(p[2].x)) \(num(p[2].y)) "
            case .closeSubpath: d += "Z "
            @unknown default: break
            }
        }
        return d.trimmingCharacters(in: .whitespaces)
    }

    private static func num(_ v: CGFloat) -> String { String(format: "%.2f", v) }
    private static func num(_ v: Double) -> String { String(format: "%.2f", v) }
}

private extension String {
    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
