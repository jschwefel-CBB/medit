import XCTest
@testable import MeditKit

final class IndenterTests: XCTestCase {

    private func indent(_ line: String, tabWidth: Int = 4, useSpaces: Bool = true) -> String {
        Indenter.indent(forNewLineAfter: line, tabWidth: tabWidth, useSpaces: useSpaces)
    }

    func testNoIndent() {
        XCTAssertEqual(indent("hello"), "")
    }

    func testCopiesLeadingSpaces() {
        XCTAssertEqual(indent("    hello"), "    ")
    }

    func testCopiesLeadingTabsWhenUseSpacesFalse() {
        XCTAssertEqual(indent("\t\thello", useSpaces: false), "\t\t")
    }

    func testExtraIndentAfterOpenBrace() {
        // "  foo {" -> copy "  " + one level (4 spaces) = 6 spaces
        XCTAssertEqual(indent("  foo {"), "      ")
    }

    func testExtraIndentAfterColon() {
        XCTAssertEqual(indent("def f():"), "    ")
    }

    func testExtraIndentUsesTabWhenUseSpacesFalse() {
        XCTAssertEqual(indent("\tif x {", useSpaces: false), "\t\t")
    }

    func testTrailingWhitespaceAfterBraceStillCountsAsOpener() {
        XCTAssertEqual(indent("foo {   "), "    ")   // ignore trailing ws when finding last non-ws
    }

    func testEmptyLine() {
        XCTAssertEqual(indent(""), "")
    }

    // MARK: Split-pair (indent between brackets)

    func testShouldSplitPairMatchingFamilies() {
        XCTAssertTrue(Indenter.shouldSplitPair(before: "{", after: "}"))
        XCTAssertTrue(Indenter.shouldSplitPair(before: "(", after: ")"))
        XCTAssertTrue(Indenter.shouldSplitPair(before: "[", after: "]"))
    }

    func testShouldNotSplitPairMismatchOrNonBracket() {
        XCTAssertFalse(Indenter.shouldSplitPair(before: "{", after: ")"))
        XCTAssertFalse(Indenter.shouldSplitPair(before: "(", after: "}"))
        XCTAssertFalse(Indenter.shouldSplitPair(before: "a", after: "b"))
        XCTAssertFalse(Indenter.shouldSplitPair(before: "}", after: "{"))
    }

    func testSplitPairInsertionSpaces() {
        // No existing indent, 2-space tabs: caret line is "\n  ", closer line is "\n".
        let r = Indenter.splitPairInsertion(currentIndent: "", tabWidth: 2, useSpaces: true)
        XCTAssertEqual(r.text, "\n  \n")
        XCTAssertEqual(r.caretOffset, 3)  // after "\n  "
    }

    func testSplitPairInsertionPreservesIndentAndTabs() {
        // Existing 4-space indent, tab-based one level.
        let r = Indenter.splitPairInsertion(currentIndent: "    ", tabWidth: 4, useSpaces: false)
        XCTAssertEqual(r.text, "\n    \t\n    ")
        XCTAssertEqual(r.caretOffset, ("\n    \t").count)
    }

    func testOneLevel() {
        XCTAssertEqual(Indenter.oneLevel(tabWidth: 2, useSpaces: true), "  ")
        XCTAssertEqual(Indenter.oneLevel(tabWidth: 4, useSpaces: false), "\t")
    }
}
