import AppKit

/// TextKit-1 attachment cell standing in for a Markdown table in the preview's text
/// flow. It reserves the table's intrinsic size (so the line fragment is the right
/// height) and carries the structured cell data + theme; the live, scrollable
/// `MarkdownTableView` is built on demand by the preview view controller. Keeping the
/// view out of the renderer lets `MarkdownRenderer` stay a pure value type.
public final class MarkdownTableAttachmentCell: NSTextAttachmentCell {
    public let header: [NSAttributedString]
    public let rows: [[NSAttributedString]]
    public let theme: MarkdownRenderer.Theme
    public let tableSize: NSSize

    public init(header: [NSAttributedString], rows: [[NSAttributedString]],
                theme: MarkdownRenderer.Theme) {
        self.header = header
        self.rows = rows
        self.theme = theme
        let widths = MarkdownTableLayout.columnWidths(header: header, rows: rows)
        var h: CGFloat = 1
        for row in ([header] + rows) { h += MarkdownTableLayout.rowHeight(row, columnWidths: widths) }
        self.tableSize = NSSize(width: MarkdownTableLayout.totalWidth(columnWidths: widths), height: h)
        super.init()
    }

    @available(*, unavailable)
    public required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func cellSize() -> NSSize { tableSize }
    public override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: 0) }
    public override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) { /* live subview draws */ }

    /// Build a fresh live table view from the carried data.
    public func makeTableView() -> MarkdownTableView {
        MarkdownTableView(header: header, rows: rows, theme: theme)
    }
}
