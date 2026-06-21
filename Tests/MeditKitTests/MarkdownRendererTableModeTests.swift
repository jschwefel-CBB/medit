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

    func testInteractiveModeEmitsTableAttachmentCell() {
        let out = MarkdownRenderer(theme: theme(), tableMode: .interactive).render(md)
        let att = firstAttachment(out)
        XCTAssertTrue(att?.attachmentCell is MarkdownTableAttachmentCell,
                      "interactive tables reserve a slot via a table attachment cell")
        let cell = att?.attachmentCell as? MarkdownTableAttachmentCell
        XCTAssertTrue(cell?.makeTableView().textView.string.contains("Apples") ?? false,
                      "the cell carries real, selectable table text")
    }

    func testStaticModeEmitsImageAttachment() {
        let out = MarkdownRenderer(theme: theme(), tableMode: .static).render(md)
        let att = firstAttachment(out)
        XCTAssertNotNil(att?.image, "static mode rasterizes a grid image")
        XCTAssertFalse(att?.attachmentCell is MarkdownTableAttachmentCell)
    }

    func testDefaultModeIsInteractive() {
        let out = MarkdownRenderer(theme: theme()).render(md)
        XCTAssertTrue(firstAttachment(out)?.attachmentCell is MarkdownTableAttachmentCell)
    }
}
