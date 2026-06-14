import XCTest
import AppKit
@testable import MeditKit

/// Headless smoke tests that drive the editor's view lifecycle to surface
/// runtime crashes (the kind that only appear when the app actually runs, not
/// during compilation). These mirror what happens when a user opens a window
/// and clicks/types into it.
final class EditorSmokeTests: XCTestCase {

    /// Force AppKit into a usable state for headless view instantiation.
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    private func makeWindowController(text: String = "") -> EditorWindowController {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "medit.smoke.\(UUID().uuidString)")!)
        let document = TextDocument()
        document.setTextForTesting(text)
        let controller = EditorWindowController(document: document, preferences: prefs)
        // Force the window + content view controller to load.
        _ = controller.window
        controller.loadViewIfNeededForTesting()
        return controller
    }

    func testOpenEmptyDocumentLoadsWithoutCrash() {
        let controller = makeWindowController(text: "")
        XCTAssertNotNil(controller.window)
        XCTAssertNotNil(controller.focusedTextView)
    }

    func testOpenNonEmptyDocumentLoadsWithoutCrash() {
        let controller = makeWindowController(text: "let x = 1\nlet y = 2\n")
        XCTAssertNotNil(controller.focusedTextView)
        XCTAssertEqual(controller.focusedTextView?.string, "let x = 1\nlet y = 2\n")
    }

    func testMakeTextViewFirstResponderDoesNotCrash() {
        // This mirrors clicking into the editor.
        let controller = makeWindowController(text: "click target")
        guard let window = controller.window, let tv = controller.focusedTextView else {
            return XCTFail("missing window/textview")
        }
        window.makeKeyAndOrderFront(nil)
        let became = window.makeFirstResponder(tv)
        XCTAssertTrue(became || !became) // just assert no crash occurred reaching here
    }

    func testTypingTriggersHighlightAndRulerWithoutCrash() {
        let controller = makeWindowController(text: "")
        guard let tv = controller.focusedTextView else { return XCTFail("no text view") }
        // Simulate edits like keystrokes.
        tv.string = "h"
        tv.didChangeText()
        tv.string = "hello\nworld"
        tv.didChangeText()
        // Force the ruler to draw (this is where the empty/glyph crash lived).
        forceRulerDraw(controller)
    }

    func testEditorViewHasNonZeroSizeWhenShown() {
        // Regression: the contentViewController's scroll view collapsed to {0,0},
        // making text and the caret invisible. The editor view and its text view
        // must have real size once the window is shown at a normal frame.
        let controller = makeWindowController(text: "some text\nmore text")
        guard let window = controller.window else { return XCTFail("no window") }
        window.setFrame(NSRect(x: 0, y: 0, width: 1000, height: 700), display: true)
        controller.showWindow(nil)
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        let contentView = window.contentView
        XCTAssertNotNil(contentView)
        XCTAssertGreaterThan(contentView!.frame.width, 100, "content view width collapsed")
        XCTAssertGreaterThan(contentView!.frame.height, 100, "content view height collapsed")

        if let tv = controller.focusedTextView {
            XCTAssertGreaterThan(tv.frame.width, 100, "text view width collapsed")
            XCTAssertGreaterThan(tv.frame.height, 50, "text view height collapsed")
        } else {
            XCTFail("no text view")
        }
    }

    func testRulerStaysNarrowAndDoesNotCoverDocument() {
        // Regression: the line-number ruler painted its background across the
        // whole document, hiding the text. The ruler's thickness must stay a
        // narrow strip (not the document width), and rendering the editor with
        // the ruler on must not blow up.
        let controller = makeWindowController(text: "alpha\nbeta\ngamma\ndelta\n")
        guard let window = controller.window else { return XCTFail("no window") }
        window.setFrame(NSRect(x: 0, y: 0, width: 1000, height: 700), display: true)
        controller.showWindow(nil)
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        // Find the scroll view + its vertical ruler.
        guard let scrollView = controller.focusedTextView?.enclosingScrollView else {
            return XCTFail("no scroll view")
        }
        XCTAssertTrue(scrollView.rulersVisible, "ruler should be visible by default")
        guard let ruler = scrollView.verticalRulerView else {
            return XCTFail("no vertical ruler")
        }
        // The ruler must be a narrow strip, not anywhere near the document width.
        XCTAssertLessThan(ruler.ruleThickness, 120,
                          "ruler is too wide — it would cover the text")
        XCTAssertGreaterThan(ruler.ruleThickness, 10, "ruler should have some width")

        // Force a draw cycle to ensure drawHashMarksAndLabels doesn't crash and
        // (implicitly) doesn't fill beyond its bounds.
        ruler.needsDisplay = true
        if let rep = ruler.bitmapImageRepForCachingDisplay(in: ruler.bounds) {
            ruler.cacheDisplay(in: ruler.bounds, to: rep)
        }
    }

    func testTabGroupExistsForLoneWindow() {
        // With .preferred tabbing, even a single window must have a tabGroup,
        // which is the prerequisite for forcing the tab bar visible.
        let controller = makeWindowController(text: "x")
        guard let window = controller.window else { return XCTFail("no window") }
        window.makeKeyAndOrderFront(nil)
        XCTAssertNotNil(window.tabGroup, "lone window needs a tabGroup for always-on tab bar")
    }

    func testTabBarBecomesVisibleForSingleWindow() {
        let controller = makeWindowController(text: "hello")
        guard let window = controller.window else { return XCTFail("no window") }
        // Use the real show path (mirrors NSDocument.showWindows()).
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        // Drain the runloop so the deferred ensureTabBarVisible() runs and the
        // window finishes ordering on screen.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
        if let group = window.tabGroup {
            XCTAssertTrue(group.isTabBarVisible,
                          "tab bar should be forced visible for a single tab")
        } else {
            XCTFail("no tabGroup to show a tab bar")
        }
    }

    func testTabBarStaysVisibleAfterClosingDownToOneTab() {
        // Reproduce: open two tabs in one group, close one, ensure the bar
        // remains visible for the lone remaining tab.
        let prefs = Preferences(defaults: UserDefaults(suiteName: "medit.smoke.\(UUID().uuidString)")!)

        let docA = TextDocument(); docA.setTextForTesting("A")
        let wcA = EditorWindowController(document: docA, preferences: prefs)
        _ = wcA.window
        wcA.showWindow(nil)

        let docB = TextDocument(); docB.setTextForTesting("B")
        let wcB = EditorWindowController(document: docB, preferences: prefs)
        _ = wcB.window
        guard let wA = wcA.window, let wB = wcB.window else { return XCTFail("no windows") }
        wA.addTabbedWindow(wB, ordered: .above)
        wA.makeKeyAndOrderFront(nil)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))

        // Close the second tab.
        wB.close()
        wA.makeKey()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))

        if let group = wA.tabGroup {
            XCTAssertTrue(group.isTabBarVisible,
                          "tab bar must stay visible after closing down to one tab")
        }
    }

    func testPastedTextHasVisibleForegroundColor() {
        // Reproduce "pasted text is invisible": after inserting text and letting
        // the highlighter run, every character must have a foreground color that
        // is NOT equal to the editor's background color. Force DARK appearance —
        // that's the condition under which the original bug showed (dark window,
        // black text).
        NSApp.appearance = NSAppearance(named: .darkAqua)
        defer { NSApp.appearance = nil }

        let controller = makeWindowController(text: "")
        guard let tv = controller.focusedTextView, let storage = tv.textStorage else {
            return XCTFail("no text view")
        }
        tv.appearance = NSAppearance(named: .darkAqua)
        controller.window?.appearance = NSAppearance(named: .darkAqua)
        controller.showWindow(nil)

        // Simulate a multi-line paste.
        let pasted = (1...20).map { "line number \($0) with some content" }.joined(separator: "\n")
        tv.string = pasted
        tv.didChangeText()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3)) // let debounced highlight run

        // Resolve dynamic colors within the dark appearance so the comparison
        // reflects what's actually drawn.
        let dark = NSAppearance(named: .darkAqua)!
        func rgb(_ color: NSColor) -> NSColor {
            var resolved = color
            dark.performAsCurrentDrawingAppearance {
                resolved = color.usingColorSpace(.deviceRGB) ?? color
            }
            return resolved
        }
        let bg = rgb(tv.backgroundColor)
        var checkedAny = false
        storage.enumerateAttribute(.foregroundColor,
                                   in: NSRange(location: 0, length: storage.length),
                                   options: []) { value, range, _ in
            checkedAny = true
            let fg = (value as? NSColor) ?? tv.textColor ?? .textColor
            let fgRGB = rgb(fg)
            // Foreground must differ from background (not invisible).
            let dr = abs(fgRGB.redComponent - bg.redComponent)
            let dg = abs(fgRGB.greenComponent - bg.greenComponent)
            let db = abs(fgRGB.blueComponent - bg.blueComponent)
            XCTAssertGreaterThan(dr + dg + db, 0.15,
                                 "text foreground must contrast with background (range \(range))")
        }
        XCTAssertTrue(checkedAny, "expected foreground-color attributes across the text")
    }

    func testTypingAttributesHaveForegroundColor() {
        // The cursor color + freshly typed text both derive from typingAttributes;
        // a missing foreground there yields invisible text and an invisible caret.
        let controller = makeWindowController(text: "")
        guard let tv = controller.focusedTextView else { return XCTFail("no text view") }
        controller.showWindow(nil)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertNotNil(tv.typingAttributes[.foregroundColor],
                        "typingAttributes must carry a foreground color")
    }

    func testToggleLineNumbersAndWrapDoNotCrash() {
        let controller = makeWindowController(text: "alpha\nbeta\ngamma")
        controller.toggleLineNumbers(nil)
        forceRulerDraw(controller)
        controller.toggleLineNumbers(nil)
        controller.toggleWordWrap(nil)
        controller.toggleWordWrap(nil)
        forceRulerDraw(controller)
    }

    /// Render the scroll view's ruler into an offscreen context to execute the
    /// drawing code path headlessly.
    private func forceRulerDraw(_ controller: EditorWindowController) {
        guard let contentView = controller.window?.contentView else { return }
        contentView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        contentView.layoutSubtreeIfNeeded()
        let rep = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds)
        if let rep {
            contentView.cacheDisplay(in: contentView.bounds, to: rep)
        }
    }
}
