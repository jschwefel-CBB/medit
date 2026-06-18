# Markdown v2 Phase 1 — View Support — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A per-tab ⇧⌘V toggle that swaps the editor pane for a read-only,
native (NSAttributedString) Markdown preview, with an auto-refresh preference
(default on) that keeps it current from buffer edits and on-disk changes.

**Architecture:** Apple `swift-markdown` parses GFM → a `MarkdownRenderer` walks
the AST into a styled `NSAttributedString` → shown in a read-only `NSTextView`
swapped in for the editor scroll view. No web view. Theme matches the editor.

**Tech Stack:** Swift 6 / AppKit, `apple/swift-markdown` (product `Markdown`),
existing `EditorColors` / `Preferences`.

Design spec: `docs/specs/2026-06-18-markdown-v2-phase1-view-support-design.md`.

---

### Task 1: Add the swift-markdown dependency

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Add the package dependency and product**

swift-markdown ships only `swift-DEVELOPMENT-SNAPSHOT-*` tags (no semver). Pin an
exact snapshot tag known to build with the project's Swift 6 toolchain, so CI is
reproducible (do NOT track a branch). In `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/smittytone/HighlighterSwift", from: "3.1.0"),
    .package(url: "https://github.com/apple/swift-markdown.git",
             revision: "swift-DEVELOPMENT-SNAPSHOT-2026-06-12-a"),
],
```
And add to the `MeditKit` target dependencies:
```swift
.product(name: "Markdown", package: "swift-markdown"),
```

- [ ] **Step 2: Resolve and confirm it builds**

Run: `swift build`
Expected: resolves swift-markdown (+ swift-cmark gfm), builds clean. If the
pinned snapshot fails against the toolchain, bump to the newest
`swift-DEVELOPMENT-SNAPSHOT-*` tag and retry; record the working tag.

- [ ] **Step 3: Smoke-import test**

Add `Tests/MeditKitTests/MarkdownDependencyTests.swift`:
```swift
import XCTest
import Markdown
@testable import MeditKit

final class MarkdownDependencyTests: XCTestCase {
    func testCanParseDocument() {
        let doc = Document(parsing: "# Hello\n\nA *para*.")
        XCTAssertEqual(doc.childCount, 2)        // heading + paragraph
    }
}
```
Run: `swift test --filter MarkdownDependencyTests` — expect PASS.

- [ ] **Step 4: Commit**

```bash
git add Package.swift Package.resolved Tests/MeditKitTests/MarkdownDependencyTests.swift
git commit -m "Add apple/swift-markdown dependency (pinned snapshot)"
```

---

### Task 2: MarkdownRenderer — inline elements (TDD)

**Files:**
- Create: `Sources/MeditKit/MarkdownRenderer.swift`
- Test: `Tests/MeditKitTests/MarkdownRendererTests.swift`

- [ ] **Step 1: Write failing tests for inline rendering**

```swift
import XCTest
import AppKit
@testable import MeditKit

final class MarkdownRendererTests: XCTestCase {
    private func renderer() -> MarkdownRenderer {
        MarkdownRenderer(theme: .init(
            baseFont: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            foreground: .textColor, secondary: .secondaryLabelColor,
            codeBackground: NSColor.gray.withAlphaComponent(0.15),
            linkColor: .linkColor, isDark: false))
    }
    private func attrs(_ s: NSAttributedString, at i: Int) -> [NSAttributedString.Key: Any] {
        s.attributes(at: i, effectiveRange: nil)
    }

    func testPlainTextRendersWithBaseFont() {
        let out = renderer().render("hello")
        XCTAssertTrue(out.string.contains("hello"))
        XCTAssertNotNil(attrs(out, at: 0)[.font])
    }
    func testStrongIsBold() {
        let out = renderer().render("a **bold** b")
        let i = out.string.range(of: "bold")!.lowerBound.utf16Offset(in: out.string)
        let f = attrs(out, at: i)[.font] as! NSFont
        XCTAssertTrue(f.fontDescriptor.symbolicTraits.contains(.bold))
    }
    func testEmphasisIsItalic() {
        let out = renderer().render("a *it* b")
        let i = out.string.range(of: "it")!.lowerBound.utf16Offset(in: out.string)
        let f = attrs(out, at: i)[.font] as! NSFont
        XCTAssertTrue(f.fontDescriptor.symbolicTraits.contains(.italic))
    }
    func testStrikethroughHasAttribute() {
        let out = renderer().render("a ~~gone~~ b")
        let i = out.string.range(of: "gone")!.lowerBound.utf16Offset(in: out.string)
        XCTAssertNotNil(attrs(out, at: i)[.strikethroughStyle])
    }
    func testInlineCodeHasBackground() {
        let out = renderer().render("a `code` b")
        let i = out.string.range(of: "code")!.lowerBound.utf16Offset(in: out.string)
        XCTAssertNotNil(attrs(out, at: i)[.backgroundColor])
    }
    func testLinkCarriesURL() {
        let out = renderer().render("[txt](https://example.com)")
        let i = out.string.range(of: "txt")!.lowerBound.utf16Offset(in: out.string)
        XCTAssertEqual((attrs(out, at: i)[.link] as? URL)?.host, "example.com")
    }
}
```

Run: `swift test --filter MarkdownRendererTests` — Expected: FAIL (no type yet).

- [ ] **Step 2: Implement MarkdownRenderer with a MarkupVisitor for inline + paragraphs**

```swift
import AppKit
import Markdown

public struct MarkdownRenderer {
    public struct Theme {
        public var baseFont: NSFont
        public var foreground: NSColor
        public var secondary: NSColor
        public var codeBackground: NSColor
        public var linkColor: NSColor
        public var isDark: Bool
        public init(baseFont: NSFont, foreground: NSColor, secondary: NSColor,
                    codeBackground: NSColor, linkColor: NSColor, isDark: Bool) {
            self.baseFont = baseFont; self.foreground = foreground
            self.secondary = secondary; self.codeBackground = codeBackground
            self.linkColor = linkColor; self.isDark = isDark
        }
    }

    private let theme: Theme
    public init(theme: Theme) { self.theme = theme }

    public func render(_ markdown: String) -> NSAttributedString {
        let document = Document(parsing: markdown)
        var visitor = AttributedStringBuilder(theme: theme)
        return visitor.build(document)
    }
}

/// Walks the markdown AST accumulating an NSAttributedString. Inline styling is
/// tracked with an InlineStyle stack; block styling is applied per paragraph.
private struct AttributedStringBuilder: MarkupVisitor {
    typealias Result = Void
    let theme: MarkdownRenderer.Theme
    var out = NSMutableAttributedString()

    // Inline style state pushed/popped as we descend.
    private var bold = false, italic = false, strike = false, code = false
    private var link: URL? = nil

    mutating func build(_ doc: Document) -> NSAttributedString {
        visit(doc)
        return out
    }

    private func baseFont(bold: Bool, italic: Bool, mono: Bool) -> NSFont {
        var font = mono
            ? NSFont.monospacedSystemFont(ofSize: theme.baseFont.pointSize, weight: .regular)
            : theme.baseFont
        var traits: NSFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        if !traits.isEmpty {
            let d = font.fontDescriptor.withSymbolicTraits(traits)
            font = NSFont(descriptor: d, size: font.pointSize) ?? font
        }
        return font
    }

    private mutating func emit(_ text: String) {
        var a: [NSAttributedString.Key: Any] = [
            .font: baseFont(bold: bold, italic: italic, mono: code),
            .foregroundColor: link != nil ? theme.linkColor : theme.foreground,
        ]
        if strike { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if code { a[.backgroundColor] = theme.codeBackground }
        if let link { a[.link] = link }
        out.append(NSAttributedString(string: text, attributes: a))
    }

    // MARK: MarkupVisitor

    mutating func defaultVisit(_ markup: Markup) -> Void {
        for child in markup.children { visit(child) }
    }
    mutating func visitText(_ text: Text) -> Void { emit(text.string) }
    mutating func visitSoftBreak(_ s: SoftBreak) -> Void { emit(" ") }
    mutating func visitLineBreak(_ b: LineBreak) -> Void { emit("\n") }
    mutating func visitInlineCode(_ c: InlineCode) -> Void {
        let was = code; code = true; emit(c.code); code = was
    }
    mutating func visitEmphasis(_ e: Emphasis) -> Void {
        let was = italic; italic = true; defaultVisit(e); italic = was
    }
    mutating func visitStrong(_ s: Strong) -> Void {
        let was = bold; bold = true; defaultVisit(s); bold = was
    }
    mutating func visitStrikethrough(_ s: Strikethrough) -> Void {
        let was = strike; strike = true; defaultVisit(s); strike = was
    }
    mutating func visitLink(_ l: Link) -> Void {
        let was = link; link = l.destination.flatMap(URL.init(string:)); defaultVisit(l); link = was
    }
    mutating func visitParagraph(_ p: Paragraph) -> Void {
        defaultVisit(p)
        out.append(NSAttributedString(string: "\n\n"))
    }
}
```

- [ ] **Step 3: Run inline tests — expect PASS**

Run: `swift test --filter MarkdownRendererTests`
Expected: the 6 inline tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/MeditKit/MarkdownRenderer.swift Tests/MeditKitTests/MarkdownRendererTests.swift
git commit -m "MarkdownRenderer: inline elements (bold/italic/strike/code/link)"
```

---

### Task 3: MarkdownRenderer — block elements (TDD)

**Files:**
- Modify: `Sources/MeditKit/MarkdownRenderer.swift`
- Test: `Tests/MeditKitTests/MarkdownRendererTests.swift`

- [ ] **Step 1: Add failing block tests**

```swift
extension MarkdownRendererTests {
    func testHeadingIsLargerAndBold() {
        let out = renderer().render("# Big")
        let f = out.attributes(at: 0, effectiveRange: nil)[.font] as! NSFont
        XCTAssertGreaterThan(f.pointSize, 13)
        XCTAssertTrue(f.fontDescriptor.symbolicTraits.contains(.bold))
    }
    func testUnorderedListHasHangingIndent() {
        let out = renderer().render("- one\n- two")
        let p = out.attributes(at: 0, effectiveRange: nil)[.paragraphStyle] as! NSParagraphStyle
        XCTAssertGreaterThan(p.headIndent, 0)
        XCTAssertTrue(out.string.contains("one"))
    }
    func testOrderedListShowsNumbers() {
        let out = renderer().render("1. a\n2. b")
        XCTAssertTrue(out.string.contains("1.") && out.string.contains("2."))
    }
    func testCodeBlockIsMonospacedWithBackground() {
        let out = renderer().render("```\nlet x = 1\n```")
        let i = out.string.range(of: "let x")!.lowerBound.utf16Offset(in: out.string)
        let f = out.attributes(at: i, effectiveRange: nil)[.font] as! NSFont
        XCTAssertTrue(f.fontDescriptor.symbolicTraits.contains(.monoSpace) || f.isFixedPitch)
        XCTAssertNotNil(out.attributes(at: i, effectiveRange: nil)[.backgroundColor])
    }
    func testBlockQuoteIsIndented() {
        let out = renderer().render("> quoted")
        let i = out.string.range(of: "quoted")!.lowerBound.utf16Offset(in: out.string)
        let p = out.attributes(at: i, effectiveRange: nil)[.paragraphStyle] as! NSParagraphStyle
        XCTAssertGreaterThan(p.firstLineHeadIndent, 0)
    }
    func testTaskListShowsCheckboxes() {
        let out = renderer().render("- [ ] todo\n- [x] done")
        XCTAssertTrue(out.string.contains("☐") && out.string.contains("☑"))
    }
    func testThematicBreakRenders() {
        let out = renderer().render("a\n\n---\n\nb")
        XCTAssertTrue(out.string.contains("a") && out.string.contains("b"))
    }
    func testTableRendersCellsAndHeaderBold() {
        let out = renderer().render("| H |\n|---|\n| c |")
        XCTAssertTrue(out.string.contains("H") && out.string.contains("c"))
        let i = out.string.range(of: "H")!.lowerBound.utf16Offset(in: out.string)
        let f = out.attributes(at: i, effectiveRange: nil)[.font] as! NSFont
        XCTAssertTrue(f.fontDescriptor.symbolicTraits.contains(.bold))
    }
}
```

Run: `swift test --filter MarkdownRendererTests` — Expected: new tests FAIL.

- [ ] **Step 2: Implement block visitors**

Add to `AttributedStringBuilder`. Use a helper to apply a paragraph style to a
just-appended block, and append block separators. Key methods:

```swift
private mutating func appendBlock(_ body: () -> Void, style: NSParagraphStyle, font: NSFont? = nil) {
    let start = out.length
    body()
    if out.length > start {
        out.addAttribute(.paragraphStyle, value: style, range: NSRange(location: start, length: out.length - start))
        if let font { out.addAttribute(.font, value: font, range: NSRange(location: start, length: out.length - start)) }
    }
    out.append(NSAttributedString(string: "\n\n"))
}

mutating func visitHeading(_ h: Heading) -> Void {
    let scale: CGFloat = [1: 2.0, 2: 1.6, 3: 1.3, 4: 1.15, 5: 1.05, 6: 1.0][h.level] ?? 1.0
    let size = theme.baseFont.pointSize * scale
    let headFont = NSFont.boldSystemFont(ofSize: size)
    let para = NSMutableParagraphStyle(); para.paragraphSpacingBefore = size * 0.4; para.paragraphSpacing = size * 0.2
    appendBlock({ defaultVisit(h) }, style: para, font: headFont)
}

mutating func visitCodeBlock(_ c: CodeBlock) -> Void {
    let para = NSMutableParagraphStyle(); para.firstLineHeadIndent = 8; para.headIndent = 8
    let mono = NSFont.monospacedSystemFont(ofSize: theme.baseFont.pointSize, weight: .regular)
    let start = out.length
    out.append(NSAttributedString(string: c.code, attributes: [
        .font: mono, .foregroundColor: theme.foreground,
        .backgroundColor: theme.codeBackground, .paragraphStyle: para]))
    _ = start
    out.append(NSAttributedString(string: "\n\n"))
}

mutating func visitBlockQuote(_ q: BlockQuote) -> Void {
    let para = NSMutableParagraphStyle(); para.firstLineHeadIndent = 16; para.headIndent = 16
    appendBlock({ defaultVisit(q) }, style: para)
}

mutating func visitUnorderedList(_ list: UnorderedList) -> Void { renderList(list, ordered: false) }
mutating func visitOrderedList(_ list: OrderedList) -> Void { renderList(list, ordered: true) }

private mutating func renderList(_ list: ListItemContainer, ordered: Bool) {
    let para = NSMutableParagraphStyle(); para.headIndent = 24; para.firstLineHeadIndent = 8
    var n = 1
    for case let item as ListItem in list.children {
        let marker: String
        if let checkbox = item.checkbox {            // GFM task list
            marker = (checkbox == .checked ? "☑ " : "☐ ")
        } else if ordered {
            marker = "\(n). "; n += 1
        } else {
            marker = "•  "
        }
        let start = out.length
        out.append(NSAttributedString(string: marker, attributes: [.font: theme.baseFont, .foregroundColor: theme.foreground]))
        for child in item.children { visit(child) }   // paragraph(s) inside the item
        // Trim the paragraph's trailing block separators into a single newline for list tightness.
        out.addAttribute(.paragraphStyle, value: para, range: NSRange(location: start, length: out.length - start))
    }
    out.append(NSAttributedString(string: "\n"))
}

mutating func visitThematicBreak(_ t: ThematicBreak) -> Void {
    let para = NSMutableParagraphStyle()
    out.append(NSAttributedString(string: "\u{00A0}\n", attributes: [
        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
        .strikethroughColor: theme.secondary, .paragraphStyle: para]))
    out.append(NSAttributedString(string: "\n"))
}

mutating func visitTable(_ table: Table) -> Void {
    // Simple tabbed layout: header row bold, one row per line, cells tab-separated.
    func renderRow(_ row: Markup, bold: Bool) {
        let wasBold = self.bold; self.bold = bold
        var first = true
        for cell in row.children {
            if !first { out.append(NSAttributedString(string: "\t")) }
            for c in cell.children { visit(c) }
            first = false
        }
        self.bold = wasBold
        out.append(NSAttributedString(string: "\n"))
    }
    if let head = table.head as Markup? { renderRow(head, bold: true) }
    for row in table.body.children { renderRow(row, bold: false) }
    out.append(NSAttributedString(string: "\n"))
}
```

Note on list-item paragraphs: `visitParagraph` appends `"\n\n"`; inside tight
lists that doubles spacing. If a block test shows extra blank lines, add a
`inListItem` flag that makes `visitParagraph` append a single `"\n"` when set.
Verify against `testUnorderedListHasHangingIndent` / `testOrderedListShowsNumbers`.

Adjust exact `Table` child-access (`table.head`, `table.body`, row/cell types
`Table.Head`, `Table.Row`, `Table.Cell`) to the swift-markdown API discovered at
build time; the structure above matches its `Table` model.

- [ ] **Step 3: Run block tests — iterate to green**

Run: `swift test --filter MarkdownRendererTests`
Expected: all inline + block tests pass. Fix indent/spacing constants as needed.

- [ ] **Step 4: Commit**

```bash
git add Sources/MeditKit/MarkdownRenderer.swift Tests/MeditKitTests/MarkdownRendererTests.swift
git commit -m "MarkdownRenderer: block elements (headings, lists, code, quote, table, task lists)"
```

---

### Task 4: autoRefreshPreview preference (TDD)

**Files:**
- Modify: `Sources/MeditKit/Preferences.swift`
- Test: `Tests/MeditKitTests/PreferencesTests.swift`

- [ ] **Step 1: Failing default test**

In `PreferencesTests.swift`:
```swift
func testAutoRefreshPreviewDefaultsOn() {
    XCTAssertTrue(prefs.autoRefreshPreview)
    prefs.autoRefreshPreview = false
    XCTAssertFalse(Preferences(defaults: defaults).autoRefreshPreview)
}
```
Run: `swift test --filter PreferencesTests` — Expected: FAIL (no member).

- [ ] **Step 2: Add the pref**

In `Preferences.swift`: add key `static let autoRefreshPreview = "autoRefreshPreview"`,
register default `Key.autoRefreshPreview: true` in `registerDefaults()`, and an accessor mirroring the existing Bool accessors:
```swift
public var autoRefreshPreview: Bool {
    get { defaults.bool(forKey: Key.autoRefreshPreview) }
    set { defaults.set(newValue, forKey: Key.autoRefreshPreview); didChange() }
}
```

- [ ] **Step 3: Pass + commit**

Run: `swift test --filter PreferencesTests` — PASS.
```bash
git add Sources/MeditKit/Preferences.swift Tests/MeditKitTests/PreferencesTests.swift
git commit -m "Add autoRefreshPreview preference (default on)"
```

---

### Task 5: Preview pane + toggle in EditorViewController

**Files:**
- Modify: `Sources/MeditKit/EditorViewController.swift`

- [ ] **Step 1: Add preview state, views, and methods**

Add stored properties near the other per-tab state (`:10-16`):
```swift
private var isShowingPreview = false
private var previewScrollView: NSScrollView?
private var previewTextView: NSTextView?
private var previewRefreshWorkItem: DispatchWorkItem?
```

Add (mirroring `applyShowInvisibles` `:515-518`):
```swift
public var isPreviewVisible: Bool { isShowingPreview }

public func showPreview(_ show: Bool) {
    if show { buildPreviewIfNeeded(); renderPreview() }
    isShowingPreview = show
    previewScrollView?.isHidden = !show
    scrollView.isHidden = show
}

private func buildPreviewIfNeeded() {
    guard previewScrollView == nil, let container = view as NSView? else { return }
    let tv = NSTextView()
    tv.isEditable = false; tv.isSelectable = true
    tv.drawsBackground = true
    tv.backgroundColor = .textBackgroundColor
    tv.textContainerInset = NSSize(width: CGFloat(prefs.editorPadding), height: CGFloat(prefs.editorPadding))
    tv.setAccessibilityIdentifier("markdownPreviewTextView")
    let sv = NSScrollView()
    sv.translatesAutoresizingMaskIntoConstraints = false
    sv.hasVerticalScroller = true
    sv.documentView = tv
    sv.isHidden = true
    container.addSubview(sv)
    // Same band as the editor scroll view: below the find bar, above the status bar.
    NSLayoutConstraint.activate([
        sv.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
        sv.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
        sv.topAnchor.constraint(equalTo: scrollView.topAnchor),
        sv.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
    ])
    previewScrollView = sv; previewTextView = tv
}

private func renderPreview() {
    guard let tv = previewTextView else { return }
    let theme = MarkdownRenderer.Theme(
        baseFont: currentEditorFont(),
        foreground: EditorColors.foreground,
        secondary: .secondaryLabelColor,
        codeBackground: NSColor.gray.withAlphaComponent(view.effectiveAppearance.isDark ? 0.22 : 0.12),
        linkColor: .linkColor,
        isDark: view.effectiveAppearance.isDark)
    let rendered = MarkdownRenderer(theme: theme).render(currentText)
    tv.textStorage?.setAttributedString(rendered)
}

private func schedulestylePreviewRefresh() {
    guard isShowingPreview, prefs.autoRefreshPreview else { return }
    previewRefreshWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.renderPreview() }
    previewRefreshWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
}
```
Add a small `currentEditorFont()` helper if one doesn't exist, reusing
`configureFont()`'s logic (`NSFont(name: prefs.fontName, size: prefs.fontSize) ?? .monospacedSystemFont(...)`).

- [ ] **Step 2: Wire render triggers**

- In `textDidChange` (`:689-697`), after the existing body, add: `scheduleStylePreviewRefresh()` (correct the name to `schedulePreviewRefresh`).
- In `reloadFromDocument()` (`:257-263`): `if isShowingPreview { renderPreview() }`.
- In the appearance-KVO block (`:379-385`) and `preferencesChanged` (`:410-440`): `if isShowingPreview { renderPreview() }` (covers theme/font flips, and re-applies hidden-state if padding changed).

- [ ] **Step 3: Test hooks**

Add near other `…ForTesting` (`:634-653`):
```swift
public var isPreviewVisibleForTesting: Bool { isShowingPreview }
public func togglePreviewForTesting() { showPreview(!isShowingPreview) }
public var previewAttributedStringForTesting: NSAttributedString? { previewTextView?.attributedString() }
```

- [ ] **Step 4: Build**

Run: `swift build` — Expected: clean. Fix any helper-name mismatches
(`schedulePreviewRefresh`).

- [ ] **Step 5: Commit**

```bash
git add Sources/MeditKit/EditorViewController.swift
git commit -m "EditorViewController: Markdown preview pane, render + debounced auto-refresh"
```

---

### Task 6: Menu item + window-controller toggle + gating

**Files:**
- Modify: `Sources/MeditKit/EditorWindowController.swift`, `Sources/MeditKit/MainMenu.swift`

- [ ] **Step 1: Window-controller action (mirror `toggleInvisibles` `:330-333`)**

```swift
@IBAction public func toggleMarkdownPreview(_ sender: Any?) {
    guard let editor else { return }
    editor.showPreview(!editor.isPreviewVisible)
}
```

- [ ] **Step 2: validateMenuItem case (`:343-365`)**

```swift
case #selector(toggleMarkdownPreview(_:)):
    let isMarkdown = (documentForTesting ?? document as? TextDocument)?.highlightLanguage == "markdown"
    menuItem.state = (editor?.isPreviewVisible == true) ? .on : .off
    return isMarkdown
```
(Use the controller's real document accessor; `highlightLanguage` at
`TextDocument.swift:252-254`.)

- [ ] **Step 3: Menu item (`MainMenu.swift`, View menu after rainbow `:224`)**

```swift
let preview = NSMenuItem(title: "Show Markdown Preview",
    action: #selector(EditorWindowController.toggleMarkdownPreview(_:)), keyEquivalent: "V")
preview.keyEquivalentModifierMask = [.command, .shift]
view.addItem(preview)
```

- [ ] **Step 4: Build + commit**

Run: `swift build` — clean.
```bash
git add Sources/MeditKit/EditorWindowController.swift Sources/MeditKit/MainMenu.swift
git commit -m "View ▸ Show Markdown Preview (⇧⌘V), gated to Markdown files"
```

---

### Task 7: Settings checkbox for auto-refresh + tooltip

**Files:**
- Modify: `Sources/MeditKit/PreferencesWindowController.swift`

- [ ] **Step 1: Add the checkbox with tooltip**

In `buildUI()`, add (e.g. a new "Markdown" header after the Brackets section, or
under Editor):
```swift
autoRefreshPreviewCheck = check("Auto-refresh preview", #selector(checkChanged))
autoRefreshPreviewCheck.toolTip = "Keep the Markdown preview up to date as you edit or the file changes"
```
Declare the property, place it in the stack under a `header("Markdown")`, write it
back in `checkChanged` (`prefs.autoRefreshPreview = autoRefreshPreviewCheck.state == .on`),
and set it in `syncFromPrefs()`.

- [ ] **Step 2: Tests pass (tooltip guard is automatic)**

Run: `swift test --filter PreferencesTooltipTests` — PASS (new control already has a tooltip; the guard would fail otherwise).

- [ ] **Step 3: Commit**

```bash
git add Sources/MeditKit/PreferencesWindowController.swift
git commit -m "Settings: Auto-refresh preview checkbox (+ tooltip)"
```

---

### Task 8: Editor smoke tests for the toggle (TDD-ish)

**Files:**
- Modify: `Tests/MeditKitTests/EditorSmokeTests.swift`

- [ ] **Step 1: Add toggle + gating + render tests**

Mirror `testToggleLineNumbersAndWrapDoNotCrash` (`:434-442`) and
`testManualLanguageOverrideWinsOverDetection` (`:648-658`):
```swift
func testMarkdownPreviewTogglesAndRenders() {
    let wc = makeWindowController(text: "# Title\n\n- a\n- b")
    wc.documentForTesting?.setLanguageOverrideForTesting("markdown") // ensure gating sees markdown
    let editor = wc.editorForTesting!
    XCTAssertFalse(editor.isPreviewVisibleForTesting)
    editor.togglePreviewForTesting()
    XCTAssertTrue(editor.isPreviewVisibleForTesting)
    let rendered = editor.previewAttributedStringForTesting
    XCTAssertTrue(rendered?.string.contains("Title") == true)
    editor.togglePreviewForTesting()
    XCTAssertFalse(editor.isPreviewVisibleForTesting)
}
```
(If `setLanguageOverrideForTesting` is on the editor not the document, adjust to
match `EditorViewController.setLanguageOverrideForTesting` `:496`.)

- [ ] **Step 2: Run + full suite**

Run: `swift test` — Expected: all green (240 prior + new).

- [ ] **Step 3: Commit**

```bash
git add Tests/MeditKitTests/EditorSmokeTests.swift
git commit -m "Smoke tests: Markdown preview toggle + render"
```

---

### Task 9: Live verification + AutoPilot plan + ship prep

**Files:**
- Create: `docs/testplans/markdown/preview-toggle.json` (AutoPilot)

- [ ] **Step 1: Build and run the app on a Markdown file**

Build universal Release, install, open a `.md` fixture, press ⇧⌘V, confirm the
preview renders (headings larger, lists, code blocks, a table), toggle back,
edit text and confirm auto-refresh updates the preview (with the pref on), and
that the menu item is disabled for a non-Markdown file.

- [ ] **Step 2: AutoPilot plan**

Add `docs/testplans/markdown/preview-toggle.json`: open a fixture `.md` via
`launchFiles`, assert `markdownPreviewTextView` is absent, `menu ["View","Show Markdown Preview"]`,
assert the preview text view appears and contains expected text, toggle back.
Run it against the built app.

- [ ] **Step 3: Bump version + ship**

When Phase 1 is verified: bump to the v2 version (confirm number with the user —
e.g. 2.0.0), then the standard flow — PR → CI → admin-bypass merge → tag → universal
GitHub Release as Latest (REQUIRED SUB-SKILL: superpowers:finishing-a-development-branch).

---

## Self-review notes

- **Spec coverage:** parser dep (T1), renderer inline+block incl. full GFM (T2-3),
  auto-refresh pref (T4), preview pane + triggers (T5), toggle + gating (T6),
  Settings + tooltip (T7), tests (T2-3,8), live + AutoPilot + ship (T9). All spec
  sections map to a task.
- **Type consistency:** `MarkdownRenderer.Theme`, `showPreview(_:)`,
  `isPreviewVisible`, `previewAttributedStringForTesting`, `autoRefreshPreview`,
  `toggleMarkdownPreview(_:)`, AX id `markdownPreviewTextView` used consistently.
- **Known unknowns to resolve at build time (flagged in-task):** the exact
  swift-markdown snapshot tag that builds with the toolchain (T1 Step 2); the
  `Table` child-access API (`head`/`body`/`Row`/`Cell`) (T3); list-item paragraph
  tightness (T3 note); the controller's real `document` accessor name (T6).
  Each task says to adjust to the discovered API.
