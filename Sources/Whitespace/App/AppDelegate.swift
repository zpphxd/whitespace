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
    private var fileSearch: FileSearchWindow!
    private var paletteHidden = false

    private var autosaveItem: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { return }

        scene = Scene(elements: DocumentStore.load(from: DocumentStore.defaultURL))

        window = DesktopWindow(screen: screen)
        canvas = CanvasView(frame: screen.frame, scene: scene, controller: controller)
        canvas.autoresizingMask = [.width, .height]
        canvas.onSceneChange = { [weak self] in self?.scheduleAutosave() }
        window.contentView = canvas
        window.orderFront(nil)

        palette = PaletteWindow(controller: controller)

        fileSearch = FileSearchWindow()
        fileSearch.onPick = { [weak self] path in self?.canvas.addFileNode(path: path) }
        canvas.onSlashSearch = { [weak self] in self?.fileSearch.show() }

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
            onExportSVG: { [weak self] in self?.export(.svg) }
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
        DocumentStore.save(scene.elements, to: DocumentStore.defaultURL)
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

    @objc private func screensChanged() {
        if let screen = NSScreen.main { window.fit(to: screen) }
    }
}
