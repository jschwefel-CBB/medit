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
}
