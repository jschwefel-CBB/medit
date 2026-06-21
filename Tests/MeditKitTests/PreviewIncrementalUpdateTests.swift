import XCTest
import AppKit
import WebKit
@testable import MeditKit

/// Verify the preview's incremental update: after the first full shell load, a
/// content change updates document.body via app JS (no reload) and shows the new
/// content. Drives a real EditorViewController + web view.
final class PreviewIncrementalUpdateTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }

    func testIncrementalBodyUpdateShowsNewContent() {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "medit.inc.\(UUID().uuidString)")!)
        let doc = TextDocument()
        doc.setTextForTesting("# First")
        let wc = EditorWindowController(document: doc, preferences: prefs)
        _ = wc.window
        wc.loadViewIfNeededForTesting()
        wc.window?.setContentSize(NSSize(width: 700, height: 500))
        wc.window?.makeKeyAndOrderFront(nil)
        let editor = wc.editorForTesting!
        editor.showPreview(true)
        guard let wv = editor.previewWebViewForTesting else { return XCTFail("no web view") }

        // Wait for the first (shell) load.
        let firstLoaded = expectation(description: "first load")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { firstLoaded.fulfill() }
        wait(for: [firstLoaded], timeout: 3)

        // A real edit (the preview reads currentText = editor text view string),
        // then trigger a re-render — same theme → the incremental JS path.
        wc.focusedTextView?.string = "# First\n\n## SECOND HEADING"
        editor.refreshPreviewForTesting()

        // After the JS body update, the new heading must be present.
        let exp = expectation(description: "body contains new heading")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            wv.evaluateJavaScript("document.body.innerText") { result, _ in
                let text = (result as? String) ?? ""
                XCTAssertTrue(text.contains("SECOND HEADING"),
                              "incremental update should show new content; got: \(text.prefix(120))")
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 3)
    }
}
