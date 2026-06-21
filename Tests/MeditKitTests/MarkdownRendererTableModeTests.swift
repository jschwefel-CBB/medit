import XCTest
import AppKit
@testable import MeditKit

final class MarkdownRendererTableModeTests: XCTestCase {
    private func theme() -> MarkdownRenderer.Theme { MarkdownTableLayoutTests.testTheme() }
    private let md = """
    | Name | Qty |
    | ---- | --- |
    | Apples | 5 |
    """

    /// Find the first attachment in a rendered string.
    private func firstAttachment(_ s: NSAttributedString) -> NSTextAttachment? {
        var found: NSTextAttachment?
        s.enumerateAttribute(.attachment, in: NSRange(location: 0, length: s.length)) { v, _, stop in
            if let a = v as? NSTextAttachment { found = a; stop.pointee = true }
        }
        return found
    }

    func testInteractiveModeEmitsTableAttachmentCell() {
        let r = MarkdownRenderer(theme: theme(), tableMode: .interactive)
        let out = r.render(md)
        let att = firstAttachment(out)
        XCTAssertNotNil(att)
        XCTAssertTrue(att?.attachmentCell is MarkdownTableAttachmentCell)
        // Real cell text is carried, not rasterized.
        let cell = att?.attachmentCell as? MarkdownTableAttachmentCell
        XCTAssertTrue(cell?.makeTableView().textView.string.contains("Apples") ?? false)
    }

    func testStaticModeEmitsImageAttachment() {
        let r = MarkdownRenderer(theme: theme(), tableMode: .static)
        let out = r.render(md)
        let att = firstAttachment(out)
        XCTAssertNotNil(att?.image)
        XCTAssertFalse(att?.attachmentCell is MarkdownTableAttachmentCell)
    }

    func testDefaultModeIsInteractive() {
        let out = MarkdownRenderer(theme: theme()).render(md)
        XCTAssertTrue(firstAttachment(out)?.attachmentCell is MarkdownTableAttachmentCell)
    }
}
