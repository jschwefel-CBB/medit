import XCTest
import AppKit
@testable import MeditKit

final class AlreadyOpenFocusTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }

    func testFocusIfAlreadyOpenFindsRegisteredDocumentAndDoesNotDuplicate() throws {
        // Register a document for a URL deterministically (avoid openDocument's async
        // window/registration timing, which is GUI-runtime behavior, not the logic
        // under test). focusIfAlreadyOpen's job: find the already-registered doc for
        // a URL and return true without creating a second one.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("medit-focus-\(UUID().uuidString).txt")
        try "hello".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let doc = TextDocument()
        doc.fileURL = tmp
        NSDocumentController.shared.addDocument(doc)
        defer { NSDocumentController.shared.removeDocument(doc) }

        // Look it up by the document's own registered URL.
        let registered = doc.fileURL ?? tmp
        let countBefore = NSDocumentController.shared.documents.count

        let focused = EditorWindowController.focusIfAlreadyOpen(registered)
        XCTAssertTrue(focused, "a registered (already-open) file should be focusable")
        XCTAssertEqual(NSDocumentController.shared.documents.count, countBefore,
                       "focusing must not register a duplicate document")
    }

    func testFocusIfAlreadyOpenReturnsFalseForUnopenedFile() {
        let notOpen = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("medit-not-open-\(UUID().uuidString).txt")
        XCTAssertFalse(EditorWindowController.focusIfAlreadyOpen(notOpen),
                       "a file that isn't open should not be reported as focusable")
    }
}
