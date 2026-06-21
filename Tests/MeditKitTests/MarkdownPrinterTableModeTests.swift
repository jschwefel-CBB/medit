import XCTest
import AppKit
@testable import MeditKit

final class MarkdownPrinterTableModeTests: XCTestCase {
    func testPrinterOperationRendersStaticTable() {
        let op = MarkdownPrinter.operation(forMarkdown: "| A | B |\n| - | - |\n| 1 | 2 |")
        let tv = op.view as? NSTextView
        XCTAssertNotNil(tv)
        var att: NSTextAttachment?
        tv?.textStorage?.enumerateAttribute(.attachment,
            in: NSRange(location: 0, length: tv?.textStorage?.length ?? 0)) { v, _, stop in
            if let a = v as? NSTextAttachment { att = a; stop.pointee = true }
        }
        XCTAssertNotNil(att?.image, "printer should rasterize tables to a static grid")
        XCTAssertFalse(att?.attachmentCell is MarkdownTableAttachmentCell)
    }
}
