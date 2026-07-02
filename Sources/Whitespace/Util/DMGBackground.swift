import AppKit
import CoreGraphics

/// Dev harness: render the DMG installer window background — a hand-drawn curved
/// arrow (Whitespace's own rough style) sweeping from the app to the
/// Applications folder, with an Excalifont title. Invoked `--render-dmg-bg`.
///
/// Writes a multi-resolution TIFF (1× + 2×) so Finder sizes it in points but
/// renders crisp on Retina. The window is 640×420 pt; the app icon sits at
/// ~(170,210) and Applications at ~(470,210), so the art lives in the gap.
@MainActor
enum DMGBackground {
    static let size = NSSize(width: 640, height: 420)

    static func run(to path: String) {
        guard let img1 = render(scale: 1), let img2 = render(scale: 2) else { return }
        let rep1 = NSBitmapImageRep(cgImage: img1); rep1.size = size
        let rep2 = NSBitmapImageRep(cgImage: img2); rep2.size = size
        let image = NSImage(size: size)
        image.addRepresentation(rep1)
        image.addRepresentation(rep2)
        guard let tiff = image.tiffRepresentation else { return }
        try? tiff.write(to: URL(fileURLWithPath: path))
        FileHandle.standardError.write(Data("wrote DMG background (1×+2×) to \(path)\n".utf8))
    }

    private static func render(scale: CGFloat) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        guard let ctx = CGContext(
            data: nil, width: w * Int(scale), height: h * Int(scale),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setFillColor(NSColor(hex: 0xfbfbfd).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w * Int(scale), height: h * Int(scale)))
        ctx.scaleBy(x: scale, y: scale)
        BackgroundPattern.draw("dots", bounds: CGRect(x: 0, y: 0, width: w, height: h), camera: Camera(), in: ctx)

        // Flip to y-down scene space for the renderer.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)

        var els: [Element] = []
        var title = Element(type: "text", x: 100, y: 40, width: 440, height: 46, seed: 1)
        title.text = "Install Whitespace"; title.fontSize = 34; title.fontFamily = 1
        title.textAlign = "center"; title.strokeColor = "#1e1e1e"
        els.append(title)

        var sub = Element(type: "text", x: 100, y: 344, width: 440, height: 26, seed: 2)
        sub.text = "Drag the app onto the Applications folder"
        sub.fontSize = 17; sub.fontFamily = 1; sub.textAlign = "center"; sub.strokeColor = "#868e96"
        els.append(sub)

        var arrow = Element(type: "arrow", x: 250, y: 205, width: 152, height: 52, seed: 3)
        arrow.points = [[0, 0], [78, -50], [152, -4]]
        arrow.roundness = Element.Roundness(type: 2)
        arrow.endArrowhead = "arrow"
        arrow.strokeColor = "#6965db"; arrow.strokeWidth = 3; arrow.roughness = 1
        els.append(arrow)

        ElementRenderer().draw(scene: Scene(elements: els), camera: Camera(), in: ctx)
        return ctx.makeImage()
    }
}
