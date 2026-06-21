import AppKit

/// Pure geometry for a Markdown table: column widths (content-fit, clamped),
/// per-row heights (with cell wrapping), and vertical-divider x-positions. Shared
/// by `MarkdownTableView` and its tests so layout math has one source of truth.
public enum MarkdownTableLayout {
    public static let maxColumnWidth: CGFloat = 420
    public static let minColumnWidth: CGFloat = 36
    public static let cellPaddingX: CGFloat = 14
    public static let cellPaddingY: CGFloat = 10

    /// Inner content width per column (excludes padding), clamped to [min, max].
    public static func columnWidths(header: [NSAttributedString],
                                    rows: [[NSAttributedString]]) -> [CGFloat] {
        let columnCount = max(header.count, rows.map(\.count).max() ?? 0)
        guard columnCount > 0 else { return [] }
        var widths = [CGFloat](repeating: minColumnWidth, count: columnCount)
        for row in ([header] + rows) {
            for (i, cell) in row.enumerated() where i < columnCount {
                let w = min(maxColumnWidth, ceil(cell.size().width))
                widths[i] = max(widths[i], w)
            }
        }
        return widths
    }

    /// Padded column width = inner width + horizontal padding on both sides.
    private static func paddedWidth(_ inner: CGFloat) -> CGFloat { inner + cellPaddingX * 2 }

    /// X-positions (from the row's left edge) of every column edge to the RIGHT of
    /// the first: each interior divider AND the outer right edge. The layout manager
    /// draws a vertical line at each, so the full grid (incl. the right border) is
    /// drawn — matching the old image renderer.
    public static func dividerXs(columnWidths: [CGFloat]) -> [CGFloat] {
        guard !columnWidths.isEmpty else { return [] }
        var xs: [CGFloat] = []
        var x: CGFloat = 0
        for w in columnWidths {
            x += paddedWidth(w)
            xs.append(x)
        }
        return xs   // last element is the outer right edge
    }

    /// Row height = the tallest wrapped cell, expressed as a whole number of
    /// padded line-heights so it matches the per-line `minimumLineHeight` the
    /// paragraph style sets (keeps reserved height == drawn height).
    public static func rowHeight(_ row: [NSAttributedString],
                                 columnWidths: [CGFloat],
                                 baseFont: NSFont) -> CGFloat {
        let lineH = ceil(baseFont.ascender - baseFont.descender + baseFont.leading)
        let paddedLine = lineH + cellPaddingY * 2
        var maxLines = 1
        for (i, cell) in row.enumerated() where i < columnWidths.count {
            let bounds = cell.boundingRect(
                with: NSSize(width: columnWidths[i], height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading])
            let lines = max(1, Int(ceil(ceil(bounds.height) / lineH)))
            maxLines = max(maxLines, lines)
        }
        return paddedLine * CGFloat(maxLines)
    }

    /// Total table width: sum of padded column widths + 1 for the right border.
    public static func totalWidth(columnWidths: [CGFloat]) -> CGFloat {
        columnWidths.reduce(0) { $0 + paddedWidth($1) } + 1
    }

    /// Build the tab-separated, decoration-tagged attributed string a table view's
    /// text storage holds. One line per row (cells joined by `\t`, terminated by
    /// `\n`). The header row carries `.tableHeader`; every row carries
    /// `blockKind = .tableRow` and `.tableColumns` (divider x-positions), so the
    /// `MarkdownPreviewLayoutManager` draws the grid + header shading behind the text.
    public static func attributedRows(header: [NSAttributedString],
                                      rows: [[NSAttributedString]],
                                      columnWidths: [CGFloat],
                                      theme: MarkdownRenderer.Theme) -> NSAttributedString {
        let dividers = dividerXs(columnWidths: columnWidths)
        let dividerNumbers = dividers.map { NSNumber(value: Double($0)) }

        // BODY tab stops: each cell's text starts at the column's left edge + padding.
        var leftStops: [NSTextTab] = []
        var lx: CGFloat = cellPaddingX
        leftStops.append(NSTextTab(textAlignment: .left, location: lx))
        for w in columnWidths.dropLast() {
            lx += w + cellPaddingX * 2
            leftStops.append(NSTextTab(textAlignment: .left, location: lx))
        }

        // HEADER tab stops: a CENTER tab at each column's mid-x, so header cells
        // centre over their column (the reference look). Column k spans
        // [edge(k-1), edge(k)] where edge(-1)=0 and edge = cumulative padded widths.
        var centerStops: [NSTextTab] = []
        var edge: CGFloat = 0
        for w in columnWidths {
            let mid = edge + (w + cellPaddingX * 2) / 2
            centerStops.append(NSTextTab(textAlignment: .center, location: mid))
            edge += w + cellPaddingX * 2
        }

        // The last column's text-start x; wrapped body lines indent here so a long
        // value (almost always the rightmost column, PDF-style) wraps WITHIN its
        // column instead of spilling back under the first column.
        let lastColLeft = leftStops.last?.location ?? cellPaddingX

        func rowParagraph(header: Bool) -> NSMutableParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.tabStops = header ? centerStops : leftStops
            p.defaultTabInterval = 0
            p.lineBreakMode = .byWordWrapping
            // First line of a body row hangs at the first column's left padding;
            // wrapped continuation lines indent to the LAST column so long values
            // stay within their column. Header rows start with a leading tab.
            p.firstLineHeadIndent = header ? 0 : cellPaddingX
            p.headIndent = header ? 0 : lastColLeft
            // Vertical breathing room: enlarge the line box by 2×padding. Text is
            // nudged toward the vertical centre via a baselineOffset on the cells.
            let f = theme.baseFont
            let lineH = ceil(f.ascender - f.descender + f.leading)
            p.minimumLineHeight = lineH + cellPaddingY * 2
            p.maximumLineHeight = lineH + cellPaddingY * 2
            p.alignment = .left
            return p
        }

        /// Inverted header: dark Cold Bore Blue text on the light Stainless band.
        func styledHeaderCell(_ cell: NSAttributedString) -> NSAttributedString {
            let m = NSMutableAttributedString(attributedString: cell)
            m.addAttribute(.foregroundColor, value: CBBColors.blue,
                           range: NSRange(location: 0, length: m.length))
            return m
        }

        func line(_ cells: [NSAttributedString], isHeader: Bool) -> NSAttributedString {
            let out = NSMutableAttributedString()
            for (i, cell) in cells.enumerated() {
                // Header: EVERY cell gets a leading tab so it lands on a center tab
                // (incl. the first). Body: first cell hangs at the head indent, the
                // rest are tab-separated to the left tab stops.
                if isHeader || i > 0 { out.append(NSAttributedString(string: "\t")) }
                out.append(isHeader ? styledHeaderCell(cell) : cell)
            }
            out.append(NSAttributedString(string: "\n"))
            let full = NSRange(location: 0, length: out.length)
            out.addAttribute(.paragraphStyle, value: rowParagraph(header: isHeader), range: full)
            // With the line box enlarged by 2×padding, TextKit seats the baseline low;
            // raise the glyphs by one padding so the single line sits centred.
            out.addAttribute(.baselineOffset, value: cellPaddingY, range: full)
            out.addAttribute(MarkdownBlockAttribute.blockKind,
                             value: MarkdownBlockAttribute.Kind.tableRow.rawValue, range: full)
            out.addAttribute(MarkdownBlockAttribute.tableColumns, value: dividerNumbers, range: full)
            if isHeader {
                out.addAttribute(MarkdownBlockAttribute.tableHeader, value: true, range: full)
            }
            return out
        }

        let result = NSMutableAttributedString()
        result.append(line(header, isHeader: true))
        for row in rows { result.append(line(row, isHeader: false)) }
        return result
    }
}
