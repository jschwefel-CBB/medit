import AppKit

/// Custom attribute keys the MarkdownRenderer attaches to paragraph ranges so the
/// preview's layout manager can draw block decorations (panels, rules, grids)
/// that plain text attributes can't express.
public enum MarkdownBlockAttribute {
    /// Marks a run as belonging to a decorated block. Value is a `Kind` raw.
    public static let blockKind = NSAttributedString.Key("medit.md.blockKind")
    /// For headings: the level (1–6), used to size the underline rule.
    public static let headingLevel = NSAttributedString.Key("medit.md.headingLevel")
    /// Marks an inline-code run so the layout manager can draw a tight rounded box
    /// behind its glyphs (symmetric padding), instead of `.backgroundColor` which
    /// fills the whole 1.35× line height and looks top-heavy.
    public static let inlineCode = NSAttributedString.Key("medit.md.inlineCode")

    public enum Kind: Int {
        case codeBlock = 1
        case blockQuote = 2
        case headingRule = 3      // heading that gets an underline rule (h1/h2)
        case thematicBreak = 5
    }
}

/// Draws Markdown block decorations behind the text: rounded code-block panels,
/// a blockquote bar, heading underline rules, table grid + header shading. Reads
/// the custom attributes above off the text storage and paints in
/// `drawBackground(forGlyphRange:at:)` using each block's line-fragment rects.
public final class MarkdownPreviewLayoutManager: NSLayoutManager {

    public struct Palette {
        public var codePanel: NSColor
        public var quoteBar: NSColor
        public var rule: NSColor
        /// Fill behind inline-code spans (the tight rounded box).
        public var inlineCodeFill: NSColor
        public init(codePanel: NSColor, quoteBar: NSColor, rule: NSColor,
                    inlineCodeFill: NSColor = .clear) {
            self.codePanel = codePanel; self.quoteBar = quoteBar; self.rule = rule
            self.inlineCodeFill = inlineCodeFill
        }
    }
    public var palette = Palette(codePanel: .clear, quoteBar: .gray, rule: .separatorColor)

    public override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        storage.enumerateAttribute(MarkdownBlockAttribute.blockKind, in: charRange,
                                   options: []) { value, range, _ in
            guard let raw = value as? Int, let kind = MarkdownBlockAttribute.Kind(rawValue: raw) else { return }
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let blockRect = self.boundingRect(forGlyphRange: glyphRange, in: self.textContainers[0])
                .offsetBy(dx: origin.x, dy: origin.y)
            switch kind {
            case .codeBlock:
                self.drawCodePanel(blockRect)
            case .blockQuote:
                self.drawQuoteBar(blockRect)
            case .headingRule:
                self.drawHeadingRule(blockRect)
            case .thematicBreak:
                self.drawThematicBreak(blockRect)
            }
        }

        // Inline-code spans: a tight rounded box hugging the glyphs (symmetric top/
        // bottom), drawn per line fragment so a wrapped code span boxes each piece.
        guard palette.inlineCodeFill != NSColor.clear else { return }
        storage.enumerateAttribute(MarkdownBlockAttribute.inlineCode, in: charRange,
                                   options: []) { value, range, _ in
            guard value != nil else { return }
            self.drawInlineCode(charRange: range, origin: origin)
        }
    }

    private func drawInlineCode(charRange: NSRange, origin: NSPoint) {
        let glyphRange = self.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard let container = textContainers.first,
              let font = textStorage?.attribute(.font, at: charRange.location, effectiveRange: nil) as? NSFont
        else { return }
        palette.inlineCodeFill.setFill()
        // Box height is keyed to the FONT (ascender..descender), centred on the
        // glyphs with symmetric vertical padding — not the tall 1.35× line box (which
        // seated the text low and looked top-heavy). Geometry verified by spike.
        let vPad: CGFloat = 2
        let textHeight = font.ascender - font.descender
        enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, lineGlyphRange, _ in
            let piece = NSIntersectionRange(glyphRange, lineGlyphRange)
            guard piece.length > 0 else { return }
            let runRect = self.boundingRect(forGlyphRange: piece, in: container)
            let baseline = usedRect.maxY + font.descender   // text baseline (flipped y)
            let top = baseline - font.ascender              // top of the glyphs
            let boxRect = NSRect(x: runRect.minX - 3, y: top - vPad,
                                 width: runRect.width + 6, height: textHeight + vPad * 2)
                .offsetBy(dx: origin.x, dy: origin.y)
            NSBezierPath(roundedRect: boxRect, xRadius: 4, yRadius: 4).fill()
        }
    }

    // MARK: Drawing

    private func drawCodePanel(_ rect: NSRect) {
        let inset = rect.insetBy(dx: -6, dy: -2)
        let path = NSBezierPath(roundedRect: inset, xRadius: 6, yRadius: 6)
        palette.codePanel.setFill()
        path.fill()
    }

    private func drawQuoteBar(_ rect: NSRect) {
        let bar = NSRect(x: rect.minX - 2, y: rect.minY, width: 3, height: rect.height)
        palette.quoteBar.setFill()
        NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
    }

    private func drawHeadingRule(_ rect: NSRect) {
        let y = rect.maxY - 1
        let line = NSRect(x: rect.minX, y: y, width: max(rect.width, containerWidth()), height: 1)
        palette.rule.setFill()
        line.fill()
    }

    private func drawThematicBreak(_ rect: NSRect) {
        let y = rect.midY
        let line = NSRect(x: rect.minX, y: y, width: max(rect.width, containerWidth()), height: 1)
        palette.rule.setFill()
        line.fill()
    }

    private func containerWidth() -> CGFloat {
        guard let c = textContainers.first else { return 0 }
        return c.size.width - 2 * c.lineFragmentPadding
    }
}
