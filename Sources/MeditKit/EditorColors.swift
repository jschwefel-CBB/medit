import AppKit

/// Editor color choices. The plain-text foreground is intentionally a softened
/// off-white in dark mode (pure `.textColor` white is harsh against a dark
/// background) and a near-black in light mode, both easy on the eyes.
public enum EditorColors {

    /// Softened foreground that adapts to the effective appearance.
    public static let foreground = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(white: 0.82, alpha: 1.0)   // soft off-white (~#D1D1D1)
            : NSColor(white: 0.13, alpha: 1.0)   // near-black (~#212121)
    }

    /// Appearance-resolving color: picks `dark` under a dark effective appearance.
    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    /// Build an opaque sRGB color from a 0xRRGGBB literal.
    static func hex(_ rgb: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255.0,
                green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
                blue: CGFloat(rgb & 0xFF) / 255.0,
                alpha: 1.0)
    }

    /// Rainbow-bracket depth palette (cycled %6), appearance-aware. "Editor-classic"
    /// gold/blue/magenta/teal/orange/violet cycle — saturated for clear level-to-
    /// level separation on both light and dark backgrounds.
    public static let bracketDepthColors: [NSColor] = [
        dynamic(light: hex(0xC99A00), dark: hex(0xE8C547)),   // 0 gold
        dynamic(light: hex(0x1E6FE0), dark: hex(0x5AA6FF)),   // 1 blue
        dynamic(light: hex(0xC42BA6), dark: hex(0xEE6FD0)),   // 2 magenta
        dynamic(light: hex(0x009688), dark: hex(0x3FD0C0)),   // 3 teal
        dynamic(light: hex(0xD9601A), dark: hex(0xFF9D4D)),   // 4 orange
        dynamic(light: hex(0x7A4FE0), dark: hex(0xB48CFF)),   // 5 violet
    ]

    /// Color for a stray / mismatched bracket.
    public static let bracketUnmatchedColor: NSColor =
        dynamic(light: hex(0xB33A3A), dark: hex(0xD97070))

    /// Color for a bracket at the given nesting depth (cycles through the palette).
    public static func bracketColor(forDepth depth: Int) -> NSColor {
        let n = bracketDepthColors.count
        return bracketDepthColors[((depth % n) + n) % n]
    }
}
