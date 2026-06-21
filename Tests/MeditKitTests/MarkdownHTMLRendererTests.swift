import XCTest
@testable import MeditKit

final class MarkdownHTMLRendererTests: XCTestCase {
    private func html(_ md: String) -> String { MarkdownHTMLRenderer.renderBody(md) }

    func testHeading() {
        XCTAssertTrue(html("# Hi").contains("<h1>Hi</h1>"))
        XCTAssertTrue(html("## Sub").contains("<h2>Sub</h2>"))
    }

    func testParagraphAndInlineStyles() {
        let h = html("a **b** _c_ ~~d~~")
        XCTAssertTrue(h.contains("<p>"))
        XCTAssertTrue(h.contains("<strong>b</strong>"))
        XCTAssertTrue(h.contains("<em>c</em>"))
        XCTAssertTrue(h.contains("<del>d</del>"))
    }

    func testInlineCode() {
        XCTAssertTrue(html("use `nameField` now").contains("<code>nameField</code>"))
    }

    func testCodeBlockWithLanguageClass() {
        let h = html("```swift\nlet x = 1\n```")
        XCTAssertTrue(h.contains("<pre>"))
        XCTAssertTrue(h.contains("language-swift"))
        XCTAssertTrue(h.contains("let x = 1"))
    }

    func testBlockquote() {
        XCTAssertTrue(html("> quoted").contains("<blockquote>"))
    }

    func testLists() {
        XCTAssertTrue(html("- a\n- b").contains("<ul>"))
        XCTAssertTrue(html("1. a\n2. b").contains("<ol>"))
        XCTAssertTrue(html("- a").contains("<li>"))
    }

    func testTable() {
        let h = html("| H1 | H2 |\n| --- | --- |\n| a | b |")
        XCTAssertTrue(h.contains("<table>"))
        XCTAssertTrue(h.contains("<thead>"))
        XCTAssertTrue(h.contains("<th>H1</th>"))
        XCTAssertTrue(h.contains("<tbody>"))
        XCTAssertTrue(h.contains("<td>a</td>"))
    }

    func testLink() {
        let h = html("[txt](https://example.com)")
        XCTAssertTrue(h.contains("href=\"https://example.com\""))
        XCTAssertTrue(h.contains(">txt</a>"))
    }

    func testThematicBreak() {
        XCTAssertTrue(html("---").contains("<hr"))
    }

    /// Document text must be HTML-escaped so it can't inject markup/script.
    func testHTMLEscaping() {
        let h = html("a < b & c > d \"e\"")
        XCTAssertTrue(h.contains("&lt;"))
        XCTAssertTrue(h.contains("&amp;"))
        XCTAssertTrue(h.contains("&gt;"))
        XCTAssertFalse(h.contains("a < b"), "raw < must be escaped")
    }

    func testScriptInjectionEscaped() {
        let h = html("text <script>alert(1)</script>")
        XCTAssertFalse(h.contains("<script>"), "script tags from content must be escaped")
        XCTAssertTrue(h.contains("&lt;script&gt;"))
    }
}
