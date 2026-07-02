import AppKit
import SwiftUI

/// Key-capable panel so the search field accepts typing (and Esc closes).
private final class SidebarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The right-docked "shelf": a full-height Liquid Glass panel with tabs for
/// Search, Library, and (soon) an Obsidian Vault browser. Mirrors the other
/// chrome panels' frosted look, but docks to the right edge and spans the
/// display height. Shown only while editing.
@MainActor
final class RightSidebarWindow {
    let panel: NSPanel
    private let width: CGFloat = 300

    init(controller: CanvasController,
         query: @escaping (String) -> [SearchHit],
         onPick: @escaping (SearchHit) -> Void,
         onHighlight: @escaping (Set<String>) -> Void,
         onInsert: @escaping (String) -> Void,
         onSaveSelection: @escaping () -> Void,
         onImportLibrary: @escaping () -> Void,
         onDeleteCustom: @escaping (String) -> Void,
         onConnectVault: @escaping () -> Void,
         onTogglePin: @escaping () -> Void,
         onClose: @escaping () -> Void) {
        let root = SidebarView(controller: controller,
                               query: query, onPick: onPick, onHighlight: onHighlight,
                               onInsert: onInsert,
                               onSaveSelection: onSaveSelection, onImportLibrary: onImportLibrary,
                               onDeleteCustom: onDeleteCustom,
                               onConnectVault: onConnectVault,
                               onInsertNote: { controller.insertVaultNoteByPathAction?($0) },
                               onTogglePin: onTogglePin, onClose: onClose)
            .environment(\.controlActiveState, .inactive)
        let host = NSHostingController(rootView: root)
        panel = SidebarPanel(contentViewController: host)
        panel.styleMask = [.borderless, .nonactivatingPanel]
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.hasShadow = false
        panel.collectionBehavior = [.moveToActiveSpace, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.appearance = NSAppearance(named: .aqua)
    }

    /// On-screen resting frame on whichever display the cursor is on.
    private func targetFrame() -> NSRect {
        let loc = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let h = visible.height - 40
        return NSRect(x: visible.maxX - width - 16, y: visible.minY + 20, width: width, height: h)
    }

    /// Slide in from just off the right edge.
    func show() {
        let target = targetFrame()
        var start = target
        start.origin.x = target.maxX + 24   // fully off-screen right
        panel.setFrame(start, display: false)
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.26
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
        }
    }

    /// Slide back out to the right, then order out.
    func hide() {
        guard panel.isVisible else { panel.orderOut(nil); return }
        var off = panel.frame
        off.origin.x = targetFrame().maxX + 24
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(off, display: true)
        }, completionHandler: { [weak panel] in panel?.orderOut(nil) })
    }

    var isVisible: Bool { panel.isVisible }
}

private enum SidebarTab: String, CaseIterable { case search, library, vault
    var symbol: String {
        switch self {
        case .search: return "magnifyingglass"
        case .library: return "books.vertical"
        case .vault: return "note.text"
        }
    }
}

/// A built-in library stencil: an id the canvas knows how to drop, an SF Symbol
/// for the tile, and a caption.
private struct Stencil: Identifiable {
    let id: String
    let symbol: String
    let label: String
}

private struct SidebarView: View {
    @ObservedObject var controller: CanvasController
    let query: (String) -> [SearchHit]
    let onPick: (SearchHit) -> Void
    let onHighlight: (Set<String>) -> Void
    let onInsert: (String) -> Void
    let onSaveSelection: () -> Void
    let onImportLibrary: () -> Void
    let onDeleteCustom: (String) -> Void
    let onConnectVault: () -> Void
    let onInsertNote: (String) -> Void
    let onTogglePin: () -> Void
    let onClose: () -> Void

    @State private var tab: SidebarTab = .search
    @State private var pinned = Settings.sidebarPinned

    var body: some View {
        VStack(spacing: 12) {
            tabStrip
            Group {
                switch tab {
                case .search:  SearchTab(query: query, onPick: onPick, onHighlight: onHighlight)
                case .library: LibraryTab(controller: controller, onInsert: onInsert,
                                          onSaveSelection: onSaveSelection, onImportLibrary: onImportLibrary,
                                          onDeleteCustom: onDeleteCustom)
                case .vault:   VaultTab(controller: controller, onConnectVault: onConnectVault, onInsertNote: onInsertNote)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .liquidGlassPanel(cornerRadius: 18)
        .onExitCommand { onClose() }
        .onChange(of: controller.sidebarSearchTick) { _ in tab = .search }   // ⌘F → Search tab
    }

    private var tabStrip: some View {
        HStack(spacing: 6) {
            ForEach(SidebarTab.allCases, id: \.self) { t in
                Button { tab = t } label: {
                    Image(systemName: t.symbol)
                        .frame(width: 32, height: 30)
                        .background(tab == t ? Color(hex: 0x6965db) : .clear)
                        .foregroundStyle(tab == t ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button {
                pinned.toggle(); onTogglePin()
            } label: {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .frame(width: 32, height: 30)
                    .foregroundStyle(pinned ? Color(hex: 0x6965db) : .primary)
            }
            .buttonStyle(.plain)
            .help(pinned ? "Unpin (auto-hide)" : "Pin open")
            Button { onClose() } label: {
                Image(systemName: "xmark").frame(width: 32, height: 30)
            }
            .buttonStyle(.plain)
            .help("Close sidebar")
        }
    }
}

// MARK: - Search tab

private struct SearchTab: View {
    let query: (String) -> [SearchHit]
    let onPick: (SearchHit) -> Void
    let onHighlight: (Set<String>) -> Void

    @State private var text = ""
    @State private var hits: [SearchHit] = []
    @FocusState private var focused: Bool

    /// Preserve first-seen order of kinds so groups are stable as you type.
    private var groups: [(String, [SearchHit])] {
        var order: [String] = []
        var map: [String: [SearchHit]] = [:]
        for h in hits {
            if map[h.kind] == nil { order.append(h.kind) }
            map[h.kind, default: []].append(h)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search all boards…", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($focused)
                    .onSubmit { if let first = hits.first { onPick(first) } }
                    .onChange(of: text) { new in
                        hits = query(new)
                        onHighlight(Set(hits.map(\.elementId)))
                    }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if text.isEmpty {
                hint("Type to search text, links, and code across every board.")
            } else if hits.isEmpty {
                hint("No matches.")
            } else {
                Text("\(hits.count) result\(hits.count == 1 ? "" : "s")")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(groups, id: \.0) { kind, rows in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind).font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary).padding(.leading, 4)
                                ForEach(rows) { hit in
                                    Button { onPick(hit) } label: {
                                        VStack(alignment: .leading, spacing: 1) {
                                            highlighted(hit.snippet, match: text)
                                                .font(.system(size: 14)).lineLimit(1)
                                            Text(hit.boardName).font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onDisappear { onHighlight([]) }
    }

    private func hint(_ s: String) -> some View {
        Text(s).font(.system(size: 13)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
    }

    /// Bold the matched substring, like Excalidraw's result rows.
    private func highlighted(_ s: String, match: String) -> Text {
        let q = match.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let r = s.range(of: q, options: .caseInsensitive) else { return Text(s) }
        return Text(s[s.startIndex..<r.lowerBound])
            + Text(s[r]).fontWeight(.bold)
            + Text(s[r.upperBound..<s.endIndex])
    }
}

// MARK: - Library tab

private struct LibraryTab: View {
    @ObservedObject var controller: CanvasController
    let onInsert: (String) -> Void
    let onSaveSelection: () -> Void
    let onImportLibrary: () -> Void
    let onDeleteCustom: (String) -> Void

    // Only stencils that AREN'T a one-click top-bar tool — plain rect/ellipse/
    // diamond/line/arrow live in the toolbar, so they're deliberately absent here.
    // Flow + Architecture tiles show REAL previews rendered by the app's own
    // rough renderer; only the code-cell tiles keep symbolic icons.
    private let flow: [(id: String, name: String, elements: [Element])] = [
        ("pill", "Start/end", StencilThumbnails.flowElements("pill")),
        ("curved", "Curved", StencilThumbnails.flowElements("curved")),
    ]
    private let architecture = StencilLibrary.systemDesign.map {
        (id: $0.id, name: $0.name, elements: $0.elements)
    }
    private let whitespace = [Stencil(id: "python", symbol: "chevron.left.forwardslash.chevron.right", label: "Python"),
                              Stencil(id: "shell", symbol: "terminal", label: "Shell"),
                              Stencil(id: "chart", symbol: "chart.bar", label: "Chart"),
                              Stencil(id: "test", symbol: "checkmark.seal", label: "Test")]

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
    private let cellCols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                personal
                previewGroup("Flow", flow)
                previewGroup("Architecture", architecture)
                cellGroup("Whitespace", whitespace)
            }
        }
    }

    /// A grid of stencils whose tiles are actual renders of their elements.
    private func previewGroup(_ title: String, _ items: [(id: String, name: String, elements: [Element])]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(items, id: \.id) { s in
                    StencilTile(label: s.name,
                                image: StencilThumbnails.image(key: s.id, elements: s.elements),
                                symbol: "square.on.square") { onInsert(s.id) }
                }
            }
        }
    }

    /// User-saved stencils, plus a button to store the current selection.
    private var personal: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Personal library").font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: 0x6965db))
                Spacer()
                Button { onImportLibrary() } label: {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Import an Excalidraw library file (.excalidrawlib)")
                Button { onSaveSelection() } label: {
                    Label("Save selection", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(!controller.hasSelection)
                .foregroundStyle(controller.hasSelection ? Color(hex: 0x6965db) : .secondary)
                .help("Save the current canvas selection as a reusable stencil")
            }
            if controller.customStencils.isEmpty {
                Text("Select something on the canvas, then Save selection to keep it here.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.18), style: SwiftUI.StrokeStyle(lineWidth: 1, dash: [4])))
            } else {
                LazyVGrid(columns: cols, spacing: 8) {
                    ForEach(controller.customStencils) { s in
                        StencilTile(label: s.name,
                                    image: StencilThumbnails.image(key: s.id, elements: s.elements),
                                    symbol: "square.on.square") { onInsert(s.id) }
                        .contextMenu {
                            Button(role: .destructive) { onDeleteCustom(s.id) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    /// Code-cell stencils: app widgets, so symbolic icons (no meaningful render).
    private func cellGroup(_ title: String, _ items: [Stencil]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            LazyVGrid(columns: cellCols, spacing: 8) {
                ForEach(items) { s in
                    StencilTile(label: s.label, image: nil, symbol: s.symbol) { onInsert(s.id) }
                }
            }
        }
    }
}

/// One library tile: a real rendered preview (or an SF Symbol fallback) over a
/// caption, with a springy hover highlight.
private struct StencilTile: View {
    let label: String
    let image: NSImage?
    let symbol: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: symbol).font(.system(size: 18))
                    }
                }
                .frame(height: 42)
                .frame(maxWidth: .infinity)
                Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 7).padding(.horizontal, 5)
            .background(.white.opacity(hovered ? 0.24 : 0.10), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Color(hex: 0x6965db).opacity(hovered ? 0.6 : 0), lineWidth: 1))
            .scaleEffect(hovered ? 1.05 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: hovered)
        .help("Add \(label)")
    }
}

// MARK: - Vault tab (Obsidian note browser)

/// A node in the vault's folder tree: either a folder (with children) or a note.
private final class VaultNode: Identifiable {
    let id: String        // vault-relative path (folder path, or note id)
    let name: String
    let isFolder: Bool
    let noteId: String?
    var children: [VaultNode] = []
    init(id: String, name: String, isFolder: Bool, noteId: String? = nil) {
        self.id = id; self.name = name; self.isFolder = isFolder; self.noteId = noteId
    }
}

/// Recursively renders the collapsible folder tree. Folders toggle their id in
/// `expanded`; notes drop an obsidian:// link on click.
private struct VaultTree: View {
    let nodes: [VaultNode]
    let depth: Int
    let vaultBase: String   // absolute vault folder path, for building drag URLs
    @Binding var expanded: Set<String>
    let onInsertNote: (String) -> Void

    /// On-disk URL for a tree node ("" ext for folders, ".md" for notes).
    private func fileURL(for node: VaultNode) -> NSURL {
        let rel = node.isFolder ? node.id : node.id + ".md"
        let full = vaultBase.isEmpty ? rel : vaultBase + "/" + rel
        return URL(fileURLWithPath: full) as NSURL
    }

    var body: some View {
        ForEach(nodes) { node in
            if node.isFolder {
                let isOpen = expanded.contains(node.id)
                Button {
                    if isOpen { expanded.remove(node.id) } else { expanded.insert(node.id) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).frame(width: 12)
                        Image(systemName: isOpen ? "folder.fill" : "folder")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Text(node.name).font(.system(size: 14)).lineLimit(1)
                        Spacer()
                    }
                    .padding(.leading, CGFloat(depth) * 14)
                    .padding(.vertical, 5).padding(.trailing, 6).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onDrag { NSItemProvider(object: fileURL(for: node)) }   // drag folder → link node
                .help("Click to expand · drag onto the canvas to add a folder link")
                if isOpen {
                    VaultTree(nodes: node.children, depth: depth + 1, vaultBase: vaultBase,
                              expanded: $expanded, onInsertNote: onInsertNote)
                }
            } else {
                Button { onInsertNote(node.noteId ?? node.id) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text").font(.system(size: 12)).foregroundStyle(.secondary)
                        Text(node.name).font(.system(size: 14)).lineLimit(1)
                        Spacer()
                    }
                    .padding(.leading, CGFloat(depth) * 14 + 18)
                    .padding(.vertical, 5).padding(.trailing, 6).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onDrag { NSItemProvider(object: fileURL(for: node)) }   // drag note → file link
                .help("Click to add an obsidian:// link · drag for a file link")
            }
        }
    }
}

private struct VaultTab: View {
    @ObservedObject var controller: CanvasController
    let onConnectVault: () -> Void
    let onInsertNote: (String) -> Void

    @State private var filter = ""
    @State private var expanded: Set<String> = []

    /// Build a folder tree from the flat note list (ids are vault-relative paths).
    static func buildTree(_ notes: [VaultNote]) -> [VaultNode] {
        let root = VaultNode(id: "", name: "", isFolder: true)
        for n in notes {
            let parts = n.id.split(separator: "/").map(String.init)
            guard !parts.isEmpty else { continue }
            var cur = root
            for i in 0..<parts.count {
                if i == parts.count - 1 {
                    cur.children.append(VaultNode(id: n.id, name: n.name, isFolder: false, noteId: n.id))
                } else {
                    let fpath = parts[0...i].joined(separator: "/")
                    if let existing = cur.children.first(where: { $0.isFolder && $0.id == fpath }) {
                        cur = existing
                    } else {
                        let node = VaultNode(id: fpath, name: parts[i], isFolder: true)
                        cur.children.append(node); cur = node
                    }
                }
            }
        }
        sort(root)
        return root.children
    }

    /// Folders before notes, each alphabetical; recurse.
    private static func sort(_ node: VaultNode) {
        node.children.sort {
            $0.isFolder != $1.isFolder ? $0.isFolder
                : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        for c in node.children where c.isFolder { sort(c) }
    }

    private var notes: [VaultNote] {
        let q = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return controller.vaultNotes }
        return controller.vaultNotes.filter {
            $0.name.lowercased().contains(q) || $0.folder.lowercased().contains(q)
        }
    }

    var body: some View {
        if let vault = controller.vaultName {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "folder").foregroundStyle(.secondary).font(.system(size: 12))
                    Text(vault).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Spacer()
                    Menu {
                        Button("Connect a different vault…") { onConnectVault() }
                        Divider()
                        Button("Disconnect vault", role: .destructive) { controller.disconnectVaultAction?() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Vault options")
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Filter notes…", text: $filter).textFieldStyle(.plain).font(.system(size: 14))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text("\(notes.count) note\(notes.count == 1 ? "" : "s") · click to add a link")
                    .font(.system(size: 11)).foregroundStyle(.secondary)

                if notes.isEmpty {
                    Text(controller.vaultNotes.isEmpty ? "No markdown notes found in this vault." : "No matches.")
                        .font(.system(size: 13)).foregroundStyle(.secondary).padding(.horizontal, 4)
                } else if !filter.isEmpty {
                    // While filtering: flat matching list with folder subtitle.
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(notes) { note in
                                Button { onInsertNote(note.id) } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "doc.text").font(.system(size: 12)).foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(note.name).font(.system(size: 14)).lineLimit(1)
                                            if !note.folder.isEmpty {
                                                Text(note.folder).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8).padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } else {
                    // Browsing: collapsible folder tree (folders first, then notes).
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            VaultTree(nodes: VaultTab.buildTree(controller.vaultNotes),
                                      depth: 0, vaultBase: controller.vaultPath ?? "",
                                      expanded: $expanded, onInsertNote: onInsertNote)
                        }
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Obsidian vault").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Text("Connect a vault to browse notes and drop them onto the canvas as obsidian:// links.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Button { onConnectVault() } label: {
                    Label("Connect vault…", systemImage: "link")
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
