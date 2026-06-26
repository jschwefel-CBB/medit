import XCTest
import AppKit
import WebKit
@testable import MeditKit

/// Verify the preview's navigation-key scrolling: after the shell loads, the
/// app-injected handler (`PreviewHTMLTemplate.scrollKeyHandlerJS`) is installed and
/// a PageDown keydown scrolls the document, while Home returns to the top.
///
/// Content/page JS is disabled for security, so this handler is what makes
/// Home/End/PageUp/PageDown work in the preview. WKWebView loads + JS round-trips
/// are async with variable timing (especially headless CI), so this polls rather
/// than using fixed sleeps, and skips when no window server renders the page.
final class PreviewScrollKeyTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }

    /// Evaluate `js` (expected to return a value) repeatedly until `accept` passes
    /// or the timeout elapses, pumping the run loop so the web view can load/run JS.
    private func poll(_ wv: WKWebView, js: String,
                      until accept: (Any?) -> Bool, timeout: TimeInterval = 20) -> Any? {
        let deadline = Date().addingTimeInterval(timeout)
        var last: Any?
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
            let done = expectation(description: "eval js")
            wv.evaluateJavaScript(js) { r, _ in last = r; done.fulfill() }
            // Non-failing waiter: headless CI has no web content process, so the
            // callback may never fire — let the poll loop time out (and the outer
            // XCTSkipUnless skip) instead of failing on an unfulfilled expectation.
            _ = XCTWaiter().wait(for: [done], timeout: 1)
            if accept(last) { return last }
        }
        return last
    }

    func testPageDownAndHomeScrollPreview() throws {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "medit.scroll.\(UUID().uuidString)")!)
        let doc = TextDocument()
        // Enough lines to overflow a 500pt-tall viewport so there is room to scroll.
        let long = (1...200).map { "Line \($0)" }.joined(separator: "\n\n")
        doc.setTextForTesting("# Top\n\n\(long)\n\n## Bottom")
        let wc = EditorWindowController(document: doc, preferences: prefs)
        _ = wc.window
        wc.loadViewIfNeededForTesting()
        wc.window?.setContentSize(NSSize(width: 700, height: 500))
        wc.window?.makeKeyAndOrderFront(nil)
        let editor = wc.editorForTesting!
        editor.showPreview(true)
        guard let wv = editor.previewWebViewForTesting else { return XCTFail("no web view") }

        // Wait for the handler to be installed by didFinish. If it never installs,
        // the page never rendered (headless / no window server) — skip.
        let installed = poll(wv, js: "window.__meditScrollKeys === true",
                             until: { ($0 as? Bool) == true })
        try XCTSkipUnless((installed as? Bool) == true,
                          "WKWebView did not render (no window server / headless); skipping scroll-key test")

        // Dispatch a real PageDown keydown — exercises the exact injected listener.
        let pageDown = "document.dispatchEvent(new KeyboardEvent('keydown',{key:'PageDown',bubbles:true})); true;"
        let scrolled = poll(wv, js: "\(pageDown) window.scrollY",
                            until: { (($0 as? NSNumber)?.doubleValue ?? 0) > 0 })
        XCTAssertGreaterThan((scrolled as? NSNumber)?.doubleValue ?? 0, 0,
                             "PageDown should scroll the preview down")

        // Home returns to the very top.
        let home = "document.dispatchEvent(new KeyboardEvent('keydown',{key:'Home',bubbles:true})); true;"
        let backToTop = poll(wv, js: "\(home) window.scrollY",
                             until: { (($0 as? NSNumber)?.doubleValue ?? 1) == 0 })
        XCTAssertEqual((backToTop as? NSNumber)?.doubleValue ?? -1, 0,
                       "Home should scroll the preview back to the top")
    }
}
