import AppKit

/// A TextKit-1 attachment cell that reserves the vertical slot a table occupies in
/// the prose flow (its height). It carries the parsed cell data + theme; the live,
/// scrollable `MarkdownTableView` is built on demand and positioned over the slot by
/// the view controller (parented to the document container, not the text view, so it
/// stays a real accessibility element). Keeps `MarkdownRenderer` view-free.
public final class MarkdownTableAttachmentCell: NSTextAttachmentCell {
    public let header: [NSAttributedString]
    public let rows: [[NSAttributedString]]
    public let theme: MarkdownRenderer.Theme
    private let tableHeight: CGFloat

    public init(header: [NSAttributedString], rows: [[NSAttributedString]],
                theme: MarkdownRenderer.Theme) {
        self.header = header
        self.rows = rows
        self.theme = theme
        // Measure the table height once (cheap) to reserve the slot. The on-screen
        // width is the viewport (set by the view controller); only height matters
        // for the prose slot.
        self.tableHeight = MarkdownTableView(header: header, rows: rows, theme: theme)
            .intrinsicTableSize.height
        super.init()
    }

    @available(*, unavailable)
    public required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Width 1 (the view controller sizes the live view to the viewport); height
    /// reserves the table's vertical slot in the prose flow.
    public override func cellSize() -> NSSize { NSSize(width: 1, height: tableHeight) }
    public override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: 0) }
    public override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) { /* live view draws */ }

    public func makeTableView() -> MarkdownTableView {
        MarkdownTableView(header: header, rows: rows, theme: theme)
    }
}

/// Locates the table attachment cells in a laid-out preview text view and the glyph
/// rect each occupies, so the view controller can position live `MarkdownTableView`s
/// at their slots.
public enum MarkdownTablePlacement {
    public struct Placement {
        public let cell: MarkdownTableAttachmentCell
        public let rect: NSRect   // in text-view coordinates (container origin applied)
    }

    public static func placements(in textView: NSTextView) -> [Placement] {
        guard let layout = textView.layoutManager,
              let container = textView.textContainer,
              let storage = textView.textStorage else { return [] }
        let origin = textView.textContainerOrigin
        var result: [Placement] = []
        storage.enumerateAttribute(.attachment,
            in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let att = value as? NSTextAttachment,
                  let cell = att.attachmentCell as? MarkdownTableAttachmentCell else { return }
            let glyphRange = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layout.boundingRect(forGlyphRange: glyphRange, in: container)
            rect.origin.x += origin.x
            rect.origin.y += origin.y
            result.append(Placement(cell: cell, rect: rect))
        }
        return result
    }
}
