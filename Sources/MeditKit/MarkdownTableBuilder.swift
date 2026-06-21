import AppKit

/// Builds a Markdown table as native `NSTextTable` attributed text. Each cell is an
/// `NSTextTableBlock` attached as a paragraph attribute, so cells wrap independently
/// side-by-side (no hollow gaps) and the result is ordinary selectable/copyable text
/// in the preview's `NSTextView`. Replaces the old tab-stop/subview approach.
public enum MarkdownTableBuilder {
    /// Per-cell padding (inside the border), in points.
    static let cellPadding: CGFloat = 9
    /// Per-cell border thickness, in points.
    static let borderWidth: CGFloat = 1

    public static func attributedTable(header: [NSAttributedString],
                                       rows: [[NSAttributedString]],
                                       theme: MarkdownRenderer.Theme) -> NSAttributedString {
        let columnCount = max(header.count, rows.map(\.count).max() ?? 0)
        guard columnCount > 0 else { return NSAttributedString() }

        let table = NSTextTable()
        table.numberOfColumns = columnCount
        table.layoutAlgorithm = .automaticLayoutAlgorithm

        let border = theme.isDark
            ? NSColor.white.withAlphaComponent(0.16)
            : NSColor.black.withAlphaComponent(0.14)

        let out = NSMutableAttributedString()

        // allRows = header (row 0) + body rows.
        let allRows = [header] + rows
        for (r, row) in allRows.enumerated() {
            let isHeader = (r == 0)
            for c in 0..<columnCount {
                let raw = c < row.count ? row[c] : NSAttributedString(string: "")
                out.append(cellString(raw, row: r, col: c, isHeader: isHeader,
                                      table: table, border: border, theme: theme))
            }
        }
        return out
    }

    private static func cellString(_ content: NSAttributedString, row: Int, col: Int,
                                   isHeader: Bool, table: NSTextTable,
                                   border: NSColor, theme: MarkdownRenderer.Theme) -> NSAttributedString {
        let block = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1,
                                     startingColumn: col, columnSpan: 1)
        block.setBorderColor(border)
        block.setWidth(borderWidth, type: .absoluteValueType, for: .border)
        block.setWidth(cellPadding, type: .absoluteValueType, for: .padding)
        if isHeader {
            block.backgroundColor = CBBColors.steel
        }

        let para = NSMutableParagraphStyle()
        para.textBlocks = [block]
        para.alignment = isHeader ? .center : .left
        para.lineBreakMode = .byWordWrapping

        // Header cells: dark Cold Bore Blue text on the steel band.
        let cell: NSAttributedString
        if isHeader {
            let m = NSMutableAttributedString(attributedString: content)
            m.addAttribute(.foregroundColor, value: CBBColors.blue,
                           range: NSRange(location: 0, length: m.length))
            cell = m
        } else {
            cell = content
        }

        let result = NSMutableAttributedString(attributedString: cell)
        result.append(NSAttributedString(string: "\n"))   // each cell ends a paragraph
        result.addAttribute(.paragraphStyle, value: para,
                            range: NSRange(location: 0, length: result.length))
        return result
    }
}
