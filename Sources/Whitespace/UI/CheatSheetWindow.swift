import AppKit
import SwiftUI

private final class CheatKeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Full-screen Liquid Glass overlay listing every keyboard shortcut. Opened by
/// "?" (and the gear menu); dismissed by Esc, a click outside, or pressing "?"
/// again.
@MainActor
final class CheatSheetWindow {
    private var panel: NSPanel?

    func toggle() { panel == nil ? show() : hide() }

    func show() {
        hide()
        let host = NSHostingController(rootView: CheatSheetView(onClose: { [weak self] in self?.hide() }))
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let p = CheatKeyPanel(contentViewController: host)
        p.styleMask = [.borderless, .nonactivatingPanel]
        p.isFloatingPanel = true
        p.level = .modalPanel
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.collectionBehavior = [.moveToActiveSpace, .ignoresCycle, .fullScreenAuxiliary]
        p.setFrame(screen, display: true)
        p.appearance = NSAppearance(named: .aqua)
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        panel = p
    }

    func hide() { panel?.orderOut(nil); panel = nil }
}

struct CheatSheetView: View {
    let onClose: () -> Void

    private typealias Row = (keys: String, label: String)
    private let tools: [Row] = [
        ("V", "Select"), ("H", "Hand / pan"), ("R", "Rectangle"), ("O", "Ellipse"),
        ("D", "Diamond"), ("A", "Arrow"), ("L", "Line"), ("P", "Draw"), ("T", "Text"), ("E", "Eraser"),
    ]
    private let edit: [Row] = [
        ("⌘Z", "Undo"), ("⇧⌘Z", "Redo"), ("⌘C", "Copy"), ("⌘X", "Cut"), ("⌘V", "Paste"),
        ("⌘A", "Select all"), ("⌫", "Delete"), ("⌘G", "Group"), ("⇧⌘G", "Ungroup"),
        ("↩", "Edit text / label"), ("esc", "Deselect"),
    ]
    private let view: [Row] = [
        ("⇧1", "Zoom to fit"), ("⌘0", "Reset zoom"), ("⌘ +", "Zoom in"), ("⌘ −", "Zoom out"),
        ("⌘ scroll", "Zoom"), ("space-drag", "Pan"), ("⌥ arrows", "Pan"),
    ]
    private let create: [Row] = [
        ("⌘K", "Link a URL"), ("/", "Link a file"),
        ("paste data", "Chart wheel"), ("right-click link", "→ QR code"),
    ]
    // The edit / panel toggles reflect whatever they're currently bound to.
    private var app: [Row] {
        [("⌘F", "Search boards"),
         (Shortcut.display(keyCode: Settings.saveKeyCode, mods: Settings.saveMods), "Save now"),
         (Shortcut.display(keyCode: Settings.newBoardKeyCode, mods: Settings.newBoardMods), "New board"),
         (Shortcut.display(keyCode: Settings.editKeyCode, mods: Settings.editMods), "Toggle edit mode"),
         (Shortcut.display(keyCode: Settings.paletteKeyCode, mods: Settings.paletteMods), "Toggle panels"),
         ("?", "This cheat sheet")]
    }
    private let cells: [Row] = [
        ("⌘↩", "Run cell"), ("⇧⌘↩", "Run graph"),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
            card
            Button(action: onClose) { EmptyView() }
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0).opacity(0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Keyboard Shortcuts").font(.system(size: 18, weight: .bold))
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            HStack(alignment: .top, spacing: 34) {
                VStack(alignment: .leading, spacing: 18) { section("Tools", tools); section("Cells", cells) }
                VStack(alignment: .leading, spacing: 18) { section("Edit", edit) }
                VStack(alignment: .leading, spacing: 18) { section("View", view); section("Create", create); section("App", app) }
            }
            Text("Edit & panel toggles are configurable — gear ▸ Configure Hotkeys.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 740)
        .liquidGlassPanel(cornerRadius: 22)
        .contentShape(Rectangle())   // clicks on the card don't dismiss
    }

    private func section(_ title: String, _ rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 1)
            ForEach(rows, id: \.keys) { row in
                HStack(spacing: 9) {
                    keyChip(row.keys)
                    Text(row.label).font(.system(size: 12.5))
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func keyChip(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .frame(minWidth: 60, alignment: .leading)
            .background(Color.primary.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }
}
