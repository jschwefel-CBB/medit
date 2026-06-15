import XCTest
@testable import MeditKit

final class BracketMatcherTests: XCTestCase {

    private func match(_ text: String, _ offset: Int) -> Int? {
        BracketMatcher.matchingOffset(in: text, at: offset)
    }

    func testSimplePairForward() {
        // "(x)" caret just after '(' at offset 1 -> partner ')' at offset 2
        XCTAssertEqual(match("(x)", 1), 2)
    }

    func testSimplePairBackward() {
        // "(x)" caret just after ')' at offset 3 -> partner '(' at offset 0
        XCTAssertEqual(match("(x)", 3), 0)
    }

    func testNested() {
        // "[ (a) ]" -> caret after outer '[' (offset 1) matches ']' at offset 6
        XCTAssertEqual(match("[ (a) ]", 1), 6)
    }

    func testUnbalancedReturnsNil() {
        XCTAssertNil(match("(a b", 1))
    }

    func testCaretNotOnBracketReturnsNil() {
        XCTAssertNil(match("abc", 2))
    }

    func testMismatchedTypesReturnsNil() {
        // "(]" caret after '(' -> no valid ')' partner
        XCTAssertNil(match("(]", 1))
    }
}
