import XCTest
import AppKit
@testable import MeditKit

final class MarkdownTableLayoutTests: XCTestCase {
    private func cell(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: 15)])
    }

    func testColumnWidthsClampToMinAndMax() {
        let header = [cell("A"), cell("B")]                 // narrow -> min
        let longText = String(repeating: "wide ", count: 100)
        let rows = [[cell("x"), cell(longText)]]            // 2nd col exceeds max
        let widths = MarkdownTableLayout.columnWidths(header: header, rows: rows)
        XCTAssertEqual(widths.count, 2)
        XCTAssertEqual(widths[0], MarkdownTableLayout.minColumnWidth, accuracy: 0.5)
        XCTAssertEqual(widths[1], MarkdownTableLayout.maxColumnWidth, accuracy: 0.5)
    }

    func testDividerXsAreCumulativePaddedWidths() {
        let widths: [CGFloat] = [50, 80]
        let xs = MarkdownTableLayout.dividerXs(columnWidths: widths)
        // One interior divider, after the first padded column.
        let firstPadded = 50 + 2 * MarkdownTableLayout.cellPaddingX
        XCTAssertEqual(xs, [firstPadded])
    }

    func testRowHeightGrowsWhenCellWraps() {
        let widths: [CGFloat] = [MarkdownTableLayout.maxColumnWidth]
        let oneLine = MarkdownTableLayout.rowHeight([cell("short")], columnWidths: widths)
        let manyLines = MarkdownTableLayout.rowHeight(
            [cell(String(repeating: "word ", count: 200))], columnWidths: widths)
        XCTAssertGreaterThan(manyLines, oneLine)
    }

    func testTotalWidthSumsPaddedColumnsPlusBorder() {
        let widths: [CGFloat] = [50, 80]
        let total = MarkdownTableLayout.totalWidth(columnWidths: widths)
        let expected: CGFloat = (50 + 24) + (80 + 24) + 1
        XCTAssertEqual(total, expected, accuracy: 0.5)
    }
}
