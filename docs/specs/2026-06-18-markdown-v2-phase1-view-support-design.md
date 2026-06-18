# medit v2 — Markdown support, Phase 1: View Support (design)

**Goal:** A per-tab toggle that swaps the editor's center pane between the raw
text editor and a rendered, read-only Markdown **preview** (a native
`NSAttributedString` in a text view). Available for Markdown documents.

**This is Phase 1 of 3.** Phase 2 adds direct editing with Markdown syntax (live
re-render, syntax affordances); Phase 3 adds a formatting "style bar". Each phase
is independently shippable and gets its own spec/plan. Decisions locked during
brainstorming:

- **Native, all three phases** — `NSAttributedString` in a native text view; **no
  web view**. This is the foundation Phases 2–3 build on.
- **Parser: Apple `swift-markdown`** — full GFM AST (tables, task lists, source
  ranges), reused across all phases.
- **Scope: full GFM rendering** in Phase 1.
- **Phase 1 view model: toggle** (preview replaces the editor pane). An
  **"Auto-refresh preview" preference (default ON)** keeps the preview current
  from **both** change sources — the editor buffer (as the text changes) and the
  file on disk (external changes). With it **off**, the preview is a static
  snapshot (re-rendered only on entry + on document reload). This pulls the
  live-render that was originally Phase 2 into Phase 1, gated behind the toggle.
- **Shortcut: ⇧⌘V** ("Show Markdown Preview"), matching VS Code's "Open Preview".
  Verified no collision (⌘V is Paste; ⇧⌘V is free).

---

## Architecture

Three units, each with one clear responsibility:

### 1. `MarkdownRenderer` (pure logic — the bulk of the work, fully testable)

`Sources/MeditKit/MarkdownRenderer.swift`

```swift
public struct MarkdownRenderer {
    public struct Theme {
        public var baseFont: NSFont
        public var foreground: NSColor
        public var secondary: NSColor      // blockquote bar, rule, table borders
        public var codeBackground: NSColor
        public var linkColor: NSColor
        public var isDark: Bool
    }
    public init(theme: Theme)
    /// Parse GFM and render to a styled attributed string.
    public func render(_ markdown: String) -> NSAttributedString
}
```

- Parses with `swift-markdown`’s `Document(parsing:)` and walks the AST with a
  `MarkupWalker`/`MarkupVisitor`, emitting an `NSMutableAttributedString`.
- Establishes a **visible base** (`baseFont` + `foreground`) over every run first,
  so nothing renders invisible on dark backgrounds — mirrors
  `SyntaxHighlightingController.highlightNow()` (`SyntaxHighlightingController.swift:100-110`).
- Block elements via `NSParagraphStyle`:
  - **Headings** (`# … ######`): scaled bold sizes (e.g. h1 = base×2.0 down to
    h6 = base×1.0), space-before/after.
  - **Paragraphs**: base, paragraph spacing.
  - **Lists** (ordered/unordered, nested): hanging indent via
    `headIndent`/`firstLineHeadIndent` + tab stops; bullet/number markers
    rendered into the string.
  - **Task lists** (GFM): `☐`/`☑` markers from the checkbox state.
  - **Blockquotes**: leading indent + a left vertical bar (drawn via a colored
    leading "▏" run or paragraph background), `secondary` color.
  - **Fenced/indented code blocks**: monospace, `codeBackground`, full-width
    paragraph background, no smart substitutions.
  - **Inline code**: monospace + `codeBackground`.
  - **Emphasis / strong / strikethrough (GFM)**: italic / bold /
    `.strikethroughStyle`.
  - **Links**: `linkColor` + `.link` attribute (URL); read-only view makes them
    clickable.
  - **Images**: render alt text + the URL as a styled placeholder (no network
    fetch in Phase 1 — keep it offline/native; inline image loading is a later
    enhancement, explicitly out of scope here).
  - **Thematic breaks (`---`)**: a full-width rule (a styled line run).
  - **GFM tables**: rendered as monospace, aligned columns using tab stops and
    column-width measurement; header row bold; column alignment honored. (Tables
    are the fiddliest block; acceptable to start with a simple fixed/tabbed
    layout and refine.)
- No `NSApp.appearance` assumptions — the caller passes `isDark` from
  `view.effectiveAppearance.isDark` (the editor reads appearance per-view;
  `AppDelegate` never sets `NSApp.appearance`).

### 2. Preview pane in `EditorViewController`

`Sources/MeditKit/EditorViewController.swift`

- New stored, **per-tab** state and views (NOT a global `Preferences` flag —
  preview only makes sense per Markdown document):
  ```swift
  private var isShowingPreview = false
  private var previewScrollView: NSScrollView!     // lazily created
  private var previewTextView: NSTextView!         // isEditable=false, isSelectable=true, drawsBackground
  ```
- `previewScrollView` is added to the same `container` and constrained to the
  **identical band as the editor `scrollView`**: top → `bar.bottomAnchor`
  (`:164-166`), bottom → `statusBar.topAnchor` (`:206`), leading/trailing to
  container. The toggle swaps `scrollView.isHidden` ⇆ `previewScrollView.isHidden`.
  The reload banner, find bar, and status bar stay put.
- New methods (mirroring `applyShowInvisibles` at `:515-518`):
  ```swift
  public func showPreview(_ show: Bool)   // build pane lazily, render, swap isHidden
  public var isPreviewVisible: Bool { isShowingPreview }
  private func renderPreview()            // build Theme from current font/colors/appearance, set previewTextView attributed string
  ```
- **Render triggers:** `renderPreview()` always runs when entering preview
  (`showPreview(true)`), on `reloadFromDocument()` (`:257-263`) while preview is
  visible, and on the appearance-KVO (`:379-385`) / `preferencesChanged`
  (`:410-440`) hooks while visible (theme/font flips re-render).
  **When `Preferences.autoRefreshPreview` is true (default):** it *also* re-renders
  (debounced ~0.15s, mirroring `SyntaxHighlightingController.scheduleHighlight`
  `:73-78`) on `textDidChange` (`:689-697`) — buffer changes — and after an
  external-change auto-reload — disk changes. When the pref is false, the preview
  is a static snapshot (entry + reload + theme only). The debounce field
  (`previewRefreshWorkItem`) lives on `EditorViewController`.
- Theme built from the same accessors the editor uses: `Preferences.fontName`/
  `fontSize` with the `NSFont(name:size:) ?? .monospacedSystemFont` fallback
  (`configureFont()` `:270-276`), `EditorColors.foreground`, `.textBackgroundColor`,
  and `view.effectiveAppearance.isDark`.

### 3. Toggle wiring (mirror `toggleInvisibles`)

- **Menu** (`MainMenu.swift`, View menu after the rainbow item `:224`):
  ```swift
  let preview = NSMenuItem(title: "Show Markdown Preview",
      action: #selector(EditorWindowController.toggleMarkdownPreview(_:)), keyEquivalent: "V")
  preview.keyEquivalentModifierMask = [.command, .shift]   // ⇧⌘V
  ```
  (Distinct selector name — avoid AppKit-collision pitfalls noted at
  `EditorWindowController.swift:270-274`.)
- **Window controller** (`EditorWindowController.swift`, mirror `toggleInvisibles`
  `:330-333`):
  ```swift
  @IBAction public func toggleMarkdownPreview(_ sender: Any?) {
      guard let editor else { return }
      editor.showPreview(!editor.isPreviewVisible)
  }
  ```
- **`validateMenuItem`** (`:343-365`): add a case that (a) sets `.on/.off` from the
  front editor's `isPreviewVisible`, and (b) **returns `false` (disabled) unless
  `document?.highlightLanguage == "markdown"`** — so the item is greyed out for
  non-Markdown files. `highlightLanguage` already covers `.md`/`.markdown`
  extension, manual language override, and markdown shebang (`TextDocument.swift:252-254`).

---

## What the user sees

- Open a `.md`/`.markdown` file → **View ▸ Show Markdown Preview** (⇧⌘V) is
  enabled. Trigger it → the editor pane is replaced by the rendered document;
  the menu item shows a checkmark. Trigger again → back to the raw editor.
- For non-Markdown files the item is disabled (greyed).
- Preview matches the editor’s font, colors, and light/dark appearance.
- The preview is read-only and selectable; links are clickable.

## Auto-refresh preference

New global pref in `Preferences.swift` (mirrors the existing Bool accessors at
`:124-197`):

```swift
public var autoRefreshPreview: Bool   // default true; registered in registerDefaults()
```

- **Default ON.** When on, an open preview stays current from both the editor
  buffer (debounced `textDidChange`) and the file on disk (after the external-
  change auto-reload path runs). When off, the preview only refreshes on entry,
  on explicit document reload, and on theme/font change.
- **Disk source:** reuse the existing external-change machinery
  (`externalChangePolicy`, the reload banner, `documentTextDidReload()` →
  `reloadFromDocument()`). `reloadFromDocument()` already re-renders the preview
  when visible (above), so external reloads refresh the preview for free; the
  auto-refresh pref only governs whether a *clean* external change reloads
  silently vs. via the existing notify/prompt policy. Phase 1 keeps the existing
  `externalChangePolicy` semantics and simply ensures the preview re-renders
  whenever a reload occurs.
- **Settings control:** add an **"Auto-refresh preview"** checkbox to the Settings
  window (likely a new short **"Markdown"** section, or under Editor), wired like
  the other checkboxes, **with a tooltip** per the 1.6 rule
  (e.g. `Keep the Markdown preview up to date as you edit or the file changes`).
  The `PreferencesTooltipTests` guard will require the tooltip automatically.

## Out of scope for Phase 1 (explicit)

- **Editing in the preview** (typing into the rendered view) → Phase 2. (Phase 1’s
  preview is read-only; live *re-render* of the read-only preview IS in Phase 1
  via the auto-refresh toggle.)
- **Style/formatting bar** → Phase 3.
- **Source ↔ preview scroll sync** → later (Phase 2 candidate).
- **Network image loading** — Phase 1 shows alt text + URL placeholder only.
- Preview *visibility* state is **not** persisted across launches (per-tab,
  ephemeral). The `autoRefreshPreview` pref **is** persisted (it’s a global
  Preference).

## Testing

- **`MarkdownRendererTests`** (headless, the core coverage): for each GFM block
  and inline element, assert the rendered `NSAttributedString` carries the
  expected attributes over the expected ranges — heading font size/bold,
  list indent (`NSParagraphStyle.headIndent`), code-block background + monospace,
  blockquote indent, emphasis→italic, strong→bold, strikethrough style, link URL
  attribute, table header bold, task-list marker glyphs. Pure value tests, no UI.
- **`EditorSmokeTests`** additions (mirror `testToggleLineNumbersAndWrapDoNotCrash`
  `:434-442`): toggling preview on a Markdown document doesn’t crash; the
  preview pane becomes visible and the editor scroll view hides; toggling back
  restores the editor. Plus a gating test: the toggle is a no-op / disabled for a
  non-Markdown document (mirror `testManualLanguageOverrideWinsOverDetection`
  `:648-658`).
- **Test hooks** on `EditorViewController` (mirror existing `…ForTesting`
  pattern): `isPreviewVisibleForTesting`, `previewAttributedStringForTesting`,
  `togglePreviewForTesting()`.
- **AutoPilot** plan (after the unit work): open a fixture `.md`, ⇧⌘V, assert the
  preview pane appears (a new AX-identified preview text view), ⇧⌘V back.

## Dependency

- Add `https://github.com/apple/swift-markdown` to `Package.swift` (the project’s
  2nd dependency, after HighlighterSwift). Product `Markdown`. Pin a released
  version. Transitively pulls cmark-gfm (C) — acceptable; it is Apple’s own
  reference GFM parser and the native choice for full-GFM scope.

## File structure

- **Create:** `Sources/MeditKit/MarkdownRenderer.swift`,
  `Tests/MeditKitTests/MarkdownRendererTests.swift`.
- **Modify:** `Sources/MeditKit/EditorViewController.swift` (preview pane +
  methods + render hooks + debounced auto-refresh), `Sources/MeditKit/EditorWindowController.swift`
  (`toggleMarkdownPreview` + `validateMenuItem` case), `Sources/MeditKit/MainMenu.swift`
  (View-menu item), `Sources/MeditKit/Preferences.swift` (`autoRefreshPreview`),
  `Sources/MeditKit/PreferencesWindowController.swift` (Auto-refresh checkbox +
  tooltip), `Package.swift` (dependency),
  `Tests/MeditKitTests/EditorSmokeTests.swift` (toggle + gating + auto-refresh
  tests), `Tests/MeditKitTests/PreferencesTests.swift` (autoRefreshPreview
  default).

## Versioning

- This is the start of **v2**. Phase 1 ships as its own release once complete
  (version number — e.g. 2.0.0 — confirmed at ship time).
