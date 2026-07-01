import AppKit
import SwiftUI

/// Floating panel that can become key (so its text fields — e.g. tab rename —
/// accept typing) without fully activating the app away from the canvas.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Floating tool palette, shown only while editing. Uses an `NSHostingController`
/// so the panel sizes itself exactly to the SwiftUI content (no clipping, no
/// hard-coded width). Stays on the active Space (won't hover over fullscreen
/// apps) and is draggable by its background.
@MainActor
final class PaletteWindow {
    private let panel: NSPanel

    init(controller: CanvasController) {
        let host = NSHostingController(rootView: ToolPaletteView(controller: controller))

        panel = KeyablePanel(contentViewController: host)
        panel.styleMask = [.borderless, .nonactivatingPanel]
        panel.isMovableByWindowBackground = false   // static panel — drags stay with the controls (e.g. sliders)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.hasShadow = false   // the window shadow reads as a black outline
        panel.collectionBehavior = [.moveToActiveSpace, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
    }

    func show() {
        panel.layoutIfNeeded()
        let size = panel.frame.size
        // Dock to the left of whichever display the cursor is on.
        let loc = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) } ?? NSScreen.main
        if let screen {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.minX + 20,
                y: visible.midY - size.height / 2
            ))
        }
        panel.orderFront(nil)
    }

    func hide() { panel.orderOut(nil) }
}
