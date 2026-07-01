import SwiftUI
import UniformTypeIdentifiers

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
            HStack(spacing: 6) {
                tabBar
                gearMenu
            }
            Divider()
            tools
            Divider()
            inspector
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(width: 376)
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
                        .onDrag { NSItemProvider(object: String(i) as NSString) }
                        .onDrop(of: [.text], isTargeted: nil) { providers in
                            providers.first?.loadObject(ofClass: NSString.self) { obj, _ in
                                if let s = obj as? String, let from = Int(s) {
                                    DispatchQueue.main.async { controller.moveTab?(from, i) }
                                }
                            }
                            return true
                        }
                        .contextMenu {
                            Button("Rename") { renameText = name; editingTab = i }
                            Button("Export as PNG…") { controller.exportTab?(i, "png") }
                            Button("Export as SVG…") { controller.exportTab?(i, "svg") }
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

    private var gearMenu: some View {
        Menu {
            Picker("When editing", selection: Binding(
                get: { Double(Settings.editBoardOpacity) },
                set: { controller.setEditOpacity?(CGFloat($0)) })) {
                Text("Light wash").tag(0.85)
                Text("Solid white").tag(1.0)
                Text("Transparent").tag(0.0)
            }
            Picker("Link color", selection: Binding(
                get: { Settings.linkColor },
                set: { controller.setLinkColorAction?($0) })) {
                Text("Purple").tag("#6965db")
                Text("Blue").tag("#1971c2")
                Text("Green").tag("#2f9e44")
                Text("Red").tag("#e03131")
                Text("Orange").tag("#f08c00")
                Text("Gray").tag("#868e96")
                Text("Black").tag("#1e1e1e")
            }
            Picker("File links", selection: Binding(
                get: { Settings.linkStyle },
                set: { controller.setLinkStyleAction?($0) })) {
                Text("Preview").tag("preview")
                Text("Icon + name").tag("icon")
                Text("Colored text").tag("text")
            }
            Picker("When hidden (⌥⌘W)", selection: Binding(
                get: { Settings.stayOnWallpaper },
                set: { controller.setStayOnWallpaperAction?($0) })) {
                Text("Stay on wallpaper").tag(true)
                Text("Hide everything").tag(false)
            }
            Divider()
            Button("Keyboard Shortcuts…") { controller.openShortcutsAction?() }
        } label: {
            Image(systemName: "gearshape").frame(width: 22, height: 22)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Settings")
    }

    private var tools: some View {
        HStack(spacing: 2) {
            ForEach(Tool.primary, id: \.self) { tool in
                Button {
                    controller.tool = tool
                } label: {
                    Image(systemName: tool.symbol)
                        .frame(width: 24, height: 26)
                        .background(controller.tool == tool ? Color(hex: 0x6965db) : .clear)
                        .foregroundStyle(controller.tool == tool ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help("\(tool.rawValue.capitalized) (\(String(tool.key)))")
            }
            Divider().frame(height: 18).padding(.horizontal, 1)
            Button { controller.insertImageAction?() } label: {
                Image(systemName: "photo").frame(width: 25, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .help("Insert image")
            Menu {
                Button("Link File or Folder…") { controller.linkFileAction?() }
                Button("Link URL…") { controller.linkURLAction?() }
            } label: {
                Image(systemName: "paperclip").frame(width: 25, height: 26)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Link a file, folder, or URL")

            Menu {
                Button { controller.tool = .frame } label: { Label(Tool.frame.label, systemImage: Tool.frame.symbol) }
                Button { controller.tool = .laser } label: { Label(Tool.laser.label, systemImage: Tool.laser.symbol) }
                Button { controller.tool = .lasso } label: { Label(Tool.lasso.label, systemImage: Tool.lasso.symbol) }
                Divider()
                Menu {
                    Button("Shell") { controller.insertCellAction?("shell") }
                    Button("Python") { controller.insertCellAction?("python") }
                    Button("JavaScript") { controller.insertCellAction?("javascript") }
                    Button("Ruby") { controller.insertCellAction?("ruby") }
                } label: { Label("Code Cell", systemImage: "chevron.left.forwardslash.chevron.right") }
                Button { controller.runGraphAction?() } label: { Label("Run Graph (⌘⇧↵)", systemImage: "play.circle") }
            } label: {
                Image(systemName: "ellipsis.circle").frame(width: 25, height: 26)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More tools")
        }
    }

    /// Element type the inspector should reflect: the selection, else the tool.
    private var contextType: String { controller.selectionType ?? controller.tool.rawValue }
    private var showsFill: Bool { ["rectangle", "diamond", "ellipse", "line"].contains(contextType) }
    private var isArrow: Bool { contextType == "arrow" }
    private var isText: Bool { contextType == "text" }
    /// Text and file/link/folder nodes both carry an editable label font.
    private var isTextual: Bool { contextType == "text" || contextType == "file" }
    private var isStrokable: Bool { contextType != "text" && contextType != "file" }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                section("Stroke") {
                    swatchRow(strokeSwatches, selected: controller.style.strokeColor) {
                        controller.style.strokeColor = $0; apply()
                    }
                }
                if showsFill {
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
                }
            }
            Group {
                if isStrokable {
                    section("Stroke width") {
                        Slider(value: Binding(
                            get: { controller.style.strokeWidth },
                            set: { controller.style.strokeWidth = $0; apply() }), in: 1...8)
                    }
                    section("Stroke style") {
                        IconSegment(options: [
                            (.solid, AnyView(StrokeStyleGlyph(style: .solid))),
                            (.dashed, AnyView(StrokeStyleGlyph(style: .dashed))),
                            (.dotted, AnyView(StrokeStyleGlyph(style: .dotted))),
                        ], selection: Binding<StrokeStyle>(
                            get: { controller.style.strokeStyle },
                            set: { controller.style.strokeStyle = $0; apply() }))
                    }
                    section("Sloppiness") {
                        TextSegment(options: [
                            (value: 0.0, label: "Architect"), (value: 1.0, label: "Artist"),
                            (value: 2.0, label: "Cartoonist"),
                        ], selection: Binding<Double>(
                            get: { controller.style.roughness },
                            set: { controller.style.roughness = $0; apply() }))
                    }
                }
            }
            Group {
                if contextType == "rectangle" {
                    section("Edges") {
                        TextSegment(options: [(value: false, label: "Sharp"), (value: true, label: "Round")],
                                    selection: Binding<Bool>(
                                        get: { controller.style.rounded },
                                        set: { controller.style.rounded = $0; apply() }))
                    }
                }
                if isArrow {
                    section("Arrow type") {
                        IconSegment(options: [
                            (false, AnyView(ArrowTypeGlyph(elbow: false))),
                            (true, AnyView(ArrowTypeGlyph(elbow: true))),
                        ], selection: Binding<Bool>(
                            get: { controller.style.elbowArrow },
                            set: { controller.style.elbowArrow = $0; apply() }))
                    }
                    section("Arrowheads") {
                        VStack(alignment: .leading, spacing: 6) {
                            arrowheadSegment(start: true)
                            arrowheadSegment(start: false)
                        }
                    }
                }
                if isTextual {
                    section("Font") {
                        Menu {
                            ForEach(Fonts.options) { opt in
                                Button { controller.style.fontFamily = opt.id; apply() } label: {
                                    Text(opt.name).font(.custom(opt.psName, size: 14))
                                }
                            }
                        } label: {
                            let cur = Fonts.option(controller.style.fontFamily)
                            Text(cur.name)
                                .font(.custom(cur.psName, size: 14))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .menuStyle(.borderlessButton)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color.gray.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    section("Text size — \(Int(controller.style.fontSize)) pt") {
                        Slider(value: Binding(
                            get: { controller.style.fontSize },
                            set: { controller.style.fontSize = $0; apply() }), in: 8...72)
                    }
                }
            }
            section("Opacity — \(Int(controller.style.opacity))") {
                Slider(value: Binding(
                    get: { controller.style.opacity },
                    set: { controller.style.opacity = $0; apply() }), in: 0...100)
            }
            if controller.selectionCount >= 2 {
                section("Align") { alignRow }
            }
            bottomBar
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

    private var bottomBar: some View {
        HStack(spacing: 6) {
            Button { controller.clearBoardAction?() } label: {
                Label("Clear", systemImage: "eraser")
            }
            Spacer()
            if controller.hasSelection {
                Button { controller.sendSelectionToBack?() } label: { Image(systemName: "arrow.down.to.line") }
                    .help("Send to back")
                Button { controller.sendSelectionBackward?() } label: { Image(systemName: "arrow.down") }
                    .help("Send backward")
                Button { controller.bringSelectionForward?() } label: { Image(systemName: "arrow.up") }
                    .help("Bring forward")
                Button { controller.bringSelectionToFront?() } label: { Image(systemName: "arrow.up.to.line") }
                    .help("Bring to front")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
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

    private var alignRow: some View {
        HStack(spacing: 4) {
            ForEach([
                ("left", "align.horizontal.left"), ("centerH", "align.horizontal.center"),
                ("right", "align.horizontal.right"), ("top", "align.vertical.top"),
                ("middleV", "align.vertical.center"), ("bottom", "align.vertical.bottom"),
                ("distH", "arrow.left.and.right"), ("distV", "arrow.up.and.down"),
            ], id: \.0) { mode, symbol in
                Button { controller.alignAction?(mode) } label: {
                    Image(systemName: symbol).frame(width: 26, height: 22)
                        .background(Color.gray.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func arrowheadSegment(start: Bool) -> some View {
        IconSegment(options: [
            (value: "none", icon: AnyView(ArrowheadGlyph(type: "none"))),
            (value: "arrow", icon: AnyView(ArrowheadGlyph(type: "arrow"))),
            (value: "triangle", icon: AnyView(ArrowheadGlyph(type: "triangle"))),
            (value: "dot", icon: AnyView(ArrowheadGlyph(type: "dot"))),
            (value: "bar", icon: AnyView(ArrowheadGlyph(type: "bar"))),
        ], selection: Binding<String>(
            get: { start ? controller.style.startArrowhead : controller.style.endArrowhead },
            set: {
                if start { controller.style.startArrowhead = $0 } else { controller.style.endArrowhead = $0 }
                apply()
            }))
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
