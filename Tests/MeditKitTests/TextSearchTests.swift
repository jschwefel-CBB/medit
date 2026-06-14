import XCTest
@testable import MeditKit

final class TextSearchTests: XCTestCase {

    func testLiteralCaseInsensitive() {
        let text = "The cat sat on the Cat mat."
        let q = SearchQuery(term: "cat", isRegex: false, caseSensitive: false)
        let matches = TextSearch.matches(of: q, in: text)
        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual((text as NSString).substring(with: matches[0]), "cat")
        XCTAssertEqual((text as NSString).substring(with: matches[1]), "Cat")
    }

    func testLiteralCaseSensitive() {
        let text = "Cat cat CAT"
        let q = SearchQuery(term: "cat", isRegex: false, caseSensitive: true)
        let matches = TextSearch.matches(of: q, in: text)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual((text as NSString).substring(with: matches[0]), "cat")
    }

    func testLiteralSpecialCharsAreNotRegex() {
        // Parentheses are literal when isRegex == false.
        let text = "call foo() and foo()"
        let q = SearchQuery(term: "foo()", isRegex: false, caseSensitive: false)
        let matches = TextSearch.matches(of: q, in: text)
        XCTAssertEqual(matches.count, 2)
    }

    func testRegexDigits() {
        let text = "a1 b22 c333"
        let q = SearchQuery(term: "[0-9]+", isRegex: true, caseSensitive: false)
        let matches = TextSearch.matches(of: q, in: text)
        XCTAssertEqual(matches.map { (text as NSString).substring(with: $0) }, ["1", "22", "333"])
    }

    func testRegexCaseInsensitiveFlag() {
        let text = "Foo foo FOO"
        let q = SearchQuery(term: "foo", isRegex: true, caseSensitive: false)
        XCTAssertEqual(TextSearch.matches(of: q, in: text).count, 3)
    }

    func testInvalidRegexReturnsEmptyAndReportsError() {
        let text = "anything"
        let q = SearchQuery(term: "(unclosed", isRegex: true, caseSensitive: false)
        XCTAssertTrue(TextSearch.matches(of: q, in: text).isEmpty)
        XCTAssertNotNil(TextSearch.validate(q), "invalid regex should yield a validation error message")
    }

    func testValidQueryValidatesNil() {
        XCTAssertNil(TextSearch.validate(SearchQuery(term: "ok", isRegex: false, caseSensitive: false)))
        XCTAssertNil(TextSearch.validate(SearchQuery(term: "[a-z]+", isRegex: true, caseSensitive: false)))
    }

    func testEmptyTermYieldsNoMatches() {
        XCTAssertTrue(TextSearch.matches(of: SearchQuery(term: "", isRegex: false, caseSensitive: false), in: "abc").isEmpty)
    }

    func testReplaceAllLiteral() {
        let text = "red green red blue red"
        let q = SearchQuery(term: "red", isRegex: false, caseSensitive: false)
        let (result, count) = TextSearch.replacingAll(of: q, in: text, with: "X")
        XCTAssertEqual(result, "X green X blue X")
        XCTAssertEqual(count, 3)
    }

    func testReplaceAllRegexWithCapture() {
        let text = "key=1; key=2"
        let q = SearchQuery(term: "key=([0-9])", isRegex: true, caseSensitive: false)
        let (result, count) = TextSearch.replacingAll(of: q, in: text, with: "val:$1")
        XCTAssertEqual(result, "val:1; val:2")
        XCTAssertEqual(count, 2)
    }

    func testMultilineSearchAcrossNewlines() {
        let text = "line one\nline two\nline three"
        let q = SearchQuery(term: "line", isRegex: false, caseSensitive: false)
        XCTAssertEqual(TextSearch.matches(of: q, in: text).count, 3)
    }

    func testLineNumberForMatch() {
        let text = "alpha\nbeta\ngamma target\ndelta"
        let q = SearchQuery(term: "target", isRegex: false, caseSensitive: false)
        let matches = TextSearch.matches(of: q, in: text)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(TextSearch.lineNumber(for: matches[0].location, in: text), 3)
    }
}
