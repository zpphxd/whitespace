import SwiftUI

/// One selectable wedge in the paste-to-chart wheel.
struct ChartWheelOption {
    let type: String
    let title: String
}

/// A GTA-style radial chooser rendered in Liquid Glass. Hover a wedge to
/// preview it in the hub; click to choose. Esc or a click outside cancels.
struct ChartWheel: View {
    let options: [ChartWheelOption]
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    @State private var hovered: Int?

    private let inner: CGFloat = 94
    private let outer: CGFloat = 190
    private let gapDeg: Double = 2.2
    private var discSize: CGFloat { outer * 2 + 26 }

    var body: some View {
        ZStack {
            Color.black.opacity(0.26)
                .contentShape(Rectangle())
                .onTapGesture { onCancel() }
            wheel
                .frame(width: discSize, height: discSize)
                .overlay(interaction)          // one tracking layer drives hover + click
            // Invisible button so Esc (cancelAction) dismisses the wheel.
            Button(action: onCancel) { EmptyView() }
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    /// A single transparent layer over the disc: cursor *angle* picks the wedge
    /// (GTA-style), so moving anywhere in the ring highlights instantly and a
    /// click selects the pointed-at wedge — no hover-first required.
    private var interaction: some View {
        Color.clear
            .contentShape(Circle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc): hovered = wedgeIndex(at: loc)
                case .ended: hovered = nil
                }
            }
            .gesture(DragGesture(minimumDistance: 0).onEnded { g in
                if let i = wedgeIndex(at: g.location) { onSelect(options[i].type) } else { onCancel() }
            })
    }

    /// Wedge under a point in disc-local coordinates, or nil (dead center / rim).
    private func wedgeIndex(at loc: CGPoint) -> Int? {
        let n = max(options.count, 1)
        let seg = 360.0 / Double(n)
        let dx = Double(loc.x - discSize / 2), dy = Double(loc.y - discSize / 2)
        let r = (dx * dx + dy * dy).squareRoot()
        guard r >= Double(inner) * 0.42, r <= Double(outer) else { return nil }
        let deg = atan2(dy, dx) * 180 / .pi
        let raw = ((deg + 90) / seg).rounded()
        return ((Int(raw) % n) + n) % n
    }

    private var wheel: some View {
        let n = max(options.count, 1)
        let seg = 360.0 / Double(n)
        return ZStack {
            Circle().fill(Color.white.opacity(0.05))
                .frame(width: discSize, height: discSize)
                .liquidGlassPanel(cornerRadius: discSize / 2)

            ForEach(Array(options.enumerated()), id: \.offset) { i, opt in
                let start = Angle(degrees: Double(i) * seg - 90 - seg / 2 + gapDeg)
                let end = Angle(degrees: Double(i) * seg - 90 + seg / 2 - gapDeg)
                let hot = hovered == i
                let sector = AnnularSector(startAngle: start, endAngle: end,
                                           innerRadius: inner, outerRadius: outer)
                sector
                    .fill(hot ? Color(hex: 0x6965db).opacity(0.70) : Color.white.opacity(0.10))
                    .overlay(sector.stroke(Color.white.opacity(hot ? 0.5 : 0.22), lineWidth: 1))

                WheelIcon(type: opt.type, accent: hot)
                    .frame(width: 42, height: 42)
                    .offset(iconOffset(i, seg: seg))
            }

            hub.frame(width: inner * 2 - 12, height: inner * 2 - 12)
        }
        .frame(width: discSize, height: discSize)
        .allowsHitTesting(false)               // the interaction overlay handles input
    }

    private func iconOffset(_ i: Int, seg: Double) -> CGSize {
        let a = (Double(i) * seg - 90) * .pi / 180
        let r = Double((inner + outer) / 2)
        return CGSize(width: cos(a) * r, height: sin(a) * r)
    }

    private var hub: some View {
        VStack(spacing: 7) {
            if let h = hovered, h < options.count {
                WheelIcon(type: options[h].type, accent: false).frame(width: 36, height: 36)
                Text(options[h].title).font(.system(size: 15, weight: .semibold))
            } else {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 26)).foregroundStyle(.secondary)
                Text("Choose a chart").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
    }
}

/// A tiny custom-drawn preview of each chart type (no SF Symbol dependency).
struct WheelIcon: View {
    let type: String
    var accent = false

    var body: some View {
        let color: Color = accent ? .white : .primary
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let pad: CGFloat = 5
            let shade = GraphicsContext.Shading.color(color)
            func px(_ t: CGFloat) -> CGFloat { pad + t * (w - 2 * pad) }
            func py(_ t: CGFloat) -> CGFloat { h - pad - t * (h - 2 * pad) }   // t=0 → bottom

            switch type {
            case "hbar":
                let vals: [CGFloat] = [0.6, 1.0, 0.4]
                let bh = (h - 2 * pad) / CGFloat(vals.count) * 0.62
                for (i, v) in vals.enumerated() {
                    let cy = pad + (CGFloat(i) + 0.5) / CGFloat(vals.count) * (h - 2 * pad)
                    ctx.fill(Path(roundedRect: CGRect(x: pad, y: cy - bh / 2, width: v * (w - 2 * pad), height: bh), cornerRadius: 1.5), with: shade)
                }
            case "line", "step":
                let ys: [CGFloat] = type == "step" ? [0.72, 0.72, 0.42, 0.42, 0.15] : [0.75, 0.42, 0.6, 0.2]
                var p = Path()
                for (i, v) in ys.enumerated() {
                    let x = px(CGFloat(i) / CGFloat(ys.count - 1)), y = py(v)
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                    else if type == "step" {
                        p.addLine(to: CGPoint(x: x, y: py(ys[i - 1]))); p.addLine(to: CGPoint(x: x, y: y))
                    } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
                ctx.stroke(p, with: shade, style: SwiftUI.StrokeStyle(lineWidth: 2, lineCap: CGLineCap.round, lineJoin: CGLineJoin.round))
                if type == "line" {
                    for (i, v) in ys.enumerated() {
                        let x = px(CGFloat(i) / CGFloat(ys.count - 1)), y = py(v)
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4)), with: shade)
                    }
                }
            case "scatter":
                for (tx, ty) in [(0.2, 0.68), (0.44, 0.32), (0.6, 0.58), (0.82, 0.22), (0.34, 0.5)] as [(CGFloat, CGFloat)] {
                    ctx.fill(Path(ellipseIn: CGRect(x: px(tx) - 2.6, y: py(ty) - 2.6, width: 5.2, height: 5.2)), with: shade)
                }
            case "lollipop":
                let ys: [CGFloat] = [0.55, 0.3, 0.8, 0.45]
                for (i, v) in ys.enumerated() {
                    let x = px((CGFloat(i) + 0.5) / CGFloat(ys.count))
                    var st = Path(); st.move(to: CGPoint(x: x, y: py(0))); st.addLine(to: CGPoint(x: x, y: py(v)))
                    ctx.stroke(st, with: shade, style: SwiftUI.StrokeStyle(lineWidth: 1.5))
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 2.6, y: py(v) - 2.6, width: 5.2, height: 5.2)), with: shade)
                }
            case "text":
                let ws: [CGFloat] = [0.9, 0.7, 0.85, 0.5]
                for (i, ww) in ws.enumerated() {
                    let y = pad + (CGFloat(i) + 0.5) / CGFloat(ws.count) * (h - 2 * pad)
                    ctx.fill(Path(roundedRect: CGRect(x: pad, y: y - 1.4, width: ww * (w - 2 * pad), height: 2.8), cornerRadius: 1.4), with: shade)
                }
                return
            default: // bar
                let vals: [CGFloat] = [0.5, 0.85, 0.35, 1.0]
                let bw = (w - 2 * pad) / CGFloat(vals.count) * 0.6
                for (i, v) in vals.enumerated() {
                    let cx = px((CGFloat(i) + 0.5) / CGFloat(vals.count))
                    ctx.fill(Path(roundedRect: CGRect(x: cx - bw / 2, y: py(v), width: bw, height: py(0) - py(v)), cornerRadius: 1.5), with: shade)
                }
            }

            // Baseline axis (chart types only).
            var axis = Path(); axis.move(to: CGPoint(x: pad, y: py(0))); axis.addLine(to: CGPoint(x: w - pad, y: py(0)))
            ctx.stroke(axis, with: shade, style: SwiftUI.StrokeStyle(lineWidth: 1))
        }
    }
}

/// One annular (ring) sector — a wedge of the wheel.
struct AnnularSector: Shape {
    var startAngle: Angle
    var endAngle: Angle
    var innerRadius: CGFloat
    var outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.addArc(center: c, radius: outerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        p.addLine(to: CGPoint(x: c.x + innerRadius * cos(CGFloat(endAngle.radians)),
                              y: c.y + innerRadius * sin(CGFloat(endAngle.radians))))
        p.addArc(center: c, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)
        p.closeSubpath()
        return p
    }
}
