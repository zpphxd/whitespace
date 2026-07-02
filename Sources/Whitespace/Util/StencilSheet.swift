import AppKit
import CoreGraphics
import CoreText

/// Dev harness: composite every bundled architecture stencil's REAL library
/// thumbnail (the exact `StencilThumbnails` output the sidebar tiles show) into
/// one labeled contact sheet PNG. Invoked with `--render-stencils <path>`.
@MainActor
enum StencilSheet {
    static func run(to path: String) {
        let comps = StencilLibrary.systemDesign
        let cols = 5
        let thumbSize = CGSize(width: 200, height: 110)
        let cellW = 232.0, cellH = 164.0, pad = 24.0
        let rows = (comps.count + cols - 1) / cols
        let width = Int(pad * 2 + Double(cols) * cellW)
        let height = Int(pad * 2 + Double(rows) * cellH)

        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        for (i, c) in comps.enumerated() {
            guard let thumb = StencilThumbnails.image(key: c.id, elements: c.elements, size: thumbSize),
                  let cg = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let col = Double(i % cols), row = Double(i / cols)
            let x = pad + col * cellW + (cellW - thumbSize.width) / 2
            // CG bitmap is y-up: flip the row index so item 0 lands top-left.
            let yTop = pad + row * cellH
            let y = Double(height) - yTop - thumbSize.height - 8
            ctx.draw(cg, in: CGRect(x: x, y: y, width: thumbSize.width, height: thumbSize.height))

            // Caption under the thumbnail.
            let font = NSFont.systemFont(ofSize: 12, weight: .medium)
            let attr = NSAttributedString(string: c.name, attributes: [
                .font: font, .foregroundColor: NSColor(hex: 0x868e96),
            ])
            let line = CTLineCreateWithAttributedString(attr)
            let tw = CTLineGetTypographicBounds(line, nil, nil, nil)
            ctx.textPosition = CGPoint(x: x + (thumbSize.width - tw) / 2, y: y - 16)
            CTLineDraw(line, ctx)
        }

        guard let image = ctx.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        FileHandle.standardError.write(Data("wrote stencil sheet (\(comps.count) components) to \(path)\n".utf8))
    }

    /// Dev harness: render a pasted table + its QR code side by side, exactly as
    /// the paste-wheel/context-menu paths build them. Invoked `--render-table`.
    static func renderTable(to path: String) {
        let tsv = "Month\tRevenue\tCosts\nJan\t52\t31\nFeb\t55\t28\nMar\t51\t34\nApr\t60\t30\nMay\t72\t41\nJun\t58\t36"
        guard let cells = ChartMaker.cells(tsv) else { return }
        var elements = TableMaker.elements(cells, center: CGPoint(x: 230, y: 200))

        // The QR the context menu would generate for a URL, dropped as an image.
        if let qrPath = QRCode.generatePNG(for: "https://whitespace.app"),
           let qr = NSImage(contentsOfFile: qrPath) {
            var img = Element(type: "image", x: 470, y: 120, width: 160, height: 160)
            img.link = qrPath; img.backgroundColor = "transparent"
            elements.append(img)
            _ = qr
        }

        let width = 680, height = 360
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ElementRenderer().draw(scene: Scene(elements: elements), camera: Camera(), in: ctx)

        guard let image = ctx.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        FileHandle.standardError.write(Data("wrote table+QR sample to \(path)\n".utf8))
    }

    /// Dev harness: render the stencil drop pop-in as a filmstrip — one frame
    /// per time step, drawn through the same `drawOverlay` pass the canvas uses.
    /// Invoked with `--render-drop-anim <path>`.
    static func renderDropAnimation(to path: String) {
        guard let comp = StencilLibrary.systemDesign.first(where: { $0.id == "sd-relational-db" })
            ?? StencilLibrary.systemDesign.first else { return }
        let frames = 6
        let cellW = 190.0, cellH = 170.0, pad = 16.0
        let width = Int(pad * 2 + Double(frames) * cellW)
        let height = Int(pad * 2 + cellH)
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        // Same easing as CanvasView.easeOutBack.
        func easeOutBack(_ t: CGFloat) -> CGFloat {
            let c1: CGFloat = 1.70158, c3 = c1 + 1
            return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
        }

        let renderer = ElementRenderer()
        for f in 0..<frames {
            let t = CGFloat(f) / CGFloat(frames - 1)
            let pivot = CGPoint(x: pad + Double(f) * cellW + cellW / 2, y: pad + cellH / 2)
            let placed = comp.elements.map { e -> Element in
                var c = e
                c.id = "frame\(f)-\(e.id)"   // unique per frame: the rough cache keys on id+version
                c.x += pivot.x; c.y += pivot.y
                return c
            }
            renderer.drawOverlay(elements: placed, camera: Camera(), pivot: pivot,
                                 scale: 0.55 + 0.45 * easeOutBack(t),
                                 alpha: min(1, t * 3 + 0.15), in: ctx)
        }

        guard let image = ctx.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        FileHandle.standardError.write(Data("wrote drop-animation filmstrip (\(frames) frames) to \(path)\n".utf8))
    }
}
