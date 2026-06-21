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

    func testDividerXsAreCumulativePaddedWidthsIncludingRightEdge() {
        let widths: [CGFloat] = [50, 80]
        let xs = MarkdownTableLayout.dividerXs(columnWidths: widths)
        // Every column edge to the right of the first: the interior divider after
        // column 0, then the outer right edge after column 1.
        let pad = 2 * MarkdownTableLayout.cellPaddingX
        let firstEdge = 50 + pad
        let rightEdge = firstEdge + 80 + pad
        XCTAssertEqual(xs, [firstEdge, rightEdge])
    }

    func testRowHeightGrowsWhenCellWraps() {
        let widths: [CGFloat] = [MarkdownTableLayout.maxColumnWidth]
        let f = NSFont.systemFont(ofSize: 15)
        let oneLine = MarkdownTableLayout.rowHeight([cell("short")], columnWidths: widths, baseFont: f)
        let manyLines = MarkdownTableLayout.rowHeight(
            [cell(String(repeating: "word ", count: 200))], columnWidths: widths, baseFont: f)
        XCTAssertGreaterThan(manyLines, oneLine)
    }

    func testTotalWidthSumsPaddedColumnsPlusBorder() {
        let widths: [CGFloat] = [50, 80]
        let total = MarkdownTableLayout.totalWidth(columnWidths: widths)
        let pad = MarkdownTableLayout.cellPaddingX * 2
        let expected: CGFloat = (50 + pad) + (80 + pad) + 1
        XCTAssertEqual(total, expected, accuracy: 0.5)
    }

    func testAttributedRowsTagsHeaderAndColumns() {
        let theme = MarkdownTableLayoutTests.testTheme()
        let header = [cell("H1"), cell("H2")]
        let rows = [[cell("a"), cell("b")]]
        let widths = MarkdownTableLayout.columnWidths(header: header, rows: rows)
        let attr = MarkdownTableLayout.attributedRows(
            header: header, rows: rows, columnWidths: widths, theme: theme)

        // Two lines (header + 1 body), each terminated by \n -> 2 newlines.
        XCTAssertEqual(attr.string.filter { $0 == "\n" }.count, 2)
        // Cells are tab-separated.
        XCTAssertTrue(attr.string.contains("H1\tH2"))

        // First char of the header row is tagged as a table row AND a header.
        let kind = attr.attribute(MarkdownBlockAttribute.blockKind, at: 0, effectiveRange: nil) as? Int
        XCTAssertEqual(kind, MarkdownBlockAttribute.Kind.tableRow.rawValue)
        XCTAssertNotNil(attr.attribute(MarkdownBlockAttribute.tableHeader, at: 0, effectiveRange: nil))
        let cols = attr.attribute(MarkdownBlockAttribute.tableColumns, at: 0, effectiveRange: nil) as? [NSNumber]
        XCTAssertEqual(cols?.count, MarkdownTableLayout.dividerXs(columnWidths: widths).count)

        // The body row is a table row but NOT a header.
        let bodyStart = (attr.string as NSString).range(of: "a\t").location
        XCTAssertNil(attr.attribute(MarkdownBlockAttribute.tableHeader, at: bodyStart, effectiveRange: nil))
    }
}

extension MarkdownTableLayoutTests {
    static func testTheme() -> MarkdownRenderer.Theme {
        MarkdownRenderer.Theme(
            baseFont: NSFont.systemFont(ofSize: 15),
            monoFont: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            foreground: .labelColor, secondary: .secondaryLabelColor,
            codeBackground: .clear, headingColor: .labelColor,
            quoteBarColor: .gray, tableBorderColor: .separatorColor,
            linkColor: .linkColor, isDark: false)
    }
}
