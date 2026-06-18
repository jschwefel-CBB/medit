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

    func testGutterHiddenWhenDocumentEmptyShownWhenNot() {
        // Line numbers ON, but an empty document should not show the gutter
        // (otherwise a wide, contentless gutter appears, especially with the
        // sidebar open). Typing content brings it back.
        let controller = makeWindowController(text: "")
        guard let editor = controller.editorForTesting,
              let tv = controller.focusedTextView else { return XCTFail("no editor") }
        XCTAssertTrue(editor.showLineNumbersForTesting, "precondition: line numbers default on")

        XCTAssertFalse(editor.rulersVisibleForTesting, "gutter should hide for empty text")

        tv.string = "hello\nworld"
        tv.didChangeText()
        XCTAssertTrue(editor.rulersVisibleForTesting, "gutter should show once there's text")

        tv.string = ""
        tv.didChangeText()
        XCTAssertFalse(editor.rulersVisibleForTesting, "gutter should hide again when emptied")
    }

    func testStatusBarWrapSegmentReflectsAndToggles() {
        let bar = StatusBarView(frame: NSRect(x: 0, y: 0, width: 600, height: 22))
        var toggled = false
        bar.onWrapToggle = { toggled = true }

        bar.update(line: 1, column: 1, language: "Plain Text", encoding: "UTF-8",
                   lineEnding: .lf, overwrite: false, wrap: true)
        XCTAssertEqual(bar.wrapTitleForTesting, "Wrap: On")

        bar.update(line: 1, column: 1, language: "Plain Text", encoding: "UTF-8",
                   lineEnding: .lf, overwrite: false, wrap: false)
        XCTAssertEqual(bar.wrapTitleForTesting, "Wrap: Off")

        bar.simulateWrapClickForTesting()
        XCTAssertTrue(toggled, "clicking the wrap segment should fire onWrapToggle")
    }

    func testStatusBarWrapTogglesWrapPreferenceLive() {
        // End-to-end: clicking the segment via the editor's wiring flips the pref.
        let controller = makeWindowController(text: "abc")
        guard let editor = controller.editorForTesting else { return XCTFail("no editor") }
        let before = editor.wrapLinesForTesting
        editor.simulateStatusBarWrapClickForTesting()
        XCTAssertNotEqual(before, editor.wrapLinesForTesting, "wrap pref should flip")
    }

    func testRainbowBracketsApplyTemporaryColorAndClearOnDisable() {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "medit.smoke.\(UUID().uuidString)")!)
        prefs.rainbowBrackets = true
        let doc = TextDocument(); doc.setTextForTesting("f(x){y}")
        let wc = EditorWindowController(document: doc, preferences: prefs)
        _ = wc.window
        wc.loadViewIfNeededForTesting()
        guard let editor = wc.editorForTesting, let tv = wc.focusedTextView,
              let lm = tv.layoutManager else { return XCTFail("no editor") }

        editor.refreshBracketColorizerForTesting()
        // The '(' at offset 1 should carry a temporary foreground (depth) color.
        let attr = lm.temporaryAttribute(.foregroundColor, atCharacterIndex: 1, effectiveRange: nil)
        XCTAssertNotNil(attr, "bracket should have a depth color overlay")

        // Disabling clears the overlay.
        prefs.rainbowBrackets = false
        editor.applyPreferencesForTesting()
        let cleared = lm.temporaryAttribute(.foregroundColor, atCharacterIndex: 1, effectiveRange: nil)
        XCTAssertNil(cleared, "overlay should be cleared when rainbow brackets is off")
    }

    func testDraggedFileOpensInsteadOfPastingPath() {
        let controller = makeWindowController(text: "hello")
        guard let tv = controller.focusedTextView as? EditorTextView else { return XCTFail("no text view") }
        var opened: [URL] = []
        tv.onOpenFiles = { opened = $0 }
        let dropped = [URL(fileURLWithPath: "/tmp/example.txt")]
        tv.performFileDropForTesting(dropped)
        // The file-open hook fired; the path was NOT inserted into the text.
        XCTAssertEqual(opened, dropped)
        XCTAssertEqual(tv.string, "hello", "dragged file path must not be pasted into the editor")
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

    func testWrappedTextContainerReflowsWhenWidened() {
        // Regression: in wrap mode, widening the window didn't re-flow text live
        // because the container width was pinned to a stale snapshot. The wrapping
        // container width must follow the scroll view's content width on resize.
        let controller = makeWindowController(text: String(repeating: "word ", count: 200))
        guard let window = controller.window, let editor = controller.editorForTesting else {
            return XCTFail("no editor")
        }
        window.setFrame(NSRect(x: 0, y: 0, width: 700, height: 600), display: true)
        controller.showWindow(nil)
        window.layoutIfNeeded()
        editor.applyWrapMode(true)
        editor.syncWrapWidthForTesting()
        window.layoutIfNeeded()
        let narrowWidth = editor.wrapContainerWidthForTesting
        XCTAssertGreaterThan(narrowWidth, 0, "wrap container should have a real width")

        // Widen the window substantially.
        window.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 600), display: true)
        window.layoutIfNeeded()
        editor.syncWrapWidthForTesting()
        let wideWidth = editor.wrapContainerWidthForTesting

        XCTAssertGreaterThan(wideWidth, narrowWidth + 200,
                             "wrap container width must grow with the window (live reflow)")
    }

    func testShowInvisiblesTogglesWithoutBreakingRender() {
        let controller = makeWindowController(text: "a b\tc\nd e")
        guard let window = controller.window, let editor = controller.editorForTesting else { return XCTFail("no editor") }
        window.setFrame(NSRect(x: 0, y: 0, width: 900, height: 600), display: true)
        controller.showWindow(nil)
        window.layoutIfNeeded()
        editor.applyShowInvisibles(true)
        window.layoutIfNeeded()
        // Force a draw cycle; must not crash and text view must still have size.
        if let tv = controller.focusedTextView {
            let rep = tv.bitmapImageRepForCachingDisplay(in: tv.bounds)
            if let rep { tv.cacheDisplay(in: tv.bounds, to: rep) }
            XCTAssertGreaterThan(tv.frame.width, 100, "editor collapsed with invisibles on")
            XCTAssertEqual(tv.string, "a b\tc\nd e", "text unchanged by invisibles rendering")
        }
        editor.applyShowInvisibles(false)
        window.layoutIfNeeded()
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

    func testFindBarShowsAndEditorStillRenders() {
        // Showing the find bar must not collapse/hide the editor.
        let controller = makeWindowController(text: "find me here\nand find me again\n")
        guard let window = controller.window else { return XCTFail("no window") }
        window.setFrame(NSRect(x: 0, y: 0, width: 1000, height: 700), display: true)
        controller.showWindow(nil)
        window.layoutIfNeeded()
        controller.editorForTesting?.showFindBar(nil)
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        if let tv = controller.focusedTextView {
            XCTAssertGreaterThan(tv.frame.width, 100, "editor shrank to nothing when find bar shown")
            XCTAssertGreaterThan(tv.frame.height, 50)
        } else { XCTFail("no text view") }
    }

    func testFindBarReservesNoSpaceWhenHidden() {
        // Regression: a hidden find bar left a dead gap above the first line.
        // When hidden, the bar must collapse to zero height.
        let controller = makeWindowController(text: "line one\nline two")
        guard let window = controller.window, let editor = controller.editorForTesting else {
            return XCTFail("no editor")
        }
        window.setFrame(NSRect(x: 0, y: 0, width: 900, height: 600), display: true)
        controller.showWindow(nil)
        window.layoutIfNeeded()

        let barHeightHidden = editor.findBarHeightForTesting
        XCTAssertEqual(barHeightHidden, 0, accuracy: 0.5,
                       "hidden find bar must reserve zero height")

        editor.showFindBar(nil)
        window.layoutIfNeeded()
        XCTAssertGreaterThan(editor.findBarHeightForTesting, 20,
                             "shown find bar should have real height")

        // Close it again -> back to zero.
        editor.closeFindBarForTesting()
        window.layoutIfNeeded()
        XCTAssertEqual(editor.findBarHeightForTesting, 0, accuracy: 0.5,
                       "closed find bar must collapse back to zero")
    }

    func testRegexFindSelectsMatch() {
        let controller = makeWindowController(text: "alpha 123 beta 456 gamma")
        guard let editor = controller.editorForTesting, let tv = controller.focusedTextView else {
            return XCTFail("no editor")
        }
        controller.showWindow(nil)
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        // Regex for digit runs.
        editor.runFindForTesting(SearchQuery(term: "[0-9]+", isRegex: true, caseSensitive: false), forward: true)
        let sel = tv.selectedRange()
        XCTAssertEqual((tv.string as NSString).substring(with: sel), "123",
                       "regex find should select the first digit run")
    }

    func testRegexReplaceAllWithCapture() {
        let controller = makeWindowController(text: "key=1; key=2; key=3")
        guard let editor = controller.editorForTesting, let tv = controller.focusedTextView else {
            return XCTFail("no editor")
        }
        controller.showWindow(nil)
        editor.runReplaceAllForTesting(
            SearchQuery(term: "key=([0-9])", isRegex: true, caseSensitive: false),
            with: "val:$1")
        XCTAssertEqual(tv.string, "val:1; val:2; val:3",
                       "regex replace-all should expand $1 capture groups")
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

    func testEditorStillRendersWithSplitViewHostingSidebar() {
        let controller = makeWindowController(text: "line one\nline two\nline three")
        guard let window = controller.window else { return XCTFail("no window") }
        window.setFrame(NSRect(x: 0, y: 0, width: 1000, height: 700), display: true)
        controller.showWindow(nil)
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        // The window's contentViewController is now a split view; the editor must
        // still be present and rendering.
        XCTAssertTrue(window.contentViewController is NSSplitViewController)
        if let tv = controller.focusedTextView {
            XCTAssertGreaterThan(tv.frame.width, 100, "editor collapsed under the split view")
            XCTAssertEqual(tv.string, "line one\nline two\nline three")
        } else { XCTFail("no text view") }
    }

    func testSidebarActivateBuildsTreeAndDeactivateClears() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("medit-sb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try Data("x".utf8).write(to: tmp.appendingPathComponent("a.txt"))

        let sb = SidebarViewController(preferences: Preferences(defaults: UserDefaults(suiteName: "medit.sb.\(UUID().uuidString)")!))
        sb.loadViewIfNeeded()
        // Seed a root directly and activate.
        sb.setRootForTesting(tmp)
        sb.activate()
        XCTAssertGreaterThan(sb.outlineView.numberOfRows, 0, "tree should have rows after activate")
        sb.deactivate()
        XCTAssertEqual(sb.outlineView.numberOfRows, 0, "deactivate should clear the tree (zero overhead)")
    }

    func testSidebarDeactivateStopsWatchers() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("medit-sbw-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let sb = SidebarViewController(preferences: Preferences(defaults: UserDefaults(suiteName: "medit.sbw.\(UUID().uuidString)")!))
        sb.loadViewIfNeeded()
        sb.setRootForTesting(tmp)
        sb.activate()
        XCTAssertGreaterThan(sb.watcherCountForTesting, 0, "active sidebar should watch its roots")
        sb.deactivate()
        XCTAssertEqual(sb.watcherCountForTesting, 0, "deactivate must stop all watchers (zero overhead)")
    }

    func testEditorUsesEditorTextViewAndRenders() {
        let controller = makeWindowController(text: "line one\nline two\nline three")
        guard let window = controller.window else { return XCTFail("no window") }
        window.setFrame(NSRect(x: 0, y: 0, width: 900, height: 600), display: true)
        controller.showWindow(nil)
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertTrue(controller.focusedTextView is EditorTextView, "editor should use EditorTextView")
        if let tv = controller.focusedTextView {
            XCTAssertGreaterThan(tv.frame.width, 100, "editor collapsed")
            XCTAssertEqual(tv.string, "line one\nline two\nline three")
        }
    }

    func testOverwriteModeReplacesNextCharacter() {
        let controller = makeWindowController(text: "abcdef")
        guard let tv = controller.focusedTextView as? EditorTextView else { return XCTFail("not EditorTextView") }
        controller.showWindow(nil)
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        tv.toggleOverwriteForTesting()
        tv.insertText("X", replacementRange: tv.selectedRange())
        XCTAssertEqual(tv.string, "Xbcdef", "overwrite should replace 'a', not insert")
    }

    /// Synthesize a real Insert keyDown (hardware keyCode 114 = Insert/Help on
    /// Mac) and verify it toggles overwrite mode through the actual keyDown path.
    /// Regression: detecting by NSInsertFunctionKey missed this — a PC Insert key
    /// reports keyCode 114 / NSHelpFunctionKey, so the key did nothing (beeped).
    func testInsertKeyTogglesOverwriteViaKeyDown() {
        let controller = makeWindowController(text: "hello")
        guard let tv = controller.focusedTextView as? EditorTextView else { return XCTFail("not EditorTextView") }
        controller.showWindow(nil)
        XCTAssertFalse(tv.isOverwriteMode)

        let insertEvent = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: tv.window?.windowNumber ?? 0, context: nil,
            characters: "\u{F746}",                 // NSHelpFunctionKey
            charactersIgnoringModifiers: "\u{F746}",
            isARepeat: false, keyCode: 114)!
        tv.keyDown(with: insertEvent)
        XCTAssertTrue(tv.isOverwriteMode, "Insert (keyCode 114) should toggle overwrite ON")

        tv.keyDown(with: insertEvent)
        XCTAssertFalse(tv.isOverwriteMode, "Insert again should toggle overwrite OFF")
    }

    /// With the PC-keys preference off, the Insert key must NOT be intercepted.
    func testInsertKeyIgnoredWhenPreferenceOff() {
        let controller = makeWindowController(text: "hello")
        guard let tv = controller.focusedTextView as? EditorTextView else { return XCTFail("not EditorTextView") }
        controller.showWindow(nil)
        tv.pcStyleNavigationKeys = false
        let insertEvent = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: tv.window?.windowNumber ?? 0, context: nil,
            characters: "\u{F746}", charactersIgnoringModifiers: "\u{F746}",
            isARepeat: false, keyCode: 114)!
        tv.keyDown(with: insertEvent)
        XCTAssertFalse(tv.isOverwriteMode, "preference off: Insert must not toggle overwrite")
    }

    func testInsertModeStillInserts() {
        let controller = makeWindowController(text: "abcdef")
        guard let tv = controller.focusedTextView as? EditorTextView else { return XCTFail("not EditorTextView") }
        controller.showWindow(nil)
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        tv.insertText("X", replacementRange: tv.selectedRange())
        XCTAssertEqual(tv.string, "Xabcdef", "insert mode should insert")
    }

    func testOverwriteAtEndOfLineAppends() {
        let controller = makeWindowController(text: "ab\ncd")
        guard let tv = controller.focusedTextView as? EditorTextView else { return XCTFail("not EditorTextView") }
        controller.showWindow(nil)
        tv.setSelectedRange(NSRange(location: 2, length: 0))
        tv.toggleOverwriteForTesting()
        tv.insertText("X", replacementRange: tv.selectedRange())
        XCTAssertEqual(tv.string, "abX\ncd", "at end of line, overwrite appends (no newline eaten)")
    }

    func testTurningOffPreferencePropagatesAndResetsOverwrite() {
        // Task 4 wiring: when the PC-style-navigation preference is turned off,
        // the editor must push the new value into its text view AND reset
        // overwrite mode. Build the controller directly so we hold the exact
        // prefs instance the editor observes.
        let prefs = Preferences(defaults: UserDefaults(suiteName: "medit.smoke.\(UUID().uuidString)")!)
        prefs.pcStyleNavigationKeys = true
        let document = TextDocument()
        document.setTextForTesting("abcdef")
        let controller = EditorWindowController(document: document, preferences: prefs)
        _ = controller.window
        controller.loadViewIfNeededForTesting()
        controller.showWindow(nil)

        guard let tv = controller.focusedTextView as? EditorTextView else {
            return XCTFail("not EditorTextView")
        }

        // Enter overwrite mode.
        tv.toggleOverwriteForTesting()
        XCTAssertTrue(tv.isOverwriteMode, "overwrite mode should be on after toggle")

        // Turn the preference OFF — this posts the change notification the
        // editor observes.
        prefs.pcStyleNavigationKeys = false
        // Pump the run loop so the notification is delivered.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        XCTAssertFalse(tv.pcStyleNavigationKeys,
                       "preference change should propagate into the text view")
        XCTAssertFalse(tv.isOverwriteMode,
                       "turning off the preference should reset overwrite mode")
    }

    func testAutoCloseInsertsClosingBracket() {
        let controller = makeWindowController(text: "")
        guard let tv = controller.focusedTextView as? EditorTextView else { return XCTFail("no tv") }
        controller.showWindow(nil)
        tv.autoCloseBracketsEnabled = true
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        tv.insertText("(", replacementRange: tv.selectedRange())
        XCTAssertEqual(tv.string, "()", "typing ( should insert the closing )")
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 1, length: 0), "caret between the pair")
    }

    func testAutoCloseSkipsOverExistingCloser() {
        let controller = makeWindowController(text: "()")
        guard let tv = controller.focusedTextView as? EditorTextView else { return XCTFail("no tv") }
        controller.showWindow(nil)
        tv.autoCloseBracketsEnabled = true
        tv.setSelectedRange(NSRange(location: 1, length: 0))  // between ( and )
        tv.insertText(")", replacementRange: tv.selectedRange())
        XCTAssertEqual(tv.string, "()", "typing ) over an existing ) should not duplicate it")
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 2, length: 0), "caret moved past )")
    }

    func testAutoCloseWrapsSelection() {
        let controller = makeWindowController(text: "abc")
        guard let tv = controller.focusedTextView as? EditorTextView else { return XCTFail("no tv") }
        controller.showWindow(nil)
        tv.autoCloseBracketsEnabled = true
        tv.setSelectedRange(NSRange(location: 0, length: 3))  // select "abc"
        tv.insertText("(", replacementRange: tv.selectedRange())
        XCTAssertEqual(tv.string, "(abc)", "typing ( with a selection should wrap it")
    }

    func testAutoIndentCopiesLeadingWhitespace() {
        let controller = makeWindowController(text: "    foo")
        guard let tv = controller.focusedTextView as? EditorTextView else { return XCTFail("no tv") }
        controller.showWindow(nil)
        tv.autoIndentEnabled = true
        tv.indentUseSpaces = true
        tv.indentTabWidth = 4
        tv.setSelectedRange(NSRange(location: 7, length: 0))  // end of "    foo"
        tv.insertNewline(nil)
        XCTAssertEqual(tv.string, "    foo\n    ", "new line should copy the 4-space indent")
    }

    func testManualLanguageOverrideWinsOverDetection() {
        let controller = makeWindowController(text: "print('hi')")
        guard let editor = controller.editorForTesting else { return XCTFail("no editor") }
        controller.showWindow(nil)
        // Force a manual override and confirm the document reports it.
        editor.setLanguageOverrideForTesting("rust")
        XCTAssertEqual(controller.documentForTesting?.highlightLanguage, "rust")
        // Auto-detect clears it (untitled doc with no extension/shebang -> nil).
        editor.setLanguageOverrideForTesting(nil)
        XCTAssertNil(controller.documentForTesting?.highlightLanguage)
    }

    func testReloadBannerShowsAndHidesWithoutBreakingRender() {
        let controller = makeWindowController(text: "content")
        guard let window = controller.window, let editor = controller.editorForTesting else { return XCTFail("no editor") }
        window.setFrame(NSRect(x: 0, y: 0, width: 900, height: 600), display: true)
        controller.showWindow(nil)
        window.layoutIfNeeded()
        editor.showReloadBanner(message: "This file has changed on disk.")
        window.layoutIfNeeded()
        if let tv = controller.focusedTextView {
            XCTAssertGreaterThan(tv.frame.width, 100, "editor collapsed when banner shown")
            XCTAssertEqual(tv.string, "content")
        }
        editor.hideReloadBanner()
        window.layoutIfNeeded()
    }

    func testAutoIndentAddsLevelAfterBrace() {
        let controller = makeWindowController(text: "if x {")
        guard let tv = controller.focusedTextView as? EditorTextView else { return XCTFail("no tv") }
        controller.showWindow(nil)
        tv.autoIndentEnabled = true
        tv.indentUseSpaces = true
        tv.indentTabWidth = 4
        tv.setSelectedRange(NSRange(location: 6, length: 0))  // end of "if x {"
        tv.insertNewline(nil)
        XCTAssertEqual(tv.string, "if x {\n    ", "new line after { should add one indent level")
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

    // MARK: Markdown preview

    func testMarkdownPreviewTogglesAndRenders() {
        let wc = makeWindowController(text: "# Title\n\n- a\n- b")
        wc.documentForTesting?.languageOverride = "markdown"
        let editor = wc.editorForTesting!
        XCTAssertFalse(editor.isPreviewVisibleForTesting)
        editor.togglePreviewForTesting()
        XCTAssertTrue(editor.isPreviewVisibleForTesting)
        let rendered = editor.previewAttributedStringForTesting
        XCTAssertTrue(rendered?.string.contains("Title") == true,
                      "preview should render the heading text")
        XCTAssertTrue(rendered?.string.contains("a") == true)
        editor.togglePreviewForTesting()
        XCTAssertFalse(editor.isPreviewVisibleForTesting)
    }

    func testMarkdownPreviewMenuGatedToMarkdown() {
        let wc = makeWindowController(text: "plain text")
        let item = NSMenuItem(title: "Show Markdown Preview",
            action: #selector(EditorWindowController.toggleMarkdownPreview(_:)), keyEquivalent: "")
        XCTAssertFalse(wc.validateMenuItem(item),
                       "preview toggle should be disabled for non-Markdown documents")

        let mdWC = makeWindowController(text: "# md")
        mdWC.documentForTesting?.languageOverride = "markdown"
        let mdItem = NSMenuItem(title: "Show Markdown Preview",
            action: #selector(EditorWindowController.toggleMarkdownPreview(_:)), keyEquivalent: "")
        XCTAssertTrue(mdWC.validateMenuItem(mdItem),
                      "preview toggle should be enabled for Markdown documents")
    }

    func testAutoShowPreviewOpensPreviewForMarkdown() {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "medit.smoke.\(UUID().uuidString)")!)
        prefs.autoShowPreviewForMarkdown = true
        let document = TextDocument()
        document.setTextForTesting("# auto")
        document.languageOverride = "markdown"
        let wc = EditorWindowController(document: document, preferences: prefs)
        _ = wc.window
        wc.loadViewIfNeededForTesting()
        XCTAssertTrue(wc.editorForTesting?.isPreviewVisibleForTesting == true,
                      "preview should auto-open for a Markdown doc when the pref is on")
    }
}
