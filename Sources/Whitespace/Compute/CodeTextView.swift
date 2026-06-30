import AppKit

/// A monospaced text view for editing a cell's source. Runs the cell on ⌘↵
/// instead of inserting a newline.
final class CodeTextView: NSTextView {
    var onRun: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "\r" {
            onRun?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
