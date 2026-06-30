import SwiftUI

/// A compact segmented control whose options render as custom icon views.
struct IconSegment<Value: Hashable>: View {
    let options: [(value: Value, icon: AnyView)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 5) {
            ForEach(options.indices, id: \.self) { i in
                let opt = options[i]
                Button { selection = opt.value } label: {
                    opt.icon
                        .frame(width: 30, height: 24)
                        .background(selection == opt.value
                                    ? Color(hex: 0x6965db).opacity(0.28) : Color.gray.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A horizontal line drawn solid / dashed / dotted.
struct StrokeStyleGlyph: View {
    let style: StrokeStyle
    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            p.move(to: CGPoint(x: 5, y: size.height / 2))
            p.addLine(to: CGPoint(x: size.width - 5, y: size.height / 2))
            let dash: [CGFloat] = style == .dashed ? [4, 3] : (style == .dotted ? [0.5, 3] : [])
            ctx.stroke(p, with: .color(.primary), style: .init(lineWidth: 2, lineCap: .round, dash: dash))
        }
    }
}

/// Straight vs elbow arrow.
struct ArrowTypeGlyph: View {
    let elbow: Bool
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            var p = Path()
            let tip: CGPoint
            if elbow {
                p.move(to: CGPoint(x: 5, y: 6))
                p.addLine(to: CGPoint(x: w / 2, y: 6))
                p.addLine(to: CGPoint(x: w / 2, y: h - 6))
                p.addLine(to: CGPoint(x: w - 7, y: h - 6))
                tip = CGPoint(x: w - 7, y: h - 6)
            } else {
                p.move(to: CGPoint(x: 5, y: h - 6))
                p.addLine(to: CGPoint(x: w - 7, y: 6))
                tip = CGPoint(x: w - 7, y: 6)
            }
            ctx.stroke(p, with: .color(.primary), style: .init(lineWidth: 2, lineCap: .round, lineJoin: .round))
            var head = Path()
            head.move(to: CGPoint(x: tip.x - 5, y: tip.y))
            head.addLine(to: tip)
            head.addLine(to: CGPoint(x: tip.x, y: tip.y + (elbow ? -5 : 5)))
            ctx.stroke(head, with: .color(.primary), style: .init(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

/// A line ending in the given arrowhead type.
struct ArrowheadGlyph: View {
    let type: String
    var body: some View {
        Canvas { ctx, size in
            let midY = size.height / 2
            let tipX = size.width - 6
            var line = Path()
            line.move(to: CGPoint(x: 4, y: midY))
            line.addLine(to: CGPoint(x: type == "none" ? size.width - 4 : tipX - 2, y: midY))
            ctx.stroke(line, with: .color(.primary), style: .init(lineWidth: 2, lineCap: .round))
            let tip = CGPoint(x: tipX, y: midY)
            switch type {
            case "arrow":
                var h = Path()
                h.move(to: CGPoint(x: tip.x - 6, y: midY - 5)); h.addLine(to: tip)
                h.addLine(to: CGPoint(x: tip.x - 6, y: midY + 5))
                ctx.stroke(h, with: .color(.primary), style: .init(lineWidth: 2, lineCap: .round, lineJoin: .round))
            case "triangle":
                var h = Path()
                h.move(to: CGPoint(x: tip.x - 7, y: midY - 5)); h.addLine(to: tip)
                h.addLine(to: CGPoint(x: tip.x - 7, y: midY + 5)); h.closeSubpath()
                ctx.fill(h, with: .color(.primary))
            case "dot":
                ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 4, y: midY - 4, width: 8, height: 8)), with: .color(.primary))
            case "bar":
                var h = Path()
                h.move(to: CGPoint(x: tip.x, y: midY - 6)); h.addLine(to: CGPoint(x: tip.x, y: midY + 6))
                ctx.stroke(h, with: .color(.primary), style: .init(lineWidth: 2, lineCap: .round))
            default: break // none
            }
        }
    }
}
