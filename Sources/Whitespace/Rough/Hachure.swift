import CoreGraphics
import Foundation

/// Scan-line hachure fill, ported from rough.js `scan-line-hachure`. Returns the
/// parallel fill line segments (in the polygon's own space) for a closed
/// polygon, at the given gap and angle. Each segment is later jittered via
/// `Rough.doubleLine(filling:)`.
enum Hachure {

    private final class Edge {
        let ymin: Double
        let ymax: Double
        var x: Double
        let islope: Double
        init(ymin: Double, ymax: Double, x: Double, islope: Double) {
            self.ymin = ymin; self.ymax = ymax; self.x = x; self.islope = islope
        }
    }

    static func lines(polygon: [CGPoint], gap rawGap: Double,
                      angleDegrees: Double) -> [(CGPoint, CGPoint)] {
        let angle = angleDegrees + 90
        var gap = rawGap
        gap = Swift.max(gap, 0.1)

        var poly = polygon
        if angle != 0 { rotate(&poly, degrees: angle) }
        var segs = scanLines(poly, gap: gap)
        if angle != 0 { rotateSegments(&segs, degrees: -angle) }
        return segs
    }

    private static func rotate(_ points: inout [CGPoint], degrees: Double) {
        let a = (.pi / 180) * degrees
        let c = cos(a), s = sin(a)
        for i in points.indices {
            let x = Double(points[i].x), y = Double(points[i].y)
            points[i] = CGPoint(x: x * c - y * s, y: x * s + y * c)
        }
    }

    private static func rotateSegments(_ segs: inout [(CGPoint, CGPoint)], degrees: Double) {
        let a = (.pi / 180) * degrees
        let c = cos(a), s = sin(a)
        func r(_ p: CGPoint) -> CGPoint {
            let x = Double(p.x), y = Double(p.y)
            return CGPoint(x: x * c - y * s, y: x * s + y * c)
        }
        for i in segs.indices { segs[i] = (r(segs[i].0), r(segs[i].1)) }
    }

    private static func scanLines(_ polygon: [CGPoint], gap: Double) -> [(CGPoint, CGPoint)] {
        var vertices = polygon
        guard let first = vertices.first, let last = vertices.last else { return [] }
        if first != last { vertices.append(first) }
        guard vertices.count > 2 else { return [] }

        var edges: [Edge] = []
        for i in 0..<(vertices.count - 1) {
            let p1 = vertices[i], p2 = vertices[i + 1]
            if p1.y != p2.y {
                let ymin = Swift.min(Double(p1.y), Double(p2.y))
                edges.append(Edge(
                    ymin: ymin,
                    ymax: Swift.max(Double(p1.y), Double(p2.y)),
                    x: Double(p1.y) == ymin ? Double(p1.x) : Double(p2.x),
                    islope: Double(p2.x - p1.x) / Double(p2.y - p1.y)
                ))
            }
        }
        edges.sort { e1, e2 in
            if e1.ymin != e2.ymin { return e1.ymin < e2.ymin }
            if e1.x != e2.x { return e1.x < e2.x }
            return e1.ymax < e2.ymax
        }
        guard !edges.isEmpty else { return [] }

        var lines: [(CGPoint, CGPoint)] = []
        var active: [Edge] = []
        var y = edges[0].ymin
        while !active.isEmpty || !edges.isEmpty {
            if !edges.isEmpty {
                var ix = -1
                for i in edges.indices {
                    if edges[i].ymin > y { break }
                    ix = i
                }
                if ix >= 0 {
                    active.append(contentsOf: edges[0...ix])
                    edges.removeFirst(ix + 1)
                }
            }
            active.removeAll { $0.ymax <= y }
            active.sort { $0.x < $1.x }
            if active.count > 1 {
                var i = 0
                while i < active.count {
                    let nexti = i + 1
                    if nexti >= active.count { break }
                    lines.append((
                        CGPoint(x: (active[i].x).rounded(), y: y),
                        CGPoint(x: (active[nexti].x).rounded(), y: y)
                    ))
                    i += 2
                }
            }
            y += gap
            for e in active { e.x += gap * e.islope }
        }
        return lines
    }
}
