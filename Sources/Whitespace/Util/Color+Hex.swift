import AppKit

extension NSColor {
    /// Build a color from a 24-bit RGB integer, e.g. `0x6965db`.
    convenience init(hex: Int, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }

    /// Parse an Excalidraw color string: `#rrggbb`, `#rgb`, or `transparent`.
    /// Returns `nil` for "transparent" so callers can skip filling.
    static func excalidraw(_ string: String) -> NSColor? {
        let s = string.trimmingCharacters(in: .whitespaces).lowercased()
        if s == "transparent" { return nil }
        var hex = s
        if hex.hasPrefix("#") { hex.removeFirst() }
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6, let value = Int(hex, radix: 16) else {
            return NSColor(hex: 0x1e1e1e)
        }
        return NSColor(hex: value)
    }
}
