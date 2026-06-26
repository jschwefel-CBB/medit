import XCTest
import AppKit
@testable import MeditKit

/// Verify that pressing Return (insertNewline) keeps the new line visible by
/// scrolling the caret into view — even when the caret is past the bottom of the
/// visible area. The editor's custom `insertNewline` override (auto-indent,
/// bracket-pair split) replaces AppKit's, which would have scrolled the caret
/// itself; the override must do the same.
final class EditorNewlineScrollTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }

    private func makeController(text: String) -> EditorWindowController {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "medit.nlscroll.\(UUID().uuidString)")!)
        let doc = TextDocument()
        doc.setTextForTesting(text)
        let wc = EditorWindowController(document: doc, preferences: prefs)
        _ = wc.window
        wc.loadViewIfNeededForTesting()
        // Small window so a long document overflows and there is room to scroll.
        wc.window?.setContentSize(NSSize(width: 500, height: 200))
        wc.window?.makeKeyAndOrderFront(nil)
        return wc
    }

    /// The caret's rect in the text view's coordinate space (post-layout).
    private func caretRect(_ tv: NSTextView) -> NSRect {
        let r = tv.selectedRange()
        guard let lm = tv.layoutManager, let tc = tv.textContainer else { return .zero }
        let glyphRange = lm.glyphRange(forCharacterRange: NSRange(location: r.location, length: 0),
                                       actualCharacterRange: nil)
        var rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
        rect.origin.x += tv.textContainerInset.width
        rect.origin.y += tv.textContainerInset.height
        return rect
    }

    func testReturnPastBottomScrollsNewLineIntoView() throws {
        // Many lines so the end sits well below a 200pt-tall viewport.
        let lines = (1...200).map { "line \($0)" }.joined(separator: "\n")
        let wc = makeController(text: lines)
        guard let tv = wc.focusedTextView as? EditorTextView else { return XCTFail("no text view") }
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)

        // Caret at the very end (past the visible area), then scroll back to the top
        // so the caret is definitely NOT visible before we press Return.
        let end = (tv.string as NSString).length
        tv.setSelectedRange(NSRange(location: end, length: 0))
        tv.scroll(.zero)
        wc.window?.layoutIfNeeded()
        let visibleBefore = tv.visibleRect
        XCTAssertFalse(visibleBefore.contains(caretRect(tv)),
                       "precondition: caret should be off-screen before Return")

        // Press Return — the custom override inserts the newline.
        tv.insertNewline(nil)
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        wc.window?.layoutIfNeeded()

        // The new caret must now be within the visible rect.
        let caret = caretRect(tv)
        let visibleAfter = tv.visibleRect
        XCTAssertTrue(visibleAfter.intersects(caret),
                      "Return should scroll the new line into view; caret \(caret) not in visible \(visibleAfter)")
    }

    func testReturnInsertsNewlineRegardlessOfScroll() {
        // Functional guard: the override still inserts a newline at the caret.
        let wc = makeController(text: "alpha")
        guard let tv = wc.focusedTextView as? EditorTextView else { return XCTFail("no text view") }
        tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
        tv.insertNewline(nil)
        XCTAssertEqual(tv.string, "alpha\n", "Return should append a newline")
    }
}
