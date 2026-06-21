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
            totalHeight += MarkdownTableLayout.rowHeight(row, columnWidths: widths, baseFont: theme.baseFont)
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
        // Transparent body so cells sit on the SAME surface as the surrounding
        // preview — only the Cold Bore Blue header band stands out, not the whole
        // table. (An opaque .textBackgroundColor resolved to the editor's navy,
        // which made the entire table look blue.)
        tv.drawsBackground = false
        tv.isHorizontallyResizable = true
        tv.isVerticallyResizable = true
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.textContainerInset = .zero
        tv.setAccessibilityIdentifier("markdownTableTextView")
        self.textView = tv

        super.init(frame: NSRect(origin: .zero, size: intrinsicTableSize))

        // Distinct header band + thin uniform gridlines on every cell (no special
        // column shading).
        let border = theme.isDark
            ? NSColor.white.withAlphaComponent(0.16)
            : NSColor.black.withAlphaComponent(0.14)
        tableLayoutManager.palette = MarkdownPreviewLayoutManager.Palette(
            codePanel: .clear, quoteBar: theme.quoteBarColor, rule: border,
            tableBorder: border, tableHeaderFill: CBBColors.steel)
        tv.textStorage?.setAttributedString(attr)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        // Scroll/clip views transparent; the table's own light body surface (the
        // text view's backgroundColor) is the visible slab.
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
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

/// The Markdown preview's text view. Embedded `MarkdownTableView` subviews are added
/// on top of it; a plain `NSTextView` swallows mouse events across its whole bounds,
/// so clicks never reach an embedded table (no selection, no copy). Overriding
/// `hitTest` to defer to a table subview when the point lands inside one lets the
/// table's own text view become first responder and handle selection/copy.
public final class MarkdownPreviewTextView: NSTextView {
    public override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` is in OUR superview's coordinate system. Convert it into our own
        // coordinates, then ask each table subview whether it contains it; if so,
        // route the hit into that subview so its text view handles the click.
        let localPoint = convert(point, from: superview)
        for sub in subviews where sub is MarkdownTableView {
            if sub.frame.contains(localPoint) {
                // NSView.hitTest takes a point in the receiver's SUPERVIEW coords;
                // sub's superview is self, so localPoint is already correct.
                return sub.hitTest(localPoint) ?? sub
            }
        }
        return super.hitTest(point)
    }
}
