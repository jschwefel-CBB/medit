import XCTest
@testable import MeditKit

final class TextTransformsTests: XCTestCase {

    private func fullRange(_ s: String) -> NSRange { NSRange(location: 0, length: (s as NSString).length) }

    // MARK: Sort lines

    func testSortAscending() {
        let s = "banana\napple\ncherry"
        let e = TextTransforms.sortLines(s, range: fullRange(s), ascending: true, caseInsensitive: false)
        XCTAssertEqual(e.text, "apple\nbanana\ncherry")
    }

    func testSortDescending() {
        let s = "apple\nbanana\ncherry"
        let e = TextTransforms.sortLines(s, range: fullRange(s), ascending: false, caseInsensitive: false)
        XCTAssertEqual(e.text, "cherry\nbanana\napple")
    }

    func testSortCaseInsensitive() {
        let s = "Banana\napple\nCherry"
        let ci = TextTransforms.sortLines(s, range: fullRange(s), ascending: true, caseInsensitive: true)
        XCTAssertEqual(ci.text, "apple\nBanana\nCherry")
    }

    func testSortPreservesTrailingNewline() {
        let s = "b\na\n"
        let e = TextTransforms.sortLines(s, range: fullRange(s), ascending: true, caseInsensitive: false)
        XCTAssertEqual(e.text, "a\nb\n")
    }

    func testSortOnlySelectedLines() {
        let s = "z\nb\nc\na"
        // Select lines "b" and "c" (middle two).
        let r = (s as NSString).range(of: "b\nc")
        let e = TextTransforms.sortLines(s, range: r, ascending: true, caseInsensitive: false)
        XCTAssertEqual(e.text, "z\nb\nc\na")   // already sorted; z and a untouched
        let s2 = "z\nc\nb\na"
        let r2 = (s2 as NSString).range(of: "c\nb")
        let e2 = TextTransforms.sortLines(s2, range: r2, ascending: true, caseInsensitive: false)
        XCTAssertEqual(e2.text, "z\nb\nc\na")
    }

    func testSortSingleLineNoOp() {
        let s = "only one line"
        let e = TextTransforms.sortLines(s, range: fullRange(s), ascending: true, caseInsensitive: false)
        XCTAssertEqual(e.text, s)
    }

    // MARK: Change case

    func testUpperCase() {
        let s = "Hello World"
        let r = (s as NSString).range(of: "World")
        let e = TextTransforms.changeCase(s, range: r, to: .upper)
        XCTAssertEqual(e.text, "Hello WORLD")
    }

    func testLowerCase() {
        let s = "Hello World"
        let e = TextTransforms.changeCase(s, range: fullRange(s), to: .lower)
        XCTAssertEqual(e.text, "hello world")
    }

    func testTitleCase() {
        let s = "the quick brown fox"
        let e = TextTransforms.changeCase(s, range: fullRange(s), to: .title)
        XCTAssertEqual(e.text, "The Quick Brown Fox")
    }

    func testChangeCaseEmptySelectionUsesCurrentWord() {
        let s = "make this upper"
        // Caret inside "this" (no selection).
        let caret = NSRange(location: 7, length: 0)   // within "this"
        let e = TextTransforms.changeCase(s, range: caret, to: .upper)
        XCTAssertEqual(e.text, "make THIS upper")
    }
}
