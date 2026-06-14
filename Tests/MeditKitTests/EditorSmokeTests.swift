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
