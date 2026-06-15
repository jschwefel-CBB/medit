import XCTest
@testable import MeditKit

final class TextLocatorTests: XCTestCase {

    private func idx(_ line: Int, _ text: String) -> Int? {
        TextLocator.characterIndex(forLine: line, in: text)
    }

    func testFirstLine() {
        XCTAssertEqual(idx(1, "alpha\nbeta\ngamma"), 0)
    }

    func testMiddleLine() {
        // line 2 ("beta") starts right after "alpha\n" => offset 6
        XCTAssertEqual(idx(2, "alpha\nbeta\ngamma"), 6)
    }

    func testLastLine() {
        // line 3 ("gamma") starts after "alpha\nbeta\n" => 11
        XCTAssertEqual(idx(3, "alpha\nbeta\ngamma"), 11)
    }

    func testLastLineWithTrailingNewline() {
        let text = "alpha\nbeta\n"   // 2 content lines + an empty line 3
        XCTAssertEqual(idx(1, text), 0)
        XCTAssertEqual(idx(2, text), 6)
        XCTAssertEqual(idx(3, text), 11)   // the empty final line exists at offset 11 (== length)
        XCTAssertNil(idx(4, text))
    }

    func testLineZeroOrNegativeIsNil() {
        XCTAssertNil(idx(0, "alpha"))
        XCTAssertNil(idx(-3, "alpha"))
    }

    func testLineBeyondCountIsNil() {
        XCTAssertNil(idx(99, "alpha\nbeta"))
    }

    func testEmptyDocument() {
        XCTAssertEqual(idx(1, ""), 0)
        XCTAssertNil(idx(2, ""))
    }
}
