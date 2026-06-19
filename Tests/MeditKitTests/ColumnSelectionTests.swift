import XCTest
@testable import MeditKit

final class ColumnSelectionTests: XCTestCase {

    // A 3-line uniform block.
    private let uniform = "abcd\nefgh\nijkl"
    // Ragged: short middle line.
    private let ragged = "abcdef\nxy\nABCDEF"

    func testPerLineRangesUniform() {
        // Columns 1..3 on all three lines.
        let ranges = ColumnSelection.perLineRanges(in: uniform, startLine: 0, endLine: 2, startColumn: 1, endColumn: 3)
        let ns = uniform as NSString
        XCTAssertEqual(ranges.map { ns.substring(with: $0) }, ["bc", "fg", "jk"])
    }

    func testPerLineRangesRaggedClampsShortLines() {
        // Columns 2..5 — the middle line "xy" only has length 2, so its range is empty at end.
        let ranges = ColumnSelection.perLineRanges(in: ragged, startLine: 0, endLine: 2, startColumn: 2, endColumn: 5)
        let ns = ragged as NSString
        let subs = ranges.map { ns.substring(with: $0) }
        XCTAssertEqual(subs[0], "cde")   // "abcdef" cols 2..5
        XCTAssertEqual(subs[1], "")      // "xy" has nothing at cols 2..5
        XCTAssertEqual(subs[2], "CDE")   // "ABCDEF" cols 2..5
    }

    func testDeleteBlockUniform() {
        // Delete columns 1..3 from every line.
        let e = ColumnSelection.deleteBlock(in: uniform, startLine: 0, endLine: 2, startColumn: 1, endColumn: 3)
        XCTAssertEqual(e.text, "ad\neh\nil")
    }

    func testInsertIntoBlockSameStringEveryRow() {
        // Zero-width block at column 2 on all lines; insert ">>".
        let e = ColumnSelection.insertIntoBlock(">>", in: uniform, startLine: 0, endLine: 2, startColumn: 2, endColumn: 2)
        XCTAssertEqual(e.text, "ab>>cd\nef>>gh\nij>>kl")
    }

    func testInsertIntoBlockRaggedPadsShortLines() {
        // Insert "#" at column 4 across ragged lines; "xy" (len 2) is padded with
        // spaces so the insert still lands at the column.
        let e = ColumnSelection.insertIntoBlock("#", in: ragged, startLine: 0, endLine: 2, startColumn: 4, endColumn: 4)
        XCTAssertEqual(e.text, "abcd#ef\nxy  #\nABCD#EF")
    }

    func testCopyBlockJoinsRowsWithNewlines() {
        let text = ColumnSelection.copyBlock(in: uniform, startLine: 0, endLine: 2, startColumn: 1, endColumn: 3)
        XCTAssertEqual(text, "bc\nfg\njk")
    }

    func testSingleLineBlockDegeneratesToNormalRange() {
        let e = ColumnSelection.deleteBlock(in: uniform, startLine: 1, endLine: 1, startColumn: 1, endColumn: 3)
        XCTAssertEqual(e.text, "abcd\neh\nijkl")
    }
}
