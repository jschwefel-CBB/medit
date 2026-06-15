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
}
