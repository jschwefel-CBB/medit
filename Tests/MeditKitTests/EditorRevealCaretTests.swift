import XCTest
import AppKit
@testable import MeditKit

/// Verify the editor reveals the caret on first appearance when it sits below the
/// visible area. macOS UI state restoration can restore the caret/selection to a
/// spot below the fold (e.g. the end of a long file) AFTER viewDidLoad, without
/// scrolling it into view — so the editor opened showing the top while the caret
/// sat far down. `EditorViewController.viewDidAppear` scrolls the current
/// selection into view once to fix that.
///
/// This is the broader bug the narrow 2.6.1 `insertNewline` fix missed: the caret
/// can be off-screen from open/restore (or any non-Return caret move), not just
/// after a Return. AutoPilot confirmed it live (scroll thumb 0.014 → 0.989 with
/// the caret at the end); this is the deterministic, headless regression gate.
final class EditorRevealCaretTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }

    /// Build the controller and size the window, but DO NOT order it front yet —
    /// ordering front can trigger AppKit's own `viewDidAppear`, which would consume
    /// the one-shot reveal guard before the test sets up the restored-caret state.
    private func makeController(text: String) -> EditorWindowController {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "medit.reveal.\(UUID().uuidString)")!)
        let doc = TextDocument()
        doc.setTextForTesting(text)
        let wc = EditorWindowController(document: doc, preferences: prefs)
        _ = wc.window
        wc.loadViewIfNeededForTesting()
        wc.window?.setContentSize(NSSize(width: 500, height: 200))
        return wc
    }

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

    func testViewDidAppearRevealsCaretBelowTheFold() throws {
        // Long doc; caret restored to the end, view left at the top (the bug state).
        let lines = (1...200).map { "line \($0)" }.joined(separator: "\n")
        let wc = makeController(text: lines)
        guard let editor = wc.editorForTesting,
              let tv = wc.focusedTextView else { return XCTFail("no editor") }
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)

        // Simulate restoration: caret at the very end, but the view scrolled to top.
        let end = (tv.string as NSString).length
        tv.setSelectedRange(NSRange(location: end, length: 0))
        tv.scroll(.zero)
        wc.window?.layoutIfNeeded()
        XCTAssertFalse(tv.visibleRect.intersects(caretRect(tv)),
                       "precondition: caret should be off-screen before viewDidAppear")

        // The fix: viewDidAppear reveals the restored caret.
        editor.viewDidAppear()
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        wc.window?.layoutIfNeeded()

        XCTAssertTrue(tv.visibleRect.intersects(caretRect(tv)),
                      "viewDidAppear should scroll the restored caret into view; "
                      + "caret \(caretRect(tv)) not in visible \(tv.visibleRect)")
    }

    func testViewDidAppearRevealOnlyFiresOnce() throws {
        // Re-appearing a tab must not yank the user's scroll position back to the
        // caret. After the first reveal, scroll away and a second viewDidAppear
        // must leave the scroll position alone.
        let lines = (1...200).map { "line \($0)" }.joined(separator: "\n")
        let wc = makeController(text: lines)
        guard let editor = wc.editorForTesting,
              let tv = wc.focusedTextView else { return XCTFail("no editor") }
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))

        editor.viewDidAppear()                 // first reveal (consumes the one-shot)
        wc.window?.layoutIfNeeded()

        // User scrolls back to the top deliberately.
        tv.scroll(.zero)
        wc.window?.layoutIfNeeded()
        let originBefore = tv.visibleRect.origin

        editor.viewDidAppear()                 // second appearance — must NOT re-reveal
        wc.window?.layoutIfNeeded()
        XCTAssertEqual(tv.visibleRect.origin.y, originBefore.y, accuracy: 1.0,
                       "a second viewDidAppear should not move the user's scroll position")
    }
}
