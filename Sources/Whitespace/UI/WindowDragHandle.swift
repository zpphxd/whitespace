import AppKit
import SwiftUI

/// A slim grab-bar that moves its window when dragged. The palette keeps
/// `isMovableByWindowBackground = false` (so dragging a slider adjusts the
/// slider, not the window) — this handle is the deliberate way to reposition it.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
        override func draw(_ dirtyRect: NSRect) {
            let pill = NSRect(x: bounds.midX - 18, y: bounds.midY - 2, width: 36, height: 4)
            NSColor.secondaryLabelColor.withAlphaComponent(0.45).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 2, yRadius: 2).fill()
        }
    }
}
