import XCTest
import AppKit
@testable import MeditKit

final class MarkdownRendererTests: XCTestCase {
    private func renderer() -> MarkdownRenderer {
        MarkdownRenderer(theme: .init(
            baseFont: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            foreground: .textColor, secondary: .secondaryLabelColor,
            codeBackground: NSColor.gray.withAlphaComponent(0.15),
            linkColor: .linkColor, isDark: false))
    }
    private func attrs(_ s: NSAttributedString, at i: Int) -> [NSAttributedString.Key: Any] {
        s.attributes(at: i, effectiveRange: nil)
    }
    private func offset(_ s: NSAttributedString, of sub: String) -> Int {
        s.string.range(of: sub)!.lowerBound.utf16Offset(in: s.string)
    }

    // MARK: Inline

    func testPlainTextRendersWithBaseFont() {
        let out = renderer().render("hello")
        XCTAssertTrue(out.string.contains("hello"))
        XCTAssertNotNil(attrs(out, at: 0)[.font])
    }
    func testStrongIsBold() {
        let out = renderer().render("a **bold** b")
        let f = attrs(out, at: offset(out, of: "bold"))[.font] as! NSFont
        XCTAssertTrue(f.fontDescriptor.symbolicTraits.contains(.bold))
    }
    func testEmphasisIsItalic() {
        let out = renderer().render("a *it* b")
        let f = attrs(out, at: offset(out, of: "it"))[.font] as! NSFont
        XCTAssertTrue(f.fontDescriptor.symbolicTraits.contains(.italic))
    }
    func testStrikethroughHasAttribute() {
        let out = renderer().render("a ~~gone~~ b")
        XCTAssertNotNil(attrs(out, at: offset(out, of: "gone"))[.strikethroughStyle])
    }
    func testInlineCodeHasBackground() {
        let out = renderer().render("a `code` b")
        XCTAssertNotNil(attrs(out, at: offset(out, of: "code"))[.backgroundColor])
    }
    func testLinkCarriesURL() {
        let out = renderer().render("[txt](https://example.com)")
        XCTAssertEqual((attrs(out, at: offset(out, of: "txt"))[.link] as? URL)?.host, "example.com")
    }
}
