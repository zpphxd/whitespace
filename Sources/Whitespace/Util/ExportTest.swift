import AppKit

/// Dev harness: build a small scene and write PNG + SVG via `Export`, to verify
/// the export pipeline. Invoked with `--export-test <dir>`.
enum ExportTest {
    static func run(to dir: String) {
        var elements: [Element] = []
        var rrect = Element(type: "rectangle", x: 60, y: 60, width: 160, height: 100,
                            backgroundColor: "#a5d8ff", fillStyle: .hachure, strokeStyle: .dashed, seed: 7)
        rrect.roundness = Element.Roundness(type: 3)   // rounded + dashed
        elements.append(rrect)
        elements.append(Element(type: "ellipse", x: 280, y: 70, width: 150, height: 90,
                                angle: 0.4, backgroundColor: "#b2f2bb", fillStyle: .solid,
                                strokeStyle: .dotted, seed: 8))
        // Straight bound arrow from rect → ellipse, routed to their edges.
        let rectId = elements[0].id, ellId = elements[1].id
        var arrow = Element(type: "arrow", x: 0, y: 0, seed: 9,
                            startArrowhead: "dot", endArrowhead: "triangle",
                            startBindingId: rectId, endBindingId: ellId)
        arrow.points = [[0, 0], [1, 1]]
        // edge points: rect center→ell center and back
        let rc = CGPoint(x: elements[0].rect.midX, y: elements[0].rect.midY)
        let ec = CGPoint(x: elements[1].rect.midX, y: elements[1].rect.midY)
        let a = ArrowBinding.edgePoint(of: elements[0], toward: ec)
        let b = ArrowBinding.edgePoint(of: elements[1], toward: rc)
        arrow.x = a.x; arrow.y = a.y; arrow.points = [[0, 0], [b.x - a.x, b.y - a.y]]
        elements.append(arrow)

        // Elbow arrow below.
        var elbow = Element(type: "arrow", x: 90, y: 220, seed: 11, endArrowhead: "arrow", elbowed: true)
        let route = ArrowBinding.elbowRoute(CGPoint(x: 90, y: 220), CGPoint(x: 360, y: 280))
        elbow.points = route.map { [$0.x - 90, $0.y - 220] }
        elements.append(elbow)

        // Narrow box to verify the text wraps to fit (not single-line/scaled).
        elements.append(Element(type: "text", x: 70, y: 320, width: 150, height: 90, seed: 10,
                                text: "This text should wrap to fit the box width", fontSize: 20,
                                fontFamily: 11))

        // Container-bound, centered text inside a rounded rectangle.
        var box = Element(type: "rectangle", x: 60, y: 430, width: 200, height: 90,
                          backgroundColor: "#ffec99", fillStyle: .solid, seed: 14)
        box.roundness = Element.Roundness(type: 3)
        var label = Element(type: "text", x: 60, y: 430, width: 200, height: 90, seed: 15,
                            text: "Centered label that wraps inside the box", fontSize: 18)
        label.containerId = box.id
        label.textAlign = "center"; label.verticalAlign = "middle"
        elements.append(box)
        elements.append(label)

        var frame = Element(type: "frame", x: 430, y: 250, width: 220, height: 150, seed: 16)
        frame.text = "Frame 1"
        elements.append(frame)

        var image = Element(type: "image", x: 470, y: 60, width: 120, height: 120, seed: 13)
        image.link = "/Users/zachpowers/whitespace/AppIcon.png"
        elements.append(image)

        var fileNode = Element(type: "file", x: 700, y: 60, width: 150, height: 172, seed: 12)
        fileNode.text = "Package.swift"
        fileNode.link = "/Users/zachpowers/whitespace/Package.swift"
        fileNode.backgroundColor = "#ffffff"
        elements.append(fileNode)
        var missingNode = Element(type: "file", x: 700, y: 250, width: 150, height: 172, seed: 18)
        missingNode.text = "gone.pdf"
        missingNode.link = "/Users/zachpowers/whitespace/gone.pdf"
        missingNode.backgroundColor = "#ffffff"
        elements.append(missingNode)

        let pngURL = URL(fileURLWithPath: dir).appendingPathComponent("export_test.png")
        let svgURL = URL(fileURLWithPath: dir).appendingPathComponent("export_test.svg")
        if let png = Export.png(elements) {
            try? png.write(to: pngURL)
            FileHandle.standardError.write(Data("PNG \(png.count) bytes -> \(pngURL.path)\n".utf8))
        } else {
            FileHandle.standardError.write(Data("PNG export returned nil\n".utf8))
        }
        if let svg = Export.svg(elements) {
            try? svg.write(to: svgURL, atomically: true, encoding: .utf8)
            FileHandle.standardError.write(Data("SVG \(svg.count) chars -> \(svgURL.path)\n".utf8))
        } else {
            FileHandle.standardError.write(Data("SVG export returned nil\n".utf8))
        }
    }
}
