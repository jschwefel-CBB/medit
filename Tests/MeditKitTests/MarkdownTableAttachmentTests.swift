import XCTest
import AppKit
@testable import MeditKit

final class MarkdownTableAttachmentTests: XCTestCase {
    private func cell(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: 15)])
    }
    private func theme() -> MarkdownRenderer.Theme { MarkdownTableLayoutTests.testTheme() }

    func testCellSizeMatchesTableIntrinsicSize() {
        let header = [cell("A"), cell("B")]
        let rows = [[cell("a"), cell("b")]]
        let c = MarkdownTableAttachmentCell(header: header, rows: rows, theme: theme())
        let v = c.makeTableView()
        XCTAssertEqual(c.cellSize().width, v.intrinsicTableSize.width, accuracy: 1.0)
        XCTAssertEqual(c.cellSize().height, v.intrinsicTableSize.height, accuracy: 1.0)
    }

    func testMakeTableViewCarriesData() {
        let c = MarkdownTableAttachmentCell(
            header: [cell("Name")], rows: [[cell("Bob")]], theme: theme())
        XCTAssertTrue(c.makeTableView().textView.string.contains("Bob"))
    }

    func testEnumerateTableAttachmentsReturnsCellAndRect() {
        let theme = MarkdownTableLayoutTests.testTheme()
        let storage = NSTextStorage()
        let layout = MarkdownPreviewLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        layout.addTextContainer(container)
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: container)

        let rendered = MarkdownRenderer(theme: theme, tableMode: .interactive)
            .render("intro\n\n| A | B |\n| - | - |\n| 1 | 2 |\n\noutro")
        tv.textStorage?.setAttributedString(rendered)
        layout.ensureLayout(for: container)

        let placements = MarkdownTablePlacement.placements(in: tv)
        XCTAssertEqual(placements.count, 1)
        XCTAssertTrue(placements[0].cell.makeTableView().textView.string.contains("1"))
        XCTAssertGreaterThan(placements[0].rect.height, 0)
        XCTAssertGreaterThan(placements[0].rect.width, 0)
    }
}
