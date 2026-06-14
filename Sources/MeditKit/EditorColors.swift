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
}
