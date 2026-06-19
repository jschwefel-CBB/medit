import XCTest
@testable import MeditKit

final class MarkdownEditingTests: XCTestCase {

    // Helper: range of a substring in `s` as an NSRange.
    private func range(of sub: String, in s: String) -> NSRange {
        (s as NSString).range(of: sub)
    }

    // MARK: Inline toggle (bold/italic/etc.)

    func testWrapSelectionInBold() {
        let s = "make me bold"
        let r = range(of: "bold", in: s)
        let e = MarkdownEditing.toggleInline(s, r, marker: "**")
        XCTAssertEqual(e.text, "make me **bold**")
        // Selection stays on the inner word.
        XCTAssertEqual((e.text as NSString).substring(with: e.selectedRange), "bold")
    }

    func testUnwrapAlreadyBold() {
        let s = "make me **bold** now"
        let r = range(of: "bold", in: s)   // selection is the inner text
        let e = MarkdownEditing.toggleInline(s, r, marker: "**")
        XCTAssertEqual(e.text, "make me bold now")
        XCTAssertEqual((e.text as NSString).substring(with: e.selectedRange), "bold")
    }

    func testEmptySelectionInsertsMarkerPairWithCaretBetween() {
        let s = "x"
        let r = NSRange(location: 1, length: 0)   // caret at end
        let e = MarkdownEditing.toggleInline(s, r, marker: "**")
        XCTAssertEqual(e.text, "x****")
        XCTAssertEqual(e.selectedRange, NSRange(location: 3, length: 0)) // between the **|**
    }

    func testItalicMarker() {
        let s = "hi"
        let e = MarkdownEditing.toggleInline(s, range(of: "hi", in: s), marker: "*")
        XCTAssertEqual(e.text, "*hi*")
    }

    func testInlineCodeMarker() {
        let s = "code"
        let e = MarkdownEditing.toggleInline(s, range(of: "code", in: s), marker: "`")
        XCTAssertEqual(e.text, "`code`")
    }

    // MARK: Link

    func testInsertLinkWrapsSelectionAndCaretInURL() {
        let s = "click here"
        let r = range(of: "here", in: s)
        let e = MarkdownEditing.insertLink(s, r)
        XCTAssertEqual(e.text, "click [here]()")
        // Caret lands inside the empty () for the URL.
        XCTAssertEqual(e.selectedRange, NSRange(location: ("click [here](" as NSString).length, length: 0))
    }

    // MARK: Line prefixes

    func testToggleHeadingAddsPrefix() {
        let s = "Title"
        let e = MarkdownEditing.toggleLinePrefix(s, NSRange(location: 0, length: 0), prefix: .heading(2))
        XCTAssertEqual(e.text, "## Title")
    }

    func testToggleHeadingRemovesWhenPresent() {
        let s = "## Title"
        let e = MarkdownEditing.toggleLinePrefix(s, NSRange(location: 0, length: 0), prefix: .heading(2))
        XCTAssertEqual(e.text, "Title")
    }

    func testBulletListMultiLineAdd() {
        let s = "one\ntwo\nthree"
        let e = MarkdownEditing.toggleLinePrefix(s, NSRange(location: 0, length: (s as NSString).length), prefix: .bullet)
        XCTAssertEqual(e.text, "- one\n- two\n- three")
    }

    func testBulletListMultiLineRemoveWhenAllPresent() {
        let s = "- one\n- two"
        let e = MarkdownEditing.toggleLinePrefix(s, NSRange(location: 0, length: (s as NSString).length), prefix: .bullet)
        XCTAssertEqual(e.text, "one\ntwo")
    }

    func testOrderedListNumbers() {
        let s = "a\nb\nc"
        let e = MarkdownEditing.toggleLinePrefix(s, NSRange(location: 0, length: (s as NSString).length), prefix: .ordered)
        XCTAssertEqual(e.text, "1. a\n2. b\n3. c")
    }

    func testQuotePrefix() {
        let s = "quote me"
        let e = MarkdownEditing.toggleLinePrefix(s, NSRange(location: 0, length: 0), prefix: .quote)
        XCTAssertEqual(e.text, "> quote me")
    }

    // MARK: Code block

    func testCodeBlockWrapsSelectedLines() {
        let s = "let x = 1"
        let e = MarkdownEditing.toggleCodeBlock(s, NSRange(location: 0, length: (s as NSString).length))
        XCTAssertEqual(e.text, "```\nlet x = 1\n```")
    }

    func testCodeBlockUnwrapsWhenFenced() {
        let s = "```\nlet x = 1\n```"
        let e = MarkdownEditing.toggleCodeBlock(s, NSRange(location: 0, length: (s as NSString).length))
        XCTAssertEqual(e.text, "let x = 1")
    }
}
