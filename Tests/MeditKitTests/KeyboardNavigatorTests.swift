import XCTest
@testable import MeditKit

final class KeyboardNavigatorTests: XCTestCase {

    // A logical-line provider over the test string (mirrors NSString.lineRange).
    private func logicalLineProvider(_ text: String) -> (NSRange) -> NSRange {
        let ns = text as NSString
        return { range in ns.lineRange(for: range) }
    }

    private func nav(_ text: String, _ current: NSRange,
                     _ command: KeyboardNavigator.NavCommand, extend: Bool) -> NSRange {
        KeyboardNavigator.newSelection(in: text, current: current, command: command,
                                       extend: extend, lineRangeProvider: logicalLineProvider(text))
    }

    // MARK: Home (lineStart)

    func testHomeMovesToLineStart() {
        let text = "alpha\nbeta gamma\ndelta"
        let betaStart = (text as NSString).range(of: "beta").location
        let caret = NSRange(location: betaStart + 7, length: 0) // somewhere in gamma
        let result = nav(text, caret, .lineStart, extend: false)
        XCTAssertEqual(result, NSRange(location: betaStart, length: 0))
    }

    func testHomeAtLineStartStaysPut() {
        let text = "alpha\nbeta"
        let betaStart = (text as NSString).range(of: "beta").location
        let result = nav(text, NSRange(location: betaStart, length: 0), .lineStart, extend: false)
        XCTAssertEqual(result, NSRange(location: betaStart, length: 0))
    }

    func testHomeOnFirstLine() {
        let text = "hello world"
        let result = nav(text, NSRange(location: 6, length: 0), .lineStart, extend: false)
        XCTAssertEqual(result, NSRange(location: 0, length: 0))
    }

    // MARK: End (lineEnd)

    func testEndMovesToLineEndBeforeNewline() {
        let text = "alpha\nbeta gamma\ndelta"
        let betaStart = (text as NSString).range(of: "beta").location
        let caret = NSRange(location: betaStart + 1, length: 0)
        let result = nav(text, caret, .lineEnd, extend: false)
        let expected = betaStart + ("beta gamma" as NSString).length
        XCTAssertEqual(result, NSRange(location: expected, length: 0))
    }

    func testEndOnLastLineNoTrailingNewline() {
        let text = "alpha\ndelta"
        let result = nav(text, NSRange(location: 7, length: 0), .lineEnd, extend: false)
        XCTAssertEqual(result, NSRange(location: (text as NSString).length, length: 0))
    }

    // MARK: Shift+Home / Shift+End extend selection

    func testShiftHomeExtendsToLineStart() {
        let text = "hello world"
        let result = nav(text, NSRange(location: 8, length: 0), .lineStart, extend: true)
        XCTAssertEqual(result, NSRange(location: 0, length: 8))
    }

    func testShiftEndExtendsToLineEnd() {
        let text = "hello world"
        let result = nav(text, NSRange(location: 2, length: 0), .lineEnd, extend: true)
        XCTAssertEqual(result, NSRange(location: 2, length: ("hello world" as NSString).length - 2))
    }

    func testShiftHomeFromExistingSelectionKeepsAnchor() {
        let text = "hello world"
        let result = nav(text, NSRange(location: 4, length: 3), .lineStart, extend: true)
        XCTAssertEqual(result, NSRange(location: 0, length: 4))
    }

    // MARK: Ctrl+Home / Ctrl+End (document)

    func testDocStart() {
        let text = "alpha\nbeta\ngamma"
        let result = nav(text, NSRange(location: 12, length: 0), .docStart, extend: false)
        XCTAssertEqual(result, NSRange(location: 0, length: 0))
    }

    func testDocEnd() {
        let text = "alpha\nbeta\ngamma"
        let result = nav(text, NSRange(location: 0, length: 0), .docEnd, extend: false)
        XCTAssertEqual(result, NSRange(location: (text as NSString).length, length: 0))
    }

    func testCtrlShiftHomeSelectsToDocStart() {
        let text = "alpha\nbeta"
        let result = nav(text, NSRange(location: 8, length: 0), .docStart, extend: true)
        XCTAssertEqual(result, NSRange(location: 0, length: 8))
    }

    func testCtrlShiftEndSelectsToDocEnd() {
        let text = "alpha\nbeta"
        let len = (text as NSString).length
        let result = nav(text, NSRange(location: 2, length: 0), .docEnd, extend: true)
        XCTAssertEqual(result, NSRange(location: 2, length: len - 2))
    }

    // MARK: Edge cases

    func testEmptyDocument() {
        let text = ""
        XCTAssertEqual(nav(text, NSRange(location: 0, length: 0), .lineStart, extend: false),
                       NSRange(location: 0, length: 0))
        XCTAssertEqual(nav(text, NSRange(location: 0, length: 0), .lineEnd, extend: false),
                       NSRange(location: 0, length: 0))
        XCTAssertEqual(nav(text, NSRange(location: 0, length: 0), .docEnd, extend: false),
                       NSRange(location: 0, length: 0))
    }

    func testEmptyLineBetweenContent() {
        let text = "a\n\nb"   // line 2 is empty (index 2)
        let result = nav(text, NSRange(location: 2, length: 0), .lineEnd, extend: false)
        XCTAssertEqual(result, NSRange(location: 2, length: 0), "empty line: start == end")
    }
}
