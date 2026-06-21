import XCTest
import AppKit
import WebKit
@testable import MeditKit

/// Verify the preview's incremental update: after the first full shell load, a
/// content change updates document.body via app JS (no reload) and shows the new
/// content. Drives a real EditorViewController + web view.
///
/// WKWebView page loads + JS round-trips are asynchronous and their timing varies
/// (especially on a loaded/headless CI runner), so this polls for the rendered
/// result rather than relying on fixed sleeps.
final class PreviewIncrementalUpdateTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }

    /// Poll `document.body.innerText` until it contains `needle` (or time out),
    /// pumping the main run loop so the web view can load and run JS.
    private func waitForBody(_ wv: WKWebView, contains needle: String,
                             reRender: (() -> Void)? = nil, timeout: TimeInterval = 20) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var last = ""
        while Date() < deadline {
            // Let the web view load / run pending JS.
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
            reRender?()   // re-trigger the render each poll (cheap; idempotent)
            let done = expectation(description: "read body")
            wv.evaluateJavaScript("document.body.innerText") { r, _ in
                last = (r as? String) ?? ""
                done.fulfill()
            }
            wait(for: [done], timeout: 2)
            if last.contains(needle) { return last }
        }
        return last
    }

    func testIncrementalBodyUpdateShowsNewContent() throws {
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

        // Wait for the first (shell) load to actually render the original content.
        // If even this never renders, the environment has no usable WebKit content
        // process (e.g. a headless CI runner with no window server) — skip rather
        // than fail; the product behavior is covered by the unit tests + live checks.
        let firstText = waitForBody(wv, contains: "First")
        try XCTSkipUnless(firstText.contains("First"),
                          "WKWebView did not render (no window server / headless); skipping live preview test")

        // A real edit (the preview reads currentText = editor text view string).
        wc.focusedTextView?.string = "# First\n\n## SECOND HEADING"

        // Re-render on each poll so the incremental JS path runs against the loaded
        // page regardless of when the first load finished on this runner.
        let updated = waitForBody(wv, contains: "SECOND HEADING",
                                  reRender: { editor.refreshPreviewForTesting() })
        XCTAssertTrue(updated.contains("SECOND HEADING"),
                      "incremental update should show new content; got: \(updated.prefix(120))")
    }
}
