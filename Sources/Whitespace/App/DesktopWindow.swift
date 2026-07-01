import AppKit

/// A borderless window pinned to the desktop layer — it floats above the
/// wallpaper but beneath the Finder icon layer, spans every Space, and stays
/// put when other windows move. This is the proven Plash / Übersicht pattern.
///
/// Because a window at desktop level can't reliably take mouse events away from
/// the Finder icon layer, the window flips between two modes:
///   - idle: `ignoresMouseEvents = true`, parked at `.desktopWindow` level so
///     the drawing shows through and desktop icons behave normally.
///   - edit: `ignoresMouseEvents = false`, raised so it captures clicks for
///     drawing.
final class DesktopWindow: NSWindow {

    /// macOS desktop window level — directly above the wallpaper.
    private static let desktopLevel = NSWindow.Level(
        rawValue: Int(CGWindowLevelForKey(.desktopWindow))
    )

    /// While editing, sit at the normal window level so the canvas draws *above*
    /// the desktop-icon layer AND macOS desktop widgets (which live in the
    /// negative desktop region and were cutting through the drawing). The
    /// floating palette (level 3) still stays on top.
    private static let editLevel = NSWindow.Level.normal

    private(set) var isEditing = false

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = Self.desktopLevel
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        setFrame(screen.frame, display: true)
    }

    // Borderless windows are non-key by default; edit mode needs key status to
    // receive keyboard input (e.g. typing into text elements).
    override var canBecomeKey: Bool { isEditing }
    override var canBecomeMain: Bool { isEditing }

    func setEditing(_ editing: Bool) {
        isEditing = editing
        ignoresMouseEvents = !editing
        // Keep-icons mode never rises above the icon layer, so folders stay
        // visible (at the cost of limited drawing on empty desktop areas).
        let activeLevel = Settings.keepDesktopIcons ? Self.desktopLevel : Self.editLevel
        level = editing ? activeLevel : Self.desktopLevel
        if editing {
            makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            resignKey()
            orderFront(nil)
        }
    }

    /// Match a (possibly new) screen geometry — called on resolution changes.
    func fit(to screen: NSScreen) {
        setFrame(screen.frame, display: true)
    }
}
