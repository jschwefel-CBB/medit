import XCTest
@testable import MeditKit

final class IndenterTests: XCTestCase {

    /// Defaults to `openersApply: true` so the opener tests below read as
    /// "in a code language, a trailing `{`/`:` indents". The context-sensitivity
    /// of that rule is covered explicitly by the plain-text / Markdown tests.
    private func indent(_ line: String, tabWidth: Int = 4, useSpaces: Bool = true,
                        openersApply: Bool = true) -> String {
        Indenter.indent(forNewLineAfter: line, tabWidth: tabWidth, useSpaces: useSpaces,
                        openersApply: openersApply)
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

    // A whitespace-only line carries no indent forward. The old suite tested only
    // the empty-string case, which happened to return "" for the wrong reason —
    // it hid that an *indented* blank line re-emitted its indent on every Return,
    // which is the "why does it auto-indent on a blank line" bug the user hit.
    func testWhitespaceOnlyLineProducesNoIndent() {
        XCTAssertEqual(indent("    "), "",
                       "Return on a blank-but-indented line must drop to column zero, "
                       + "not copy the whitespace forward")
    }

    func testTabOnlyLineProducesNoIndent() {
        XCTAssertEqual(indent("\t\t", useSpaces: false), "")
    }

    func testMixedWhitespaceOnlyLineProducesNoIndent() {
        XCTAssertEqual(indent("  \t "), "")
    }

    // MARK: Opener rule is code-language-only

    // The bug the user hit: a line ending in ':' auto-indented the next line in a
    // PLAIN-TEXT document, where ':' is prose, not a Python block opener. With
    // openers off, a trailing colon adds nothing — the next line keeps only the
    // line's own leading indent (here: none).
    func testColonDoesNotIndentWhenOpenersOff() {
        XCTAssertEqual(indent("Note:", openersApply: false), "",
                       "A colon in plain text / Markdown is prose, not a block opener")
    }

    func testBraceDoesNotIndentWhenOpenersOff() {
        XCTAssertEqual(indent("see {this}", openersApply: false), "")
    }

    // Openers-off still copies a real line's own indentation forward — only the
    // extra opener level is suppressed, not indentation entirely.
    func testOpenersOffStillCopiesLeadingIndent() {
        XCTAssertEqual(indent("    Note:", openersApply: false), "    ")
    }

    // And the code path still works: same colon line, openers on, indents.
    func testColonIndentsWhenOpenersOn() {
        XCTAssertEqual(indent("def f():", openersApply: true), "    ")
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
