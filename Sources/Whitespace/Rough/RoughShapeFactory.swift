import CoreGraphics
import Foundation

/// A render-ready rough shape: a stroked outline plus an optional fill that is
/// either a solid region (fill it) or sketchy hachure lines (stroke them).
struct RoughDrawable {
    var outline: CGPath
    var fill: CGPath?
    var fillIsSolid: Bool
    var strokeWidth: CGFloat
    var fillWeight: CGFloat
}

/// Style inputs shared by the rough primitives.
struct RoughStyle {
    var strokeWidth: Double
    var roughness: Double
    var fillStyle: FillStyle
    var strokeStyle: StrokeStyle
    var seed: Int
    var hasFill: Bool
}

/// Builds `RoughDrawable`s from geometry + style. One `Rough` engine per shape so
/// the seeded RNG advances across outline-then-fill exactly as rough.js does.
enum RoughShapeFactory {

    private static func options(_ s: RoughStyle) -> RoughOptions {
        var o = RoughOptions()
        o.seed = s.seed
        o.roughness = s.roughness
        o.strokeWidth = s.strokeWidth
        o.fillWeight = s.strokeWidth / 2
        o.hachureGap = s.strokeWidth * 4
        o.disableMultiStroke = s.strokeStyle != .solid
        // Excalidraw keeps vertices crisp except at the highest roughness.
        o.preserveVertices = s.roughness < 2
        return o
    }

    static func rectangle(_ rect: CGRect, style: RoughStyle) -> RoughDrawable {
        let pts = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
        ]
        return polygon(pts, style: style)
    }

    static func diamond(_ rect: CGRect, style: RoughStyle) -> RoughDrawable {
        let pts = [
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.midY),
        ]
        return polygon(pts, style: style)
    }

    static func polygon(_ pts: [CGPoint], style: RoughStyle) -> RoughDrawable {
        let o = options(style)
        let rough = Rough(o)
        let outline = Rough.path(from: rough.linearPath(pts, close: true))
        let fill = makeFill(polygon: pts, rough: rough, o: o, style: style)
        return RoughDrawable(outline: outline, fill: fill.path, fillIsSolid: fill.solid,
                             strokeWidth: o.strokeWidth, fillWeight: o.fillWeight)
    }

    static func ellipse(_ rect: CGRect, style: RoughStyle) -> RoughDrawable {
        let o = options(style)
        let rough = Rough(o)
        let outline = Rough.path(from: rough.ellipse(
            cx: rect.midX, cy: rect.midY, width: rect.width, height: rect.height))
        // Fill boundary: sample the ellipse perimeter as a polygon.
        let boundary = ellipsePolygon(rect)
        let fill = makeFill(polygon: boundary, rough: rough, o: o, style: style,
                            solidPath: CGPath(ellipseIn: rect, transform: nil))
        return RoughDrawable(outline: outline, fill: fill.path, fillIsSolid: fill.solid,
                             strokeWidth: o.strokeWidth, fillWeight: o.fillWeight)
    }

    static func line(_ pts: [CGPoint], style: RoughStyle) -> RoughDrawable {
        let o = options(style)
        let rough = Rough(o)
        let outline = Rough.path(from: rough.linearPath(pts, close: false))
        return RoughDrawable(outline: outline, fill: nil, fillIsSolid: false,
                             strokeWidth: o.strokeWidth, fillWeight: o.fillWeight)
    }

    // MARK: Fill

    private static func makeFill(polygon: [CGPoint], rough: Rough, o: RoughOptions,
                                 style: RoughStyle,
                                 solidPath: CGPath? = nil) -> (path: CGPath?, solid: Bool) {
        guard style.hasFill else { return (nil, false) }
        switch style.fillStyle {
        case .solid:
            let p = CGMutablePath()
            if let solidPath { p.addPath(solidPath) }
            else { p.addLines(between: polygon); p.closeSubpath() }
            return (p, true)
        case .hachure, .zigzag:
            return (hachureFill(polygon: polygon, rough: rough, o: o, cross: false), false)
        case .crossHatch:
            return (hachureFill(polygon: polygon, rough: rough, o: o, cross: true), false)
        }
    }

    private static func hachureFill(polygon: [CGPoint], rough: Rough, o: RoughOptions,
                                    cross: Bool) -> CGPath {
        var ops: [RoughOp] = []
        let segs = Hachure.lines(polygon: polygon, gap: o.hachureGap, angleDegrees: o.hachureAngle)
        for s in segs {
            ops += rough.doubleLine(Double(s.0.x), Double(s.0.y),
                                    Double(s.1.x), Double(s.1.y), filling: true)
        }
        if cross {
            let segs2 = Hachure.lines(polygon: polygon, gap: o.hachureGap,
                                      angleDegrees: o.hachureAngle + 90)
            for s in segs2 {
                ops += rough.doubleLine(Double(s.0.x), Double(s.0.y),
                                        Double(s.1.x), Double(s.1.y), filling: true)
            }
        }
        return Rough.path(from: ops)
    }

    private static func ellipsePolygon(_ rect: CGRect) -> [CGPoint] {
        let cx = Double(rect.midX), cy = Double(rect.midY)
        let rx = Double(rect.width) / 2, ry = Double(rect.height) / 2
        let n = 36
        return (0..<n).map { i in
            let a = (Double(i) / Double(n)) * .pi * 2
            return CGPoint(x: cx + rx * cos(a), y: cy + ry * sin(a))
        }
    }
}
