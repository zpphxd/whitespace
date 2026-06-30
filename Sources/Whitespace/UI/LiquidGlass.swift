import AppKit
import SwiftUI

/// Translucent behind-window blur — used only as the pre-Tahoe fallback when the
/// native Liquid Glass API isn't available.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var cornerRadius: CGFloat = 26

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.layer?.cornerRadius = cornerRadius
    }
}

extension View {
    /// Real Liquid Glass on macOS 26+ (translucent, refractive, self-lit rim via
    /// the OS). Falls back to a translucent blurred panel on earlier systems.
    /// Deliberately minimal — no opaque tint to smother the effect.
    @ViewBuilder
    func liquidGlassPanel(cornerRadius: CGFloat = 26) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(
                .regular.interactive(),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            // Keep the panel defined over ANY backdrop (incl. a flat white board,
            // where pure glass would wash out and look like it vanished): a
            // hairline edge plus a soft drop shadow.
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 8)
        } else {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            background { VisualEffectBackground(material: .hudWindow, cornerRadius: cornerRadius) }
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.5), .white.opacity(0.12)],
                            startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.3), radius: 22, x: 0, y: 12)
        }
    }
}
