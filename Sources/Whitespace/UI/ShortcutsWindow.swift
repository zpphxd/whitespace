import AppKit
import Carbon.HIToolbox

/// Carbon modifier mask → NSEvent flags and human-readable symbols.
enum Shortcut {
    static func carbonMods(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    static func display(keyCode: UInt32, mods: UInt32) -> String {
        var s = ""
        if mods & UInt32(controlKey) != 0 { s += "⌃" }
        if mods & UInt32(optionKey) != 0 { s += "⌥" }
        if mods & UInt32(shiftKey) != 0 { s += "⇧" }
        if mods & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + keyName(keyCode)
    }

    private static let names: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0",
        49: "Space", 36: "Return", 53: "Esc",
    ]
    static func keyName(_ code: UInt32) -> String { names[code] ?? "Key\(code)" }
}

/// Click to record a new shortcut; captures the next modifier+key combo.
final class KeyRecorder: NSView {
    var keyCode: UInt32
    var mods: UInt32
    var onCapture: ((UInt32, UInt32) -> Void)?
    private var recording = false

    init(keyCode: UInt32, mods: UInt32) {
        self.keyCode = keyCode; self.mods = mods
        super.init(frame: NSRect(x: 0, y: 0, width: 130, height: 26))
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 130).isActive = true
        heightAnchor.constraint(equalToConstant: 26).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 130, height: 26) }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        recording = true
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        let m = Shortcut.carbonMods(event.modifierFlags)
        guard m != 0 else { return }  // require at least one modifier
        keyCode = UInt32(event.keyCode)
        mods = m
        recording = false
        onCapture?(keyCode, mods)
        window?.makeFirstResponder(nil)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlColor).setFill()
        path.fill()
        NSColor.separatorColor.setStroke(); path.stroke()
        let text = recording ? "Press keys…" : Shortcut.display(keyCode: keyCode, mods: mods)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: recording ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attrs)
    }
}

@MainActor
final class ShortcutsWindow {
    private let panel: NSPanel
    var onChange: (() -> Void)?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 150),
                        styleMask: [.titled, .closable, .utilityWindow],
                        backing: .buffered, defer: false)
        panel.title = "Keyboard Shortcuts"
        panel.isFloatingPanel = true

        func row(_ label: String, recorder: KeyRecorder) -> NSStackView {
            let l = NSTextField(labelWithString: label)
            l.font = .systemFont(ofSize: 13)
            let s = NSStackView(views: [l, NSView(), recorder])
            s.orientation = .horizontal
            s.distribution = .fill
            l.setContentHuggingPriority(.defaultLow, for: .horizontal)
            return s
        }

        let editRec = KeyRecorder(keyCode: Settings.editKeyCode, mods: Settings.editMods)
        editRec.onCapture = { [weak self] code, mods in
            Settings.editKeyCode = code; Settings.editMods = mods; self?.onChange?()
        }
        let palRec = KeyRecorder(keyCode: Settings.paletteKeyCode, mods: Settings.paletteMods)
        palRec.onCapture = { [weak self] code, mods in
            Settings.paletteKeyCode = code; Settings.paletteMods = mods; self?.onChange?()
        }

        let stack = NSStackView(views: [
            row("Toggle whiteboard", recorder: editRec),
            row("Hide / show palette", recorder: palRec),
        ])
        stack.orientation = .vertical
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])
        panel.contentView = content
    }

    func show() {
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}
