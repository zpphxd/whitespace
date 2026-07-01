import AppKit
import SwiftUI

/// Key-capable panel so the wheel can receive Esc and clicks.
private final class WheelPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Presents the full-screen `ChartWheel` chooser and reports the pick (or nil
/// on cancel) exactly once.
@MainActor
final class ChartWheelWindow {
    private var panel: NSPanel?
    private var completion: ((String?) -> Void)?

    func present(options: [ChartWheelOption], completion: @escaping (String?) -> Void) {
        finish(nil)   // clear any stale wheel first
        self.completion = completion

        let root = ChartWheel(
            options: options,
            onSelect: { [weak self] type in self?.finish(type) },
            onCancel: { [weak self] in self?.finish(nil) })
        let host = NSHostingController(rootView: root)

        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let p = WheelPanel(contentViewController: host)
        p.styleMask = [.borderless, .nonactivatingPanel]
        p.isFloatingPanel = true
        p.level = .modalPanel
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.collectionBehavior = [.moveToActiveSpace, .ignoresCycle, .fullScreenAuxiliary]
        p.setFrame(screenFrame, display: true)

        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        panel = p
    }

    private func finish(_ type: String?) {
        guard let c = completion else { panel?.orderOut(nil); panel = nil; return }
        completion = nil
        panel?.orderOut(nil); panel = nil
        c(type)
    }
}
