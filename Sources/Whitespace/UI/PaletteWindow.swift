import AppKit
import SwiftUI

/// Floating panel that can become key (so its text fields — e.g. tab rename —
/// accept typing) without fully activating the app away from the canvas.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Where a chrome panel docks itself on the active display.
private enum PanelDock {
    /// Centered horizontally near the top of the screen (Excalidraw's toolbar).
    case topCenter
    /// Left edge, vertically centered (Excalidraw's property inspector).
    case leftMiddle
}

/// Shared base for the floating chrome panels. Uses an `NSHostingController` so
/// each panel sizes itself exactly to its SwiftUI content (no clipping, no
/// hard-coded width). Stays on the active Space (won't hover over fullscreen
/// apps). Subclasses only differ in the SwiftUI root and where they dock.
@MainActor
class ChromePanelWindow {
    let panel: NSPanel
    private let dock: PanelDock

    fileprivate init(dock: PanelDock, root: some View) {
        self.dock = dock
        let host = NSHostingController(rootView: root)

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
        // Dock on whichever display the cursor is on.
        let loc = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) } ?? NSScreen.main
        if let screen {
            let visible = screen.visibleFrame
            let origin: NSPoint
            switch dock {
            case .topCenter:
                origin = NSPoint(
                    x: visible.midX - size.width / 2,
                    y: visible.maxY - size.height - 20
                )
            case .leftMiddle:
                origin = NSPoint(
                    x: visible.minX + 20,
                    y: visible.midY - size.height / 2
                )
            }
            panel.setFrameOrigin(origin)
        }
        panel.orderFront(nil)
    }

    func hide() { panel.orderOut(nil) }
}

/// The centered top toolbar (tools row), shown only while editing.
@MainActor
final class TopToolbarWindow: ChromePanelWindow {
    init(controller: CanvasController) {
        super.init(dock: .topCenter, root: TopToolbarView(controller: controller))
    }
}

/// The left-docked style inspector (board tabs, gear, style controls), shown
/// only while editing.
@MainActor
final class InspectorWindow: ChromePanelWindow {
    init(controller: CanvasController) {
        super.init(dock: .leftMiddle, root: InspectorView(controller: controller))
    }
}
