import AppKit
import CoreGraphics

/// Renders stencil element groups into small preview images using the real
/// `ElementRenderer`, so library tiles show the actual hand-drawn component
/// (not a stand-in SF Symbol). Rendered once per key, then cached.
@MainActor
enum StencilThumbnails {
    private static var cache: [String: NSImage] = [:]
    private static let renderer = ElementRenderer()

    /// Drop cached previews whose stencil changed or was removed (custom edits).
    static func invalidate(_ key: String) { cache.removeValue(forKey: key) }

    /// A fitted, transparent-background preview of `elements` (which are stored
    /// centered on the origin). Retina-rendered at 2× the requested point size.
    static func image(key: String, elements: [Element], size: CGSize = CGSize(width: 116, height: 64)) -> NSImage? {
        if let hit = cache[key] { return hit }
        guard let first = elements.first else { return nil }

        let box = elements.dropFirst().reduce(first.boundingRect) { $0.union($1.boundingRect) }
            .insetBy(dx: -6, dy: -6)   // padding so strokes/roughness don't clip
        guard box.width > 1, box.height > 1 else { return nil }

        // Fit the group into the tile; never blow tiny shapes up past 1:1.
        let zoom = min(size.width / box.width, size.height / box.height, 1.0)
        var camera = Camera()
        camera.zoom = zoom
        camera.offset = CGPoint(x: box.midX - size.width / (2 * zoom),
                                y: box.midY - size.height / (2 * zoom))

        let scale: CGFloat = 2   // retina
        let pxW = Int(size.width * scale), pxH = Int(size.height * scale)
        guard let ctx = CGContext(
            data: nil, width: pxW, height: pxH, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Flip to y-down scene coordinates (bitmap contexts are y-up), at 2×.
        ctx.translateBy(x: 0, y: CGFloat(pxH))
        ctx.scaleBy(x: scale, y: -scale)

        renderer.draw(scene: Scene(elements: elements), camera: camera, in: ctx)

        guard let cg = ctx.makeImage() else { return nil }
        let image = NSImage(cgImage: cg, size: size)
        cache[key] = image
        return image
    }

    /// Preview elements for the Flow stencils (mirrors what `insertStencil`
    /// drops, so the tile shows exactly what you'll get).
    static func flowElements(_ id: String) -> [Element] {
        switch id {
        case "pill":
            return [Element(type: "rectangle", x: -75, y: -26, width: 150, height: 52,
                            seed: 7001, roundness: Element.Roundness(type: 3))]
        case "curved":
            var e = Element(type: "arrow", x: -70, y: -8, width: 140, height: 34, seed: 7002)
            e.roundness = Element.Roundness(type: 2)
            e.points = [[0, 17], [70, -17], [140, 17]]
            e.endArrowhead = "arrow"
            return [e]
        default:
            return []
        }
    }
}
