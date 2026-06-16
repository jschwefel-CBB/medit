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

    // MARK: enclosingPair

    func testEnclosingPairInOpenSpace() {
        // "f( a, [ b ] )" caret just after 'b' (offset 9) -> innermost is the [ ] pair.
        let text = "f( a, [ b ] )"
        let pair = BracketMatcher.enclosingPair(in: text, at: 9)
        XCTAssertEqual(pair?.open, 6)
        XCTAssertEqual(pair?.close, 10)
    }

    func testEnclosingPairFallsToOuter() {
        let text = "f( a, [ b ] )"
        // caret right after ']' (offset 11) is NOT inside [ ]; innermost enclosing is ( ).
        let pair = BracketMatcher.enclosingPair(in: text, at: 11)
        XCTAssertEqual(pair?.open, 1)
        XCTAssertEqual(pair?.close, 12)
    }

    func testEnclosingPairNoneAtTopLevel() {
        XCTAssertNil(BracketMatcher.enclosingPair(in: "abc def", at: 3))
        XCTAssertNil(BracketMatcher.enclosingPair(in: "", at: 0))
    }

    func testEnclosingPairInnermostWhenNested() {
        // "((x))" caret at offset 2 (the x) -> innermost enclosing is inner ( ) = 1..3
        let pair = BracketMatcher.enclosingPair(in: "((x))", at: 2)
        XCTAssertEqual(pair?.open, 1)
        XCTAssertEqual(pair?.close, 3)
    }
}
