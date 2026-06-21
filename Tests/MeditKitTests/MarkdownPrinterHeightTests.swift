import XCTest
import AppKit
@testable import MeditKit

final class MarkdownPrinterHeightTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }

    /// Regression: the print view must be sized to the FULL content height, not its
    /// tiny initial frame. Before the fix, lazy NSTextView layout left the view ~100pt
    /// tall, so the print engine clipped everything past the first ~100pt (tables and
    /// most content never printed).
    func testPrintViewSizedToFullContentHeight() {
        var md = "# Heading\n\n| # | Item |\n| --- | --- |\n"
        for i in 1...60 { md += "| \(i) | Row \(i) |\n" }
        let op = MarkdownPrinter.operation(forMarkdown: md)
        let tv = op.view as! NSTextView
        XCTAssertGreaterThan(tv.frame.height, 1000,
                             "print view should be tall enough to hold a 60-row table, not its initial 100pt")
    }
}
