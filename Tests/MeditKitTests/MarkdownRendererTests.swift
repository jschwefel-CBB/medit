import XCTest
import AppKit
@testable import MeditKit

final class MarkdownRendererTests: XCTestCase {
    private func renderer() -> MarkdownRenderer {
        MarkdownRenderer(theme: .init(
            baseFont: NSFont.systemFont(ofSize: 15),
            monoFont: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            foreground: .textColor, secondary: .secondaryLabelColor,
            codeBackground: NSColor.gray.withAlphaComponent(0.15),
            headingColor: .systemBlue, quoteBarColor: .systemOrange,
            tableBorderColor: .separatorColor,
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

    // MARK: Blocks

    func testHeadingIsLargerAndBold() {
        let out = renderer().render("# Big")
        let f = attrs(out, at: 0)[.font] as! NSFont
        XCTAssertGreaterThan(f.pointSize, 13)
        XCTAssertTrue(f.fontDescriptor.symbolicTraits.contains(.bold))
    }
    func testUnorderedListHasHangingIndentAndBullet() {
        let out = renderer().render("- one\n- two")
        XCTAssertTrue(out.string.contains("one") && out.string.contains("two"))
        let p = attrs(out, at: offset(out, of: "one"))[.paragraphStyle] as! NSParagraphStyle
        XCTAssertGreaterThan(p.headIndent, 0)
    }
    func testOrderedListShowsNumbers() {
        let out = renderer().render("1. a\n2. b")
        XCTAssertTrue(out.string.contains("1.") && out.string.contains("2."))
    }
    func testCodeBlockIsMonospacedAndMarkedForPanel() {
        let out = renderer().render("```\nlet x = 1\n```")
        let i = offset(out, of: "let x")
        let f = attrs(out, at: i)[.font] as! NSFont
        XCTAssertTrue(f.fontDescriptor.symbolicTraits.contains(.monoSpace) || f.isFixedPitch)
        // The full-width panel is drawn by the layout manager off this block attr.
        XCTAssertEqual(attrs(out, at: i)[MarkdownBlockAttribute.blockKind] as? Int,
                       MarkdownBlockAttribute.Kind.codeBlock.rawValue)
    }
    func testBlockQuoteIsIndented() {
        let out = renderer().render("> quoted")
        let p = attrs(out, at: offset(out, of: "quoted"))[.paragraphStyle] as! NSParagraphStyle
        XCTAssertGreaterThan(p.firstLineHeadIndent, 0)
    }
    func testTaskListShowsCheckboxes() {
        let out = renderer().render("- [ ] todo\n- [x] done")
        XCTAssertTrue(out.string.contains("☐") && out.string.contains("☑"))
    }
    func testThematicBreakRenders() {
        let out = renderer().render("a\n\n---\n\nb")
        XCTAssertTrue(out.string.contains("a") && out.string.contains("b"))
    }
    func testH1IsMarkedForUnderlineRule() {
        let out = renderer().render("# Title")
        XCTAssertEqual(attrs(out, at: 0)[MarkdownBlockAttribute.blockKind] as? Int,
                       MarkdownBlockAttribute.Kind.headingRule.rawValue)
    }
    func testH3IsNotMarkedForRule() {
        let out = renderer().render("### Small")
        XCTAssertNil(attrs(out, at: 0)[MarkdownBlockAttribute.blockKind])
    }
    func testBlockQuoteIsMarked() {
        let out = renderer().render("> quoted")
        let i = offset(out, of: "quoted")
        XCTAssertEqual(attrs(out, at: i)[MarkdownBlockAttribute.blockKind] as? Int,
                       MarkdownBlockAttribute.Kind.blockQuote.rawValue)
    }

    func testTableRendersAsAnAttachmentImage() {
        // Tables render to a drawn bordered-grid image wrapped in a text attachment.
        let out = renderer().render("| H |\n|---|\n| c |")
        var foundAttachment = false
        out.enumerateAttribute(.attachment, in: NSRange(location: 0, length: out.length)) { value, _, _ in
            if let att = value as? NSTextAttachment, att.image != nil { foundAttachment = true }
        }
        XCTAssertTrue(foundAttachment, "a GFM table should render as an image attachment")
    }
}
