import AppKit

/// A Markdown table rendered as real, selectable text in a horizontally-scrollable
/// view. Reuses `MarkdownPreviewLayoutManager` so the grid + header shading draw the
/// same way the rest of the preview's block decorations do. Embedded in the preview
/// as the view backing a `MarkdownTableAttachmentCell`.
public final class MarkdownTableView: NSView {
    public let textView: NSTextView
    private let scrollView = NSScrollView()
    private let tableLayoutManager = MarkdownPreviewLayoutManager()
    private let storage = NSTextStorage()
    public let intrinsicTableSize: NSSize

    public init(header: [NSAttributedString], rows: [[NSAttributedString]],
                theme: MarkdownRenderer.Theme) {
        let widths = MarkdownTableLayout.columnWidths(header: header, rows: rows)
        let attr = MarkdownTableLayout.attributedRows(
            header: header, rows: rows, columnWidths: widths, theme: theme)
        let totalWidth = MarkdownTableLayout.totalWidth(columnWidths: widths)
        var totalHeight: CGFloat = 1   // bottom border
        for row in ([header] + rows) {
            totalHeight += MarkdownTableLayout.rowHeight(row, columnWidths: widths)
        }
        self.intrinsicTableSize = NSSize(width: totalWidth, height: totalHeight)

        // TextKit-1 stack: a non-tracking container sized to the full table width so
        // the table can exceed the visible frame and scroll horizontally.
        storage.addLayoutManager(tableLayoutManager)
        let container = NSTextContainer(
            size: NSSize(width: totalWidth, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        tableLayoutManager.addTextContainer(container)
        let tv = NSTextView(frame: NSRect(origin: .zero, size: intrinsicTableSize),
                            textContainer: container)
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.isHorizontallyResizable = true
        tv.isVerticallyResizable = true
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.textContainerInset = .zero
        self.textView = tv

        super.init(frame: NSRect(origin: .zero, size: intrinsicTableSize))

        tableLayoutManager.palette = MarkdownPreviewLayoutManager.Palette(
            codePanel: .clear, quoteBar: theme.quoteBarColor, rule: theme.tableBorderColor,
            tableBorder: theme.tableBorderColor, tableHeaderFill: theme.codeBackground)
        tv.textStorage?.setAttributedString(attr)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = tv
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
