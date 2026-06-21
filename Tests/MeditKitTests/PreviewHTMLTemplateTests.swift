import XCTest
@testable import MeditKit

final class PreviewHTMLTemplateTests: XCTestCase {
    func testWrapsBodyInDocument() {
        let doc = PreviewHTMLTemplate.htmlDocument(body: "<p>hi</p>", isDark: true)
        XCTAssertTrue(doc.contains("<html"))
        XCTAssertTrue(doc.contains("<style>"))
        XCTAssertTrue(doc.contains("<body"))
        XCTAssertTrue(doc.contains("<p>hi</p>"))
    }

    func testTableCSSEnablesHorizontalScrollAndGrowToContent() {
        let doc = PreviewHTMLTemplate.htmlDocument(body: "", isDark: true)
        // The wrapper scrolls horizontally; the table grows to content but caps at
        // the viewport — the behavior every TextKit approach couldn't deliver.
        XCTAssertTrue(doc.contains("overflow-x") && doc.contains("auto"),
                      "table wrapper must allow horizontal scroll")
        XCTAssertTrue(doc.contains("max-content"), "table grows to its content width")
        XCTAssertTrue(doc.contains("max-width") && doc.contains("100%"),
                      "table caps at the viewport width")
    }

    func testHeaderUsesCBBSteelAndBlue() {
        let doc = PreviewHTMLTemplate.htmlDocument(body: "", isDark: true)
        XCTAssertTrue(doc.lowercased().contains("#4a9fc8"), "steel header background")
        XCTAssertTrue(doc.lowercased().contains("#0a2351"), "blue header text")
    }

    func testInlineCodeChipStyled() {
        let doc = PreviewHTMLTemplate.htmlDocument(body: "", isDark: true)
        XCTAssertTrue(doc.contains("code") && doc.contains("border-radius"),
                      "inline code is a rounded chip")
    }

    func testDarkVsLightDiffer() {
        let dark = PreviewHTMLTemplate.htmlDocument(body: "", isDark: true)
        let light = PreviewHTMLTemplate.htmlDocument(body: "", isDark: false)
        XCTAssertNotEqual(dark, light, "dark and light produce different CSS")
    }

    func testJavaScriptNotRequired() {
        // The preview document carries no <script> — it's pure HTML+CSS.
        let doc = PreviewHTMLTemplate.htmlDocument(body: "<p>x</p>", isDark: true)
        XCTAssertFalse(doc.contains("<script"))
    }
}
