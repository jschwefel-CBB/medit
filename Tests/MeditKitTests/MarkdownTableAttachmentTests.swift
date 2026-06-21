import XCTest
import AppKit
@testable import MeditKit

final class MarkdownTableAttachmentTests: XCTestCase {
    private func cell(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: 15)])
    }
    private func theme() -> MarkdownRenderer.Theme { MarkdownTableLayoutTestsTheme.theme() }

    func testCellReservesTableHeightAndCarriesData() {
        let c = MarkdownTableAttachmentCell(
            header: [cell("A"), cell("B")], rows: [[cell("a"), cell("b")]], theme: theme())
        let v = c.makeTableView()
        // The reserved height matches the table's height (width is the slot, set by
        // the view controller — cell height is what reserves the prose slot).
        XCTAssertEqual(c.cellSize().height, v.intrinsicTableSize.height, accuracy: 1.0)
        XCTAssertTrue(v.textView.string.contains("a"))
    }

    func testPlacementsFindCellAndRect() {
        let storage = NSTextStorage()
        let layout = MarkdownPreviewLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        layout.addTextContainer(container)
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: container)

        let rendered = MarkdownRenderer(theme: theme(), tableMode: .interactive)
            .render("intro\n\n| A | B |\n| - | - |\n| 1 | 2 |\n\noutro")
        tv.textStorage?.setAttributedString(rendered)
        layout.ensureLayout(for: container)

        let placements = MarkdownTablePlacement.placements(in: tv)
        XCTAssertEqual(placements.count, 1)
        XCTAssertTrue(placements[0].cell.makeTableView().textView.string.contains("1"))
        XCTAssertGreaterThan(placements[0].rect.height, 0)
    }
}
