import Foundation
import Carbon.HIToolbox

/// User-configurable preferences, persisted in `UserDefaults`. Exposed in the
/// menu-bar menu so the board appearance can be flipped without a rebuild.
/// Caseless enum (no stored state) — every value reads/writes UserDefaults.
enum Settings {
    private static var defaults: UserDefaults { .standard }

    /// Anthropic API key for LLM/agent cells (user-entered, stored locally).
    static var anthropicKey: String? {
        get { defaults.string(forKey: "anthropicKey") }
        set { defaults.set(newValue, forKey: "anthropicKey") }
    }

    private enum Key {
        static let idleOpacity = "idleBoardOpacity"
        static let editOpacity = "editBoardOpacity"
        static let keepIcons = "keepDesktopIcons"
        static let linkColor = "linkColor"
        static let linkStyle = "linkStyle"
        static let stayOnWallpaper = "stayOnWallpaper"
        static let editKeyCode = "editKeyCode", editMods = "editMods"
        static let paletteKeyCode = "paletteKeyCode", paletteMods = "paletteMods"
    }

    // Global hotkeys (Carbon keyCode + modifier mask). Defaults: ⌥⌘W / ⌥⌘Q.
    static var editKeyCode: UInt32 {
        get { defaults.object(forKey: Key.editKeyCode) == nil ? UInt32(kVK_ANSI_W) : UInt32(defaults.integer(forKey: Key.editKeyCode)) }
        set { defaults.set(Int(newValue), forKey: Key.editKeyCode) }
    }
    static var editMods: UInt32 {
        get { defaults.object(forKey: Key.editMods) == nil ? UInt32(cmdKey | optionKey) : UInt32(defaults.integer(forKey: Key.editMods)) }
        set { defaults.set(Int(newValue), forKey: Key.editMods) }
    }
    static var paletteKeyCode: UInt32 {
        get { defaults.object(forKey: Key.paletteKeyCode) == nil ? UInt32(kVK_ANSI_Q) : UInt32(defaults.integer(forKey: Key.paletteKeyCode)) }
        set { defaults.set(Int(newValue), forKey: Key.paletteKeyCode) }
    }
    static var paletteMods: UInt32 {
        get { defaults.object(forKey: Key.paletteMods) == nil ? UInt32(cmdKey | optionKey) : UInt32(defaults.integer(forKey: Key.paletteMods)) }
        set { defaults.set(Int(newValue), forKey: Key.paletteMods) }
    }

    /// Color used to render linked file/folder nodes (just "– name" text).
    static var linkColor: String {
        get { defaults.string(forKey: Key.linkColor) ?? "#6965db" }
        set { defaults.set(newValue, forKey: Key.linkColor) }
    }

    /// How file/folder link nodes render: "preview" (QuickLook card),
    /// "icon" (icon + name), or "text" (colored, underlined name only).
    static var linkStyle: String {
        get { defaults.string(forKey: Key.linkStyle) ?? "preview" }
        set { defaults.set(newValue, forKey: Key.linkStyle) }
    }

    /// When true, the board never rises above the Finder desktop-icon layer, so
    /// your folders stay visible. Tradeoff: while editing below the icon layer,
    /// clicks on empty desktop go to Finder, so drawing is limited — best used
    /// as a "view my notes among my icons" mode.
    static var keepDesktopIcons: Bool {
        get { defaults.bool(forKey: Key.keepIcons) }
        set { defaults.set(newValue, forKey: Key.keepIcons) }
    }

    /// When true (default), leaving Edit Mode (⌥⌘W) keeps your drawings visible on
    /// the wallpaper. When false, ⌥⌘W hides the whole canvas — back to a clean
    /// desktop — and ⌥⌘W brings it all back.
    static var stayOnWallpaper: Bool {
        get { defaults.object(forKey: Key.stayOnWallpaper) == nil ? true : defaults.bool(forKey: Key.stayOnWallpaper) }
        set { defaults.set(newValue, forKey: Key.stayOnWallpaper) }
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
