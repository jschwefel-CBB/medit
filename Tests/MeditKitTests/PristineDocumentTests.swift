import XCTest
@testable import MeditKit

/// Guards the "replace a lone pristine Untitled tab when opening a file" rule:
/// a document is replaceable only if it has no file, is empty, and was never
/// edited.
final class PristineDocumentTests: XCTestCase {

    func testFreshUntitledIsPristine() {
        let doc = TextDocument()
        XCTAssertTrue(doc.isPristineUntitled,
                      "a brand-new untitled document is pristine")
    }

    func testEditedUntitledIsNotPristine() {
        let doc = TextDocument()
        doc.updateText("hello")   // typing into it taints it (text + change count)
        XCTAssertFalse(doc.isPristineUntitled,
                       "a document with content is not pristine")
    }

    func testTypedThenClearedIsNotPristine() {
        let doc = TextDocument()
        doc.updateText("hello")
        doc.updateText("")        // cleared back to empty, but it WAS edited
        XCTAssertFalse(doc.isPristineUntitled,
                       "empty-but-edited (changeCount > 0) is not pristine")
    }
}
