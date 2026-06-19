import XCTest
@testable import MeditKit

final class TextStatisticsTests: XCTestCase {

    private func counts(_ s: String, _ sel: NSRange = NSRange(location: 0, length: 0)) -> TextStatistics.Counts {
        TextStatistics.counts(for: s, selection: sel)
    }

    func testEmpty() {
        let c = counts("")
        XCTAssertEqual(c.characters, 0)
        XCTAssertEqual(c.words, 0)
        XCTAssertEqual(c.lines, 0)
    }

    func testSingleWord() {
        let c = counts("hello")
        XCTAssertEqual(c.characters, 5)
        XCTAssertEqual(c.words, 1)
        XCTAssertEqual(c.lines, 1)
    }

    func testMultipleWordsAndLines() {
        let c = counts("the quick brown\nfox jumps")
        XCTAssertEqual(c.words, 5)
        XCTAssertEqual(c.lines, 2)
        XCTAssertEqual(c.characters, ("the quick brown\nfox jumps" as NSString).length)
    }

    func testTrailingNewlineCountsAsLine() {
        // "a\n" is one line of content; many editors show 2 (a blank final line).
        // We define lines = number of newlines + 1 when there is content.
        let c = counts("a\nb\n")
        XCTAssertEqual(c.lines, 3)   // "a", "b", and the empty trailing line
        XCTAssertEqual(c.words, 2)
    }

    func testWhitespaceOnlyHasNoWords() {
        let c = counts("   \t  \n  ")
        XCTAssertEqual(c.words, 0)
    }

    func testCollapsesMultipleSpaces() {
        let c = counts("a    b\t\tc")
        XCTAssertEqual(c.words, 3)
    }

    func testSelectionCounts() {
        let s = "one two three four"
        let sel = (s as NSString).range(of: "two three")
        let c = counts(s, sel)
        XCTAssertEqual(c.words, 4)            // whole-doc words
        XCTAssertEqual(c.selectedWords, 2)    // "two three"
        XCTAssertEqual(c.selectedCharacters, 9)
    }

    func testNoSelectionHasZeroSelected() {
        let c = counts("hello world")
        XCTAssertEqual(c.selectedCharacters, 0)
        XCTAssertEqual(c.selectedWords, 0)
    }

    func testUnicodeWordsCountedSanely() {
        // CJK words separated by spaces; combining marks don't inflate word count.
        let c = counts("café 日本 test")
        XCTAssertEqual(c.words, 3)
    }
}
