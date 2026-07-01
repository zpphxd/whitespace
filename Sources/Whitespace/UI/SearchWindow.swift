import AppKit
import SwiftUI

/// A single cross-board search hit: which board it's on and the element to jump to.
struct SearchHit: Identifiable {
    let id = UUID()
    let boardIndex: Int
    let boardName: String
    let elementId: String
    let snippet: String
}

/// Key-capable panel so the search field accepts typing (and Esc closes).
private final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Borderless Liquid Glass panel hosting the cross-board search view. Mirrors
/// `PaletteWindow`/`ChartWheelWindow`: an `NSHostingController` in a floating
/// panel that can become key without stealing focus from the canvas.
@MainActor
final class SearchWindow {
    private var panel: NSPanel?
    private let query: (String) -> [SearchHit]
    private let onPick: (SearchHit) -> Void

    /// - Parameters:
    ///   - query: run a search string across all boards, returning ranked hits.
    ///   - onPick: switch to the hit's board and focus its element.
    init(query: @escaping (String) -> [SearchHit], onPick: @escaping (SearchHit) -> Void) {
        self.query = query
        self.onPick = onPick
    }

    func show() {
        if let panel { panel.makeKeyAndOrderFront(nil); return }   // reuse if already open

        let root = SearchView(
            query: query,
            onPick: { [weak self] hit in self?.onPick(hit); self?.close() },
            onCancel: { [weak self] in self?.close() })
        let host = NSHostingController(rootView: root)

        let p = SearchPanel(contentViewController: host)
        p.styleMask = [.borderless, .nonactivatingPanel]
        p.isFloatingPanel = true
        p.level = .modalPanel
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.collectionBehavior = [.moveToActiveSpace, .ignoresCycle, .fullScreenAuxiliary]

        // Center near the top of whichever display the cursor is on.
        let loc = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) } ?? NSScreen.main
        let size = NSSize(width: 460, height: 420)
        if let visible = screen?.visibleFrame {
            p.setFrame(NSRect(x: visible.midX - size.width / 2,
                              y: visible.maxY - size.height - 80,
                              width: size.width, height: size.height), display: true)
        }

        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        panel = p
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

/// Search field + results list, styled as a Liquid Glass card.
private struct SearchView: View {
    let query: (String) -> [SearchHit]
    let onPick: (SearchHit) -> Void
    let onCancel: () -> Void

    @State private var text = ""
    @State private var hits: [SearchHit] = []
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search all boards…", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($focused)
                .onSubmit { if let first = hits.first { onPick(first) } }
                .onChange(of: text) { new in hits = query(new) }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if hits.isEmpty {
                Text(text.isEmpty ? "Type to search text and links across every board."
                                  : "No matches.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(hits) { hit in
                            Button { onPick(hit) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.snippet)
                                        .font(.system(size: 14))
                                        .lineLimit(1)
                                    Text(hit.boardName)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 460, height: 420, alignment: .top)
        .liquidGlassPanel()
        .onAppear { focused = true }
        .onExitCommand { onCancel() }
    }
}
