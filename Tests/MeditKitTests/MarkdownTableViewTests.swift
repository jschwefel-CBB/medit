import XCTest
import AppKit
@testable import MeditKit

final class MarkdownTableViewTests: XCTestCase {
    private func cell(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: 15)])
    }
    private func theme() -> MarkdownRenderer.Theme { MarkdownTableLayoutTests.testTheme() }

    func testTableViewHoldsSelectableRealText() {
        let v = MarkdownTableView(header: [cell("Name"), cell("Qty")],
                                  rows: [[cell("Apples"), cell("5")]], theme: theme())
        XCTAssertTrue(v.textView.isSelectable)
        XCTAssertFalse(v.textView.isEditable)
        // The cell text is real characters in the storage (not an image).
        XCTAssertTrue(v.textView.string.contains("Apples"))
        XCTAssertTrue(v.textView.string.contains("Qty"))
    }

    func testIntrinsicSizeMatchesLayout() {
        let header = [cell("A"), cell("B")]
        let rows = [[cell("a"), cell("b")], [cell("c"), cell("d")]]
        let v = MarkdownTableView(header: header, rows: rows, theme: theme())
        let widths = MarkdownTableLayout.columnWidths(header: header, rows: rows)
        let expectedWidth = MarkdownTableLayout.totalWidth(columnWidths: widths)
        XCTAssertEqual(v.intrinsicTableSize.width, expectedWidth, accuracy: 1.0)
        XCTAssertGreaterThan(v.intrinsicTableSize.height, 0)
    }
}
