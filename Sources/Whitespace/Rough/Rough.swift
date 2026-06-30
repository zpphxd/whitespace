import CoreGraphics
import Foundation

/// A single drawing operation produced by the rough geometry routines.
enum RoughOp {
    case move(CGPoint)
    case curve(c1: CGPoint, c2: CGPoint, to: CGPoint) // cubic bézier
}

/// Faithful Swift port of the rough.js renderer core: seeded jittered strokes,
/// poly-lines, and ellipse curve sampling. One instance per shape-generation so
/// the RNG advances across all of that shape's edges (matching rough.js).
final class Rough {
    private let o: RoughOptions
    private let rng: RoughRandom

    init(_ options: RoughOptions) {
        self.o = options
        self.rng = RoughRandom(seed: options.seed)
    }

    // MARK: Random offsets

    private func offset(_ min: Double, _ max: Double, _ gain: Double = 1) -> Double {
        o.roughness * gain * ((rng.next() * (max - min)) + min)
    }

    private func offsetOpt(_ x: Double, _ gain: Double = 1) -> Double {
        offset(-x, x, gain)
    }

    // MARK: Single jittered line (rough.js _line)

    private func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double,
                      move: Bool, overlay: Bool) -> [RoughOp] {
        let lengthSq = pow(x1 - x2, 2) + pow(y1 - y2, 2)
        let length = sqrt(lengthSq)

        var gain = 1.0
        if length < 200 { gain = 1 }
        else if length > 500 { gain = 0.4 }
        else { gain = (-0.0016668) * length + 1.233334 }

        var off = o.maxRandomnessOffset
        if (off * off * 100) > lengthSq { off = length / 10 }
        let halfOffset = off / 2
        let divergePoint = 0.2 + rng.next() * 0.2

        var midDispX = o.bowing * o.maxRandomnessOffset * (y2 - y1) / 200
        var midDispY = o.bowing * o.maxRandomnessOffset * (x1 - x2) / 200
        midDispX = offsetOpt(midDispX, gain)
        midDispY = offsetOpt(midDispY, gain)

        let pv = o.preserveVertices
        func randomHalf() -> Double { offsetOpt(halfOffset, gain) }
        func randomFull() -> Double { offsetOpt(off, gain) }

        var ops: [RoughOp] = []
        if move {
            if overlay {
                ops.append(.move(CGPoint(x: x1 + (pv ? 0 : randomHalf()),
                                         y: y1 + (pv ? 0 : randomHalf()))))
            } else {
                ops.append(.move(CGPoint(x: x1 + (pv ? 0 : randomFull()),
                                         y: y1 + (pv ? 0 : randomFull()))))
            }
        }

        let r: () -> Double = overlay ? randomHalf : randomFull
        let c1 = CGPoint(x: midDispX + x1 + (x2 - x1) * divergePoint + r(),
                         y: midDispY + y1 + (y2 - y1) * divergePoint + r())
        let c2 = CGPoint(x: midDispX + x1 + 2 * (x2 - x1) * divergePoint + r(),
                         y: midDispY + y1 + 2 * (y2 - y1) * divergePoint + r())
        let end = CGPoint(x: x2 + (pv ? 0 : r()), y: y2 + (pv ? 0 : r()))
        ops.append(.curve(c1: c1, c2: c2, to: end))
        return ops
    }

    /// Two overlapping jittered lines — the signature rough double-stroke.
    func doubleLine(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double,
                    filling: Bool = false) -> [RoughOp] {
        let single = filling ? o.disableMultiStrokeFill : o.disableMultiStroke
        let o1 = line(x1, y1, x2, y2, move: true, overlay: false)
        if single { return o1 }
        return o1 + line(x1, y1, x2, y2, move: true, overlay: true)
    }

    // MARK: Poly-lines (rectangle, diamond, line, arrow)

    func linearPath(_ points: [CGPoint], close: Bool) -> [RoughOp] {
        let n = points.count
        guard n > 1 else { return [] }
        if n == 2 {
            return doubleLine(points[0].x, points[0].y, points[1].x, points[1].y)
        }
        var ops: [RoughOp] = []
        for i in 0..<(n - 1) {
            ops += doubleLine(points[i].x, points[i].y, points[i + 1].x, points[i + 1].y)
        }
        if close {
            ops += doubleLine(points[n - 1].x, points[n - 1].y, points[0].x, points[0].y)
        }
        return ops
    }

    // MARK: Ellipse (rough.js _computeEllipsePoints + _curve)

    func ellipse(cx: Double, cy: Double, width: Double, height: Double) -> [RoughOp] {
        let psq = sqrt(.pi * 2 * sqrt((pow(width / 2, 2) + pow(height / 2, 2)) / 2))
        let stepCount = ceil(Swift.max(o.curveStepCount, (o.curveStepCount / sqrt(200)) * psq))
        let increment = (.pi * 2) / stepCount
        let curveFitRandomness = 1 - o.curveFitting
        let rx = abs(width / 2) + offsetOpt(abs(width / 2) * curveFitRandomness)
        let ry = abs(height / 2) + offsetOpt(abs(height / 2) * curveFitRandomness)

        let overlap = increment * offset(0.1, offset(0.4, 1))
        let ap1 = computeEllipsePoints(increment, cx, cy, rx, ry, offsetMul: 1, overlap: overlap)
        var ops = curve(ap1)
        if !o.disableMultiStroke && o.roughness != 0 {
            let ap2 = computeEllipsePoints(increment, cx, cy, rx, ry, offsetMul: 1.5, overlap: 0)
            ops += curve(ap2)
        }
        return ops
    }

    private func computeEllipsePoints(_ increment: Double, _ cx: Double, _ cy: Double,
                                      _ rx: Double, _ ry: Double,
                                      offsetMul: Double, overlap: Double) -> [CGPoint] {
        var all: [CGPoint] = []
        if o.roughness == 0 {
            let inc = increment / 4
            all.append(CGPoint(x: cx + rx * cos(-inc), y: cy + ry * sin(-inc)))
            var angle = 0.0
            while angle <= .pi * 2 {
                all.append(CGPoint(x: cx + rx * cos(angle), y: cy + ry * sin(angle)))
                angle += inc
            }
            all.append(CGPoint(x: cx + rx * cos(0), y: cy + ry * sin(0)))
            all.append(CGPoint(x: cx + rx * cos(inc), y: cy + ry * sin(inc)))
            return all
        }
        let radOffset = offsetOpt(0.5) - (.pi / 2)
        all.append(CGPoint(x: offsetOpt(offsetMul) + cx + 0.9 * rx * cos(radOffset - increment),
                           y: offsetOpt(offsetMul) + cy + 0.9 * ry * sin(radOffset - increment)))
        let endAngle = .pi * 2 + radOffset - 0.01
        var angle = radOffset
        while angle < endAngle {
            all.append(CGPoint(x: offsetOpt(offsetMul) + cx + rx * cos(angle),
                               y: offsetOpt(offsetMul) + cy + ry * sin(angle)))
            angle += increment
        }
        all.append(CGPoint(x: offsetOpt(offsetMul) + cx + rx * cos(radOffset + .pi * 2 + overlap * 0.5),
                           y: offsetOpt(offsetMul) + cy + ry * sin(radOffset + .pi * 2 + overlap * 0.5)))
        all.append(CGPoint(x: offsetOpt(offsetMul) + cx + 0.98 * rx * cos(radOffset + overlap),
                           y: offsetOpt(offsetMul) + cy + 0.98 * ry * sin(radOffset + overlap)))
        all.append(CGPoint(x: offsetOpt(offsetMul) + cx + 0.9 * rx * cos(radOffset + overlap * 0.5),
                           y: offsetOpt(offsetMul) + cy + 0.9 * ry * sin(radOffset + overlap * 0.5)))
        return all
    }

    /// rough.js _curve: a Catmull-Rom-ish spline through the points.
    private func curve(_ points: [CGPoint]) -> [RoughOp] {
        let n = points.count
        var ops: [RoughOp] = []
        let s = 1 - o.curveTightness
        if n > 3 {
            ops.append(.move(points[1]))
            var i = 1
            while i + 2 < n {
                let p0 = points[i - 1], p1 = points[i], p2 = points[i + 1], p3 = points[i + 2]
                let c1 = CGPoint(x: p1.x + (s * p2.x - s * p0.x) / 6,
                                 y: p1.y + (s * p2.y - s * p0.y) / 6)
                let c2 = CGPoint(x: p2.x + (s * p1.x - s * p3.x) / 6,
                                 y: p2.y + (s * p1.y - s * p3.y) / 6)
                ops.append(.curve(c1: c1, c2: c2, to: p2))
                i += 1
            }
        } else if n == 3 {
            ops.append(.move(points[1]))
            ops.append(.curve(c1: points[1], c2: points[2], to: points[2]))
        } else if n == 2 {
            ops += doubleLine(points[0].x, points[0].y, points[1].x, points[1].y)
        }
        return ops
    }

    // MARK: Op → CGPath

    static func path(from ops: [RoughOp]) -> CGPath {
        let path = CGMutablePath()
        var hasPoint = false
        for op in ops {
            switch op {
            case .move(let p):
                path.move(to: p)
                hasPoint = true
            case .curve(let c1, let c2, let to):
                if !hasPoint { path.move(to: c1); hasPoint = true }
                path.addCurve(to: to, control1: c1, control2: c2)
            }
        }
        return path
    }
}
