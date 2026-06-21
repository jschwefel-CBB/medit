import XCTest
import AppKit
@testable import MeditKit

final class MarkdownTableBuilderTests: XCTestCase {
    private func cell(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: 15)])
    }
    private func theme() -> MarkdownRenderer.Theme { MarkdownTableLayoutTestsTheme.theme() }

    /// Every cell paragraph carries an NSTextTableBlock at the right row/column.
    func testEachCellHasATableBlock() {
        let header = [cell("A"), cell("B")]
        let rows = [[cell("a"), cell("b")], [cell("c"), cell("d")]]
        let attr = MarkdownTableBuilder.attributedTable(header: header, rows: rows, theme: theme())

        // Walk paragraph styles; collect (row, col) of each cell's block.
        var coords = Set<String>()
        var table: NSTextTable?
        attr.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: attr.length)) { value, _, _ in
            guard let p = value as? NSParagraphStyle, let block = p.textBlocks.first as? NSTextTableBlock else { return }
            table = block.table
            coords.insert("\(block.startingRow),\(block.startingColumn)")
        }
        XCTAssertEqual(table?.numberOfColumns, 2)
        // 3 rows (header + 2 body) × 2 cols = 6 cells.
        XCTAssertEqual(coords, ["0,0","0,1","1,0","1,1","2,0","2,1"])
    }

    /// Header row cells are shaded + centered; body cells are not.
    func testHeaderRowShadedAndCentered() {
        let attr = MarkdownTableBuilder.attributedTable(
            header: [cell("H1"), cell("H2")], rows: [[cell("a"), cell("b")]], theme: theme())

        func block(atRow r: Int, col c: Int) -> (NSTextTableBlock, NSParagraphStyle)? {
            var found: (NSTextTableBlock, NSParagraphStyle)?
            attr.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: attr.length)) { value, _, stop in
                guard let p = value as? NSParagraphStyle, let b = p.textBlocks.first as? NSTextTableBlock else { return }
                if b.startingRow == r && b.startingColumn == c { found = (b, p); stop.pointee = true }
            }
            return found
        }
        let header = block(atRow: 0, col: 0)
        XCTAssertNotNil(header?.0.backgroundColor, "header cell should be shaded")
        XCTAssertEqual(header?.1.alignment, .center, "header text centered")

        let body = block(atRow: 1, col: 0)
        XCTAssertNil(body?.0.backgroundColor, "body cell not shaded")
        XCTAssertEqual(body?.1.alignment, .left, "body text left-aligned")
    }

    /// Cell text is real, selectable content (round-trips the strings).
    func testCellTextIsRealContent() {
        let attr = MarkdownTableBuilder.attributedTable(
            header: [cell("Name")], rows: [[cell("Bob")]], theme: theme())
        XCTAssertTrue(attr.string.contains("Name"))
        XCTAssertTrue(attr.string.contains("Bob"))
    }

    /// Ragged rows (fewer cells than the header) are padded, not crashed.
    func testRaggedRowsPadded() {
        let attr = MarkdownTableBuilder.attributedTable(
            header: [cell("A"), cell("B"), cell("C")],
            rows: [[cell("x")]], theme: theme())
        var maxCol = 0
        attr.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: attr.length)) { value, _, _ in
            if let p = value as? NSParagraphStyle, let b = p.textBlocks.first as? NSTextTableBlock {
                maxCol = max(maxCol, b.startingColumn)
            }
        }
        XCTAssertEqual(maxCol, 2, "body row padded to 3 columns")
    }
}

/// Shared theme for builder tests (kept independent of the soon-to-be-deleted
/// MarkdownTableLayoutTests).
enum MarkdownTableLayoutTestsTheme {
    static func theme() -> MarkdownRenderer.Theme {
        MarkdownRenderer.Theme(
            baseFont: NSFont.systemFont(ofSize: 15),
            monoFont: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            foreground: .labelColor, secondary: .secondaryLabelColor,
            codeBackground: .clear, headingColor: .labelColor,
            quoteBarColor: .gray, tableBorderColor: .separatorColor,
            linkColor: .linkColor, isDark: true)
    }
}
