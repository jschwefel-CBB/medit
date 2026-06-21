import AppKit

/// A Markdown table in its own horizontally-scrollable view. The table is built by
/// `MarkdownTableBuilder` (native NSTextTable) and laid out at its NATURAL width in
/// a non-tracking container, so words never split or truncate — when the table is
/// wider than its on-screen frame the scroll view scrolls it horizontally.
///
/// Parented as a SIBLING of the preview text view inside the document container (NOT
/// a subview of the text view), so it is a real accessibility/responder element:
/// selection + copy work and AutoPilot can target `markdownTableTextView`.
public final class MarkdownTableView: NSView {
    public let textView: NSTextView
    private let scrollView = NSScrollView()
    private let storage = NSTextStorage()
    private let layoutManager = MarkdownPreviewLayoutManager()
    public let intrinsicTableSize: NSSize

    public init(header: [NSAttributedString], rows: [[NSAttributedString]],
                theme: MarkdownRenderer.Theme) {
        let attr = MarkdownTableBuilder.attributedTable(header: header, rows: rows, theme: theme)

        storage.addLayoutManager(layoutManager)
        // Non-tracking, effectively unbounded width so the NSTextTable lays out at
        // its full natural width (no shrink-to-fit, no word splitting).
        let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                     height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let tv = NSTextView(frame: .zero, textContainer: container)
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.isHorizontallyResizable = true
        tv.isVerticallyResizable = true
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.textContainerInset = .zero
        tv.setAccessibilityIdentifier("markdownTableTextView")
        self.textView = tv

        tv.textStorage?.setAttributedString(attr)
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        self.intrinsicTableSize = NSSize(width: ceil(used.width), height: ceil(used.height))
        tv.minSize = intrinsicTableSize
        tv.frame = NSRect(origin: .zero, size: intrinsicTableSize)

        super.init(frame: NSRect(origin: .zero, size: intrinsicTableSize))

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

    // Real AX element: expose the inner text view so it isn't an opaque AXUnknown.
    public override func isAccessibilityElement() -> Bool { false }
    public override func accessibilityRole() -> NSAccessibility.Role? { .group }
    public override func accessibilityLabel() -> String? { "markdown table" }
    public override func accessibilityChildren() -> [Any]? { [textView] }

    // Route clicks anywhere on the table into the text view so selection works.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if let hit, hit.isDescendant(of: self) { return textView }
        return hit
    }
}
