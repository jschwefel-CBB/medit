import AppKit

/// Custom attribute keys the MarkdownRenderer attaches to paragraph ranges so the
/// preview's layout manager can draw block decorations (panels, rules, grids)
/// that plain text attributes can't express.
public enum MarkdownBlockAttribute {
    /// Marks a run as belonging to a decorated block. Value is a `Kind` raw.
    public static let blockKind = NSAttributedString.Key("medit.md.blockKind")
    /// For headings: the level (1–6), used to size the underline rule.
    public static let headingLevel = NSAttributedString.Key("medit.md.headingLevel")
    /// For table rows: the x positions (in text-container points) of column
    /// dividers, as an [CGFloat] in an NSValue-wrapped array (stored as [NSNumber]).
    public static let tableColumns = NSAttributedString.Key("medit.md.tableColumns")
    /// Marks the table header row (shaded background).
    public static let tableHeader = NSAttributedString.Key("medit.md.tableHeader")

    public enum Kind: Int {
        case codeBlock = 1
        case blockQuote = 2
        case headingRule = 3      // heading that gets an underline rule (h1/h2)
        case tableRow = 4
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
        public var tableBorder: NSColor
        public var tableHeaderFill: NSColor
        public init(codePanel: NSColor, quoteBar: NSColor, rule: NSColor,
                    tableBorder: NSColor, tableHeaderFill: NSColor) {
            self.codePanel = codePanel; self.quoteBar = quoteBar; self.rule = rule
            self.tableBorder = tableBorder; self.tableHeaderFill = tableHeaderFill
        }
    }
    public var palette = Palette(codePanel: .clear, quoteBar: .gray, rule: .separatorColor,
                                 tableBorder: .separatorColor, tableHeaderFill: .clear)

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
            case .tableRow:
                self.drawTableRow(storage: storage, charRange: range, blockRect: blockRect, origin: origin)
            }
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

    private func drawTableRow(storage: NSTextStorage, charRange: NSRange, blockRect: NSRect, origin: NSPoint) {
        // Header shading.
        if storage.attribute(MarkdownBlockAttribute.tableHeader, at: charRange.location, effectiveRange: nil) != nil {
            palette.tableHeaderFill.setFill()
            blockRect.fill()
        }
        // Outer + column borders.
        palette.tableBorder.setStroke()
        let border = NSBezierPath(rect: blockRect)
        border.lineWidth = 1
        border.stroke()
        if let cols = storage.attribute(MarkdownBlockAttribute.tableColumns, at: charRange.location,
                                        effectiveRange: nil) as? [NSNumber] {
            for c in cols {
                let x = blockRect.minX + CGFloat(c.doubleValue)
                let v = NSBezierPath()
                v.move(to: NSPoint(x: x, y: blockRect.minY))
                v.line(to: NSPoint(x: x, y: blockRect.maxY))
                v.lineWidth = 1
                v.stroke()
            }
        }
    }

    private func containerWidth() -> CGFloat {
        guard let c = textContainers.first else { return 0 }
        return c.size.width - 2 * c.lineFragmentPadding
    }
}
