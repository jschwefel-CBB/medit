import AppKit

/// Cold Bore Ballistics canonical brand palette (from the CBB Brand & Legal
/// Language Guide §5). The HEX string is the single source of truth; both the
/// `NSColor` (AppKit drawing/print) and the `cssHex` (web-view preview CSS) derive
/// from it, so the palette can't drift between the two render paths.
public enum CBBColors {
    /// Cold Bore Blue — primary brand fill. Header text on the steel band.
    public static let blue = BrandColor("#0a2351")
    /// Cold Bore Steel — accent; rings, strokes, table header band, code text.
    public static let steel = BrandColor("#4a9fc8")
    /// Cold Bore Stainless — lightest tint; light card background, wordmark text.
    public static let stainless = BrandColor("#d6e4ef")
    /// Muted divider text.
    public static let mutedSteel = BrandColor("#6a8fa8")
}

/// A brand color defined by its canonical hex string, exposing both an `NSColor`
/// and the CSS hex so one literal drives every render path.
public struct BrandColor {
    public let cssHex: String           // e.g. "#4a9fc8"
    public let color: NSColor

    public init(_ hex: String) {
        self.cssHex = hex
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let v = UInt32(h, radix: 16) ?? 0
        self.color = NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                             green: CGFloat((v >> 8) & 0xFF) / 255,
                             blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
