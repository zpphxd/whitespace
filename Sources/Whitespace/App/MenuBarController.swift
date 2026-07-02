import AppKit

/// Status-bar item: the always-available control surface for the desktop
/// canvas. Toggling Edit Mode is the primary action (also bound to a hotkey).
@MainActor
final class MenuBarController {

    private let statusItem: NSStatusItem
    private let editItem: NSMenuItem
    private let onToggleEdit: () -> Void
    private var quitHandler: (() -> Void)?
    private var setEditOpacity: ((CGFloat) -> Void)?
    private var setBoardPattern: ((String) -> Void)?
    private var toggleKeepIcons: ((Bool) -> Void)?
    private var togglePalette: (() -> Void)?
    private var exportPNG: (() -> Void)?
    private var exportSVG: (() -> Void)?
    private var exportHTML: (() -> Void)?
    private var linkFile: (() -> Void)?
    private var setLinkColor: ((String) -> Void)?
    private var openFile: (() -> Void)?
    private var search: (() -> Void)?
    private var connectVault: (() -> Void)?
    private var insertVaultNote: (() -> Void)?
    private var checkForUpdates: (() -> Void)?
    private let paletteItem: NSMenuItem
    private var loginMenuItem: NSMenuItem?

    init(onToggleEdit: @escaping () -> Void,
         onQuit: @escaping () -> Void,
         onSetEditOpacity: @escaping (CGFloat) -> Void,
         onSetBoardPattern: @escaping (String) -> Void,
         onToggleKeepIcons: @escaping (Bool) -> Void,
         onTogglePalette: @escaping () -> Void,
         onExportPNG: @escaping () -> Void,
         onExportSVG: @escaping () -> Void,
         onExportHTML: @escaping () -> Void,
         onLinkFile: @escaping () -> Void,
         onSetLinkColor: @escaping (String) -> Void,
         onOpenFile: @escaping () -> Void,
         onSearch: @escaping () -> Void,
         onConnectVault: @escaping () -> Void,
         onInsertVaultNote: @escaping () -> Void,
         onCheckForUpdates: @escaping () -> Void) {
        self.onToggleEdit = onToggleEdit
        self.quitHandler = onQuit
        self.setEditOpacity = onSetEditOpacity
        self.setBoardPattern = onSetBoardPattern
        self.toggleKeepIcons = onToggleKeepIcons
        self.togglePalette = onTogglePalette
        self.exportPNG = onExportPNG
        self.exportSVG = onExportSVG
        self.exportHTML = onExportHTML
        self.linkFile = onLinkFile
        self.setLinkColor = onSetLinkColor
        self.openFile = onOpenFile
        self.search = onSearch
        self.connectVault = onConnectVault
        self.insertVaultNote = onInsertVaultNote
        self.checkForUpdates = onCheckForUpdates
        paletteItem = NSMenuItem(title: "Hide Palette", action: nil, keyEquivalent: "q")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        editItem = NSMenuItem(title: "Start Drawing", action: nil, keyEquivalent: "w")

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "scribble.variable",
                accessibilityDescription: "Whitespace"
            )
        }

        let menu = NSMenu()
        let header = NSMenuItem(title: "Whitespace — Desktop Whiteboard", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        editItem.target = self
        editItem.action = #selector(toggleEdit)
        editItem.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(editItem)

        paletteItem.target = self
        paletteItem.action = #selector(togglePaletteItem)
        paletteItem.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(paletteItem)
        menu.addItem(.separator())

        menu.addItem(makeBoardMenu())
        menu.addItem(.separator())

        let searchItem = NSMenuItem(title: "Search Boards…", action: #selector(searchAction), keyEquivalent: "")
        searchItem.target = self
        menu.addItem(searchItem)
        menu.addItem(.separator())

        let linkItem = NSMenuItem(title: "Link File…", action: #selector(linkFileAction), keyEquivalent: "")
        linkItem.target = self
        menu.addItem(linkItem)
        menu.addItem(makeLinkColorMenu())
        menu.addItem(.separator())

        let connectVaultItem = NSMenuItem(title: "Connect Obsidian Vault…", action: #selector(connectVaultAction), keyEquivalent: "")
        connectVaultItem.target = self
        menu.addItem(connectVaultItem)
        let insertNoteItem = NSMenuItem(title: "Insert Vault Note…", action: #selector(insertVaultNoteAction), keyEquivalent: "")
        insertNoteItem.target = self
        menu.addItem(insertNoteItem)
        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open .excalidraw…", action: #selector(openFileAction), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())

        let exportPNGItem = NSMenuItem(title: "Export as PNG…", action: #selector(exportPNGItemAction), keyEquivalent: "")
        exportPNGItem.target = self
        menu.addItem(exportPNGItem)
        let exportSVGItem = NSMenuItem(title: "Export as SVG…", action: #selector(exportSVGItemAction), keyEquivalent: "")
        exportSVGItem.target = self
        menu.addItem(exportSVGItem)
        let exportHTMLItem = NSMenuItem(title: "Export as HTML…", action: #selector(exportHTMLItemAction), keyEquivalent: "")
        exportHTMLItem.target = self
        menu.addItem(exportHTMLItem)
        menu.addItem(.separator())

        let updatesItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesItem), keyEquivalent: "")
        updatesItem.target = self
        menu.addItem(updatesItem)

        let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLoginItem(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LoginItem.isEnabled ? .on : .off
        loginMenuItem = loginItem
        menu.addItem(loginItem)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Whitespace", action: nil, keyEquivalent: "q")
        quit.target = self
        quit.action = #selector(quit(_:))
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func makeBoardMenu() -> NSMenuItem {
        let board = NSMenuItem(title: "Board Appearance", action: nil, keyEquivalent: "")
        let sub = NSMenu()

        let editHeader = NSMenuItem(title: "White Board Transparency:", action: nil, keyEquivalent: "")
        editHeader.isEnabled = false
        sub.addItem(editHeader)
        for (title, value) in [("Light wash", 0.85), ("Solid white", 1.0), ("Transparent", 0.0)] {
            let item = NSMenuItem(title: "  \(title)", action: #selector(editOpacity(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = Settings.editBoardOpacity == CGFloat(value) ? .on : .off
            sub.addItem(item)
        }

        sub.addItem(.separator())
        let bgHeader = NSMenuItem(title: "Background:", action: nil, keyEquivalent: "")
        bgHeader.isEnabled = false
        sub.addItem(bgHeader)
        for (title, value) in [("Dots", "dots"), ("Grid", "grid"), ("Plain", "none")] {
            let item = NSMenuItem(title: "  \(title)", action: #selector(boardPattern(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = Settings.boardPattern == value ? .on : .off
            sub.addItem(item)
        }
        board.submenu = sub
        return board
    }

    @objc private func checkForUpdatesItem() { checkForUpdates?() }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        let now = LoginItem.setEnabled(!(sender.state == .on))
        sender.state = now ? .on : .off
    }

    /// Sync the menu checkmark with the current login-item state (after the
    /// first-run prompt toggles it).
    func refreshLoginItem() { loginMenuItem?.state = LoginItem.isEnabled ? .on : .off }

    @objc private func boardPattern(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Settings.boardPattern = value
        setBoardPattern?(value)
        sender.menu?.items.forEach { item in
            if item.action == #selector(boardPattern(_:)) {
                item.state = (item.representedObject as? String) == value ? .on : .off
            }
        }
    }

    private func refreshChecks(in menu: NSMenu?, selector: Selector, current: CGFloat) {
        menu?.items.forEach { item in
            guard item.action == selector, let v = item.representedObject as? Double else { return }
            item.state = CGFloat(v) == current ? .on : .off
        }
    }

    @objc private func editOpacity(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? Double else { return }
        Settings.editBoardOpacity = CGFloat(v)
        setEditOpacity?(CGFloat(v))
        refreshChecks(in: sender.menu, selector: #selector(editOpacity(_:)), current: CGFloat(v))
    }

    func setEditing(_ editing: Bool) {
        editItem.title = editing ? "Stop Drawing (show desktop)" : "Start Drawing"
        editItem.state = editing ? .on : .off
        if let button = statusItem.button {
            let symbol = editing ? "scribble.variable" : "scribble"
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Whitespace")
        }
    }

    @objc private func toggleKeepIconsItem(_ sender: NSMenuItem) {
        let newValue = !(sender.state == .on)
        sender.state = newValue ? .on : .off
        Settings.keepDesktopIcons = newValue
        toggleKeepIcons?(newValue)
    }

    func setPaletteHidden(_ hidden: Bool) {
        paletteItem.title = hidden ? "Show Palette" : "Hide Palette"
    }

    private func makeLinkColorMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Link Color", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let colors: [(String, String)] = [
            ("Purple", "#6965db"), ("Blue", "#1971c2"), ("Green", "#2f9e44"),
            ("Red", "#e03131"), ("Orange", "#f08c00"), ("Gray", "#868e96"), ("Black", "#1e1e1e"),
        ]
        for (name, hex) in colors {
            let i = NSMenuItem(title: name, action: #selector(linkColorItem(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = hex
            i.state = Settings.linkColor.lowercased() == hex ? .on : .off
            sub.addItem(i)
        }
        item.submenu = sub
        return item
    }

    @objc private func linkColorItem(_ sender: NSMenuItem) {
        guard let hex = sender.representedObject as? String else { return }
        Settings.linkColor = hex
        setLinkColor?(hex)
        sender.menu?.items.forEach { $0.state = ($0.representedObject as? String) == hex ? .on : .off }
    }

    @objc private func togglePaletteItem() { togglePalette?() }
    @objc private func exportPNGItemAction() { exportPNG?() }
    @objc private func exportSVGItemAction() { exportSVG?() }
    @objc private func exportHTMLItemAction() { exportHTML?() }
    @objc private func linkFileAction() { linkFile?() }
    @objc private func openFileAction() { openFile?() }
    @objc private func searchAction() { search?() }
    @objc private func connectVaultAction() { connectVault?() }
    @objc private func insertVaultNoteAction() { insertVaultNote?() }
    @objc private func toggleEdit() { onToggleEdit() }
    @objc private func quit(_ sender: Any?) { quitHandler?() }
}
