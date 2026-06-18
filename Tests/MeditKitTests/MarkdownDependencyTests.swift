import XCTest
import Markdown
@testable import MeditKit

/// Smoke test confirming the swift-markdown dependency resolves and parses.
final class MarkdownDependencyTests: XCTestCase {
    func testCanParseDocument() {
        let doc = Document(parsing: "# Hello\n\nA *para*.")
        XCTAssertEqual(doc.childCount, 2)   // heading + paragraph
    }

    func testParsesGFMTable() {
        // GFM table extension is compiled into swift-markdown's cmark-gfm.
        let doc = Document(parsing: "| H |\n|---|\n| c |")
        var sawTable = false
        for child in doc.children where child is Markdown.Table { sawTable = true }
        XCTAssertTrue(sawTable, "GFM tables should parse as Table nodes")
    }
}
