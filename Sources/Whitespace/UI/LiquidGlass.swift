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
            // Non-interactive: `.interactive()` reacts to the pointer with a
            // scale/bounce that reads as a jumpy animation on a static palette.
            // Pure native Liquid Glass — no added border or shadow (those read
            // as a black outline around the panel).
            glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
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
