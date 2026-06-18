import AppKit

/// Draws a GFM table as a bordered grid image (header shading, cell borders,
/// padded cells) so the Markdown preview shows a real table rather than a
/// tab/box-glyph approximation. Cell content is pre-rendered attributed strings.
enum MarkdownTableRenderer {
    private static let cellPaddingX: CGFloat = 12
    private static let cellPaddingY: CGFloat = 6
    private static let maxColumnWidth: CGFloat = 280
    private static let minColumnWidth: CGFloat = 36

    static func image(header: [NSAttributedString], rows: [[NSAttributedString]],
                      theme: MarkdownRenderer.Theme) -> NSImage {
        let columnCount = max(header.count, rows.map(\.count).max() ?? 0)
        guard columnCount > 0 else { return NSImage(size: NSSize(width: 1, height: 1)) }

        let allRows = [header] + rows
        // Column widths = max content width in that column (clamped), + padding.
        var colWidths = [CGFloat](repeating: minColumnWidth, count: columnCount)
        for row in allRows {
            for (i, cell) in row.enumerated() where i < columnCount {
                let w = min(maxColumnWidth, ceil(cell.size().width))
                colWidths[i] = max(colWidths[i], w)
            }
        }
        let colInnerWidths = colWidths
        colWidths = colWidths.map { $0 + cellPaddingX * 2 }

        // Row heights = max wrapped content height per row.
        func cellHeight(_ cell: NSAttributedString, innerWidth: CGFloat) -> CGFloat {
            let bounds = cell.boundingRect(with: NSSize(width: innerWidth, height: .greatestFiniteMagnitude),
                                           options: [.usesLineFragmentOrigin, .usesFontLeading])
            return ceil(bounds.height)
        }
        var rowHeights: [CGFloat] = []
        for row in allRows {
            var h: CGFloat = 0
            for (i, cell) in row.enumerated() where i < columnCount {
                h = max(h, cellHeight(cell, innerWidth: colInnerWidths[i]))
            }
            rowHeights.append(h + cellPaddingY * 2)
        }

        let totalWidth = colWidths.reduce(0, +) + 1     // +1 for right border
        let totalHeight = rowHeights.reduce(0, +) + 1   // +1 for bottom border

        let image = NSImage(size: NSSize(width: totalWidth, height: totalHeight))
        image.lockFocusFlipped(true)
        let ctx = NSGraphicsContext.current
        ctx?.shouldAntialias = true

        // Header background.
        let headerHeight = rowHeights.first ?? 0
        theme.codeBackground.setFill()    // subtle shaded header (reuses code panel tone)
        NSRect(x: 0, y: 0, width: totalWidth, height: headerHeight).fill()

        // Cell content.
        var y: CGFloat = 0
        for (rIdx, row) in allRows.enumerated() {
            var x: CGFloat = 0
            for cIdx in 0..<columnCount {
                let cell = cIdx < row.count ? row[cIdx] : NSAttributedString(string: "")
                let rect = NSRect(x: x + cellPaddingX, y: y + cellPaddingY,
                                  width: colInnerWidths[cIdx],
                                  height: rowHeights[rIdx] - cellPaddingY * 2)
                cell.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
                x += colWidths[cIdx]
            }
            y += rowHeights[rIdx]
        }

        // Grid lines.
        theme.tableBorderColor.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        // Horizontal lines.
        var hy: CGFloat = 0.5
        path.move(to: NSPoint(x: 0, y: hy)); path.line(to: NSPoint(x: totalWidth, y: hy))
        for h in rowHeights {
            hy += h
            path.move(to: NSPoint(x: 0, y: hy)); path.line(to: NSPoint(x: totalWidth, y: hy))
        }
        // Vertical lines.
        var vx: CGFloat = 0.5
        path.move(to: NSPoint(x: vx, y: 0)); path.line(to: NSPoint(x: vx, y: totalHeight))
        for w in colWidths {
            vx += w
            path.move(to: NSPoint(x: vx, y: 0)); path.line(to: NSPoint(x: vx, y: totalHeight))
        }
        path.stroke()

        image.unlockFocus()
        return image
    }
}
