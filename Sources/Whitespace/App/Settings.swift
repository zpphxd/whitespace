import Foundation

/// User-configurable preferences, persisted in `UserDefaults`. Exposed in the
/// menu-bar menu so the board appearance can be flipped without a rebuild.
/// Caseless enum (no stored state) — every value reads/writes UserDefaults.
enum Settings {
    private static var defaults: UserDefaults { .standard }

    private enum Key {
        static let idleOpacity = "idleBoardOpacity"
        static let editOpacity = "editBoardOpacity"
        static let keepIcons = "keepDesktopIcons"
        static let linkColor = "linkColor"
    }

    /// Color used to render linked file/folder nodes (just "– name" text).
    static var linkColor: String {
        get { defaults.string(forKey: Key.linkColor) ?? "#6965db" }
        set { defaults.set(newValue, forKey: Key.linkColor) }
    }

    /// When true, the board never rises above the Finder desktop-icon layer, so
    /// your folders stay visible. Tradeoff: while editing below the icon layer,
    /// clicks on empty desktop go to Finder, so drawing is limited — best used
    /// as a "view my notes among my icons" mode.
    static var keepDesktopIcons: Bool {
        get { defaults.bool(forKey: Key.keepIcons) }
        set { defaults.set(newValue, forKey: Key.keepIcons) }
    }

    // NOTE: read with `double(forKey:)` — `object(forKey:) as? CGFloat` fails to
    // cast the stored NSNumber, so it always returned the default (the bug where
    // the gear's "When idle" setting never seemed to change).

    /// Backdrop opacity when not editing. 0 = drawings float on the wallpaper.
    static var idleBoardOpacity: CGFloat {
        get { defaults.object(forKey: Key.idleOpacity) == nil ? 0.0 : CGFloat(defaults.double(forKey: Key.idleOpacity)) }
        set { defaults.set(Double(newValue), forKey: Key.idleOpacity) }
    }

    /// Backdrop opacity while editing. A light wash so it reads as a canvas.
    static var editBoardOpacity: CGFloat {
        get { defaults.object(forKey: Key.editOpacity) == nil ? 0.85 : CGFloat(defaults.double(forKey: Key.editOpacity)) }
        set { defaults.set(Double(newValue), forKey: Key.editOpacity) }
    }
}
