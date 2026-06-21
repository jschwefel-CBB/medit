import XCTest
import AppKit
@testable import MeditKit

final class MarkdownRendererTableModeTests: XCTestCase {
    private func theme() -> MarkdownRenderer.Theme { MarkdownTableLayoutTestsTheme.theme() }
    private let md = """
    | Name | Qty |
    | ---- | --- |
    | Apples | 5 |
    """

    private func firstAttachment(_ s: NSAttributedString) -> NSTextAttachment? {
        var found: NSTextAttachment?
        s.enumerateAttribute(.attachment, in: NSRange(location: 0, length: s.length)) { v, _, stop in
            if let a = v as? NSTextAttachment { found = a; stop.pointee = true }
        }
        return found
    }

    /// True if the string has any cell laid out via an NSTextTableBlock.
    private func hasTextTable(_ s: NSAttributedString) -> Bool {
        var found = false
        s.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: s.length)) { v, _, stop in
            if let p = v as? NSParagraphStyle, p.textBlocks.contains(where: { $0 is NSTextTableBlock }) {
                found = true; stop.pointee = true
            }
        }
        return found
    }

    func testInteractiveModeEmitsInlineTextTable() {
        let out = MarkdownRenderer(theme: theme(), tableMode: .interactive).render(md)
        XCTAssertTrue(hasTextTable(out), "interactive tables are native NSTextTable text")
        XCTAssertNil(firstAttachment(out), "no image attachment in interactive mode")
        XCTAssertTrue(out.string.contains("Apples"), "cell text is real selectable text")
    }

    func testStaticModeEmitsImageAttachment() {
        let out = MarkdownRenderer(theme: theme(), tableMode: .static).render(md)
        XCTAssertNotNil(firstAttachment(out)?.image, "static mode rasterizes a grid image")
        XCTAssertFalse(hasTextTable(out), "static mode is not an NSTextTable")
    }

    func testDefaultModeIsInteractive() {
        let out = MarkdownRenderer(theme: theme()).render(md)
        XCTAssertTrue(hasTextTable(out))
    }
}
