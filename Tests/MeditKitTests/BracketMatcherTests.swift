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

    /// Call the String.Index API with a character offset and translate the result
    /// back to character offsets, so assertions stay as readable as before.
    private func enclosing(_ text: String, _ charOffset: Int) -> (open: Int, close: Int)? {
        let caret = text.index(text.startIndex, offsetBy: charOffset)
        guard let pair = BracketMatcher.enclosingPair(in: text, at: caret) else { return nil }
        return (text.distance(from: text.startIndex, to: pair.open.lowerBound),
                text.distance(from: text.startIndex, to: pair.close.lowerBound))
    }

    func testEnclosingPairInOpenSpace() {
        // "f( a, [ b ] )" caret just after 'b' (offset 9) -> innermost is the [ ] pair.
        let pair = enclosing("f( a, [ b ] )", 9)
        XCTAssertEqual(pair?.open, 6)
        XCTAssertEqual(pair?.close, 10)
    }

    func testEnclosingPairFallsToOuter() {
        // caret right after ']' (offset 11) is NOT inside [ ]; innermost enclosing is ( ).
        let pair = enclosing("f( a, [ b ] )", 11)
        XCTAssertEqual(pair?.open, 1)
        XCTAssertEqual(pair?.close, 12)
    }

    func testEnclosingPairNoneAtTopLevel() {
        XCTAssertNil(enclosing("abc def", 3))
        XCTAssertNil(enclosing("", 0))
    }

    func testEnclosingPairInnermostWhenNested() {
        // "((x))" caret at offset 2 (the x) -> innermost enclosing is inner ( ) = 1..3
        let pair = enclosing("((x))", 2)
        XCTAssertEqual(pair?.open, 1)
        XCTAssertEqual(pair?.close, 3)
    }

    /// The colorizer computes the enclosing pair from the depth scanner's hit
    /// list (sparse — bracket characters only) instead of walking the text. That
    /// is claimed equivalent to the matcher by construction; this pins it: for
    /// every caret position of every adversarial case, both must agree. Cases
    /// cover nesting, mixed families, unmatched/unbalanced brackets, carets ON
    /// brackets, and multibyte content (where char and UTF-16 offsets diverge).
    func testColorizerHitWalkAgreesWithMatcherAtEveryCaret() {
        let cases = [
            "f( a, [ b ] )", "((x))", "([{}])", "(]", ")(", "((", "))",
            "abc def", "", "{a(b[c]d)e}", "😀(é🎯)", "x😀[a(b)c]y",
            "( [ ) ]", "}{",
        ]
        for text in cases {
            let hits = BracketDepthScanner.scan(text)
            let utf16Count = (text as NSString).length
            for caretUTF16 in 0...utf16Count {
                // Matcher ground truth (String.Index space -> UTF-16 offsets).
                // Skip carets that fall inside a surrogate pair — not reachable
                // from a real text view selection.
                let utf16View = text.utf16
                let viewIdx = utf16View.index(utf16View.startIndex, offsetBy: caretUTF16)
                guard let caretIdx = viewIdx.samePosition(in: text) else { continue }
                let expected = BracketMatcher.enclosingPair(in: text, at: caretIdx).map {
                    (NSRange($0.open, in: text).location, NSRange($0.close, in: text).location)
                }
                let got = BracketColorizer.enclosingPair(inHits: hits, caretUTF16: caretUTF16).map {
                    ($0.open.utf16Offset, $0.close.utf16Offset)
                }
                XCTAssertEqual(got?.0, expected?.0,
                               "open mismatch in \(text.debugDescription) at caret \(caretUTF16)")
                XCTAssertEqual(got?.1, expected?.1,
                               "close mismatch in \(text.debugDescription) at caret \(caretUTF16)")
            }
        }
    }

    /// Multibyte content before and inside the pair. The old API had no multibyte
    /// coverage at all; the index-based walk must stay grapheme-correct, and the
    /// returned ranges must convert to the right UTF-16 NSRanges (what the
    /// colorizer actually paints with).
    func testEnclosingPairWithMultibyteContent() {
        // "😀(é🎯)" — caret after 'é' (character offset 3).
        let text = "😀(é🎯)"
        let caret = text.index(text.startIndex, offsetBy: 3)
        guard let pair = BracketMatcher.enclosingPair(in: text, at: caret) else {
            return XCTFail("no enclosing pair")
        }
        XCTAssertEqual(text[pair.open], "(")
        XCTAssertEqual(text[pair.close], ")")
        // 😀 is 2 UTF-16 units, so '(' sits at UTF-16 location 2; é(1) + 🎯(2)
        // put ')' at location 6. These are the NSRanges the colorizer applies.
        XCTAssertEqual(NSRange(pair.open, in: text), NSRange(location: 2, length: 1))
        XCTAssertEqual(NSRange(pair.close, in: text), NSRange(location: 6, length: 1))
    }
}
