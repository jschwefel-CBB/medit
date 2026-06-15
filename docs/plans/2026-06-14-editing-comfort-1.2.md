# Editing-comfort Polish (1.2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Go to Line, a status bar, auto-indent + bracket assistance, trailing-whitespace hygiene, and a Show Invisibles toggle to medit — each as its own commit, behind preferences/toggles where appropriate.

**Architecture:** Correctness-heavy logic goes in small pure value types (`TextLocator`, `TextPosition`, `Indenter`, `BracketMatcher`, `TextHygiene`) tested exhaustively like the existing `TextSearch`/`KeyboardNavigator`. The AppKit layer (`EditorTextView`, `EditorViewController`, new views) calls them and is covered by headless smoke tests. New preferences follow the existing `Preferences` pattern; View toggles follow `toggleLineNumbers`.

**Tech Stack:** Swift, AppKit, XCTest, local SwiftPM package `MeditKit`.

**SAFETY (every task):** A live instance of the medit app may be running. NEVER run `pkill`, `open`, or launch/reinstall the app. Verify ONLY with `cd /Users/jschwefel/repositories/medit && swift build` and `swift test`. Use plain `git commit` (NO `-c` identity override; the repo's configured identity is correct). Work from `/Users/jschwefel/repositories/medit` on a feature branch.

---

## File Structure

New pure-logic units (one responsibility each, fully tested):
- `Sources/MeditKit/TextLocator.swift` — line number → character offset (Go to Line).
- `Sources/MeditKit/TextPosition.swift` — character offset → (line, column) (status bar).
- `Sources/MeditKit/Indenter.swift` — indent string for a new line (auto-indent).
- `Sources/MeditKit/BracketMatcher.swift` — matching-bracket offset (highlight).
- `Sources/MeditKit/TextHygiene.swift` — strip trailing ws + ensure final newline.

New views / controllers:
- `Sources/MeditKit/GoToLineSheet.swift` — the modal sheet.
- `Sources/MeditKit/StatusBarView.swift` — the bottom status bar (dumb display).
- `Sources/MeditKit/InvisiblesLayoutManager.swift` — draws whitespace markers.

Modified:
- `EditorTextView.swift` — auto-indent, auto-close/skip, bracket highlight, ⌃G, overwrite-change callback.
- `EditorViewController.swift` — host status bar, Go to Line action, selection hook, install layout manager, push prefs.
- `EditorWindowController.swift` — View toggles (Show Status Bar, Show Invisibles).
- `MainMenu.swift` — Go to Line item; View → Show Status Bar / Show Invisibles.
- `Preferences.swift` (+ 5 prefs), `PreferencesWindowController.swift` (checkboxes), `TextDocument.swift` (strip on save).
- Test files alongside each.

---

## Task 0: Create the feature branch

- [ ] **Step 1: Branch off main**

```bash
cd /Users/jschwefel/repositories/medit
git checkout main
git pull --ff-only 2>/dev/null || true
git checkout -b feature/editing-comfort-1.2
git branch --show-current   # expect: feature/editing-comfort-1.2
```

No commit — this just creates the branch.

---

## Task 1: Go to Line

**Files:**
- Create: `Sources/MeditKit/TextLocator.swift`, `Tests/MeditKitTests/TextLocatorTests.swift`
- Create: `Sources/MeditKit/GoToLineSheet.swift`
- Modify: `Sources/MeditKit/EditorViewController.swift`, `Sources/MeditKit/MainMenu.swift`

- [ ] **Step 1: Write the failing test for TextLocator**

Create `Tests/MeditKitTests/TextLocatorTests.swift`:

```swift
import XCTest
@testable import MeditKit

final class TextLocatorTests: XCTestCase {

    private func idx(_ line: Int, _ text: String) -> Int? {
        TextLocator.characterIndex(forLine: line, in: text)
    }

    func testFirstLine() {
        XCTAssertEqual(idx(1, "alpha\nbeta\ngamma"), 0)
    }

    func testMiddleLine() {
        // line 2 ("beta") starts right after "alpha\n" => offset 6
        XCTAssertEqual(idx(2, "alpha\nbeta\ngamma"), 6)
    }

    func testLastLine() {
        // line 3 ("gamma") starts after "alpha\nbeta\n" => 11
        XCTAssertEqual(idx(3, "alpha\nbeta\ngamma"), 11)
    }

    func testLastLineWithTrailingNewline() {
        let text = "alpha\nbeta\n"   // 2 content lines + an empty line 3
        XCTAssertEqual(idx(1, text), 0)
        XCTAssertEqual(idx(2, text), 6)
        XCTAssertEqual(idx(3, text), 11)   // the empty final line exists at offset 11 (== length)
        XCTAssertNil(idx(4, text))
    }

    func testLineZeroOrNegativeIsNil() {
        XCTAssertNil(idx(0, "alpha"))
        XCTAssertNil(idx(-3, "alpha"))
    }

    func testLineBeyondCountIsNil() {
        XCTAssertNil(idx(99, "alpha\nbeta"))
    }

    func testEmptyDocument() {
        XCTAssertEqual(idx(1, ""), 0)
        XCTAssertNil(idx(2, ""))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter TextLocatorTests 2>&1 | grep -E "error:|cannot find"`
Expected: `cannot find 'TextLocator' in scope`.

- [ ] **Step 3: Implement TextLocator**

Create `Sources/MeditKit/TextLocator.swift`:

```swift
import Foundation

/// Maps a 1-based line number to the UTF-16 character offset of that line's
/// start. Pure value logic, fully tested. Returns nil for out-of-range lines.
public enum TextLocator {

    /// Character offset of the start of `line` (1-based), or nil if the line is
    /// out of range. A document always has at least line 1 (offset 0). A file
    /// ending in a newline has an extra empty final line.
    public static func characterIndex(forLine line: Int, in text: String) -> Int? {
        guard line >= 1 else { return nil }
        if line == 1 { return 0 }

        let ns = text as NSString
        let length = ns.length
        var currentLine = 1
        var index = 0

        while index <= length {
            let lineRange = ns.lineRange(for: NSRange(location: index, length: 0))
            let next = NSMaxRange(lineRange)
            if next == index {
                // No progress (only happens at end with empty trailing line).
                break
            }
            currentLine += 1
            if currentLine == line {
                return next
            }
            index = next
        }
        return nil
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter TextLocatorTests 2>&1 | grep -E "Executed|failed"`
Expected: `Executed 7 tests, with 0 failures`.

- [ ] **Step 5: Commit the logic**

```bash
git add Sources/MeditKit/TextLocator.swift Tests/MeditKitTests/TextLocatorTests.swift
git commit -m "Add TextLocator: line number to character offset"
```

- [ ] **Step 6: Create the Go to Line sheet**

Create `Sources/MeditKit/GoToLineSheet.swift`:

```swift
import AppKit

/// A small modal sheet asking for a line number. Calls `onGo` with the parsed
/// line; the caller validates the range and returns true on success (dismiss)
/// or false (invalid — keep the sheet open and beep).
public final class GoToLineSheet: NSObject {

    private var panel: NSPanel?
    private var field: NSTextField!
    private var onGo: ((Int) -> Bool)?

    /// Present the sheet on `window`. `onGo` receives the entered line number and
    /// returns whether navigation succeeded.
    public func present(on window: NSWindow, onGo: @escaping (Int) -> Bool) {
        self.onGo = onGo
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 100),
                            styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Go to Line"

        let label = NSTextField(labelWithString: "Line:")
        label.translatesAutoresizingMaskIntoConstraints = false
        field = NSTextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.formatter = {
            let f = NumberFormatter(); f.numberStyle = .none; f.allowsFloats = false; f.minimum = 1
            return f
        }()
        let go = NSButton(title: "Go", target: self, action: #selector(goTapped))
        go.keyEquivalent = "\r"
        go.bezelStyle = .rounded
        go.translatesAutoresizingMaskIntoConstraints = false
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.keyEquivalent = "\u{1b}"
        cancel.bezelStyle = .rounded
        cancel.translatesAutoresizingMaskIntoConstraints = false

        let content = panel.contentView!
        [label, field, go, cancel].forEach { content.addSubview($0) }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            label.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            field.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            field.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            field.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            cancel.trailingAnchor.constraint(equalTo: go.leadingAnchor, constant: -8),
            cancel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            go.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            go.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])

        self.panel = panel
        window.beginSheet(panel) { _ in }
        panel.makeFirstResponder(field)
    }

    @objc private func goTapped() {
        guard let window = panel?.sheetParent, let panel = panel else { return }
        let value = field.integerValue
        if value >= 1, onGo?(value) == true {
            window.endSheet(panel)
            self.panel = nil
        } else {
            NSSound.beep()   // invalid / out of range — keep sheet open
        }
    }

    @objc private func cancelTapped() {
        guard let window = panel?.sheetParent, let panel = panel else { return }
        window.endSheet(panel)
        self.panel = nil
    }
}
```

- [ ] **Step 7: Add the editor action**

In `Sources/MeditKit/EditorViewController.swift`, add a stored property near the
other view properties (e.g. after `private var findReplaceBar: FindReplaceBar?`):

```swift
    private var goToLineSheet: GoToLineSheet?
```

Add the action method (place it near the find actions, e.g. after `showFindReplaceBar`):

```swift
    /// ⌘L / ⌃G — prompt for a line number and jump to it.
    @objc public func goToLine(_ sender: Any?) {
        guard let window = view.window else { return }
        let sheet = GoToLineSheet()
        goToLineSheet = sheet
        sheet.present(on: window) { [weak self] line in
            guard let self, let offset = TextLocator.characterIndex(forLine: line, in: self.textView.string) else {
                return false
            }
            let range = NSRange(location: offset, length: 0)
            self.textView.setSelectedRange(range)
            self.textView.scrollRangeToVisible(range)
            self.textView.showFindIndicator(for: range)
            self.view.window?.makeFirstResponder(self.textView)
            return true
        }
    }
```

- [ ] **Step 8: Handle ⌃G in EditorTextView**

In `Sources/MeditKit/EditorTextView.swift`, inside `keyDown(with:)`, BEFORE the
existing Insert/Home/End handling (right after the `guard pcStyleNavigationKeys`
line is fine, but ⌃G should work regardless of that pref — so place it at the very
top of `keyDown`, before the guard):

```swift
        // Ctrl+G -> Go to Line (routes up the responder chain to the controller).
        if event.modifierFlags.contains(.control),
           event.charactersIgnoringModifiers?.lowercased() == "g" {
            NSApp.sendAction(Selector(("goToLine:")), to: nil, from: self)
            return
        }
```

- [ ] **Step 9: Add the menu item**

In `Sources/MeditKit/MainMenu.swift`, in the Edit menu builder (`editMenuItem()`),
after the "Select All" item / before the spelling submenu, add:

```swift
        menu.addItem(.separator())
        let goToLine = NSMenuItem(title: "Go to Line…",
                                  action: #selector(EditorViewController.goToLine(_:)), keyEquivalent: "l")
        goToLine.keyEquivalentModifierMask = [.command]
        menu.addItem(goToLine)
```

- [ ] **Step 10: Build + verify**

Run: `swift build 2>&1 | grep -E "error:|Build complete"`
Expected: `Build complete!`
Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests, with"`
Expected: all pass (existing + 7 new).

- [ ] **Step 11: Commit the UI**

```bash
git add Sources/MeditKit/GoToLineSheet.swift Sources/MeditKit/EditorViewController.swift Sources/MeditKit/EditorTextView.swift Sources/MeditKit/MainMenu.swift
git commit -m "Add Go to Line sheet (⌘L / ⌃G)"
```

---

## Task 2: Status bar

**Files:**
- Create: `Sources/MeditKit/TextPosition.swift`, `Tests/MeditKitTests/TextPositionTests.swift`
- Create: `Sources/MeditKit/StatusBarView.swift`
- Modify: `Preferences.swift`, `PreferencesTests.swift`, `EditorViewController.swift`, `EditorTextView.swift`, `MainMenu.swift`, `EditorWindowController.swift`

- [ ] **Step 1: Write the failing test for TextPosition**

Create `Tests/MeditKitTests/TextPositionTests.swift`:

```swift
import XCTest
@testable import MeditKit

final class TextPositionTests: XCTestCase {

    private func lc(_ offset: Int, _ text: String) -> (line: Int, column: Int) {
        TextPosition.lineColumn(forOffset: offset, in: text)
    }

    func testStartOfDocument() {
        let r = lc(0, "alpha\nbeta")
        XCTAssertEqual(r.line, 1); XCTAssertEqual(r.column, 1)
    }

    func testWithinFirstLine() {
        let r = lc(3, "alpha\nbeta")   // caret before 'h' in alpha -> col 4
        XCTAssertEqual(r.line, 1); XCTAssertEqual(r.column, 4)
    }

    func testStartOfSecondLine() {
        let r = lc(6, "alpha\nbeta")   // offset 6 == 'b' -> line 2 col 1
        XCTAssertEqual(r.line, 2); XCTAssertEqual(r.column, 1)
    }

    func testEndOfMultilineDoc() {
        let text = "alpha\nbeta"
        let r = lc((text as NSString).length, text)   // end -> line 2, col 5
        XCTAssertEqual(r.line, 2); XCTAssertEqual(r.column, 5)
    }

    func testOffsetClampedToLength() {
        let text = "ab"
        let r = lc(999, text)
        XCTAssertEqual(r.line, 1); XCTAssertEqual(r.column, 3)
    }

    func testEmptyDocument() {
        let r = lc(0, "")
        XCTAssertEqual(r.line, 1); XCTAssertEqual(r.column, 1)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter TextPositionTests 2>&1 | grep -E "error:|cannot find"`
Expected: `cannot find 'TextPosition' in scope`.

- [ ] **Step 3: Implement TextPosition**

Create `Sources/MeditKit/TextPosition.swift`:

```swift
import Foundation

/// Converts a UTF-16 character offset into a 1-based (line, column). Pure value
/// logic, fully tested. Used by the status bar.
public enum TextPosition {

    public static func lineColumn(forOffset offset: Int, in text: String) -> (line: Int, column: Int) {
        let ns = text as NSString
        let clamped = max(0, min(offset, ns.length))
        // Line = 1 + number of newlines before `clamped`.
        // Column = 1 + distance from the start of the current line.
        let lineStart = ns.lineRange(for: NSRange(location: clamped, length: 0)).location
        var line = 1
        if clamped > 0 {
            ns.enumerateSubstrings(in: NSRange(location: 0, length: clamped),
                                   options: [.byLines, .substringNotRequired]) { _, _, _, _ in
                line += 1
            }
        }
        let column = clamped - lineStart + 1
        return (line, column)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter TextPositionTests 2>&1 | grep -E "Executed|failed"`
Expected: `Executed 6 tests, with 0 failures`.

> Note: `enumerateSubstrings(.byLines)` counts line breaks; for an offset exactly
> at a line start it yields the correct line because the preceding newline is
> within the range. The dedicated tests above pin the exact expectations.

- [ ] **Step 5: Commit the logic**

```bash
git add Sources/MeditKit/TextPosition.swift Tests/MeditKitTests/TextPositionTests.swift
git commit -m "Add TextPosition: offset to line/column"
```

- [ ] **Step 6: Add the showStatusBar preference**

In `Sources/MeditKit/Preferences.swift`: add to the `Key` enum (next to `wrapLines`):

```swift
        static let showStatusBar = "showStatusBar"
```

Add to `registerDefaults()` dict:

```swift
            Key.showStatusBar: true,
```

Add the property (next to `wrapLines`):

```swift
    public var showStatusBar: Bool {
        get { defaults.bool(forKey: Key.showStatusBar) }
        set { defaults.set(newValue, forKey: Key.showStatusBar); didChange() }
    }
```

In `Tests/MeditKitTests/PreferencesTests.swift`, add inside the class:

```swift
    func testShowStatusBarDefaultsOnAndPersists() {
        XCTAssertTrue(prefs.showStatusBar)
        prefs.showStatusBar = false
        XCTAssertFalse(Preferences(defaults: defaults).showStatusBar)
    }
```

- [ ] **Step 7: Create StatusBarView**

Create `Sources/MeditKit/StatusBarView.swift`:

```swift
import AppKit

/// A thin status bar shown at the bottom of an editor window. Dumb display: the
/// editor pushes values in. Shows position, language, encoding, and insert mode.
public final class StatusBarView: NSView {

    private let positionLabel = StatusBarView.makeLabel(align: .left)
    private let languageLabel = StatusBarView.makeLabel(align: .right)
    private let encodingLabel = StatusBarView.makeLabel(align: .right)
    private let modeLabel = StatusBarView.makeLabel(align: .right)

    public override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 22) }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let stack = NSStackView(views: [positionLabel, NSView(), languageLabel, sep(), encodingLabel, sep(), modeLabel])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Top hairline.
        let top = NSBox(); top.boxType = .separator; top.translatesAutoresizingMaskIntoConstraints = false
        addSubview(top)
        NSLayoutConstraint.activate([
            top.leadingAnchor.constraint(equalTo: leadingAnchor),
            top.trailingAnchor.constraint(equalTo: trailingAnchor),
            top.topAnchor.constraint(equalTo: topAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func update(line: Int, column: Int, language: String, encoding: String, overwrite: Bool) {
        positionLabel.stringValue = "Ln \(line), Col \(column)"
        languageLabel.stringValue = language
        encodingLabel.stringValue = encoding
        modeLabel.stringValue = overwrite ? "OVR" : "INS"
    }

    private func sep() -> NSView {
        let v = NSBox(); v.boxType = .separator; v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: 12).isActive = true
        return v
    }

    private static func makeLabel(align: NSTextAlignment) -> NSTextField {
        let f = NSTextField(labelWithString: "")
        f.font = .systemFont(ofSize: 11)
        f.textColor = .secondaryLabelColor
        f.alignment = align
        f.translatesAutoresizingMaskIntoConstraints = false
        return f
    }
}
```

- [ ] **Step 8: Add a display name for the document encoding**

In `Sources/MeditKit/TextEncodingDetector.swift`, add a static helper:

```swift
    /// A short human-readable name for an encoding (for the status bar).
    public static func displayName(for encoding: String.Encoding) -> String {
        switch encoding {
        case .utf8: return "UTF-8"
        case .utf16, .utf16LittleEndian, .utf16BigEndian: return "UTF-16"
        case .utf32, .utf32LittleEndian, .utf32BigEndian: return "UTF-32"
        case .isoLatin1: return "ISO Latin-1"
        case .ascii: return "ASCII"
        default: return "Text"
        }
    }
```

- [ ] **Step 9: Add an overwrite-change callback to EditorTextView**

In `Sources/MeditKit/EditorTextView.swift`, add a property and fire it in the
`isOverwriteMode` didSet:

```swift
    /// Called whenever overwrite mode changes (so the status bar can update).
    public var onOverwriteModeChange: ((Bool) -> Void)?
```

Change the `isOverwriteMode` property's `didSet` from:

```swift
    public private(set) var isOverwriteMode: Bool = false {
        didSet { needsDisplay = true }
    }
```

to:

```swift
    public private(set) var isOverwriteMode: Bool = false {
        didSet { needsDisplay = true; onOverwriteModeChange?(isOverwriteMode) }
    }
```

- [ ] **Step 10: Host the status bar in the editor + update it**

In `Sources/MeditKit/EditorViewController.swift`:

Add a stored property near `findReplaceBar`:

```swift
    private var statusBar: StatusBarView?
    private var statusBarHeightConstraint: NSLayoutConstraint?
```

In `loadView()`, after the find-bar/scroll-view constraints are activated and
before `self.view = container`, replace the existing
`scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor)` constraint
with a status-bar-aware layout. Concretely: remove that one bottom constraint from
the `NSLayoutConstraint.activate([...])` array, then add:

```swift
        let statusBar = StatusBarView()
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        self.statusBar = statusBar
        container.addSubview(statusBar)

        let sbHeight = statusBar.heightAnchor.constraint(equalToConstant: 22)
        sbHeight.isActive = true
        statusBarHeightConstraint = sbHeight

        NSLayoutConstraint.activate([
            scrollView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
```

In `viewDidLoad()`, after `configureHighlighter()`, add:

```swift
        textView.onOverwriteModeChange = { [weak self] _ in self?.updateStatusBar() }
        applyStatusBarVisibility(prefs.showStatusBar)
        updateStatusBar()
```

Add these methods to the class:

```swift
    private func updateStatusBar() {
        guard let statusBar else { return }
        let sel = textView.selectedRange()
        let pos = TextPosition.lineColumn(forOffset: sel.location, in: textView.string)
        let language = document?.highlightLanguage.map { displayLanguageName($0) } ?? "Plain Text"
        let encoding = TextEncodingDetector.displayName(for: document?.fileEncoding ?? .utf8)
        let overwrite = (textView as? EditorTextView)?.isOverwriteMode ?? false
        statusBar.update(line: pos.line, column: pos.column, language: language, encoding: encoding, overwrite: overwrite)
    }

    private func displayLanguageName(_ id: String) -> String {
        // highlight.js ids are lowercase; show a tidy label.
        switch id {
        case "cpp": return "C++"
        case "objectivec": return "Objective-C"
        case "xml": return "HTML/XML"
        case "javascript": return "JavaScript"
        case "typescript": return "TypeScript"
        default: return id.prefix(1).uppercased() + id.dropFirst()
        }
    }

    public func applyStatusBarVisibility(_ visible: Bool) {
        statusBar?.isHidden = !visible
        statusBarHeightConstraint?.constant = visible ? 22 : 0
    }
```

In the `NSTextViewDelegate` extension, add the selection-change hook (next to
`textDidChange`):

```swift
    public func textViewDidChangeSelection(_ notification: Notification) {
        updateStatusBar()
    }
```

And in the existing `textDidChange(_:)`, add a call at the end:

```swift
        updateStatusBar()
```

- [ ] **Step 11: Add the View → Show Status Bar toggle**

In `Sources/MeditKit/MainMenu.swift`, in `viewMenuItem()`, after the Wrap Lines
item, add:

```swift
        let statusBar = NSMenuItem(title: "Show Status Bar",
                                   action: #selector(EditorWindowController.toggleStatusBar(_:)), keyEquivalent: "")
        menu.addItem(statusBar)
```

In `Sources/MeditKit/EditorWindowController.swift`, add the action + validation
(mirroring `toggleLineNumbers`):

```swift
    @IBAction public func toggleStatusBar(_ sender: Any?) {
        prefs.showStatusBar.toggle()
        editor?.applyStatusBarVisibility(prefs.showStatusBar)
    }
```

And in `validateMenuItem(_:)`, add a case:

```swift
        case #selector(toggleStatusBar(_:)):
            menuItem.state = prefs.showStatusBar ? .on : .off
```

- [ ] **Step 12: Build, test, commit**

Run: `swift build 2>&1 | grep -E "error:|Build complete"` → `Build complete!`
Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests, with"` → all pass.

```bash
git add Sources/MeditKit/TextPosition.swift Tests/MeditKitTests/TextPositionTests.swift Sources/MeditKit/StatusBarView.swift Sources/MeditKit/Preferences.swift Tests/MeditKitTests/PreferencesTests.swift Sources/MeditKit/EditorViewController.swift Sources/MeditKit/EditorTextView.swift Sources/MeditKit/TextEncodingDetector.swift Sources/MeditKit/MainMenu.swift Sources/MeditKit/EditorWindowController.swift
git commit -m "Add status bar: Ln/Col, language, encoding, INS/OVR (View toggle)"
```

---

## Task 3: Auto-indent + bracket matching + auto-close

**Files:**
- Create: `Sources/MeditKit/Indenter.swift`, `Tests/MeditKitTests/IndenterTests.swift`
- Create: `Sources/MeditKit/BracketMatcher.swift`, `Tests/MeditKitTests/BracketMatcherTests.swift`
- Modify: `Preferences.swift`, `PreferencesTests.swift`, `EditorTextView.swift`, `EditorViewController.swift`, `PreferencesWindowController.swift`, `Tests/MeditKitTests/EditorSmokeTests.swift`

- [ ] **Step 1: Write the failing Indenter test**

Create `Tests/MeditKitTests/IndenterTests.swift`:

```swift
import XCTest
@testable import MeditKit

final class IndenterTests: XCTestCase {

    private func indent(_ line: String, tabWidth: Int = 4, useSpaces: Bool = true) -> String {
        Indenter.indent(forNewLineAfter: line, tabWidth: tabWidth, useSpaces: useSpaces)
    }

    func testNoIndent() {
        XCTAssertEqual(indent("hello"), "")
    }

    func testCopiesLeadingSpaces() {
        XCTAssertEqual(indent("    hello"), "    ")
    }

    func testCopiesLeadingTabsWhenUseSpacesFalse() {
        XCTAssertEqual(indent("\t\thello", useSpaces: false), "\t\t")
    }

    func testExtraIndentAfterOpenBrace() {
        // "  foo {" -> copy "  " + one level (4 spaces) = 6 spaces
        XCTAssertEqual(indent("  foo {"), "      ")
    }

    func testExtraIndentAfterColon() {
        XCTAssertEqual(indent("def f():"), "    ")
    }

    func testExtraIndentUsesTabWhenUseSpacesFalse() {
        XCTAssertEqual(indent("\tif x {", useSpaces: false), "\t\t")
    }

    func testTrailingWhitespaceAfterBraceStillCountsAsOpener() {
        XCTAssertEqual(indent("foo {   "), "    ")   // ignore trailing ws when finding last non-ws
    }

    func testEmptyLine() {
        XCTAssertEqual(indent(""), "")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter IndenterTests 2>&1 | grep -E "error:|cannot find"`
Expected: `cannot find 'Indenter' in scope`.

- [ ] **Step 3: Implement Indenter**

Create `Sources/MeditKit/Indenter.swift`:

```swift
import Foundation

/// Computes the indentation for a new line created by pressing Return after a
/// given line. Pure value logic, fully tested.
public enum Indenter {

    /// Leading whitespace of `line`, plus one extra indent level when the line's
    /// last non-whitespace character is an opener (`{` or `:`).
    public static func indent(forNewLineAfter line: String, tabWidth: Int, useSpaces: Bool) -> String {
        // Leading whitespace (spaces/tabs) of the line.
        let leading = line.prefix { $0 == " " || $0 == "\t" }
        var result = String(leading)

        // Last non-whitespace character.
        if let lastNonWS = line.reversed().first(where: { $0 != " " && $0 != "\t" }),
           lastNonWS == "{" || lastNonWS == ":" {
            result += useSpaces ? String(repeating: " ", count: max(1, tabWidth)) : "\t"
        }
        return result
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter IndenterTests 2>&1 | grep -E "Executed|failed"`
Expected: `Executed 8 tests, with 0 failures`.

- [ ] **Step 5: Commit Indenter**

```bash
git add Sources/MeditKit/Indenter.swift Tests/MeditKitTests/IndenterTests.swift
git commit -m "Add Indenter: leading-whitespace + opener-aware new-line indent"
```

- [ ] **Step 6: Write the failing BracketMatcher test**

Create `Tests/MeditKitTests/BracketMatcherTests.swift`:

```swift
import XCTest
@testable import MeditKit

final class BracketMatcherTests: XCTestCase {

    private func match(_ text: String, _ offset: Int) -> Int? {
        BracketMatcher.matchingOffset(in: text, at: offset)
    }

    func testSimplePairForward() {
        // "(x)" caret just after '(' at offset 1 -> partner ')' at offset 2
        XCTAssertEqual(match("(x)", 1), 2)
    }

    func testSimplePairBackward() {
        // "(x)" caret just after ')' at offset 3 -> partner '(' at offset 0
        XCTAssertEqual(match("(x)", 3), 0)
    }

    func testNested() {
        // "[ (a) ]" -> caret after outer '[' (offset 1) matches ']' at offset 6
        XCTAssertEqual(match("[ (a) ]", 1), 6)
    }

    func testUnbalancedReturnsNil() {
        XCTAssertNil(match("(a b", 1))
    }

    func testCaretNotOnBracketReturnsNil() {
        XCTAssertNil(match("abc", 2))
    }

    func testMismatchedTypesReturnsNil() {
        // "(]" caret after '(' -> no valid ')' partner
        XCTAssertNil(match("(]", 1))
    }
}
```

- [ ] **Step 7: Run to verify it fails**

Run: `swift test --filter BracketMatcherTests 2>&1 | grep -E "error:|cannot find"`
Expected: `cannot find 'BracketMatcher' in scope`.

- [ ] **Step 8: Implement BracketMatcher**

Create `Sources/MeditKit/BracketMatcher.swift`:

```swift
import Foundation

/// Finds the matching bracket for a caret adjacent to one of ( ) [ ] { }. Pure
/// value logic, fully tested. Brackets only — never quotes.
public enum BracketMatcher {

    private static let openers: [Character: Character] = ["(": ")", "[": "]", "{": "}"]
    private static let closers: [Character: Character] = [")": "(", "]": "[", "}": "{"]

    /// Given `offset` (a caret position), if the character immediately before OR
    /// after the caret is a bracket, return the partner's character offset, or
    /// nil if there's no balanced match. Prefers the character before the caret
    /// (matches typical editor behavior when the caret sits after a typed bracket).
    public static func matchingOffset(in text: String, at offset: Int) -> Int? {
        let chars = Array(text)
        let n = chars.count

        // Character before the caret.
        if offset - 1 >= 0, offset - 1 < n {
            if let partner = match(chars, at: offset - 1) { return partner }
        }
        // Character at the caret.
        if offset >= 0, offset < n {
            if let partner = match(chars, at: offset) { return partner }
        }
        return nil
    }

    private static func match(_ chars: [Character], at index: Int) -> Int? {
        let c = chars[index]
        if let close = openers[c] {
            var depth = 0
            var i = index
            while i < chars.count {
                if chars[i] == c { depth += 1 }
                else if chars[i] == close {
                    depth -= 1
                    if depth == 0 { return i }
                }
                i += 1
            }
            return nil
        } else if let open = closers[c] {
            var depth = 0
            var i = index
            while i >= 0 {
                if chars[i] == c { depth += 1 }
                else if chars[i] == open {
                    depth -= 1
                    if depth == 0 { return i }
                }
                i -= 1
            }
            return nil
        }
        return nil
    }
}
```

Note: `BracketMatcher` works in Character (Unicode scalar) indices for clarity; the
test strings are ASCII so Character offset == UTF-16 offset. The editor passes the
caret as a Character-count offset (it converts from NSRange via the string's
UTF-16; for ASCII brackets these coincide, which is the only case that matches).

- [ ] **Step 9: Run to verify it passes**

Run: `swift test --filter BracketMatcherTests 2>&1 | grep -E "Executed|failed"`
Expected: `Executed 6 tests, with 0 failures`.

- [ ] **Step 10: Commit BracketMatcher**

```bash
git add Sources/MeditKit/BracketMatcher.swift Tests/MeditKitTests/BracketMatcherTests.swift
git commit -m "Add BracketMatcher: matching-bracket offset (depth scan)"
```

- [ ] **Step 11: Add autoIndent + autoCloseBrackets preferences**

In `Sources/MeditKit/Preferences.swift`, add to `Key`:

```swift
        static let autoIndent = "autoIndent"
        static let autoCloseBrackets = "autoCloseBrackets"
```

Add to `registerDefaults()`:

```swift
            Key.autoIndent: true,
            Key.autoCloseBrackets: true,
```

Add the properties:

```swift
    public var autoIndent: Bool {
        get { defaults.bool(forKey: Key.autoIndent) }
        set { defaults.set(newValue, forKey: Key.autoIndent); didChange() }
    }

    public var autoCloseBrackets: Bool {
        get { defaults.bool(forKey: Key.autoCloseBrackets) }
        set { defaults.set(newValue, forKey: Key.autoCloseBrackets); didChange() }
    }
```

In `PreferencesTests.swift`, add:

```swift
    func testEditingAssistDefaultsOnAndPersist() {
        XCTAssertTrue(prefs.autoIndent)
        XCTAssertTrue(prefs.autoCloseBrackets)
        prefs.autoIndent = false
        prefs.autoCloseBrackets = false
        let r = Preferences(defaults: defaults)
        XCTAssertFalse(r.autoIndent)
        XCTAssertFalse(r.autoCloseBrackets)
    }
```

- [ ] **Step 12: Wire auto-indent + auto-close into EditorTextView**

In `Sources/MeditKit/EditorTextView.swift`, add two flags near `pcStyleNavigationKeys`:

```swift
    /// Keep indentation (and add a level after an opener) on Return.
    public var autoIndentEnabled: Bool = true
    /// Auto-insert closing brackets and skip over them; brackets only (no quotes).
    public var autoCloseBracketsEnabled: Bool = true
```

Override `insertNewline` (auto-indent) by adding this method:

```swift
    public override func insertNewline(_ sender: Any?) {
        guard autoIndentEnabled else { super.insertNewline(sender); return }
        let ns = string as NSString
        let caret = selectedRange().location
        let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
        // The text of the current line up to (not past) its newline.
        var lineText = ns.substring(with: lineRange)
        if lineText.hasSuffix("\n") { lineText.removeLast() }
        let indent = Indenter.indent(forNewLineAfter: lineText, tabWidth: indentTabWidth, useSpaces: indentUseSpaces)
        let insertion = "\n" + indent
        let sel = selectedRange()
        if shouldChangeText(in: sel, replacementString: insertion) {
            replaceCharacters(in: sel, with: insertion)
            didChangeText()
        }
    }
```

Add the two indent settings the method reads (pushed in by the editor; defaults
keep it safe if not set):

```swift
    /// Tab width and spaces-vs-tab for auto-indent (set by the editor from prefs).
    public var indentTabWidth: Int = 4
    public var indentUseSpaces: Bool = true
```

For auto-close, override `insertText` ADDITIONALLY. The class already overrides
`insertText(_:replacementRange:)` for overwrite mode. Modify that method so the
auto-close logic runs first (only for collapsed-caret single-character bracket
input), then falls through to the existing overwrite/super behavior. Replace the
current `insertText(_:replacementRange:)` body's beginning so it reads:

```swift
    public override func insertText(_ string: Any, replacementRange: NSRange) {
        if autoCloseBracketsEnabled, let typed = (string as? String) ?? (string as? NSAttributedString)?.string,
           typed.count == 1, let ch = typed.first {
            let openers: [Character: Character] = ["(": ")", "[": "]", "{": "}"]
            let closersSet: Set<Character> = [")", "]", "}"]
            let sel = selectedRange()
            let ns = self.string as NSString

            // Skip over an existing closer.
            if closersSet.contains(ch), sel.length == 0, sel.location < ns.length,
               ns.substring(with: NSRange(location: sel.location, length: 1)) == String(ch) {
                setSelectedRange(NSRange(location: sel.location + 1, length: 0))
                return
            }
            // Auto-close an opener; wrap a selection if present.
            if let close = openers[ch] {
                if sel.length > 0 {
                    let selected = ns.substring(with: sel)
                    let replacement = String(ch) + selected + String(close)
                    if shouldChangeText(in: sel, replacementString: replacement) {
                        replaceCharacters(in: sel, with: replacement)
                        didChangeText()
                        setSelectedRange(NSRange(location: sel.location + 1, length: (selected as NSString).length))
                    }
                    return
                } else {
                    let pair = String(ch) + String(close)
                    if shouldChangeText(in: sel, replacementString: pair) {
                        replaceCharacters(in: sel, with: pair)
                        didChangeText()
                        setSelectedRange(NSRange(location: sel.location + 1, length: 0))
                    }
                    return
                }
            }
        }
        // Existing overwrite-mode handling.
        guard isOverwriteMode else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }
        let sel = selectedRange()
        let ns = self.string as NSString
        if sel.length == 0, sel.location < ns.length {
            let nextChar = ns.substring(with: NSRange(location: sel.location, length: 1))
            if nextChar != "\n" {
                super.insertText(string, replacementRange: NSRange(location: sel.location, length: 1))
                return
            }
        }
        super.insertText(string, replacementRange: replacementRange)
    }
```

- [ ] **Step 13: Bracket-match highlight on selection change**

Add to `EditorTextView`:

```swift
    /// Briefly highlight the bracket matching the one adjacent to the caret.
    public func highlightMatchingBracket() {
        let sel = selectedRange()
        guard sel.length == 0 else { return }
        guard let partner = BracketMatcher.matchingOffset(in: string, at: sel.location) else { return }
        let range = NSRange(location: partner, length: 1)
        guard NSMaxRange(range) <= (string as NSString).length else { return }
        showFindIndicator(for: range)
    }
```

In `Sources/MeditKit/EditorViewController.swift`, in `textViewDidChangeSelection`,
add a call (after `updateStatusBar()`):

```swift
        (textView as? EditorTextView)?.highlightMatchingBracket()
```

- [ ] **Step 14: Push the editing-assist prefs into the text view**

In `Sources/MeditKit/EditorViewController.swift`, in `loadView()` after
`textView.pcStyleNavigationKeys = prefs.pcStyleNavigationKeys`, add:

```swift
        textView.autoIndentEnabled = prefs.autoIndent
        textView.autoCloseBracketsEnabled = prefs.autoCloseBrackets
        textView.indentTabWidth = prefs.tabWidth
        textView.indentUseSpaces = prefs.insertSpacesForTab
```

In `preferencesChanged()`, inside the existing `if let editorTextView = textView as? EditorTextView`
block, add:

```swift
            editorTextView.autoIndentEnabled = prefs.autoIndent
            editorTextView.autoCloseBracketsEnabled = prefs.autoCloseBrackets
            editorTextView.indentTabWidth = prefs.tabWidth
            editorTextView.indentUseSpaces = prefs.insertSpacesForTab
```

- [ ] **Step 15: Add editor smoke tests for auto-indent + auto-close**

In `Tests/MeditKitTests/EditorSmokeTests.swift`, add inside the class:

```swift
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
```

- [ ] **Step 16: Add Preferences checkboxes**

In `Sources/MeditKit/PreferencesWindowController.swift`, follow the existing
checkbox pattern (read the file first to match exact variable/array names and the
layout anchoring). Add two properties:

```swift
    private var autoIndentCheck: NSButton!
    private var autoCloseCheck: NSButton!
```

Build them in `buildUI()` alongside the other checkboxes:

```swift
        autoIndentCheck = NSButton(checkboxWithTitle: "Auto-indent new lines",
                                   target: self, action: #selector(checkChanged))
        autoIndentCheck.translatesAutoresizingMaskIntoConstraints = false
        autoCloseCheck = NSButton(checkboxWithTitle: "Auto-close brackets",
                                  target: self, action: #selector(checkChanged))
        autoCloseCheck.translatesAutoresizingMaskIntoConstraints = false
```

Add them to the `content.addSubview(...)` list and chain them in the constraints
below the last existing checkbox (read the file: whichever check is currently
last, anchor `autoIndentCheck.topAnchor` to its bottom +10, then
`autoCloseCheck.topAnchor` to `autoIndentCheck.bottomAnchor` +10, all
`leadingAnchor`-aligned to `lineNumbersCheck.leadingAnchor`; re-anchor the row that
used to follow the last checkbox to now follow `autoCloseCheck`).

In `syncFromPrefs()`:

```swift
        autoIndentCheck.state = prefs.autoIndent ? .on : .off
        autoCloseCheck.state = prefs.autoCloseBrackets ? .on : .off
```

In `checkChanged(_:)`:

```swift
        prefs.autoIndent = autoIndentCheck.state == .on
        prefs.autoCloseBrackets = autoCloseCheck.state == .on
```

- [ ] **Step 17: Build, test, commit**

Run: `swift build 2>&1 | grep -E "error:|Build complete"` → `Build complete!`
Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests, with"` → all pass.

```bash
git add Sources/MeditKit/Indenter.swift Sources/MeditKit/BracketMatcher.swift Sources/MeditKit/Preferences.swift Sources/MeditKit/EditorTextView.swift Sources/MeditKit/EditorViewController.swift Sources/MeditKit/PreferencesWindowController.swift Tests/MeditKitTests/IndenterTests.swift Tests/MeditKitTests/BracketMatcherTests.swift Tests/MeditKitTests/PreferencesTests.swift Tests/MeditKitTests/EditorSmokeTests.swift
git commit -m "Add auto-indent, bracket-match highlight, and bracket auto-close"
```

---

## Task 4a: Strip trailing whitespace + ensure final newline on save

**Files:**
- Create: `Sources/MeditKit/TextHygiene.swift`, `Tests/MeditKitTests/TextHygieneTests.swift`
- Modify: `Preferences.swift`, `PreferencesTests.swift`, `TextDocument.swift`, `PreferencesWindowController.swift`

- [ ] **Step 1: Write the failing TextHygiene test**

Create `Tests/MeditKitTests/TextHygieneTests.swift`:

```swift
import XCTest
@testable import MeditKit

final class TextHygieneTests: XCTestCase {

    private func clean(_ s: String, strip: Bool = true, finalNL: Bool = true) -> String {
        TextHygiene.cleaned(s, stripTrailing: strip, ensureFinalNewline: finalNL)
    }

    func testStripsTrailingSpaces() {
        XCTAssertEqual(clean("foo   \nbar  "), "foo\nbar\n")
    }

    func testStripsTrailingTabs() {
        XCTAssertEqual(clean("foo\t\t\nbar\t"), "foo\nbar\n")
    }

    func testLeadingIndentUntouched() {
        XCTAssertEqual(clean("    foo  "), "    foo\n")
    }

    func testInteriorWhitespaceUntouched() {
        XCTAssertEqual(clean("a  b  c"), "a  b  c\n")
    }

    func testAddsFinalNewlineWhenMissing() {
        XCTAssertEqual(clean("abc", strip: false), "abc\n")
    }

    func testAlreadyOneNewlineUnchanged() {
        XCTAssertEqual(clean("abc\n", strip: false), "abc\n")
    }

    func testCollapsesMultipleTrailingBlankLines() {
        XCTAssertEqual(clean("abc\n\n\n", strip: false), "abc\n")
    }

    func testEmptyString() {
        XCTAssertEqual(clean("", strip: true, finalNL: true), "")
    }

    func testWhitespaceOnlyLines() {
        XCTAssertEqual(clean("a\n   \nb"), "a\n\nb\n")
    }

    func testCRLFPreserved() {
        // strip trailing ws but keep \r\n line endings intact
        XCTAssertEqual(clean("foo  \r\nbar\r\n", finalNL: false), "foo\r\nbar\r\n")
    }

    func testNoStripNoFinalNewlineIsIdentity() {
        XCTAssertEqual(clean("foo  \nbar", strip: false, finalNL: false), "foo  \nbar")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter TextHygieneTests 2>&1 | grep -E "error:|cannot find"`
Expected: `cannot find 'TextHygiene' in scope`.

- [ ] **Step 3: Implement TextHygiene**

Create `Sources/MeditKit/TextHygiene.swift`:

```swift
import Foundation

/// Save-time text hygiene: strip trailing whitespace per line and/or ensure the
/// file ends with exactly one newline. Pure value logic, fully tested. Preserves
/// the existing line-ending style (LF or CRLF) when stripping.
public enum TextHygiene {

    public static func cleaned(_ text: String, stripTrailing: Bool, ensureFinalNewline: Bool) -> String {
        var result = text

        if stripTrailing {
            // Split on \n, strip trailing spaces/tabs and a stray \r is preserved
            // by only trimming space/tab (not \r) then re-adding it.
            let lines = result.components(separatedBy: "\n")
            let stripped = lines.map { line -> String in
                // Preserve a trailing \r (CRLF); trim spaces/tabs before it.
                if line.hasSuffix("\r") {
                    let body = String(line.dropLast())
                    return trimTrailingSpacesTabs(body) + "\r"
                }
                return trimTrailingSpacesTabs(line)
            }
            result = stripped.joined(separator: "\n")
        }

        if ensureFinalNewline {
            // Determine the dominant line ending.
            let ending = result.contains("\r\n") ? "\r\n" : "\n"
            // Trim all trailing newlines, then add exactly one.
            while result.hasSuffix("\n") || result.hasSuffix("\r") {
                result.removeLast()
            }
            if !result.isEmpty {
                result += ending
            }
        }

        return result
    }

    private static func trimTrailingSpacesTabs(_ s: String) -> String {
        var out = s
        while let last = out.last, last == " " || last == "\t" {
            out.removeLast()
        }
        return out
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter TextHygieneTests 2>&1 | grep -E "Executed|failed"`
Expected: `Executed 11 tests, with 0 failures`.

> If `testCRLFPreserved` or `testCollapsesMultipleTrailingBlankLines` fails,
> the issue is line-ending handling in `cleaned` — fix the implementation so the
> tests pass (the tests are the contract). Do not change the tests.

- [ ] **Step 5: Commit TextHygiene**

```bash
git add Sources/MeditKit/TextHygiene.swift Tests/MeditKitTests/TextHygieneTests.swift
git commit -m "Add TextHygiene: strip trailing whitespace + ensure final newline"
```

- [ ] **Step 6: Add the preference**

In `Sources/MeditKit/Preferences.swift`, add to `Key`:

```swift
        static let stripTrailingWhitespaceOnSave = "stripTrailingWhitespaceOnSave"
```

Add to `registerDefaults()`:

```swift
            Key.stripTrailingWhitespaceOnSave: true,
```

Add the property:

```swift
    public var stripTrailingWhitespaceOnSave: Bool {
        get { defaults.bool(forKey: Key.stripTrailingWhitespaceOnSave) }
        set { defaults.set(newValue, forKey: Key.stripTrailingWhitespaceOnSave); didChange() }
    }
```

In `PreferencesTests.swift`:

```swift
    func testStripOnSaveDefaultsOnAndPersists() {
        XCTAssertTrue(prefs.stripTrailingWhitespaceOnSave)
        prefs.stripTrailingWhitespaceOnSave = false
        XCTAssertFalse(Preferences(defaults: defaults).stripTrailingWhitespaceOnSave)
    }
```

- [ ] **Step 7: Apply on save in TextDocument**

In `Sources/MeditKit/TextDocument.swift`, find `data(ofType:)`. It currently pulls
the live text and encodes it. Read the method, then transform the text before
encoding when the preference is on. After the line that sets `self.text` from the
editor (or reads the current text), and before encoding, insert:

```swift
        if Preferences.shared.stripTrailingWhitespaceOnSave {
            self.text = TextHygiene.cleaned(self.text, stripTrailing: true, ensureFinalNewline: true)
        }
```

(Place it so `self.text` is cleaned right before `TextEncodingDetector.encode(...)`
is called. Read the current method body to position it exactly; the clean must
operate on whatever local/`self.text` value is passed to `encode`.)

- [ ] **Step 8: Add the Preferences checkbox**

In `Sources/MeditKit/PreferencesWindowController.swift`, add (matching the pattern):

Property:

```swift
    private var stripWSCheck: NSButton!
```

In `buildUI()`:

```swift
        stripWSCheck = NSButton(checkboxWithTitle: "Strip trailing whitespace on save",
                                target: self, action: #selector(checkChanged))
        stripWSCheck.translatesAutoresizingMaskIntoConstraints = false
```

Add to `addSubview` list + anchor below `autoCloseCheck` (top = autoCloseCheck.bottom +10,
leading aligned to lineNumbersCheck), and re-anchor the following row to it.

In `syncFromPrefs()`:

```swift
        stripWSCheck.state = prefs.stripTrailingWhitespaceOnSave ? .on : .off
```

In `checkChanged(_:)`:

```swift
        prefs.stripTrailingWhitespaceOnSave = stripWSCheck.state == .on
```

- [ ] **Step 9: Build, test, commit**

Run: `swift build 2>&1 | grep -E "error:|Build complete"` → `Build complete!`
Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests, with"` → all pass.

```bash
git add Sources/MeditKit/TextHygiene.swift Sources/MeditKit/Preferences.swift Sources/MeditKit/TextDocument.swift Sources/MeditKit/PreferencesWindowController.swift Tests/MeditKitTests/TextHygieneTests.swift Tests/MeditKitTests/PreferencesTests.swift
git commit -m "Strip trailing whitespace + ensure final newline on save (default on)"
```

---

## Task 4b: Show Invisibles

**Files:**
- Create: `Sources/MeditKit/InvisiblesLayoutManager.swift`
- Modify: `Preferences.swift`, `PreferencesTests.swift`, `EditorViewController.swift`, `MainMenu.swift`, `EditorWindowController.swift`, `Tests/MeditKitTests/EditorSmokeTests.swift`

- [ ] **Step 1: Add the preference**

In `Sources/MeditKit/Preferences.swift`, add to `Key`:

```swift
        static let showInvisibles = "showInvisibles"
```

Add to `registerDefaults()`:

```swift
            Key.showInvisibles: false,
```

Add the property:

```swift
    public var showInvisibles: Bool {
        get { defaults.bool(forKey: Key.showInvisibles) }
        set { defaults.set(newValue, forKey: Key.showInvisibles); didChange() }
    }
```

In `PreferencesTests.swift`:

```swift
    func testShowInvisiblesDefaultsOffAndPersists() {
        XCTAssertFalse(prefs.showInvisibles)
        prefs.showInvisibles = true
        XCTAssertTrue(Preferences(defaults: defaults).showInvisibles)
    }
```

- [ ] **Step 2: Implement InvisiblesLayoutManager**

Create `Sources/MeditKit/InvisiblesLayoutManager.swift`:

```swift
import AppKit

/// NSLayoutManager that, when `showInvisibles` is on, draws faint markers for
/// spaces (·) and tabs (⟶) over the text. Toggling the flag redraws via the
/// text view. Drawing markers does not modify the document text.
public final class InvisiblesLayoutManager: NSLayoutManager {

    public var showInvisibles: Bool = false

    private let markerAttributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor.tertiaryLabelColor,
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    ]

    public override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        if showInvisibles, let textStorage = textStorage {
            let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
            let string = textStorage.string as NSString
            string.enumerateSubstrings(in: charRange, options: [.byComposedCharacterSequences]) { sub, subRange, _, _ in
                guard let sub = sub else { return }
                let marker: String
                if sub == " " { marker = "·" }
                else if sub == "\t" { marker = "⟶" }
                else { return }
                let glyphRange = self.glyphRange(forCharacterRange: subRange, actualCharacterRange: nil)
                guard glyphRange.length > 0 else { return }
                var rect = self.boundingRect(forGlyphRange: NSRange(location: glyphRange.location, length: 1),
                                             in: self.textContainers.first ?? NSTextContainer())
                rect.origin.x += origin.x
                rect.origin.y += origin.y
                (marker as NSString).draw(at: rect.origin, withAttributes: self.markerAttributes)
            }
        }
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
    }
}
```

> Fallback (documented): if drawing every space proves too noisy or interacts
> badly with the highlighter, restrict the `if sub == " "` branch to only spaces
> that are trailing (followed by end-of-line). Keep tabs always marked. This is an
> acceptable v1.2 scope reduction — note it in the commit if taken.

- [ ] **Step 3: Use InvisiblesLayoutManager in the editor**

In `Sources/MeditKit/EditorViewController.swift`, `loadView()` currently builds an
`NSLayoutManager`. Replace that line:

```swift
        let layoutManager = NSLayoutManager()
```

with:

```swift
        let layoutManager = InvisiblesLayoutManager()
        layoutManager.showInvisibles = prefs.showInvisibles
```

Add a stored reference near the other view properties:

```swift
    private weak var invisiblesLayoutManager: InvisiblesLayoutManager?
```

After creating it, assign:

```swift
        self.invisiblesLayoutManager = layoutManager
```

Add a method:

```swift
    public func applyShowInvisibles(_ show: Bool) {
        invisiblesLayoutManager?.showInvisibles = show
        textView.needsDisplay = true
    }
```

In `preferencesChanged()`, add:

```swift
        applyShowInvisibles(prefs.showInvisibles)
```

- [ ] **Step 4: Add the View → Show Invisibles toggle**

In `Sources/MeditKit/MainMenu.swift`, in `viewMenuItem()` after the Show Status Bar
item:

```swift
        let invisibles = NSMenuItem(title: "Show Invisibles",
                                    action: #selector(EditorWindowController.toggleInvisibles(_:)), keyEquivalent: "")
        menu.addItem(invisibles)
```

In `Sources/MeditKit/EditorWindowController.swift`:

```swift
    @IBAction public func toggleInvisibles(_ sender: Any?) {
        prefs.showInvisibles.toggle()
        editor?.applyShowInvisibles(prefs.showInvisibles)
    }
```

In `validateMenuItem(_:)`:

```swift
        case #selector(toggleInvisibles(_:)):
            menuItem.state = prefs.showInvisibles ? .on : .off
```

- [ ] **Step 5: Add a render regression smoke test**

In `Tests/MeditKitTests/EditorSmokeTests.swift`, add:

```swift
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
```

- [ ] **Step 6: Build, test, commit**

Run: `swift build 2>&1 | grep -E "error:|Build complete"` → `Build complete!`
Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests, with"` → all pass.

```bash
git add Sources/MeditKit/InvisiblesLayoutManager.swift Sources/MeditKit/Preferences.swift Sources/MeditKit/EditorViewController.swift Sources/MeditKit/MainMenu.swift Sources/MeditKit/EditorWindowController.swift Tests/MeditKitTests/PreferencesTests.swift Tests/MeditKitTests/EditorSmokeTests.swift
git commit -m "Add Show Invisibles (View toggle, default off)"
```

---

## Task 5: Version bump to 1.2.0 + README + tag

**Files:**
- Modify: `App/Info.plist`, `App/medit.xcodeproj/project.pbxproj`, `README.md`

- [ ] **Step 1: Bump version strings**

In `App/Info.plist`, change `CFBundleShortVersionString` from `1.1.0` to `1.2.0`.
In `App/medit.xcodeproj/project.pbxproj`, change BOTH `MARKETING_VERSION = 1.1.0;`
to `1.2.0`.

- [ ] **Step 2: Update README**

In `README.md`, add to the **Features** list:

```markdown
- **Go to Line** — jump to a line number (⌘L or ⌃G).
- **Status bar** — live line:column, language, encoding, and insert/overwrite
  mode at the bottom of the window (toggle in View).
- **Auto-indent & bracket assist** — new lines keep the previous indent (and add
  a level after `{` or `:`); typing a bracket auto-closes it and highlights its
  match (toggle in Settings).
- **Whitespace hygiene** — strip trailing whitespace and ensure a final newline on
  save (on by default; toggle in Settings), plus a **Show Invisibles** view.
```

Add to the keyboard-shortcuts table:

```markdown
| ⌘L / ⌃G | Go to Line |
```

- [ ] **Step 3: Build, full test**

Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests, with"` → all pass.
Run (optional, no launch): `cd App && xcodebuild -project medit.xcodeproj -scheme medit -configuration Debug -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"` → `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add App/Info.plist App/medit.xcodeproj/project.pbxproj README.md
git commit -m "Bump version to 1.2.0; document 1.2 features"
```

- [ ] **Step 5: Tag (GATED — only after the user confirms)**

> Do NOT tag or reinstall until the user has reviewed and a running instance is
> safe to replace. When approved:

```bash
git tag -a v1.2.0 -m "medit 1.2.0 — editing-comfort polish: Go to Line, status bar, auto-indent + bracket assist, whitespace hygiene, Show Invisibles."
git describe --tags
```

---

## Self-Review

**Spec coverage:**
- Go to Line (⌘L/⌃G, sheet, out-of-range beep) → Task 1. ✓
- Status bar (Ln/Col, language, encoding, INS/OVR, View toggle) → Task 2. ✓
- Auto-indent (copy + opener) → Task 3 (Indenter + insertNewline). ✓
- Bracket-match highlight (always on) → Task 3 (BracketMatcher + highlightMatchingBracket). ✓
- Auto-close brackets only + skip-over + wrap selection → Task 3 (insertText). ✓
- Strip trailing ws + ensure final newline on save → Task 4a (TextHygiene + TextDocument). ✓
- Show Invisibles (View toggle, default off, fallback noted) → Task 4b. ✓
- Five preferences (showStatusBar, autoIndent, autoCloseBrackets, stripTrailingWhitespaceOnSave, showInvisibles) → Tasks 2/3/4a/4b. ✓
- Render regression guard → Task 4b smoke test + existing EditorSmokeTests. ✓
- Version 1.2.0 + README + tag → Task 5. ✓

**Placeholder scan:** No TBD/TODO. The two "read the file first to match the
pattern" notes (PreferencesWindowController layout, TextDocument.data placement)
are deliberate integration guidance with concrete code to add, not placeholders —
the implementer adapts anchor variable names to the existing file.

**Type consistency:** `TextLocator.characterIndex(forLine:in:)`,
`TextPosition.lineColumn(forOffset:in:)`, `Indenter.indent(forNewLineAfter:tabWidth:useSpaces:)`,
`BracketMatcher.matchingOffset(in:at:)`, `TextHygiene.cleaned(_:stripTrailing:ensureFinalNewline:)`
are used identically in their tasks and tests. EditorTextView properties
(`autoIndentEnabled`, `autoCloseBracketsEnabled`, `indentTabWidth`,
`indentUseSpaces`, `onOverwriteModeChange`, `highlightMatchingBracket()`) and
EditorViewController methods (`applyStatusBarVisibility`, `applyShowInvisibles`,
`updateStatusBar`) are consistent across definition and use. Preference names match
across Preferences.swift, the window controller, and tests.
