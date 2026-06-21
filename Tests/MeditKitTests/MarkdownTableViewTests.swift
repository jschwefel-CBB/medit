import XCTest
import AppKit
@testable import MeditKit

final class MarkdownTableViewTests: XCTestCase {
    private func cell(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: 15)])
    }
    private func theme() -> MarkdownRenderer.Theme { MarkdownTableLayoutTestsTheme.theme() }

    func testHoldsSelectableRealText() {
        let v = MarkdownTableView(header: [cell("Name"), cell("Qty")],
                                  rows: [[cell("Apples"), cell("5")]], theme: theme())
        XCTAssertTrue(v.textView.isSelectable)
        XCTAssertFalse(v.textView.isEditable)
        XCTAssertTrue(v.textView.string.contains("Apples"))
        XCTAssertEqual(v.textView.accessibilityIdentifier(), "markdownTableTextView")
    }

    /// The table view holds its NATURAL width (so words never split/wrap); a wider
    /// natural width than the on-screen frame is what the h-scroller scrolls.
    func testNaturalWidthHeldForScrolling() {
        // A long single cell → wide natural width.
        let long = cell(String(repeating: "verylongword ", count: 12))
        let v = MarkdownTableView(header: [cell("A"), cell("B")],
                                  rows: [[cell("x"), long]], theme: theme())
        XCTAssertGreaterThan(v.intrinsicTableSize.width, 300,
                             "natural width reflects the long cell, not a shrunk column")
        XCTAssertGreaterThan(v.intrinsicTableSize.height, 0)
    }

    /// The container is the document container's responsibility, but the view itself
    /// must NOT be its own accessibility element (it exposes the text view).
    func testExposesTextViewToAccessibility() {
        let v = MarkdownTableView(header: [cell("A")], rows: [[cell("b")]], theme: theme())
        XCTAssertFalse(v.isAccessibilityElement())
        XCTAssertTrue((v.accessibilityChildren() ?? []).contains { $0 as? NSTextView === v.textView })
    }
}
