import XCTest
@testable import MeditKit

final class TextHygieneTests: XCTestCase {

    private func clean(_ s: String, strip: Bool = true, finalNL: Bool = true) -> String {
        TextHygiene.cleaned(s, stripTrailing: strip, ensureFinalNewline: finalNL)
    }

    func testStripsTrailingSpaces() {
        XCTAssertEqual(clean("foo   \nbar  "), "foo\nbar\n")
    }

    func testStripsTrailingTabs() {
        XCTAssertEqual(clean("foo\t\t\nbar\t"), "foo\nbar\n")
    }

    func testLeadingIndentUntouched() {
        XCTAssertEqual(clean("    foo  "), "    foo\n")
    }

    func testInteriorWhitespaceUntouched() {
        XCTAssertEqual(clean("a  b  c"), "a  b  c\n")
    }

    func testAddsFinalNewlineWhenMissing() {
        XCTAssertEqual(clean("abc", strip: false), "abc\n")
    }

    func testAlreadyOneNewlineUnchanged() {
        XCTAssertEqual(clean("abc\n", strip: false), "abc\n")
    }

    func testCollapsesMultipleTrailingBlankLines() {
        XCTAssertEqual(clean("abc\n\n\n", strip: false), "abc\n")
    }

    func testEmptyString() {
        XCTAssertEqual(clean("", strip: true, finalNL: true), "")
    }

    func testWhitespaceOnlyLines() {
        XCTAssertEqual(clean("a\n   \nb"), "a\n\nb\n")
    }

    func testCRLFPreserved() {
        // strip trailing ws but keep \r\n line endings intact
        XCTAssertEqual(clean("foo  \r\nbar\r\n", finalNL: false), "foo\r\nbar\r\n")
    }

    func testNoStripNoFinalNewlineIsIdentity() {
        XCTAssertEqual(clean("foo  \nbar", strip: false, finalNL: false), "foo  \nbar")
    }
}
