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

    // MARK: Bare-URL autolinking
    //
    // swift-markdown does not attach the GFM autolink extension, so a URL typed as
    // plain prose is a Text node and — before this change — rendered in body colour,
    // NOT as a link. `visitText` now autolinks it so EVERY URL in the preview is a
    // highlighted `<a>`, whether written as `[label](url)`, `<url>`, or bare.
    //
    // Cross-check: `uitests/preview-autolink-urls.json` opens a `.md` with a bare
    // URL in the auto-preview and asserts the user-visible outcome — an AXLink in
    // the rendered web content. These unit tests assert the HTML the plan depends
    // on (an `<a href>` for the bare URL, and NO anchor where there must not be
    // one). A unit pass and a GUI pass cannot both be wrong in the same direction.

    private func anchorCount(_ h: String) -> Int {
        h.components(separatedBy: "<a ").count - 1
    }

    func testBareURLIsAutolinked() {
        let h = html("see https://example.com now")
        XCTAssertTrue(h.contains("<a href=\"https://example.com\">https://example.com</a>"),
                      "a bare URL must become a highlighted link")
    }

    /// Negative control: a URL used as the *text* of a Markdown link must not be
    /// wrapped in a second, nested anchor. Without the `linkDepth` guard this
    /// produces `<a ...><a ...>...</a></a>` — invalid and double-styled.
    func testURLAsLinkTextIsNotDoubleLinked() {
        let h = html("[https://x.com](https://x.com)")
        XCTAssertEqual(anchorCount(h), 1, "a URL used as link text must not be re-linked")
        XCTAssertTrue(h.contains(">https://x.com</a>"))
    }

    /// Negative control: URLs inside inline code stay literal — never linked.
    func testURLInInlineCodeIsNotLinked() {
        let h = html("run `curl https://x.com` please")
        XCTAssertTrue(h.contains("<code>curl https://x.com</code>"))
        XCTAssertEqual(anchorCount(h), 0, "a URL inside inline code must not be linked")
    }

    /// Negative control: URLs inside a fenced code block stay literal.
    func testURLInCodeBlockIsNotLinked() {
        let h = html("```\nvisit https://x.com\n```")
        XCTAssertEqual(anchorCount(h), 0, "a URL inside a code block must not be linked")
    }

    /// An angle-bracket autolink is parsed by swift-markdown into a Link node, so
    /// it must yield exactly one anchor — the `linkDepth` guard prevents the inner
    /// text from being linked a second time.
    func testAngleAutolinkIsSingleAnchor() {
        let h = html("<https://x.com>")
        XCTAssertEqual(anchorCount(h), 1)
        XCTAssertTrue(h.contains("href=\"https://x.com\""))
    }

    func testBareWWWHostIsAutolinked() {
        let h = html("go to www.example.com today")
        XCTAssertTrue(h.contains(">www.example.com</a>"), "a bare www host must be linked")
        XCTAssertTrue(h.contains("href=\"http://www.example.com\""),
                      "NSDataDetector normalizes a scheme-less host to http://")
    }

    func testBareEmailIsAutolinked() {
        let h = html("mail me at a@b.com anytime")
        XCTAssertTrue(h.contains("href=\"mailto:a@b.com\""), "a bare email must become a mailto link")
    }

    func testURLInHeadingIsAutolinked() {
        let h = html("# https://x.com")
        XCTAssertTrue(h.contains("<h1>"))
        XCTAssertEqual(anchorCount(h), 1, "a URL in a heading must be linked")
    }

    /// Surrounding prose must still be HTML-escaped when a URL is present — the
    /// autolink path must not become a hole in the escaping invariant.
    func testTextAroundAutolinkStillEscaped() {
        let h = html("a < b then https://x.com end")
        XCTAssertTrue(h.contains("&lt;"), "text around a URL must still be escaped")
        XCTAssertTrue(h.contains("<a href=\"https://x.com\">https://x.com</a>"))
    }

    /// Negative control / sentinel: prose with no URL must gain no anchors — the
    /// detector must not spuriously link ordinary words.
    func testPlainProseGetsNoAnchor() {
        XCTAssertEqual(anchorCount(html("just some ordinary words here")), 0)
    }
}
