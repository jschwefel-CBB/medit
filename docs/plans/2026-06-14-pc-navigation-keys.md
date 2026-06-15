# PC-standard Home / End / Insert Keys Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Home, End, and Insert behave like Windows/Linux — visual-line Home/End with Ctrl=document and Shift=extend, and Insert toggling overwrite mode (block caret) with Shift+Ins=paste / Ctrl+Ins=copy — behind a default-on preference.

**Architecture:** A pure, fully-tested `KeyboardNavigator` computes selection ranges from (text, selection, command, extend). An `EditorTextView: NSTextView` subclass intercepts the keys in `keyDown`, owns per-window overwrite state, and draws the block caret. A `pcStyleNavigationKeys` preference (default on) gates the behavior.

**Tech Stack:** Swift, AppKit, XCTest. Local SwiftPM package `MeditKit`.

**Safety:** All verification is `swift test` and `swift build` (plus optional `xcodebuild` to a scratch path). Do NOT run `pkill medit`, `open` the app, or reinstall — a live instance may be running.

---

## File Structure

- **Create** `Sources/MeditKit/KeyboardNavigator.swift` — pure selection-range logic.
- **Create** `Tests/MeditKitTests/KeyboardNavigatorTests.swift` — exhaustive combo tests.
- **Create** `Sources/MeditKit/EditorTextView.swift` — `NSTextView` subclass: key interception, overwrite typing, block caret.
- **Modify** `Sources/MeditKit/Preferences.swift` — add `pcStyleNavigationKeys` (default true).
- **Modify** `Tests/MeditKitTests/PreferencesTests.swift` — assert the new default + persistence.
- **Modify** `Sources/MeditKit/EditorViewController.swift` — build the editor with `EditorTextView` instead of the stock factory text view; pass the preference; react to changes.
- **Modify** `Sources/MeditKit/PreferencesWindowController.swift` — add the checkbox.
- **Modify** `Tests/MeditKitTests/EditorSmokeTests.swift` — render + overwrite smoke tests.

---

## Task 1: `KeyboardNavigator` — line/document Home & End logic

**Files:**
- Create: `Sources/MeditKit/KeyboardNavigator.swift`
- Test: `Tests/MeditKitTests/KeyboardNavigatorTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/MeditKitTests/KeyboardNavigatorTests.swift`:

```swift
import XCTest
@testable import MeditKit

final class KeyboardNavigatorTests: XCTestCase {

    // A logical-line provider over the test string (mirrors NSString.lineRange).
    private func logicalLineProvider(_ text: String) -> (NSRange) -> NSRange {
        let ns = text as NSString
        return { range in ns.lineRange(for: range) }
    }

    private func nav(_ text: String, _ current: NSRange,
                     _ command: KeyboardNavigator.NavCommand, extend: Bool) -> NSRange {
        KeyboardNavigator.newSelection(in: text, current: current, command: command,
                                       extend: extend, lineRangeProvider: logicalLineProvider(text))
    }

    // MARK: Home (lineStart)

    func testHomeMovesToLineStart() {
        let text = "alpha\nbeta gamma\ndelta"
        // caret in "gamma" (after "beta ") -> line start is index of 'b' in beta
        let betaStart = (text as NSString).range(of: "beta").location
        let caret = NSRange(location: betaStart + 7, length: 0) // somewhere in gamma
        let result = nav(text, caret, .lineStart, extend: false)
        XCTAssertEqual(result, NSRange(location: betaStart, length: 0))
    }

    func testHomeAtLineStartStaysPut() {
        let text = "alpha\nbeta"
        let betaStart = (text as NSString).range(of: "beta").location
        let result = nav(text, NSRange(location: betaStart, length: 0), .lineStart, extend: false)
        XCTAssertEqual(result, NSRange(location: betaStart, length: 0))
    }

    func testHomeOnFirstLine() {
        let text = "hello world"
        let result = nav(text, NSRange(location: 6, length: 0), .lineStart, extend: false)
        XCTAssertEqual(result, NSRange(location: 0, length: 0))
    }

    // MARK: End (lineEnd)

    func testEndMovesToLineEndBeforeNewline() {
        let text = "alpha\nbeta gamma\ndelta"
        let betaStart = (text as NSString).range(of: "beta").location
        let caret = NSRange(location: betaStart + 1, length: 0)
        let result = nav(text, caret, .lineEnd, extend: false)
        // End of "beta gamma" line = position just before the '\n'
        let expected = betaStart + ("beta gamma" as NSString).length
        XCTAssertEqual(result, NSRange(location: expected, length: 0))
    }

    func testEndOnLastLineNoTrailingNewline() {
        let text = "alpha\ndelta"
        let result = nav(text, NSRange(location: 7, length: 0), .lineEnd, extend: false)
        XCTAssertEqual(result, NSRange(location: (text as NSString).length, length: 0))
    }

    // MARK: Shift+Home / Shift+End extend selection

    func testShiftHomeExtendsToLineStart() {
        let text = "hello world"
        // caret at 8, extend to line start (0) -> selection {0, 8} with active end at 0
        let result = nav(text, NSRange(location: 8, length: 0), .lineStart, extend: true)
        XCTAssertEqual(result, NSRange(location: 0, length: 8))
    }

    func testShiftEndExtendsToLineEnd() {
        let text = "hello world"
        let result = nav(text, NSRange(location: 2, length: 0), .lineEnd, extend: true)
        XCTAssertEqual(result, NSRange(location: 2, length: ("hello world" as NSString).length - 2))
    }

    func testShiftHomeFromExistingSelectionKeepsAnchor() {
        let text = "hello world"
        // existing selection {4, 3} (chars 4..7). Shift+Home -> from anchor 4 back to 0 => {0,4}
        let result = nav(text, NSRange(location: 4, length: 3), .lineStart, extend: true)
        XCTAssertEqual(result, NSRange(location: 0, length: 4))
    }

    // MARK: Ctrl+Home / Ctrl+End (document)

    func testDocStart() {
        let text = "alpha\nbeta\ngamma"
        let result = nav(text, NSRange(location: 12, length: 0), .docStart, extend: false)
        XCTAssertEqual(result, NSRange(location: 0, length: 0))
    }

    func testDocEnd() {
        let text = "alpha\nbeta\ngamma"
        let result = nav(text, NSRange(location: 0, length: 0), .docEnd, extend: false)
        XCTAssertEqual(result, NSRange(location: (text as NSString).length, length: 0))
    }

    func testCtrlShiftHomeSelectsToDocStart() {
        let text = "alpha\nbeta"
        let result = nav(text, NSRange(location: 8, length: 0), .docStart, extend: true)
        XCTAssertEqual(result, NSRange(location: 0, length: 8))
    }

    func testCtrlShiftEndSelectsToDocEnd() {
        let text = "alpha\nbeta"
        let len = (text as NSString).length
        let result = nav(text, NSRange(location: 2, length: 0), .docEnd, extend: true)
        XCTAssertEqual(result, NSRange(location: 2, length: len - 2))
    }

    // MARK: Edge cases

    func testEmptyDocument() {
        let text = ""
        XCTAssertEqual(nav(text, NSRange(location: 0, length: 0), .lineStart, extend: false),
                       NSRange(location: 0, length: 0))
        XCTAssertEqual(nav(text, NSRange(location: 0, length: 0), .lineEnd, extend: false),
                       NSRange(location: 0, length: 0))
        XCTAssertEqual(nav(text, NSRange(location: 0, length: 0), .docEnd, extend: false),
                       NSRange(location: 0, length: 0))
    }

    func testEmptyLineBetweenContent() {
        let text = "a\n\nb"   // line 2 is empty (index 2)
        let result = nav(text, NSRange(location: 2, length: 0), .lineEnd, extend: false)
        XCTAssertEqual(result, NSRange(location: 2, length: 0), "empty line: start == end")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter KeyboardNavigatorTests 2>&1 | grep -E "error:|cannot find"`
Expected: compile error — `cannot find 'KeyboardNavigator' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/MeditKit/KeyboardNavigator.swift`:

```swift
import Foundation

/// Computes the resulting selection for PC-style Home/End navigation. Pure value
/// logic over `NSRange`s (UTF-16), so it maps directly onto NSTextView and is
/// fully unit-tested without AppKit. The current visual/logical line is supplied
/// by an injected provider so wrapped-line behavior lives in the view layer.
public enum KeyboardNavigator {

    public enum NavCommand {
        case lineStart   // Home
        case lineEnd     // End
        case docStart    // Ctrl+Home
        case docEnd      // Ctrl+End
    }

    /// Returns the new selection.
    /// - `current`: current selection (caret when length 0).
    /// - `extend`: true when Shift is held — keep the anchor, move the active end
    ///   to the target. The anchor is the end of `current` farther from the
    ///   target's direction; for a caret it's `current.location`.
    /// - `lineRangeProvider`: the range (incl. trailing newline) of the line
    ///   containing a given location.
    public static func newSelection(in text: String,
                                    current: NSRange,
                                    command: NavCommand,
                                    extend: Bool,
                                    lineRangeProvider: (NSRange) -> NSRange) -> NSRange {
        let ns = text as NSString
        let length = ns.length

        // The "caret" we move from: when extending, the active end is the
        // selection's max for forward moves and its min for backward moves; we
        // pick the anchor as the opposite end. For a plain move we use the
        // selection's active edge (location for backward, max for forward).
        let target = targetLocation(command: command, current: current, ns: ns,
                                    length: length, lineRangeProvider: lineRangeProvider)

        if !extend {
            return NSRange(location: target, length: 0)
        }

        // Extend: anchor is the fixed end of the existing selection.
        let anchor = anchorLocation(command: command, current: current)
        let lower = min(anchor, target)
        let upper = max(anchor, target)
        return NSRange(location: lower, length: upper - lower)
    }

    private static func targetLocation(command: NavCommand, current: NSRange,
                                       ns: NSString, length: Int,
                                       lineRangeProvider: (NSRange) -> NSRange) -> Int {
        switch command {
        case .docStart:
            return 0
        case .docEnd:
            return length
        case .lineStart:
            let line = lineRangeProvider(NSRange(location: caretForLineQuery(command, current), length: 0))
            return line.location
        case .lineEnd:
            let line = lineRangeProvider(NSRange(location: caretForLineQuery(command, current), length: 0))
            // Exclude a trailing newline so End lands before it.
            var end = NSMaxRange(line)
            if end > line.location {
                let lastCharRange = NSRange(location: end - 1, length: 1)
                if end <= length, ns.substring(with: lastCharRange) == "\n" {
                    end -= 1
                }
            }
            return end
        }
    }

    /// Which caret position to use when asking for the current line. For Home we
    /// use the selection's min; for End its max — so a multi-line selection
    /// resolves against the expected edge.
    private static func caretForLineQuery(_ command: NavCommand, _ current: NSRange) -> Int {
        switch command {
        case .lineStart: return current.location
        case .lineEnd: return NSMaxRange(current)
        default: return current.location
        }
    }

    /// The fixed anchor when extending: for backward targets (lineStart/docStart)
    /// the anchor is the selection's max; for forward targets it's the min.
    private static func anchorLocation(command: NavCommand, current: NSRange) -> Int {
        switch command {
        case .lineStart, .docStart: return NSMaxRange(current)
        case .lineEnd, .docEnd: return current.location
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter KeyboardNavigatorTests 2>&1 | grep -E "Executed|failed"`
Expected: all tests pass (`Executed 15 tests, with 0 failures`).

- [ ] **Step 5: Commit**

```bash
git add Sources/MeditKit/KeyboardNavigator.swift Tests/MeditKitTests/KeyboardNavigatorTests.swift
git commit -m "Add KeyboardNavigator: PC-style Home/End selection logic"
```

---

## Task 2: `pcStyleNavigationKeys` preference

**Files:**
- Modify: `Sources/MeditKit/Preferences.swift`
- Test: `Tests/MeditKitTests/PreferencesTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `Tests/MeditKitTests/PreferencesTests.swift` inside the class (e.g. after `testDefaultsAreSane`):

```swift
    func testPCNavigationDefaultsOnAndPersists() {
        XCTAssertTrue(prefs.pcStyleNavigationKeys, "PC-style nav keys should default ON")
        prefs.pcStyleNavigationKeys = false
        let reloaded = Preferences(defaults: defaults)
        XCTAssertFalse(reloaded.pcStyleNavigationKeys)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PreferencesTests/testPCNavigationDefaultsOnAndPersists 2>&1 | grep -E "error:|value of type"`
Expected: compile error — `value of type 'Preferences' has no member 'pcStyleNavigationKeys'`.

- [ ] **Step 3: Add the preference**

In `Sources/MeditKit/Preferences.swift`, add a key to the `Key` enum (alongside `wrapLines`):

```swift
        static let pcStyleNavigationKeys = "pcStyleNavigationKeys"
```

Add to the `registerDefaults()` dictionary (alongside `Key.wrapLines: false`):

```swift
            Key.pcStyleNavigationKeys: true,
```

Add the property (alongside `wrapLines`):

```swift
    public var pcStyleNavigationKeys: Bool {
        get { defaults.bool(forKey: Key.pcStyleNavigationKeys) }
        set { defaults.set(newValue, forKey: Key.pcStyleNavigationKeys); didChange() }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PreferencesTests 2>&1 | grep -E "Executed|failed"`
Expected: all Preferences tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MeditKit/Preferences.swift Tests/MeditKitTests/PreferencesTests.swift
git commit -m "Add pcStyleNavigationKeys preference (default on)"
```

---

## Task 3: `EditorTextView` subclass — key interception + overwrite + block caret

**Files:**
- Create: `Sources/MeditKit/EditorTextView.swift`

This task has no standalone unit test (its behavior is exercised by the editor
smoke tests in Task 5, since it needs a live text system). It must compile and be
self-contained.

- [ ] **Step 1: Write the implementation**

Create `Sources/MeditKit/EditorTextView.swift`:

```swift
import AppKit

/// NSTextView subclass adding PC-standard Home/End/Insert handling and an
/// overwrite ("type-over") mode with a block caret. Behavior is gated by
/// `pcStyleNavigationKeys`; when off, keys fall through to AppKit defaults.
public final class EditorTextView: NSTextView {

    /// Gates the PC-style key handling. Set by the editor from Preferences.
    public var pcStyleNavigationKeys: Bool = true

    /// Per-window overwrite ("type-over") mode. Not persisted; resets each launch.
    public private(set) var isOverwriteMode: Bool = false {
        didSet { needsDisplay = true }
    }

    // Function-key unichars for Home/End/Insert.
    private var homeChar: unichar { unichar(NSHomeFunctionKey) }
    private var endChar: unichar { unichar(NSEndFunctionKey) }
    private var insertChar: unichar { unichar(NSInsertFunctionKey) }

    // MARK: Key handling

    public override func keyDown(with event: NSEvent) {
        guard pcStyleNavigationKeys,
              let chars = event.charactersIgnoringModifiers, chars.utf16.count == 1,
              let first = chars.utf16.first else {
            super.keyDown(with: event); return
        }

        let mods = event.modifierFlags
        let shift = mods.contains(.shift)
        let control = mods.contains(.control)

        switch first {
        case homeChar:
            applyNav(control ? .docStart : .lineStart, extend: shift)
        case endChar:
            applyNav(control ? .docEnd : .lineEnd, extend: shift)
        case insertChar:
            if shift { paste(nil) }
            else if control { copy(nil) }
            else { isOverwriteMode.toggle() }
        default:
            super.keyDown(with: event)
        }
    }

    private func applyNav(_ command: KeyboardNavigator.NavCommand, extend: Bool) {
        let result = KeyboardNavigator.newSelection(
            in: string,
            current: selectedRange(),
            command: command,
            extend: extend,
            lineRangeProvider: { [weak self] range in
                self?.lineRange(for: range) ?? range
            })
        setSelectedRange(result)
        scrollRangeToVisible(result)
    }

    /// The range of the line containing `range`: the visual (wrapped) line when
    /// the container tracks the view width, else the logical line.
    private func lineRange(for range: NSRange) -> NSRange {
        let ns = string as NSString
        if let lm = layoutManager, let tc = textContainer,
           tc.widthTracksTextView, ns.length > 0 {
            let loc = min(range.location, ns.length - (range.location == ns.length ? 1 : 0))
            let glyphIndex = lm.glyphIndexForCharacter(at: max(0, min(loc, ns.length - 1)))
            var effective = NSRange()
            _ = lm.lineFragmentRect(forGlyphAt: max(0, min(glyphIndex, lm.numberOfGlyphs - 1)),
                                    effectiveRange: &effective)
            return lm.characterRange(forGlyphRange: effective, actualGlyphRange: nil)
        }
        return ns.lineRange(for: range)
    }

    // MARK: Overwrite typing

    public override func insertText(_ string: Any, replacementRange: NSRange) {
        guard isOverwriteMode else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }
        let sel = selectedRange()
        let ns = self.string as NSString
        // Only overwrite for a collapsed caret not at end-of-line / end-of-text.
        if sel.length == 0, sel.location < ns.length {
            let nextChar = ns.substring(with: NSRange(location: sel.location, length: 1))
            if nextChar != "\n" {
                super.insertText(string, replacementRange: NSRange(location: sel.location, length: 1))
                return
            }
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    // MARK: Block caret

    public override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        guard isOverwriteMode else {
            super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
            return
        }
        guard flag else { super.drawInsertionPoint(in: rect, color: color, turnedOn: flag); return }
        // Widen the caret to roughly one character for a block look.
        let charWidth = (font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
            .maximumAdvancement.width
        let width = charWidth > 1 ? charWidth : rect.height * 0.55
        let blockRect = NSRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
        color.withAlphaComponent(0.45).setFill()
        blockRect.fill()
    }

    /// Resetting overwrite mode (used when the preference is toggled off).
    public func resetOverwriteMode() { isOverwriteMode = false }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build 2>&1 | grep -E "error:|Build complete"`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/MeditKit/EditorTextView.swift
git commit -m "Add EditorTextView: Home/End/Insert handling + overwrite block caret"
```

---

## Task 4: Use `EditorTextView` in the editor; wire the preference

**Files:**
- Modify: `Sources/MeditKit/EditorViewController.swift`

The editor currently builds its text view via `NSTextView.scrollableTextView()`
(`loadView`, around lines 41–51). Replace that with the factory's known-good
recipe using `EditorTextView`, and feed the preference in.

- [ ] **Step 1: Replace the text-view construction in `loadView`**

In `Sources/MeditKit/EditorViewController.swift`, find this block in `loadView()`:

```swift
        let scrollView = NSTextView.scrollableTextView()
        scrollView.frame = frame
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        self.scrollView = scrollView

        guard let textView = scrollView.documentView as? NSTextView else {
            fatalError("scrollableTextView did not provide an NSTextView")
        }
```

Replace it with (manual assembly mirroring the factory, but with our subclass):

```swift
        let scrollView = NSScrollView(frame: frame)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        self.scrollView = scrollView

        // Build EditorTextView with the same TextKit wiring the factory uses.
        let contentSize = scrollView.contentSize
        let container = NSTextContainer(containerSize: NSSize(width: contentSize.width,
                                                              height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(container)
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let textView = EditorTextView(frame: NSRect(origin: .zero, size: contentSize),
                                      textContainer: container)
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.pcStyleNavigationKeys = prefs.pcStyleNavigationKeys
        scrollView.documentView = textView
```

Note: `self.textView` is declared as `NSTextView!`; `EditorTextView` is a
subclass so the assignment `self.textView = textView` further down still works.

- [ ] **Step 2: React to the preference in `preferencesChanged()`**

Find `preferencesChanged()` (it calls `configureFont()`, `applyWrapMode(...)`,
etc.). Add, at the end of that method body:

```swift
        if let editorTextView = textView as? EditorTextView {
            editorTextView.pcStyleNavigationKeys = prefs.pcStyleNavigationKeys
            if !prefs.pcStyleNavigationKeys { editorTextView.resetOverwriteMode() }
        }
```

- [ ] **Step 3: Build + run the full suite (headless — does NOT touch a running app)**

Run: `swift build 2>&1 | grep -E "error:|Build complete" && swift test 2>&1 | grep -E "Executed [0-9]+ tests, with"`
Expected: build complete; existing editor smoke tests still pass (text renders,
ruler/find-bar tests green).

- [ ] **Step 4: Commit**

```bash
git add Sources/MeditKit/EditorViewController.swift
git commit -m "Use EditorTextView in the editor; wire pcStyleNavigationKeys"
```

---

## Task 5: Editor smoke tests — rendering + overwrite behavior

**Files:**
- Modify: `Tests/MeditKitTests/EditorSmokeTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `Tests/MeditKitTests/EditorSmokeTests.swift` inside the class:

```swift
    func testEditorUsesEditorTextViewAndRenders() {
        let controller = makeWindowController(text: "line one\nline two\nline three")
        guard let window = controller.window else { return XCTFail("no window") }
        window.setFrame(NSRect(x: 0, y: 0, width: 900, height: 600), display: true)
        controller.showWindow(nil)
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        XCTAssertTrue(controller.focusedTextView is EditorTextView,
                      "editor should use EditorTextView")
        if let tv = controller.focusedTextView {
            XCTAssertGreaterThan(tv.frame.width, 100, "editor collapsed")
            XCTAssertEqual(tv.string, "line one\nline two\nline three")
        }
    }

    func testOverwriteModeReplacesNextCharacter() {
        let controller = makeWindowController(text: "abcdef")
        guard let tv = controller.focusedTextView as? EditorTextView else {
            return XCTFail("not EditorTextView")
        }
        controller.showWindow(nil)
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        tv.toggleOverwriteForTesting()                 // enter overwrite
        tv.insertText("X", replacementRange: tv.selectedRange())
        XCTAssertEqual(tv.string, "Xbcdef", "overwrite should replace 'a', not insert")
    }

    func testInsertModeStillInserts() {
        let controller = makeWindowController(text: "abcdef")
        guard let tv = controller.focusedTextView as? EditorTextView else {
            return XCTFail("not EditorTextView")
        }
        controller.showWindow(nil)
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        // overwrite OFF by default
        tv.insertText("X", replacementRange: tv.selectedRange())
        XCTAssertEqual(tv.string, "Xabcdef", "insert mode should insert")
    }

    func testOverwriteAtEndOfLineAppends() {
        let controller = makeWindowController(text: "ab\ncd")
        guard let tv = controller.focusedTextView as? EditorTextView else {
            return XCTFail("not EditorTextView")
        }
        controller.showWindow(nil)
        tv.setSelectedRange(NSRange(location: 2, length: 0)) // right before the '\n'
        tv.toggleOverwriteForTesting()
        tv.insertText("X", replacementRange: tv.selectedRange())
        XCTAssertEqual(tv.string, "abX\ncd", "at end of line, overwrite appends (no newline eaten)")
    }
```

- [ ] **Step 2: Add the test hook to `EditorTextView`**

In `Sources/MeditKit/EditorTextView.swift`, add (near `resetOverwriteMode`):

```swift
    /// Test hook: flip overwrite mode.
    func toggleOverwriteForTesting() { isOverwriteMode.toggle() }
```

- [ ] **Step 3: Run tests to verify they pass**

Run: `swift test --filter EditorSmokeTests 2>&1 | grep -E "Executed|failed|XCTAssert"`
Expected: all editor smoke tests pass (including the four new ones).

- [ ] **Step 4: Commit**

```bash
git add Tests/MeditKitTests/EditorSmokeTests.swift Sources/MeditKit/EditorTextView.swift
git commit -m "Test EditorTextView rendering and overwrite-mode typing"
```

---

## Task 6: Preferences window checkbox

**Files:**
- Modify: `Sources/MeditKit/PreferencesWindowController.swift`

The window already has checkboxes (`lineNumbersCheck`, `wrapCheck`,
`spacesCheck`) built and constrained in `buildUI()`, synced in `syncFromPrefs()`,
and written in `checkChanged(_:)`. Add a fourth checkbox the same way.

- [ ] **Step 1: Add the property**

Near the other checkbox properties (e.g. `private var spacesCheck: NSButton!`):

```swift
    private var pcKeysCheck: NSButton!
```

- [ ] **Step 2: Build the checkbox in `buildUI()`**

Where the checkboxes are created (alongside `spacesCheck = NSButton(checkbox...)`):

```swift
        pcKeysCheck = NSButton(checkboxWithTitle: "PC-style Home/End/Insert keys",
                               target: self, action: #selector(checkChanged))
        pcKeysCheck.translatesAutoresizingMaskIntoConstraints = false
```

Add it to the array that gets `addSubview`'d and to the layout. Find the
constraints block anchoring `spacesCheck` and add, right after it:

```swift
            pcKeysCheck.topAnchor.constraint(equalTo: spacesCheck.bottomAnchor, constant: 10),
            pcKeysCheck.leadingAnchor.constraint(equalTo: lineNumbersCheck.leadingAnchor),
```

Also add `pcKeysCheck` to the `content.addSubview(...)` list that includes the
other checks, and re-anchor the `tabTitle` row to sit below `pcKeysCheck` instead
of `spacesCheck`: change the `tabTitle.topAnchor` constraint's `equalTo:
spacesCheck.bottomAnchor` to `equalTo: pcKeysCheck.bottomAnchor`.

- [ ] **Step 3: Sync + write the value**

In `syncFromPrefs()` (alongside `spacesCheck.state = ...`):

```swift
        pcKeysCheck.state = prefs.pcStyleNavigationKeys ? .on : .off
```

In `checkChanged(_:)` (alongside the other assignments):

```swift
        prefs.pcStyleNavigationKeys = pcKeysCheck.state == .on
```

- [ ] **Step 4: Build to verify it compiles**

Run: `swift build 2>&1 | grep -E "error:|Build complete"`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Sources/MeditKit/PreferencesWindowController.swift
git commit -m "Add PC-style navigation keys checkbox to Preferences"
```

---

## Task 7: Menu hint + version bump to 1.1.0

**Files:**
- Modify: `App/Info.plist`
- Modify: `App/medit.xcodeproj/project.pbxproj`

- [ ] **Step 1: Bump the version strings**

In `App/Info.plist`, change:

```xml
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
```

to `1.1.0`.

In `App/medit.xcodeproj/project.pbxproj`, change BOTH occurrences of:

```
				MARKETING_VERSION = 1.0.0;
```

to `1.1.0`.

- [ ] **Step 2: Verify the suite is green and the app builds (scratch path)**

Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests, with"`
Expected: all tests pass.

Optionally verify the app target builds (writes to the configured DerivedData,
does NOT launch or install):
Run: `cd App && xcodebuild -project medit.xcodeproj -scheme medit -configuration Debug -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add App/Info.plist App/medit.xcodeproj/project.pbxproj
git commit -m "Bump version to 1.1.0"
```

- [ ] **Step 4: Update the README features list**

In `README.md`, under **Features**, add a bullet:

```markdown
- **PC-style navigation keys** — Home/End move to the start/end of the line
  (Ctrl for the document, Shift to select); Insert toggles overwrite mode with a
  block caret (Shift+Insert pastes, Ctrl+Insert copies). Toggle in Settings;
  on by default.
```

And add to the keyboard-shortcuts table:

```markdown
| Home / End | Line start / end |
| Ctrl+Home / Ctrl+End | Document start / end |
| Insert | Toggle overwrite mode |
```

Commit:

```bash
git add README.md
git commit -m "Document PC-style navigation keys in README"
```

---

## Task 8: Tag the release (manual gate — confirm with the user first)

> Do this only after the user has quit their running medit and is ready. Do NOT
> reinstall over a running instance without the user's go-ahead.

- [ ] **Step 1: Confirm working tree is clean and tests pass**

Run: `git status --short && swift test 2>&1 | grep -E "Executed [0-9]+ tests, with"`
Expected: clean tree, all tests pass.

- [ ] **Step 2: Create the annotated tag**

```bash
git tag -a v1.1.0 -m "medit 1.1.0 — PC-standard Home/End/Insert keys (visual-line Home/End with Ctrl=document and Shift=select; Insert toggles overwrite mode with block caret, Shift+Ins paste, Ctrl+Ins copy). Behind a default-on 'PC-style navigation keys' preference."
git describe --tags
```

Expected: `v1.1.0`.

---

## Self-Review

**Spec coverage:**
- Home/End visual-line + Ctrl=doc + Shift=extend → Task 1 (logic) + Task 3 (key routing + visual-line provider). ✓
- Insert toggle overwrite, Shift+Ins paste, Ctrl+Ins copy → Task 3. ✓
- Block caret, per-window, resets on launch → Task 3 (`isOverwriteMode` default false, `drawInsertionPoint`). ✓
- Preference default ON, off → native → Task 2 + Task 4 (gate in `keyDown`) + Task 6 (UI). ✓
- Pure tested core → Task 1; editor render/overwrite tests → Task 5. ✓
- Release 1.1.0 + tag → Task 7 + Task 8. ✓

**Placeholder scan:** No TBD/TODO; all steps contain concrete code and commands. ✓

**Type consistency:** `KeyboardNavigator.NavCommand` (`.lineStart/.lineEnd/.docStart/.docEnd`) and `newSelection(in:current:command:extend:lineRangeProvider:)` are used identically in Tasks 1, 3. `pcStyleNavigationKeys`, `isOverwriteMode`, `resetOverwriteMode()`, `toggleOverwriteForTesting()` are defined in Tasks 2/3/5 and referenced consistently. ✓

**Note on risk:** Task 4 hand-assembles the text view (the earlier invisible-text
bug). Mitigated by Task 5's `testEditorUsesEditorTextViewAndRenders` (asserts
non-zero frame + string) and the existing ruler/find-bar render tests — all
headless.
