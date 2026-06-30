import SwiftUI

/// Floating tool palette + inspector. Edits `CanvasController.style` and pushes
/// changes onto the current selection.
struct ToolPaletteView: View {
    @ObservedObject var controller: CanvasController
    @State private var editingTab: Int?
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool

    private let strokeSwatches = ["#1e1e1e", "#e03131", "#2f9e44", "#1971c2", "#f08c00"]
    private let bgSwatches = ["transparent", "#ffc9c9", "#b2f2bb", "#a5d8ff", "#ffec99"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            tabBar
            Divider()
            tools
            Divider()
            inspector
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(width: 332)
        .liquidGlassPanel(cornerRadius: 24)
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(Array(controller.tabs.enumerated()), id: \.offset) { i, name in
                    if editingTab == i {
                        TextField("Name", text: $renameText, onCommit: { commitRename(i) })
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                            .frame(width: 96)
                            .focused($renameFocused)
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { renameFocused = true }
                            }
                            .onExitCommand { editingTab = nil }
                    } else {
                        let active = i == controller.currentTab
                        HStack(spacing: 5) {
                            Text(name)
                                .font(.system(size: 11, weight: active ? .semibold : .regular))
                                .lineLimit(1)
                            if active {
                                Button { renameText = name; editingTab = i } label: {
                                    Image(systemName: "pencil").font(.system(size: 9))
                                }
                                .buttonStyle(.plain)
                                .help("Rename board")
                                if controller.tabs.count > 1 {
                                    Button { controller.closeTab?(i) } label: {
                                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Delete board")
                                }
                            }
                        }
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(active ? Color(hex: 0x6965db) : Color.white.opacity(0.14))
                        .foregroundStyle(active ? .white : .primary)
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                        // Single tap only — no double-tap gesture competing, so
                        // switching is instant. Rename via right-click.
                        .onTapGesture { controller.selectTab?(i) }
                        .contextMenu {
                            Button("Rename") { renameText = name; editingTab = i }
                            if controller.tabs.count > 1 {
                                Button("Delete", role: .destructive) { controller.closeTab?(i) }
                            }
                        }
                    }
                }
                Button { controller.addTab?() } label: {
                    Image(systemName: "plus").frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("New board")
            }
            .padding(.vertical, 1)
        }
        .frame(height: 26)
    }

    private var tools: some View {
        HStack(spacing: 2) {
            ForEach(Tool.allCases, id: \.self) { tool in
                Button {
                    controller.tool = tool
                } label: {
                    Image(systemName: tool.symbol)
                        .frame(width: 25, height: 26)
                        .background(controller.tool == tool ? Color(hex: 0x6965db) : .clear)
                        .foregroundStyle(controller.tool == tool ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help("\(tool.rawValue.capitalized) (\(String(tool.key)))")
            }
            Divider().frame(height: 18).padding(.horizontal, 1)
            Button { controller.linkFileAction?() } label: {
                Image(systemName: "paperclip")
                    .frame(width: 25, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .help("Link a file or folder")
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("Stroke") {
                swatchRow(strokeSwatches, selected: controller.style.strokeColor) {
                    controller.style.strokeColor = $0; apply()
                }
            }
            section("Background") {
                swatchRow(bgSwatches, selected: controller.style.backgroundColor) {
                    controller.style.backgroundColor = $0; apply()
                }
            }
            section("Fill") {
                Picker("", selection: Binding<FillStyle>(
                    get: { controller.style.fillStyle },
                    set: { controller.style.fillStyle = $0; apply() })) {
                    ForEach(FillStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
            }
            section("Stroke width") {
                Slider(value: Binding(
                    get: { controller.style.strokeWidth },
                    set: { controller.style.strokeWidth = $0; apply() }), in: 1...8)
            }
            section("Roughness") {
                Picker("", selection: Binding<Double>(
                    get: { controller.style.roughness },
                    set: { controller.style.roughness = $0; apply() })) {
                    Text("Architect").tag(0.0)
                    Text("Artist").tag(1.0)
                    Text("Cartoonist").tag(2.0)
                }.labelsHidden().pickerStyle(.segmented).frame(maxWidth: .infinity)
            }
            section("Text size — \(Int(controller.style.fontSize)) pt") {
                Slider(value: Binding(
                    get: { controller.style.fontSize },
                    set: { controller.style.fontSize = $0; apply() }), in: 8...72)
            }
            if controller.hasSelection { actionsSection }
        }
        .font(.system(size: 12))
    }

    private func section<Content: View>(_ title: String,
                                         @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            label(title)
            content()
        }
    }

    private var actionsSection: some View {
        HStack {
            Button(role: .destructive) { controller.deleteSelection?() } label: {
                Label("Delete", systemImage: "trash")
            }
            Spacer()
            Button { controller.sendSelectionToBack?() } label: { Image(systemName: "square.3.layers.3d.bottom.filled") }
            Button { controller.bringSelectionToFront?() } label: { Image(systemName: "square.3.layers.3d.top.filled") }
        }
        .buttonStyle(.bordered)
        .padding(.top, 4)
    }

    private func label(_ t: String) -> some View {
        Text(t).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
    }

    private func swatchRow(_ colors: [String], selected: String,
                           action: @escaping (String) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(colors, id: \.self) { hex in
                Button { action(hex) } label: {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(swatchColor(hex))
                        .frame(width: 22, height: 22)
                        .overlay(RoundedRectangle(cornerRadius: 5)
                            .stroke(selected == hex ? Color(hex: 0x6965db) : Color.gray.opacity(0.4),
                                    lineWidth: selected == hex ? 2 : 1))
                }.buttonStyle(.plain)
            }
        }
    }

    private func swatchColor(_ hex: String) -> Color {
        if hex == "transparent" { return Color.white.opacity(0.15) }
        return Color(hex: hexInt(hex))
    }

    private func hexInt(_ s: String) -> Int {
        Int(s.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0x1e1e1e
    }

    private func commitRename(_ i: Int) {
        controller.renameTab?(i, renameText)
        editingTab = nil
    }

    private func apply() {
        if controller.hasSelection { controller.applyStyleToSelection?() }
    }
}

extension Color {
    init(hex: Int) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }
}
