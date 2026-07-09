import XCTest
import AppKit
import WebKit
@testable import MeditKit

/// Regression guard for the copy-from-Markdown-preview fix: WKWebView's native
/// `copy:` does not reliably reach `NSPasteboard.general` on macOS, so
/// `EditorWindowController.copy(_:)` intercepts it, pulls the current selection
/// via JS, and writes it to the pasteboard directly. This shipped once (as
/// "v2.7.4") on a branch that was never merged into main, so the fix silently
/// never reached a release — this test exists specifically so that can't
/// happen again undetected.
///
/// WKWebView loads + JS round-trips are async with variable timing (especially
/// headless CI), so this polls rather than using fixed sleeps, and skips when
/// no window server renders the page (mirrors PreviewScrollKeyTests).
final class PreviewCopyTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }

    private func poll(_ wv: WKWebView, js: String,
                      until accept: (Any?) -> Bool, timeout: TimeInterval = 20) -> Any? {
        let deadline = Date().addingTimeInterval(timeout)
        var last: Any?
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
            let done = expectation(description: "eval js")
            wv.evaluateJavaScript(js) { r, _ in last = r; done.fulfill() }
            _ = XCTWaiter().wait(for: [done], timeout: 1)
            if accept(last) { return last }
        }
        return last
    }

    func testCopyFromPreviewWritesSelectionToPasteboard() throws {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "medit.previewcopy.\(UUID().uuidString)")!)
        let doc = TextDocument()
        doc.setTextForTesting("# Hello\n\nThis is preview copy test content.")
        let wc = EditorWindowController(document: doc, preferences: prefs)
        _ = wc.window
        wc.loadViewIfNeededForTesting()
        wc.window?.makeKeyAndOrderFront(nil)
        let editor = wc.editorForTesting!
        editor.showPreview(true)
        guard let wv = editor.previewWebViewForTesting else { return XCTFail("no web view") }

        // Wait for the page to actually render (headless CI has no content
        // process, so this can time out — skip rather than fail in that case).
        let loaded = poll(wv, js: "document.body.innerText.length > 0",
                          until: { ($0 as? Bool) == true })
        try XCTSkipUnless((loaded as? Bool) == true,
                          "WKWebView did not render (no window server / headless); skipping copy test")

        // Select all body text via WebKit's own execCommand (app-driven, not
        // content JS, so it's allowed under allowsContentJavaScript = false).
        _ = poll(wv, js: "document.execCommand('selectAll'); window.getSelection().toString().length > 0",
                until: { ($0 as? Bool) == true })

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("sentinel — must be overwritten by copy", forType: .string)

        wc.copy(nil)

        // copy(_:) writes to the pasteboard asynchronously (evaluateJavaScript
        // completion handler); poll the pasteboard rather than assert immediately.
        let deadline = Date().addingTimeInterval(5)
        var pasted: String?
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
            pasted = NSPasteboard.general.string(forType: .string)
            if let pasted, pasted.contains("Hello") { break }
        }

        XCTAssertNotNil(pasted)
        XCTAssertTrue(pasted?.contains("Hello") == true,
                      "copy(_:) should write the preview's selected text to NSPasteboard.general, got: \(pasted ?? "nil")")
        XCTAssertTrue(pasted?.contains("preview copy test content") == true)
    }

    func testCopyDoesNothingWhenPreviewIsNotVisible() {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "medit.previewcopy.\(UUID().uuidString)")!)
        let doc = TextDocument()
        doc.setTextForTesting("plain text, no preview shown")
        let wc = EditorWindowController(document: doc, preferences: prefs)
        _ = wc.window
        wc.loadViewIfNeededForTesting()

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("untouched", forType: .string)

        wc.copy(nil)

        // No preview visible -> the override must no-op and leave the pasteboard
        // alone (the editor's own copy: handles plain-text copy in this case,
        // not this override).
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "untouched")
    }
}
