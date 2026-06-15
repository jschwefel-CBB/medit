import XCTest
@testable import MeditKit

final class TextPositionTests: XCTestCase {

    private func lc(_ offset: Int, _ text: String) -> (line: Int, column: Int) {
        TextPosition.lineColumn(forOffset: offset, in: text)
    }

    func testStartOfDocument() {
        let r = lc(0, "alpha\nbeta")
        XCTAssertEqual(r.line, 1); XCTAssertEqual(r.column, 1)
    }

    func testWithinFirstLine() {
        let r = lc(3, "alpha\nbeta")   // caret before 'h' in alpha -> col 4
        XCTAssertEqual(r.line, 1); XCTAssertEqual(r.column, 4)
    }

    func testStartOfSecondLine() {
        let r = lc(6, "alpha\nbeta")   // offset 6 == 'b' -> line 2 col 1
        XCTAssertEqual(r.line, 2); XCTAssertEqual(r.column, 1)
    }

    func testEndOfMultilineDoc() {
        let text = "alpha\nbeta"
        let r = lc((text as NSString).length, text)   // end -> line 2, col 5
        XCTAssertEqual(r.line, 2); XCTAssertEqual(r.column, 5)
    }

    func testOffsetClampedToLength() {
        let text = "ab"
        let r = lc(999, text)
        XCTAssertEqual(r.line, 1); XCTAssertEqual(r.column, 3)
    }

    func testEmptyDocument() {
        let r = lc(0, "")
        XCTAssertEqual(r.line, 1); XCTAssertEqual(r.column, 1)
    }
}
