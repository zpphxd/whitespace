import CoreGraphics
import Foundation

/// Swift port of the `perfect-freehand` algorithm (Steve Ruiz), matching the
/// options Excalidraw uses for its pen tool: a variable-width, tapered outline
/// whose thickness tracks drawing speed. With no captured pressure (mouse /
/// trackpad), width is *simulated* from the spacing between points — points far
/// apart (fast) render thin, points close together (slow) render thick.
///
/// `stroke(...)` takes the raw input points and returns a closed outline polygon
/// to fill (not a centerline to stroke).
enum PerfectFreehand {

    // Excalidraw's freedraw options.
    static func stroke(_ input: [CGPoint], strokeWidth: Double) -> [CGPoint] {
        let size = max(strokeWidth * 4.25, 1)
        let pts = strokePoints(input, streamline: 0.5, size: size, isComplete: true)
        return outlinePoints(pts, size: size, thinning: 0.6, smoothing: 0.5,
                             simulatePressure: true, isComplete: true)
    }

    private static let rateOfPressureChange = 0.275
    private static let fixedPi = Double.pi + 0.0001

    // MARK: Vector helpers (on CGPoint)

    private static func add(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    private static func sub(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    private static func mul(_ a: CGPoint, _ s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
    private static func neg(_ a: CGPoint) -> CGPoint { CGPoint(x: -a.x, y: -a.y) }
    private static func per(_ a: CGPoint) -> CGPoint { CGPoint(x: a.y, y: -a.x) }
    private static func dpr(_ a: CGPoint, _ b: CGPoint) -> CGFloat { a.x * b.x + a.y * b.y }
    private static func dist2(_ a: CGPoint, _ b: CGPoint) -> CGFloat { pow(a.x - b.x, 2) + pow(a.y - b.y, 2) }
    private static func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
    private static func len(_ a: CGPoint) -> CGFloat { hypot(a.x, a.y) }
    private static func uni(_ a: CGPoint) -> CGPoint { let l = len(a); return l > 0 ? mul(a, 1 / l) : .zero }
    private static func lrp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint { add(a, mul(sub(b, a), t)) }
    private static func prj(_ a: CGPoint, _ b: CGPoint, _ c: CGFloat) -> CGPoint { add(a, mul(b, c)) }
    private static func rotAround(_ p: CGPoint, _ c: CGPoint, _ r: CGFloat) -> CGPoint {
        let s = sin(r), co = cos(r)
        let px = p.x - c.x, py = p.y - c.y
        return CGPoint(x: px * co - py * s + c.x, y: px * s + py * co + c.y)
    }

    // MARK: Stroke points (streamline + running length)

    private struct StrokePoint {
        var point: CGPoint
        var pressure: CGFloat
        var vector: CGPoint
        var distance: CGFloat
        var runningLength: CGFloat
    }

    private static func strokePoints(_ points: [CGPoint], streamline: Double,
                                     size: Double, isComplete: Bool) -> [StrokePoint] {
        guard !points.isEmpty else { return [] }
        let t = CGFloat(0.15 + (1 - streamline) * 0.85)

        var pts = points
        // Expand a 2-point stroke into 5 so tapered ends don't render as dashes.
        if pts.count == 2 {
            let last = pts[1]
            pts = [pts[0]]
            for i in 1..<5 { pts.append(lrp(points[0], last, CGFloat(i) / 4)) }
        }
        if pts.count == 1 { pts.append(add(pts[0], CGPoint(x: 1, y: 1))) }

        var result: [StrokePoint] = [
            StrokePoint(point: pts[0], pressure: 0.5, vector: CGPoint(x: 1, y: 1),
                        distance: 0, runningLength: 0)
        ]
        var hasReachedMinimumLength = false
        var runningLength: CGFloat = 0
        var prev = result[0]
        let maxI = pts.count - 1

        for i in 1..<pts.count {
            let point = (isComplete && i == maxI) ? pts[i] : lrp(prev.point, pts[i], t)
            if point == prev.point { continue }
            let d = dist(point, prev.point)
            runningLength += d
            if i < maxI && !hasReachedMinimumLength {
                if runningLength < CGFloat(size) { continue }
                hasReachedMinimumLength = true
            }
            let sp = StrokePoint(point: point, pressure: 0.5,
                                 vector: uni(sub(prev.point, point)),
                                 distance: d, runningLength: runningLength)
            result.append(sp)
            prev = sp
        }
        if result.count > 1 { result[0].vector = result[1].vector }
        return result
    }

    // MARK: Radius

    private static func easeOutSine(_ t: CGFloat) -> CGFloat { sin((t * .pi) / 2) }

    private static func strokeRadius(_ size: Double, _ thinning: Double, _ pressure: CGFloat) -> CGFloat {
        CGFloat(size) * easeOutSine(0.5 - CGFloat(thinning) * (0.5 - pressure))
    }

    // MARK: Outline

    private static func outlinePoints(_ points: [StrokePoint], size: Double, thinning: Double,
                                      smoothing: Double, simulatePressure: Bool,
                                      isComplete: Bool) -> [CGPoint] {
        guard !points.isEmpty, size > 0 else { return [] }
        let totalLength = points[points.count - 1].runningLength
        let minDistance = pow(CGFloat(size) * CGFloat(smoothing), 2)

        var leftPts: [CGPoint] = []
        var rightPts: [CGPoint] = []

        // Seed pressure from the average of the first several points so strokes
        // don't start fat.
        var prevPressure: CGFloat = points[0].pressure
        for cur in points.prefix(10) {
            var pressure = cur.pressure
            if simulatePressure {
                let sp = min(1, cur.distance / CGFloat(size))
                let rp = min(1, 1 - sp)
                pressure = min(1, prevPressure + (rp - prevPressure) * (sp * CGFloat(rateOfPressureChange)))
            }
            prevPressure = (prevPressure + pressure) / 2
        }

        var radius = strokeRadius(size, thinning, points[points.count - 1].pressure)
        var firstRadius: CGFloat?
        var prevVector = points[0].vector
        var pl = points[0].point
        var pr = points[0].point
        var tl = pl
        var tr = pr
        var isPrevPointSharpCorner = false

        for i in 0..<points.count {
            var pressure = points[i].pressure
            let point = points[i].point
            let vector = points[i].vector
            let distance = points[i].distance
            let runningLength = points[i].runningLength

            // Trim noise off the tail.
            if i < points.count - 1 && totalLength - runningLength < 3 { continue }

            if thinning != 0 {
                if simulatePressure {
                    let sp = min(1, distance / CGFloat(size))
                    let rp = min(1, 1 - sp)
                    pressure = min(1, prevPressure + (rp - prevPressure) * (sp * CGFloat(rateOfPressureChange)))
                }
                radius = strokeRadius(size, thinning, pressure)
            } else {
                radius = CGFloat(size) / 2
            }
            if firstRadius == nil { firstRadius = radius }
            radius = max(0.01, radius)

            let nextVector = (i < points.count - 1 ? points[i + 1] : points[i]).vector
            let nextDpr = i < points.count - 1 ? dpr(vector, nextVector) : 1.0
            let prevDpr = dpr(vector, prevVector)
            let isPointSharpCorner = prevDpr < 0 && !isPrevPointSharpCorner
            let isNextPointSharpCorner = nextDpr < 0

            if isPointSharpCorner || isNextPointSharpCorner {
                let offset = mul(per(prevVector), radius)
                var t: CGFloat = 0
                let step: CGFloat = 1.0 / 13.0
                while t <= 1 {
                    tl = rotAround(sub(point, offset), point, CGFloat(fixedPi) * t)
                    leftPts.append(tl)
                    tr = rotAround(add(point, offset), point, CGFloat(fixedPi) * -t)
                    rightPts.append(tr)
                    t += step
                }
                pl = tl; pr = tr
                if isNextPointSharpCorner { isPrevPointSharpCorner = true }
                continue
            }
            isPrevPointSharpCorner = false

            if i == points.count - 1 {
                let offset = mul(per(vector), radius)
                leftPts.append(sub(point, offset))
                rightPts.append(add(point, offset))
                continue
            }

            let offset = mul(per(lrp(nextVector, vector, nextDpr)), radius)
            tl = sub(point, offset)
            if i <= 1 || dist2(pl, tl) > minDistance { leftPts.append(tl); pl = tl }
            tr = add(point, offset)
            if i <= 1 || dist2(pr, tr) > minDistance { rightPts.append(tr); pr = tr }

            prevPressure = pressure
            prevVector = vector
        }

        // Caps.
        let firstPoint = points[0].point
        let lastPoint = points.count > 1 ? points[points.count - 1].point : add(points[0].point, CGPoint(x: 1, y: 1))
        var startCap: [CGPoint] = []
        var endCap: [CGPoint] = []

        if points.count == 1 {
            // A dot for a tap.
            let r = firstRadius ?? radius
            let start = prj(firstPoint, uni(per(sub(firstPoint, lastPoint))), -r)
            var dot: [CGPoint] = []
            var t: CGFloat = 1.0 / 13.0
            let step: CGFloat = 1.0 / 13.0
            while t <= 1 { dot.append(rotAround(start, firstPoint, CGFloat(fixedPi) * 2 * t)); t += step }
            return dot
        }

        // Round start cap.
        if let r0 = rightPts.first {
            var t: CGFloat = 1.0 / 13.0
            let step: CGFloat = 1.0 / 13.0
            while t <= 1 { startCap.append(rotAround(r0, firstPoint, CGFloat(fixedPi) * t)); t += step }
        }
        // Round end cap (a full turn-and-a-half so sharp end turns don't invert).
        let direction = per(neg(points[points.count - 1].vector))
        let endStart = prj(lastPoint, direction, radius)
        var te: CGFloat = 0
        let stepE: CGFloat = 1.0 / 29.0
        while te < 1 { endCap.append(rotAround(endStart, lastPoint, CGFloat(fixedPi) * 3 * te)); te += stepE }

        return leftPts + endCap + rightPts.reversed() + startCap
    }

    // MARK: Outline → smooth CGPath (quadratic through midpoints, as Excalidraw does)

    static func path(from outline: [CGPoint]) -> CGPath {
        let p = CGMutablePath()
        guard outline.count > 1 else { return p }
        if outline.count < 4 {
            p.addLines(between: outline); p.closeSubpath(); return p
        }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        let n = outline.count
        p.move(to: mid(outline[n - 1], outline[0]))
        for i in 0..<n {
            let a = outline[i], b = outline[(i + 1) % n]
            p.addQuadCurve(to: mid(a, b), control: a)
        }
        p.closeSubpath()
        return p
    }
}
