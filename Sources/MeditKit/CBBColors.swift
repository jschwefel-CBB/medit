import AppKit

/// Cold Bore Ballistics canonical brand palette (from the CBB Brand & Legal
/// Language Guide §5). Hex is the master value. Used where CBB branding makes
/// sense in medit's UI — currently the Markdown table header + gridlines.
public enum CBBColors {
    /// Cold Bore Blue — primary brand background fill. `#0a2351`.
    public static let blue = NSColor(srgbRed: 10/255, green: 35/255, blue: 81/255, alpha: 1)
    /// Cold Bore Steel — accent; rings, strokes, divider lines. `#4a9fc8`.
    public static let steel = NSColor(srgbRed: 74/255, green: 159/255, blue: 200/255, alpha: 1)
    /// Cold Bore Stainless — lightest tint; light card background, wordmark text. `#d6e4ef`.
    public static let stainless = NSColor(srgbRed: 214/255, green: 228/255, blue: 239/255, alpha: 1)
    /// Muted divider text. `#6a8fa8`.
    public static let mutedSteel = NSColor(srgbRed: 106/255, green: 143/255, blue: 168/255, alpha: 1)
}
