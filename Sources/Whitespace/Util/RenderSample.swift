import AppKit
import CoreGraphics

/// Dev harness: render a grid of rough shapes to a PNG for visual fidelity
/// checks against Excalidraw. Invoked with `--render-sample <path>`.
enum RenderSample {
    static func run(to path: String) {
        let width = 960, height = 720
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        // White canvas.
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let stroke = NSColor(hex: 0x1e1e1e)
        let blueFill = NSColor(hex: 0xa5d8ff)
        let cellW = 220.0, cellH = 160.0
        let shapeRect = CGRect(x: 30, y: 30, width: 150, height: 100)

        // Columns: roughness 0, 1, 2. Rows: rect+hachure, ellipse+solid,
        // diamond+cross-hatch, line.
        let roughnessLevels = [Roughness.architect, Roughness.artist, Roughness.cartoonist]
        for (col, roughness) in roughnessLevels.enumerated() {
            let ox = Double(col) * cellW

            func style(_ fill: FillStyle, hasFill: Bool, seed: Int) -> RoughStyle {
                RoughStyle(strokeWidth: 2, roughness: roughness, fillStyle: fill,
                           strokeStyle: .solid, seed: seed, hasFill: hasFill)
            }

            var r = shapeRect.offsetBy(dx: ox, dy: 0)
            let rect = RoughShapeFactory.rectangle(r, style: style(.hachure, hasFill: true, seed: 11))
            RoughRenderer.draw(rect, stroke: stroke, fill: blueFill, in: ctx)

            r = shapeRect.offsetBy(dx: ox, dy: cellH)
            let ell = RoughShapeFactory.ellipse(r, style: style(.solid, hasFill: true, seed: 22))
            RoughRenderer.draw(ell, stroke: stroke, fill: blueFill, in: ctx)

            r = shapeRect.offsetBy(dx: ox, dy: cellH * 2)
            let dia = RoughShapeFactory.diamond(r, style: style(.crossHatch, hasFill: true, seed: 33))
            RoughRenderer.draw(dia, stroke: stroke, fill: blueFill, in: ctx)

            r = shapeRect.offsetBy(dx: ox, dy: cellH * 3)
            let ln = RoughShapeFactory.line(
                [CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.minY)],
                style: style(.solid, hasFill: false, seed: 44))
            RoughRenderer.draw(ln, stroke: stroke, fill: nil, in: ctx)
        }

        guard let image = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        FileHandle.standardError.write(Data("wrote sample to \(path)\n".utf8))
    }
}
