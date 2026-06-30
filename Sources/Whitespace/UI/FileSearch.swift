import AppKit

/// Borderless panel that can become key (so its text field accepts typing).
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Native file-link search: a focused text field + a results table, backed by
/// Spotlight (`mdfind`). Built in AppKit (not SwiftUI) so keyboard focus and the
/// results list are deterministic. Press "/" or menu → Link File… to open.
@MainActor
final class FileSearchWindow: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let panel: KeyPanel
    private let field: NSTextField
    private let table: NSTableView
    private var results: [String] = []
    private var pending: DispatchWorkItem?

    var onPick: ((String) -> Void)?

    override init() {
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        field = NSTextField()
        table = NSTableView()
        super.init()

        panel.level = .modalPanel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.moveToActiveSpace, .ignoresCycle]

        // Glass-ish backdrop.
        let bg = NSVisualEffectView()
        bg.material = .hudWindow
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 14
        bg.layer?.masksToBounds = true
        bg.translatesAutoresizingMaskIntoConstraints = false

        field.placeholderString = "Search your files to link…"
        field.font = .systemFont(ofSize: 15)
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: .init("file"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 38
        table.backgroundColor = .clear
        table.style = .plain
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        table.doubleAction = #selector(rowClicked)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(bg)
        container.addSubview(field)
        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            bg.topAnchor.constraint(equalTo: container.topAnchor),
            bg.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bg.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            field.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            field.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),

            scroll.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])
        panel.contentView = container
    }

    func show() {
        field.stringValue = ""
        results = []
        table.reloadData()
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - 230,
                                         y: screen.frame.midY + 80))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        let ok = panel.makeFirstResponder(field)   // deterministic focus
        Log.write("filesearch.show: key=\(panel.isKeyWindow) firstResponderOK=\(ok)")
    }

    func hide() { panel.orderOut(nil) }

    // MARK: Search

    func controlTextDidChange(_ obj: Notification) {
        pending?.cancel()
        let q = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = []; table.reloadData(); return }
        let item = DispatchWorkItem {
            let out = Self.mdfind(q)
            DispatchQueue.main.async { [weak self] in
                self?.results = out
                self?.table.reloadData()
                Log.write("filesearch query=\(q) results=\(out.count)")
            }
        }
        pending = item
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    // Return = pick selected (or first); Esc = close.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            let row = table.selectedRow >= 0 ? table.selectedRow : 0
            if results.indices.contains(row) { pick(results[row]) }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            hide(); return true
        case #selector(NSResponder.moveDown(_:)):
            selectRow((table.selectedRow < 0 ? 0 : table.selectedRow + 1)); return true
        case #selector(NSResponder.moveUp(_:)):
            selectRow(table.selectedRow - 1); return true
        default:
            return false
        }
    }

    private func selectRow(_ i: Int) {
        guard results.indices.contains(i) else { return }
        table.selectRowIndexes([i], byExtendingSelection: false)
        table.scrollRowToVisible(i)
    }

    @objc private func rowClicked() {
        let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        if results.indices.contains(row) { pick(results[row]) }
    }

    private func pick(_ path: String) {
        Log.write("filesearch pick=\(path)")
        hide()
        onPick?(path)
    }

    private static func mdfind(_ q: String) -> [String] {
        let p = Process()
        p.launchPath = "/usr/bin/mdfind"
        p.arguments = ["-name", q]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.terminate()
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n").prefix(20).map(String.init)
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let path = results[row]
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? {
            let v = NSTableCellView()
            let title = NSTextField(labelWithString: "")
            title.identifier = .init("title")
            title.font = .systemFont(ofSize: 13, weight: .medium)
            let sub = NSTextField(labelWithString: "")
            sub.identifier = .init("sub")
            sub.font = .systemFont(ofSize: 10)
            sub.textColor = .secondaryLabelColor
            sub.lineBreakMode = .byTruncatingMiddle
            let stack = NSStackView(views: [title, sub])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 1
            stack.translatesAutoresizingMaskIntoConstraints = false
            v.addSubview(stack)
            v.identifier = id
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 8),
                stack.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -8),
                stack.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            ])
            return v
        }()
        (cell.subviews.first?.subviews.first as? NSTextField)?.stringValue = (path as NSString).lastPathComponent
        (cell.subviews.first?.subviews.last as? NSTextField)?.stringValue = path
        return cell
    }
}
