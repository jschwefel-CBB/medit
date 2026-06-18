import XCTest
import AppKit
@testable import MeditKit

final class MarkdownPrintTests: XCTestCase {

    func testMarkdownDocumentPrintsRenderedContent() throws {
        let doc = TextDocument()
        doc.setTextForTesting("# Title\n\nSome **bold** text.")
        doc.languageOverride = "markdown"
        let op = try doc.printOperation(withSettings: [:])
        // The print view should be a text view rendering the markdown (heading
        // text present, but the literal "#" markup gone — i.e. it's rendered).
        let tv = op.view as? NSTextView
        XCTAssertNotNil(tv)
        let printed = tv?.string ?? ""
        XCTAssertTrue(printed.contains("Title"))
        XCTAssertTrue(printed.contains("bold"))
        XCTAssertFalse(printed.contains("# Title"), "should print rendered output, not raw markdown")
    }

    func testNonMarkdownFallsBackToDefaultPrinting() throws {
        let doc = TextDocument()
        doc.setTextForTesting("plain text")
        // No markdown override; default print path returns an operation too.
        let op = try doc.printOperation(withSettings: [:])
        XCTAssertNotNil(op)
    }

    func testPlainTextPrintWithLineNumbersIncludesHeaderAndNumbers() {
        let op = MarkdownPrinter.plainTextOperation("alpha\nbeta\ngamma", jobTitle: "notes.txt",
                                                    lineNumbers: true)
        let s = (op.view as? NSTextView)?.string ?? ""
        XCTAssertTrue(s.contains("notes.txt"), "header with filename")
        XCTAssertTrue(s.contains("1") && s.contains("2") && s.contains("3"), "line numbers")
        XCTAssertTrue(s.contains("beta"))
    }

    func testPrinterBuildsOperationFromMarkdown() {
        let op = MarkdownPrinter.operation(forMarkdown: "# H\n\n| A | B |\n|---|---|\n| 1 | 2 |")
        XCTAssertNotNil(op.view as? NSTextView)
        // The rendered content includes the heading text.
        XCTAssertTrue((op.view as? NSTextView)?.string.contains("H") == true)
    }
}
