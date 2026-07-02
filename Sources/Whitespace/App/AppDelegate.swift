import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Sparkle auto-updater. Started at launch; checks the appcast feed
    /// (SUFeedURL in Info.plist) and installs Developer ID-signed updates.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    private var window: DesktopWindow!
    private var canvas: CanvasView!
    private var menuBar: MenuBarController!
    private var topToolbar: TopToolbarWindow!   // centered top: tools row
    private var inspector: InspectorWindow!     // left: tabs, gear, style controls
    private let controller = CanvasController()
    private var scene: Scene!
    private var paletteHidden = false

    private var boards: [BoardDoc] = []
    private var currentBoard = 0
    private var shortcuts: ShortcutsWindow!
    private var cheatSheet = CheatSheetWindow()
    private var searchWindow: SearchWindow!
    private var sidebar: RightSidebarWindow!

    private var autosaveItem: DispatchWorkItem?
    private var pendingOpenURL: URL?

    /// Open a `.excalidraw` passed via `open -a Whitespace <file>` (or Finder).
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        guard url.pathExtension.lowercased() == "excalidraw" else { return false }
        if scene != nil {
            if !window.isEditing { toggleEdit() }
            openExcalidraw(url)
        } else {
            pendingOpenURL = url   // arrived before setup; open after launch
        }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { return }

        let ws = Workspace.load()
        boards = ws.boards
        currentBoard = ws.current
        scene = Scene(elements: boards[currentBoard].elements)
        controller.tabs = boards.map(\.name)
        controller.currentTab = currentBoard

        window = DesktopWindow(screen: screen)
        canvas = CanvasView(frame: screen.frame, scene: scene, controller: controller)
        canvas.autoresizingMask = [.width, .height]
        canvas.onSceneChange = { [weak self] in self?.scheduleAutosave() }
        window.contentView = canvas
        window.orderFront(nil)

        topToolbar = TopToolbarWindow(controller: controller)
        inspector = InspectorWindow(controller: controller)
        searchWindow = SearchWindow(
            query: { [weak self] q in self?.searchBoards(q) ?? [] },
            onPick: { [weak self] hit in self?.jumpToHit(hit) })
        sidebar = RightSidebarWindow(
            controller: controller,
            query: { [weak self] q in self?.searchBoards(q) ?? [] },
            onPick: { [weak self] hit in self?.jumpToHit(hit) },
            onHighlight: { [weak self] ids in self?.canvas.setSearchHighlights(ids) },
            onInsert: { [weak self] id in self?.canvas.insertStencil(id) },
            onSaveSelection: { [weak self] in self?.saveSelectionToLibrary() },
            onImportLibrary: { [weak self] in self?.importLibrary() },
            onDeleteCustom: { [weak self] id in self?.deleteCustomStencil(id) },
            onConnectVault: { [weak self] in self?.connectVault() },
            onTogglePin: { Settings.sidebarPinned.toggle() },
            onClose: { [weak self] in self?.setSidebar(false) })

        canvas.onSlashSearch = { [weak self] in self?.linkFile() }
        canvas.onOpenFile = { [weak self] url in self?.openExcalidraw(url) }
        controller.linkFileAction = { [weak self] in self?.linkFile() }
        controller.linkURLAction = { [weak self] in self?.linkURL() }
        controller.insertImageAction = { [weak self] in self?.insertImage() }
        controller.insertCellAction = { [weak self] lang in self?.canvas.insertCell(language: lang) }
        controller.insertTestCellAction = { [weak self] in self?.canvas.insertTestCell() }
        controller.exportNotebookAction = { [weak self] in self?.export(.ipynb) }
        controller.openNotebookAction = { [weak self] in self?.openNotebook() }
        controller.runGraphAction = { [weak self] in self?.canvas.runGraph() }
        controller.restartKernelsAction = { Kernels.shared.restartAll() }
        controller.clearBoardAction = { [weak self] in self?.canvas.clearBoard() }
        controller.setEditOpacity = { [weak self] v in
            Settings.editBoardOpacity = v; self?.canvas.editBoardOpacity = v; self?.canvas.needsDisplay = true
        }
        controller.setKeepIcons = { [weak self] on in
            Settings.keepDesktopIcons = on
            if let self, self.window.isEditing { self.window.setEditing(true) }
        }
        controller.setLinkColorAction = { [weak self] hex in
            Settings.linkColor = hex; self?.canvas.needsDisplay = true
        }
        controller.setLinkStyleAction = { [weak self] style in
            Settings.linkStyle = style; self?.canvas.restyleFileNodes()
        }
        controller.setStayOnWallpaperAction = { [weak self] on in
            Settings.stayOnWallpaper = on
            guard let self, !self.window.isEditing else { return }
            on ? self.window.orderFront(nil) : self.window.orderOut(nil)   // apply now if idle
        }
        controller.openSearchAction = { [weak self] in self?.openSearch() }
        controller.connectVaultAction = { [weak self] in self?.connectVault() }
        controller.focusElementAction = { [weak self] id in self?.canvas.focusElement(id) }
        controller.toggleSidebarAction = { [weak self] in
            guard let self else { return }
            self.setSidebar(!self.sidebar.isVisible)
        }
        controller.openSidebarSearchAction = { [weak self] in self?.openSidebarSearch() }
        controller.customStencils = PersonalLibraryStore.load()
        controller.saveSelectionToLibraryAction = { [weak self] in self?.saveSelectionToLibrary() }
        controller.importLibraryAction = { [weak self] in self?.importLibrary() }
        controller.deleteCustomStencilAction = { [weak self] id in self?.deleteCustomStencil(id) }
        controller.insertVaultNoteByPathAction = { [weak self] rel in self?.insertVaultNote(relativePath: rel) }
        controller.disconnectVaultAction = { [weak self] in self?.disconnectVault() }

        // Route canvas keyboard shortcuts (tool keys, arrows, delete, "/", …) to
        // the canvas whichever chrome panel happens to be key — but never while
        // typing in a text field. ⌘-combos keep the normal responder chain
        // (performKeyEquivalent), so grouping/undo/etc. still work.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window.isEditing, !self.isTextEditing(),
                  !event.modifierFlags.contains(.command) else { return event }
            self.canvas.keyDown(with: event)
            return nil
        }

        controller.addTab = { [weak self] in self?.addBoard() }
        controller.selectTab = { [weak self] i in self?.selectBoard(i) }
        controller.renameTab = { [weak self] i, name in self?.renameBoard(i, name) }
        controller.closeTab = { [weak self] i in self?.closeBoard(i) }
        controller.moveTab = { [weak self] from, to in self?.moveBoard(from, to) }
        controller.exportTab = { [weak self] i, kind in self?.exportBoard(i, kind) }

        menuBar = MenuBarController(
            onToggleEdit: { [weak self] in self?.toggleEdit() },
            onQuit: { [weak self] in self?.saveNow(); NSApp.terminate(nil) },
            onSetEditOpacity: { [weak self] v in
                self?.canvas.editBoardOpacity = v; self?.canvas.needsDisplay = true
            },
            onSetBoardPattern: { [weak self] p in self?.canvas.boardPattern = p },
            onToggleKeepIcons: { [weak self] _ in
                // Re-apply the window level immediately if currently editing.
                guard let self, self.window.isEditing else { return }
                self.window.setEditing(true)
            },
            onTogglePalette: { [weak self] in self?.togglePalette() },
            onExportPNG: { [weak self] in self?.export(.png) },
            onExportSVG: { [weak self] in self?.export(.svg) },
            onExportHTML: { [weak self] in self?.export(.html) },
            onLinkFile: { [weak self] in self?.linkFile() },
            onSetLinkColor: { [weak self] _ in self?.canvas.needsDisplay = true },
            onOpenFile: { [weak self] in self?.openExcalidrawFile() },
            onSearch: { [weak self] in self?.openSearch() },
            onConnectVault: { [weak self] in self?.connectVault() },
            onInsertVaultNote: { [weak self] in self?.insertVaultNote() },
            onCheckForUpdates: { [weak self] in self?.updaterController.checkForUpdates(nil) }
        )

        registerHotKeys()
        shortcuts = ShortcutsWindow()
        shortcuts.onChange = { [weak self] in self?.registerHotKeys() }
        controller.openShortcutsAction = { [weak self] in self?.cheatSheet.toggle() }
        controller.configureHotkeysAction = { [weak self] in self?.shortcuts.show() }

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        // Start in Edit Mode so a launch is immediately visible (palette +
        // border appear); otherwise a menu-bar app with a transparent idle
        // board looks like nothing happened.
        toggleEdit()

        if let url = pendingOpenURL { pendingOpenURL = nil; openExcalidraw(url) }

        promptLaunchAtLoginIfNeeded()
    }

    /// First launch only: offer to open Whitespace automatically at login.
    private func promptLaunchAtLoginIfNeeded() {
        guard !Settings.askedLaunchAtLogin, !LoginItem.isEnabled else { return }
        Settings.askedLaunchAtLogin = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let alert = NSAlert()
            alert.messageText = "Open Whitespace at login?"
            alert.informativeText = "Whitespace lives in your menu bar and on the desktop. Launch it automatically each time you log in? You can change this anytime from the menu-bar menu."
            alert.addButton(withTitle: "Open at Login")
            alert.addButton(withTitle: "Not Now")
            // The canvas sits on the desktop layer, so a plain modal can hide
            // behind the active app. Briefly become a regular app so the prompt
            // is guaranteed frontmost, then drop back to menu-bar-only.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            let choose = alert.runModal() == .alertFirstButtonReturn
            NSApp.setActivationPolicy(.accessory)
            if choose {
                LoginItem.setEnabled(true)
                self.menuBar.refreshLoginItem()
            }
        }
    }

    private func registerHotKeys() {
        HotKeyCenter.shared.register(id: 1, keyCode: Settings.editKeyCode,
                                     modifiers: Settings.editMods) { [weak self] in self?.toggleEdit() }
        HotKeyCenter.shared.register(id: 2, keyCode: Settings.paletteKeyCode,
                                     modifiers: Settings.paletteMods) { [weak self] in self?.togglePalette() }
    }

    /// The screen the cursor is currently on (the desktop the user is using).
    private static func activeScreen() -> NSScreen? {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) } ?? NSScreen.main
    }

    private func toggleEdit() {
        let editing = !window.isEditing
        if editing, let screen = Self.activeScreen() {
            // Launch the whiteboard on whichever display the cursor is on.
            window.fit(to: screen)
        }
        window.setEditing(editing)
        canvas.isEditing = editing
        menuBar.setEditing(editing)
        if editing {
            window.makeFirstResponder(canvas)
            if !paletteHidden { showChrome() }
        } else {
            hideChrome()
            saveNow()
            // Optionally hide the whole canvas (clean desktop) instead of leaving
            // the drawings on the wallpaper.
            if !Settings.stayOnWallpaper { window.orderOut(nil) }
        }
    }

    /// Full chrome, tied to entering/leaving edit mode: the palette (top toolbar
    /// + inspector) plus the right sidebar and transient overlays.
    private func showChrome() {
        setPalette(true)
        if Settings.sidebarPinned { setSidebar(true) }   // pinned → reopens with the chrome
    }
    private func hideChrome() {
        setPalette(false)
        sidebar?.hide(); canvas.setSearchHighlights([]); controller.sidebarVisible = false
    }

    /// Just the tool palette — top toolbar + inspector (and transient overlays).
    /// Deliberately does NOT touch the right sidebar, so ⌥⌘Q leaves it open.
    private func setPalette(_ show: Bool) {
        if show {
            topToolbar.show(); inspector.show()
        } else {
            topToolbar.hide(); inspector.hide()
            cheatSheet.hide(); searchWindow?.close()
        }
    }

    /// Toggle the right sidebar (search / library / vault) from the top-toolbar
    /// button. Opening slides the panel in; closing clears any search highlight.
    private func setSidebar(_ show: Bool) {
        guard sidebar != nil else { return }
        if show { refreshVault(); sidebar.show() } else { sidebar.hide(); canvas.setSearchHighlights([]) }
        controller.sidebarVisible = show
    }

    /// ⌘F: open the sidebar (if hidden) and switch it to the Search tab. Bumping
    /// the tick tells `SidebarView` to select Search even if it was left on
    /// Library or Vault. Deliberately doesn't force keyboard focus, to keep the
    /// glass panel's frosted (inactive) look.
    private func openSidebarSearch() {
        guard sidebar != nil else { return }
        if !sidebar.isVisible { setSidebar(true) }
        controller.sidebarSearchTick += 1
    }

    /// Capture the current canvas selection as a named custom stencil in the
    /// personal library (Library tab), persisted across launches.
    private func saveSelectionToLibrary() {
        guard let elements = canvas.captureSelectionAsStencil(), !elements.isEmpty else {
            NSSound.beep(); return
        }
        let alert = NSAlert()
        alert.messageText = "Save to Library"
        alert.informativeText = "Name this stencil so you can drop it again later."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "e.g. Auth flow"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let stencil = CustomStencil(id: UUID().uuidString,
                                    name: typed.isEmpty ? "Untitled" : typed,
                                    elements: elements)
        var lib = controller.customStencils
        lib.append(stencil)
        controller.customStencils = lib
        PersonalLibraryStore.save(lib)
    }

    /// Import one or more Excalidraw library files (.excalidrawlib) — or whole
    /// .excalidraw drawings — as custom stencils in the personal library.
    private func importLibrary() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.message = "Choose Excalidraw library files (.excalidrawlib)"
        var types: [UTType] = [.json]
        if let t = UTType(filenameExtension: "excalidrawlib") { types.insert(t, at: 0) }
        if let t = UTType(filenameExtension: "excalidraw") { types.append(t) }
        panel.allowedContentTypes = types
        guard panel.runModal() == .OK else { return }
        let imported = panel.urls.flatMap { LibraryImport.stencils(from: $0) }
        guard !imported.isEmpty else {
            NSSound.beep()
            let a = NSAlert()
            a.messageText = "Nothing to import"
            a.informativeText = "That file didn't contain any library items Whitespace could read."
            a.runModal()
            return
        }
        var lib = controller.customStencils
        lib.append(contentsOf: imported)
        controller.customStencils = lib
        PersonalLibraryStore.save(lib)
    }

    /// Remove a saved custom stencil and persist the change.
    private func deleteCustomStencil(_ id: String) {
        var lib = controller.customStencils
        lib.removeAll { $0.id == id }
        controller.customStencils = lib
        PersonalLibraryStore.save(lib)
        StencilThumbnails.invalidate(id)
    }

    /// Hide/show the whole tool palette (both panels) while staying in drawing
    /// mode (⌥⌘Q).
    private func togglePalette() {
        guard window.isEditing else { return }
        paletteHidden.toggle()
        setPalette(!paletteHidden)   // sidebar stays as-is — ⌥⌘Q only hides the palette
        menuBar.setPaletteHidden(paletteHidden)
    }

    private func scheduleAutosave() {
        autosaveItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveNow() }
        autosaveItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    private func saveNow() {
        guard !boards.isEmpty else { return }
        boards[currentBoard].elements = scene.elements
        Workspace.save(WorkspaceData(boards: boards, current: currentBoard))
    }

    // MARK: Tabs / boards

    private func selectBoard(_ index: Int) {
        guard index >= 0, index < boards.count, index != currentBoard else { return }
        boards[currentBoard].elements = scene.elements   // stash current
        currentBoard = index
        scene.load(boards[index].elements)
        canvas.boardDidChange()
        controller.currentTab = index
        saveNow()
        if controller.sidebarVisible { refreshVault() }   // vault is per-board
    }

    private func addBoard() {
        boards[currentBoard].elements = scene.elements
        let board = BoardDoc(name: "Board \(boards.count + 1)")
        boards.append(board)
        currentBoard = boards.count - 1
        scene.load(board.elements)
        canvas.boardDidChange()
        controller.tabs = boards.map(\.name)
        controller.currentTab = currentBoard
        saveNow()
    }

    /// Open a `.excalidraw` file as a new board.
    private func openExcalidraw(_ url: URL) {
        let elements = DocumentStore.load(from: url)
        boards[currentBoard].elements = scene.elements
        let name = url.deletingPathExtension().lastPathComponent
        boards.append(BoardDoc(name: name.isEmpty ? "Opened" : name, elements: elements))
        currentBoard = boards.count - 1
        scene.load(elements)
        canvas.boardDidChange()
        controller.tabs = boards.map(\.name)
        controller.currentTab = currentBoard
        saveNow()
    }

    private func openExcalidrawFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if let t = UTType(filenameExtension: "excalidraw") {
            panel.allowedContentTypes = [t, .json]
        }
        panel.message = "Open an .excalidraw file as a new board"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { openExcalidraw(url) }
    }

    private func moveBoard(_ from: Int, _ to: Int) {
        guard from != to, boards.indices.contains(from), boards.indices.contains(to) else { return }
        boards[currentBoard].elements = scene.elements
        let curId = boards[currentBoard].id
        let moved = boards.remove(at: from)
        boards.insert(moved, at: to)
        currentBoard = boards.firstIndex { $0.id == curId } ?? to
        controller.tabs = boards.map(\.name)
        controller.currentTab = currentBoard
        saveNow()
    }

    private func exportBoard(_ index: Int, _ kind: String) {
        guard boards.indices.contains(index) else { return }
        let elements = index == currentBoard ? scene.elements : boards[index].elements
        guard Export.contentBounds(elements) != nil else {
            let alert = NSAlert()
            alert.messageText = "Nothing to export"
            alert.informativeText = "“\(boards[index].name)” is empty."
            alert.runModal(); return
        }
        let panel = NSSavePanel()
        let name = boards[index].name
        panel.nameFieldStringValue = "\(name).\(kind)"
        panel.allowedContentTypes = [kind == "png" ? .png : kind == "html" ? .html : kind == "ipynb" ? Self.ipynbType : .svg]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        switch kind {
        case "png": try? Export.png(elements)?.write(to: url, options: .atomic)
        case "html": try? Export.html(elements, title: name)?.write(to: url, atomically: true, encoding: .utf8)
        case "ipynb": try? Notebook.exportIPYNB(elements)?.write(to: url, options: .atomic)
        default: try? Export.svg(elements)?.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func renameBoard(_ index: Int, _ name: String) {
        guard index >= 0, index < boards.count else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        boards[index].name = trimmed.isEmpty ? boards[index].name : trimmed
        controller.tabs = boards.map(\.name)
        saveNow()
    }

    private func closeBoard(_ index: Int) {
        guard boards.count > 1, index >= 0, index < boards.count else { return }
        boards.remove(at: index)
        currentBoard = min(currentBoard, boards.count - 1)
        scene.load(boards[currentBoard].elements)
        canvas.boardDidChange()
        controller.tabs = boards.map(\.name)
        controller.currentTab = currentBoard
        saveNow()
    }

    private enum ExportKind { case png, svg, html, ipynb }

    private static let ipynbType = UTType(filenameExtension: "ipynb") ?? .json

    private func export(_ kind: ExportKind) {
        guard Export.contentBounds(scene.elements) != nil else {
            let alert = NSAlert()
            alert.messageText = "Nothing to export"
            alert.informativeText = "Draw something first, then export."
            alert.runModal()
            return
        }
        let name = boards.indices.contains(currentBoard) ? boards[currentBoard].name : "whiteboard"
        let ext: String
        let type: UTType
        switch kind {
        case .png: ext = "png"; type = .png
        case .html: ext = "html"; type = .html
        case .ipynb: ext = "ipynb"; type = Self.ipynbType
        case .svg: ext = "svg"; type = .svg
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(name).\(ext)"
        panel.allowedContentTypes = [type]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        switch kind {
        case .png:
            try? Export.png(scene.elements)?.write(to: url, options: .atomic)
        case .svg:
            try? Export.svg(scene.elements)?.write(to: url, atomically: true, encoding: .utf8)
        case .html:
            try? Export.html(scene.elements, title: name)?.write(to: url, atomically: true, encoding: .utf8)
        case .ipynb:
            try? Notebook.exportIPYNB(scene.elements)?.write(to: url, options: .atomic)
        }
    }

    /// Import a `.ipynb` and lay its code cells out on the current board.
    private func openNotebook() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowedContentTypes = [Self.ipynbType, .json]
        panel.message = "Choose a Jupyter notebook to import"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        let cells = Notebook.importIPYNB(data, at: CGPoint(x: 80, y: 80))
        guard !cells.isEmpty else { return }
        canvas.addImportedCells(cells)
    }

    // MARK: Cross-board search

    /// Open the Liquid Glass search panel over all boards (⌘F).
    private func openSearch() {
        boards[currentBoard].elements = scene.elements   // include unsaved edits
        NSApp.activate(ignoringOtherApps: true)
        searchWindow.show()
    }

    /// Case-insensitive match against every element's text + link, across all
    /// boards. Returns hits with the board and element to jump to.
    private func searchBoards(_ query: String) -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        var hits: [SearchHit] = []
        for (bi, board) in boards.enumerated() {
            for e in board.elements {
                let text = e.text ?? ""
                let link = e.link ?? ""
                guard text.lowercased().contains(q) || link.lowercased().contains(q) else { continue }
                // Which field matched drives both the snippet and the group bucket.
                let matchedLink = link.lowercased().contains(q) && !text.lowercased().contains(q)
                let raw = matchedLink ? link : text
                let snippet = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\n", with: " ")
                let kind: String
                switch e.type {
                case "cell": kind = "Code"
                case "frame": kind = "Frame"
                case "image", "link": kind = "Link"
                default: kind = matchedLink ? "Link" : (e.type == "text" ? "Text" : "Shape")
                }
                hits.append(SearchHit(boardIndex: bi, boardName: board.name,
                                      elementId: e.id, snippet: snippet.isEmpty ? "(untitled)" : snippet,
                                      kind: kind))
            }
        }
        return hits
    }

    /// Switch to the hit's board (same path as selecting a tab) and center it.
    private func jumpToHit(_ hit: SearchHit) {
        if hit.boardIndex != currentBoard { selectBoard(hit.boardIndex) }
        controller.focusElementAction?(hit.elementId)
    }

    // MARK: Obsidian vault

    /// Bind the current board to an Obsidian vault folder (persisted per board).
    private func connectVault() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Connect"
        panel.message = "Choose your Obsidian vault folder"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        boards[currentBoard].vaultPath = url.path
        saveNow()
        refreshVault()
    }

    /// Unbind the current board's vault (back to the empty "Connect vault…" state).
    private func disconnectVault() {
        guard boards.indices.contains(currentBoard) else { return }
        boards[currentBoard].vaultPath = nil
        saveNow()
        refreshVault()
    }

    /// Scan the current board's vault for `.md` notes and publish them to the
    /// sidebar's Vault tab (capped so a huge vault can't stall the list).
    private func refreshVault() {
        guard boards.indices.contains(currentBoard),
              let vaultPath = boards[currentBoard].vaultPath else {
            controller.vaultName = nil; controller.vaultPath = nil; controller.vaultNotes = []; return
        }
        let vaultURL = URL(fileURLWithPath: vaultPath).standardizedFileURL
        controller.vaultName = vaultURL.lastPathComponent
        controller.vaultPath = vaultURL.path
        let base = vaultURL.path
        var notes: [VaultNote] = []
        let fm = FileManager.default
        if let en = fm.enumerator(at: vaultURL, includingPropertiesForKeys: [.isRegularFileKey],
                                  options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let u as URL in en {
                guard u.pathExtension.lowercased() == "md" else { continue }
                let p = u.standardizedFileURL.path
                var rel = p.hasPrefix(base + "/") ? String(p.dropFirst(base.count + 1)) : u.lastPathComponent
                if rel.hasSuffix(".md") { rel = String(rel.dropLast(3)) }
                notes.append(VaultNote(id: rel, name: u.deletingPathExtension().lastPathComponent,
                                       folder: (rel as NSString).deletingLastPathComponent))
                if notes.count >= 2000 { break }
            }
        }
        notes.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        controller.vaultNotes = notes
    }

    /// Build an `obsidian://open` link for a vault-relative note path and drop it
    /// as a link node. Shared by the sidebar's Vault tab.
    private func insertVaultNote(relativePath rel: String) {
        guard boards.indices.contains(currentBoard),
              let vaultPath = boards[currentBoard].vaultPath else { return }
        let vaultName = URL(fileURLWithPath: vaultPath).lastPathComponent
        let allowed = CharacterSet.urlQueryAllowed
        let vaultEnc = vaultName.addingPercentEncoding(withAllowedCharacters: allowed) ?? vaultName
        let fileEnc = rel.addingPercentEncoding(withAllowedCharacters: allowed) ?? rel
        let link = "obsidian://open?vault=\(vaultEnc)&file=\(fileEnc)"
        canvas.addLink(link: link, name: (rel as NSString).lastPathComponent)
    }

    /// Pick a note from the connected vault and drop it as an `obsidian://` link.
    private func insertVaultNote() {
        guard boards.indices.contains(currentBoard),
              let vaultPath = boards[currentBoard].vaultPath else {
            let alert = NSAlert()
            alert.messageText = "No vault connected"
            alert.informativeText = "Connect an Obsidian vault to this board first (Connect Obsidian Vault…)."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        let vaultURL = URL(fileURLWithPath: vaultPath)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = vaultURL
        if let md = UTType(filenameExtension: "md") { panel.allowedContentTypes = [md] }
        panel.prompt = "Insert"
        panel.message = "Choose a note from the vault"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let noteURL = panel.url else { return }

        // obsidian://open?vault=<folderName>&file=<relativePathWithoutExtension>
        let vaultName = vaultURL.lastPathComponent
        let vaultBase = vaultURL.standardizedFileURL.path
        let notePath = noteURL.standardizedFileURL.path
        var relative = notePath.hasPrefix(vaultBase + "/")
            ? String(notePath.dropFirst(vaultBase.count + 1))
            : noteURL.lastPathComponent
        if relative.hasSuffix(".md") { relative = String(relative.dropLast(3)) }

        let allowed = CharacterSet.urlQueryAllowed
        let vaultEnc = vaultName.addingPercentEncoding(withAllowedCharacters: allowed) ?? vaultName
        let fileEnc = relative.addingPercentEncoding(withAllowedCharacters: allowed) ?? relative
        let link = "obsidian://open?vault=\(vaultEnc)&file=\(fileEnc)"
        canvas.addLink(link: link, name: noteURL.deletingPathExtension().lastPathComponent)
    }

    /// Pick a file/folder with the native panel and drop a linked node.
    private func linkFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Link"
        panel.message = "Choose a file or folder to link onto the whiteboard"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            canvas.addFileNode(path: url.path)
        }
    }

    private func insertImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.message = "Choose an image to place on the whiteboard"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { canvas.addImage(path: url.path) }
    }

    /// Prompt for a URL and drop a 🔗 link node.
    private func linkURL() {
        let alert = NSAlert()
        alert.messageText = "Link a URL"
        alert.informativeText = "Web (https://…) or app link (obsidian://…)."
        alert.addButton(withTitle: "Link")
        alert.addButton(withTitle: "Cancel")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        tf.placeholderString = "https://…"
        alert.accessoryView = tf
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = tf
        if alert.runModal() == .alertFirstButtonReturn {
            let url = tf.stringValue.trimmingCharacters(in: .whitespaces)
            guard !url.isEmpty else { return }
            let name = URL(string: url)?.host ?? url
            canvas.addLink(link: url, name: name)
        }
    }

    /// True when a text field / editor is focused, so "/" should type normally.
    private func isTextEditing() -> Bool {
        (NSApp.keyWindow?.firstResponder as? NSText) != nil
    }

    @objc private func screensChanged() {
        if let screen = NSScreen.main { window.fit(to: screen) }
    }
}
