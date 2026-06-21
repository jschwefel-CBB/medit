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
        /// Subtle shade behind the table's first column (row-label column), like the
        /// PDF reference. `.clear` to disable.
        public var tableFirstColFill: NSColor
        public init(codePanel: NSColor, quoteBar: NSColor, rule: NSColor,
                    tableBorder: NSColor, tableHeaderFill: NSColor,
                    tableFirstColFill: NSColor = .clear) {
            self.codePanel = codePanel; self.quoteBar = quoteBar; self.rule = rule
            self.tableBorder = tableBorder; self.tableHeaderFill = tableHeaderFill
            self.tableFirstColFill = tableFirstColFill
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
        // NOTE: `enumerateAttribute(blockKind)` merges ALL table rows into a single
        // run (they share `.tableRow`), so `charRange`/`blockRect` cover the WHOLE
        // table. We therefore walk the rows ourselves (by paragraph / line) and draw
        // each: header fill only on the header row, a horizontal divider between
        // rows, and the column verticals + outer box once for the whole table.
        let cols = (storage.attribute(MarkdownBlockAttribute.tableColumns, at: charRange.location,
                                      effectiveRange: nil) as? [NSNumber]) ?? []

        // Build one rect per ROW (newline-terminated paragraph). A wrapped cell
        // spans multiple line fragments in the same paragraph, so we union the
        // bounding rects of each paragraph's character range.
        let nsText = storage.string as NSString
        var rowRects: [(rect: NSRect, isHeader: Bool)] = []
        var i = charRange.location
        let end = NSMaxRange(charRange)
        while i < end {
            let paraRange = nsText.paragraphRange(for: NSRange(location: i, length: 0))
            // Clamp the paragraph range to the table's char range.
            let lo = max(paraRange.location, charRange.location)
            let hi = min(NSMaxRange(paraRange), end)
            let rowCharRange = NSRange(location: lo, length: hi - lo)
            let g = self.glyphRange(forCharacterRange: rowCharRange, actualCharacterRange: nil)
            let rect = self.boundingRect(forGlyphRange: g, in: self.textContainers[0])
                .offsetBy(dx: origin.x, dy: origin.y)
            let isHeader = storage.attribute(MarkdownBlockAttribute.tableHeader,
                                             at: rowCharRange.location, effectiveRange: nil) != nil
            if rect.height > 0 { rowRects.append((rect, isHeader)) }
            i = NSMaxRange(paraRange)
        }
        guard !rowRects.isEmpty else { return }

        let left = (rowRects[0].rect.minX).rounded() + 0.5
        let right = cols.last.map { left + CGFloat($0.doubleValue) } ?? rowRects[0].rect.maxX
        let topAll = (rowRects.first!.rect.minY).rounded() + 0.5
        let bottomAll = (rowRects.last!.rect.maxY).rounded() + 0.5

        // First-column shade on BODY rows (the row-label column), like the PDF.
        if palette.tableFirstColFill != NSColor.clear, let firstDivider = cols.first {
            let colRight = (left + CGFloat(firstDivider.doubleValue)).rounded() + 0.5
            palette.tableFirstColFill.setFill()
            for row in rowRects where !row.isHeader {
                NSRect(x: left, y: row.rect.minY, width: colRight - left, height: row.rect.height).fill()
            }
        }

        // Header fill — ONLY the header row(s), full width.
        for row in rowRects where row.isHeader {
            palette.tableHeaderFill.setFill()
            NSRect(x: left, y: row.rect.minY, width: right - left, height: row.rect.height).fill()
        }

        palette.tableBorder.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        // Horizontal line above each row + the final bottom line.
        for row in rowRects {
            let y = (row.rect.minY).rounded() + 0.5
            path.move(to: NSPoint(x: left, y: y)); path.line(to: NSPoint(x: right, y: y))
        }
        path.move(to: NSPoint(x: left, y: bottomAll)); path.line(to: NSPoint(x: right, y: bottomAll))
        // Verticals: left outer + every column edge (incl. outer right), full height.
        path.move(to: NSPoint(x: left, y: topAll)); path.line(to: NSPoint(x: left, y: bottomAll))
        for c in cols {
            let x = (left + CGFloat(c.doubleValue)).rounded() + 0.5
            path.move(to: NSPoint(x: x, y: topAll)); path.line(to: NSPoint(x: x, y: bottomAll))
        }
        path.stroke()
    }

    private func containerWidth() -> CGFloat {
        guard let c = textContainers.first else { return 0 }
        return c.size.width - 2 * c.lineFragmentPadding
    }
}
