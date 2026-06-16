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

    /// Rainbow-bracket depth palette (cycled %6), appearance-aware. Tuned for
    /// mutual contrast and legibility against both light and dark backgrounds.
    public static let bracketDepthColors: [NSColor] = [
        dynamic(light: NSColor(srgbRed: 0.72, green: 0.52, blue: 0.04, alpha: 1),   // gold
                dark:  NSColor(srgbRed: 0.95, green: 0.80, blue: 0.35, alpha: 1)),
        dynamic(light: NSColor(srgbRed: 0.52, green: 0.25, blue: 0.70, alpha: 1),   // violet
                dark:  NSColor(srgbRed: 0.78, green: 0.62, blue: 0.95, alpha: 1)),
        dynamic(light: NSColor(srgbRed: 0.13, green: 0.43, blue: 0.85, alpha: 1),   // blue
                dark:  NSColor(srgbRed: 0.45, green: 0.72, blue: 0.99, alpha: 1)),
        dynamic(light: NSColor(srgbRed: 0.12, green: 0.55, blue: 0.24, alpha: 1),   // green
                dark:  NSColor(srgbRed: 0.50, green: 0.85, blue: 0.55, alpha: 1)),
        dynamic(light: NSColor(srgbRed: 0.80, green: 0.45, blue: 0.10, alpha: 1),   // orange
                dark:  NSColor(srgbRed: 0.98, green: 0.70, blue: 0.40, alpha: 1)),
        dynamic(light: NSColor(srgbRed: 0.05, green: 0.55, blue: 0.55, alpha: 1),   // teal
                dark:  NSColor(srgbRed: 0.40, green: 0.85, blue: 0.85, alpha: 1)),
    ]

    /// Color for a stray / mismatched bracket.
    public static let bracketUnmatchedColor: NSColor =
        dynamic(light: NSColor(srgbRed: 0.70, green: 0.30, blue: 0.30, alpha: 1),
                dark:  NSColor(srgbRed: 0.85, green: 0.45, blue: 0.45, alpha: 1))

    /// Color for a bracket at the given nesting depth (cycles through the palette).
    public static func bracketColor(forDepth depth: Int) -> NSColor {
        let n = bracketDepthColors.count
        return bracketDepthColors[((depth % n) + n) % n]
    }
}
