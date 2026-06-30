import AppKit
import CoreGraphics

/// Dev harness: build a scene with one of every element, round-trip it through
/// the `.excalidraw` format, then render via the real `ElementRenderer`. Proves
/// the model → persistence → renderer pipeline. Invoked with `--render-scene`.
enum RenderScene {
    static func run(to path: String) {
        var elements: [Element] = []

        elements.append(Element(type: "rectangle", x: 60, y: 60, width: 180, height: 110,
                                backgroundColor: "#a5d8ff", fillStyle: .hachure, seed: 101))
        elements.append(Element(type: "ellipse", x: 300, y: 60, width: 170, height: 110,
                                backgroundColor: "#b2f2bb", fillStyle: .solid, seed: 202))
        elements.append(Element(type: "diamond", x: 520, y: 50, width: 160, height: 130,
                                strokeColor: "#e03131", backgroundColor: "#ffc9c9",
                                fillStyle: .crossHatch, seed: 303))

        var arrow = Element(type: "arrow", x: 80, y: 240, seed: 404)
        arrow.points = [[0, 0], [220, 60]]
        arrow.endArrowhead = "arrow"
        elements.append(arrow)

        var pen = Element(type: "freedraw", x: 360, y: 230, strokeColor: "#1971c2", seed: 505)
        pen.points = (0..<40).map { i in
            let t = Double(i) / 6
            return [t * 12, sin(t) * 30 + 30]
        }
        elements.append(pen)

        elements.append(Element(type: "text", x: 80, y: 360, strokeColor: "#1e1e1e",
                                seed: 606, text: "Hand-drawn ✏️", fontSize: 28))

        // Round-trip through the file format.
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ws_test.excalidraw")
        DocumentStore.save(elements, to: url)
        let reloaded = DocumentStore.load(from: url)
        FileHandle.standardError.write(Data("round-trip: saved \(elements.count), reloaded \(reloaded.count)\n".utf8))

        let scene = Scene(elements: reloaded)
        let width = 740, height = 460
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        // Flip to y-down so scene coordinates render top-down (matches the view).
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        let renderer = ElementRenderer()
        renderer.draw(scene: scene, camera: Camera(), in: ctx)

        guard let image = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        FileHandle.standardError.write(Data("wrote scene to \(path)\n".utf8))
    }
}
