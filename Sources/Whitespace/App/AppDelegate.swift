import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: DesktopWindow!
    private var canvas: CanvasView!
    private var menuBar: MenuBarController!
    private var palette: PaletteWindow!
    private let controller = CanvasController()
    private var scene: Scene!
    private var paletteHidden = false

    private var boards: [BoardDoc] = []
    private var currentBoard = 0

    private var autosaveItem: DispatchWorkItem?

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

        palette = PaletteWindow(controller: controller)

        canvas.onSlashSearch = { [weak self] in self?.linkFile() }
        controller.linkFileAction = { [weak self] in self?.linkFile() }

        // Catch "/" app-wide (works whichever of our windows is key), except
        // while typing in a text field, so it always opens the file picker.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window.isEditing else { return event }
            if event.charactersIgnoringModifiers == "/", !self.isTextEditing() {
                self.linkFile()
                return nil
            }
            return event
        }

        controller.addTab = { [weak self] in self?.addBoard() }
        controller.selectTab = { [weak self] i in self?.selectBoard(i) }
        controller.renameTab = { [weak self] i, name in self?.renameBoard(i, name) }
        controller.closeTab = { [weak self] i in self?.closeBoard(i) }

        menuBar = MenuBarController(
            onToggleEdit: { [weak self] in self?.toggleEdit() },
            onQuit: { [weak self] in self?.saveNow(); NSApp.terminate(nil) },
            onSetIdleOpacity: { [weak self] v in
                self?.canvas.idleBoardOpacity = v; self?.canvas.needsDisplay = true
            },
            onSetEditOpacity: { [weak self] v in
                self?.canvas.editBoardOpacity = v; self?.canvas.needsDisplay = true
            },
            onToggleKeepIcons: { [weak self] _ in
                // Re-apply the window level immediately if currently editing.
                guard let self, self.window.isEditing else { return }
                self.window.setEditing(true)
            },
            onTogglePalette: { [weak self] in self?.togglePalette() },
            onExportPNG: { [weak self] in self?.export(.png) },
            onExportSVG: { [weak self] in self?.export(.svg) },
            onLinkFile: { [weak self] in self?.linkFile() }
        )

        // System-wide hotkeys (one shared handler dispatches by id):
        // ⌥⌘W toggles the whiteboard, ⌥⌘Q hides the palette.
        HotKeyCenter.shared.register(id: 1, keyCode: UInt32(kVK_ANSI_W),
                                     modifiers: UInt32(cmdKey | optionKey)) { [weak self] in
            self?.toggleEdit()
        }
        HotKeyCenter.shared.register(id: 2, keyCode: UInt32(kVK_ANSI_Q),
                                     modifiers: UInt32(cmdKey | optionKey)) { [weak self] in
            self?.togglePalette()
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        // Start in Edit Mode so a launch is immediately visible (palette +
        // border appear); otherwise a menu-bar app with a transparent idle
        // board looks like nothing happened.
        toggleEdit()
    }

    private func toggleEdit() {
        let editing = !window.isEditing
        window.setEditing(editing)
        canvas.isEditing = editing
        menuBar.setEditing(editing)
        if editing {
            window.makeFirstResponder(canvas)
            if !paletteHidden { palette.show() }
        } else {
            palette.hide()
            saveNow()
        }
    }

    /// Hide/show just the tool palette while staying in drawing mode (⌥⌘Q).
    private func togglePalette() {
        guard window.isEditing else { return }
        paletteHidden.toggle()
        paletteHidden ? palette.hide() : palette.show()
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

    private enum ExportKind { case png, svg }

    private func export(_ kind: ExportKind) {
        guard Export.contentBounds(scene.elements) != nil else {
            let alert = NSAlert()
            alert.messageText = "Nothing to export"
            alert.informativeText = "Draw something first, then export."
            alert.runModal()
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = kind == .png ? "whiteboard.png" : "whiteboard.svg"
        panel.allowedContentTypes = [kind == .png ? .png : .svg]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        switch kind {
        case .png:
            try? Export.png(scene.elements)?.write(to: url, options: .atomic)
        case .svg:
            try? Export.svg(scene.elements)?.write(to: url, atomically: true, encoding: .utf8)
        }
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

    /// True when a text field / editor is focused, so "/" should type normally.
    private func isTextEditing() -> Bool {
        (NSApp.keyWindow?.firstResponder as? NSText) != nil
    }

    @objc private func screensChanged() {
        if let screen = NSScreen.main { window.fit(to: screen) }
    }
}
