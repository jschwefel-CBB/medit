import AppKit

/// Pure geometry for a Markdown table: column widths (content-fit, clamped),
/// per-row heights (with cell wrapping), and vertical-divider x-positions. Shared
/// by `MarkdownTableView` and its tests so layout math has one source of truth.
public enum MarkdownTableLayout {
    public static let maxColumnWidth: CGFloat = 280
    public static let minColumnWidth: CGFloat = 36
    public static let cellPaddingX: CGFloat = 12
    public static let cellPaddingY: CGFloat = 6

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

    /// X-positions of interior vertical dividers (cumulative padded widths),
    /// excluding the outer left (0) and right borders.
    public static func dividerXs(columnWidths: [CGFloat]) -> [CGFloat] {
        guard columnWidths.count > 1 else { return [] }
        var xs: [CGFloat] = []
        var x: CGFloat = 0
        for w in columnWidths.dropLast() {
            x += paddedWidth(w)
            xs.append(x)
        }
        return xs
    }

    /// Max wrapped cell height across a row (at each column's inner width) + padding.
    public static func rowHeight(_ row: [NSAttributedString],
                                 columnWidths: [CGFloat]) -> CGFloat {
        var h: CGFloat = 0
        for (i, cell) in row.enumerated() where i < columnWidths.count {
            let bounds = cell.boundingRect(
                with: NSSize(width: columnWidths[i], height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading])
            h = max(h, ceil(bounds.height))
        }
        return h + cellPaddingY * 2
    }

    /// Total table width: sum of padded column widths + 1 for the right border.
    public static func totalWidth(columnWidths: [CGFloat]) -> CGFloat {
        columnWidths.reduce(0) { $0 + paddedWidth($1) } + 1
    }
}
