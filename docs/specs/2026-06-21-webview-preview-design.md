# Markdown Preview via WKWebView — Design

**Date:** 2026-06-21
**Status:** Approved (researched + spiked)
**Supersedes:** all prior table-rendering specs
(`2026-06-20-selectable-markdown-tables`, `2026-06-21-nstexttable-rewrite`,
`2026-06-21-scrollable-table-subview`). Those fought `NSTextTable`/TextKit limits.

## Why this exists

The Markdown **preview** has been rendered with TextKit (`NSTextView` +
`NSAttributedString` + a custom `NSLayoutManager`), and tables with `NSTextTable`.
This caused a long string of problems — multi-column wrap gaps, copy/AX fragility,
no horizontal scroll, words splitting at narrow widths, asymmetric code boxes —
each a hand-reimplementation of something browsers do for free.

**Research finding:** the Markdown editors that "just work" (MacDown, Typora,
Marked, most others) **don't use TextKit for the preview** — they render **HTML in a
`WKWebView`**. In a web view, tables are `<table>` + CSS: wrapping, growing,
`overflow-x: auto` scrolling, selectable cells, copy, and never-split word-wrapping
are all browser-native. `NSTextTable` is a limited, half-abandoned API; we should
stop fighting it.

## Goal

Render the read-only Markdown **preview** as **HTML + CSS in a `WKWebView`**, so
tables (and code blocks, blockquotes, lists, inline code, links, images) render
correctly and consistently with near-zero custom layout code. The **editor** stays
an `NSTextView` (unchanged); only the preview changes.

## Scope

- **In:** the on-screen Markdown preview (`EditorViewController.renderPreview` and
  the preview view it builds).
- **Out (unchanged):** the editor text view; document model; syntax highlighting of
  the editor.
- **Print:** keep `MarkdownPrinter`'s existing path for now (it already prints
  correctly via the static image renderer). A later step could print the web view,
  but that's not required here.

## Spike findings

- `WKWebView` is available (no WebKit dependency added before; clean import).
- `loadHTMLString(_:baseURL: nil)` loads an HTML string with no file-system access —
  **sandbox-safe** (medit is sandboxed; this avoids file:// access entirely).
- A table HTML string loads and renders (spike confirmed the web view finished
  loading the HTML; JS round-trip needs a real app runloop, available in-app).

## Architecture

```
EditorViewController
  ├─ editor NSTextView (unchanged)
  └─ preview: WKWebView (read-only)
       loads loadHTMLString(htmlDocument(markdown), baseURL: nil)

MarkdownHTMLRenderer (new)
  swift-markdown Document → HTML body string (MarkupVisitor, parallel to the
  existing AttributedStringBuilder)

PreviewHTMLTemplate (new)
  wraps the body in <html><head><style>…theme CSS…</style></head><body>…</body>
  CSS provides: table styling (CBB steel header, borders, padding, overflow-x:auto),
  inline-code chips, code blocks, blockquote bar, headings, links, light/dark.
```

### `MarkdownHTMLRenderer` — `Sources/MeditKit/MarkdownHTMLRenderer.swift`

- `func renderBody(_ markdown: String) -> String` — parse with `Document(parsing:)`
  and walk with an HTML `MarkupVisitor` that emits HTML for each node:
  headings, paragraphs, emphasis/strong, inline code (`<code>`), code blocks
  (`<pre><code>` with the language class), blockquotes, lists (ordered/unordered,
  task list checkboxes), tables (`<table><thead>/<tbody>`), links, images,
  thematic breaks, hard breaks.
- **HTML-escape** all text content (`& < > "`), so document text can't inject markup.
- Mirror the existing renderer's behavior (it's the same AST); reuse the cell/inline
  logic conceptually.

### `PreviewHTMLTemplate` — `Sources/MeditKit/PreviewHTMLTemplate.swift`

- `func htmlDocument(body: String, theme: PreviewTheme) -> String` — wraps the body
  with a `<style>` block. CSS, derived from the theme (dark/light):
  - **Tables:** `border-collapse`, thin border (`separator`), cell padding ~9px;
    header row `background: #4a9fc8` (Cold Bore Steel), `color: #0a2351`
    (Cold Bore Blue), `text-align:center`, bold; **wrap the table in a
    `div { overflow-x: auto }`** so a too-wide table scrolls horizontally (the whole
    point — free in CSS, no word-splitting). `table { width: max-content; max-width:
    100% }` → grows to content, caps at viewport, scrolls past that.
  - **Inline code:** `code { background; border-radius:4px; padding:1px 5px }` — a
    tight, vertically-symmetric chip (CSS handles the box; no baseline hacks).
  - **Code blocks:** `pre` panel with background + padding + horizontal scroll.
  - **Blockquote:** left border bar. **Headings:** sizes + bottom rule for h1/h2.
  - **Body:** system font, comfortable line-height, reading margins.
  - **Selection/copy:** native (web view text is selectable + copyable by default).
- `enum PreviewTheme` or reuse colors: pass `isDark` + the CBB hexes.

### `EditorViewController` preview

- Replace the preview `NSScrollView`+`NSTextView` (+ `MarkdownPreviewLayoutManager`)
  with a `WKWebView` pinned to the same band, `isHidden` toggled by `showPreview`.
- `renderPreview()`:
  `webView.loadHTMLString(template.htmlDocument(body: htmlRenderer.renderBody(currentText), theme: ...), baseURL: nil)`.
- Debounced refresh stays (`schedulePreviewRefresh`).
- The web view is read-only: disable editing/right-click-reload nuances as needed;
  links open in the default browser (intercept navigation, open external URLs via
  `NSWorkspace`, cancel in-web navigation) — or keep simple (no navigation) for v1.
- **Delete** the TextKit preview machinery used only by the preview:
  `MarkdownRenderer` (attributed-string), `MarkdownPreviewLayoutManager`,
  `MarkdownTableBuilder`, `MarkdownTableView`, `MarkdownTableAttachment` — *if* not
  used by print. Print currently uses `MarkdownRenderer(.static)` +
  `MarkdownTableRenderer` + `MarkdownPreviewLayoutManager`; **keep those for print**
  and only remove the table-subview pieces (`MarkdownTableView`,
  `MarkdownTableAttachment`, `MarkdownTableBuilder`) that the web view replaces.

### Print (unchanged this step)

`MarkdownPrinter` keeps using `MarkdownRenderer(.static)` + the image table renderer
+ `MarkdownPreviewLayoutManager`. So those files stay. (Future: print the web view
via `WKWebView` PDF/print APIs — out of scope.)

## Theming / light-dark

The web view CSS is generated from the current appearance (`view.effectiveAppearance.isDark`)
and re-rendered on appearance change (the existing `renderPreview` appearance hook).
CBB colors come from `CBBColors`. The web view background is set to match the
preview surface so there's no white flash.

## Security / sandbox

- `loadHTMLString(baseURL: nil)` — no file access, sandbox-safe.
- All document text is HTML-escaped → no markup/script injection from file content.
- No remote loads for v1 (images with remote URLs: allow or disable — **disable
  remote image loads in v1** to avoid network/sandbox surprises; local data-URI or
  skip). Decision: render `<img>` for the alt text / a placeholder in v1; revisit.
- Disable JavaScript in the web view (`configuration.preferences` / content rules) —
  the preview needs no JS; disabling it removes a class of risk.

## Testing

Unit (pure, no web view):
- `MarkdownHTMLRenderer.renderBody` emits expected HTML for: heading, paragraph,
  bold/italic, inline code, code block (with language class), blockquote, ordered/
  unordered/task lists, **table (thead/tbody, cell text)**, link (href), thematic
  break. HTML-escaping of `& < > "` in text.
- `PreviewHTMLTemplate.htmlDocument` includes the table CSS (overflow-x), the steel
  header colors, and the dark/light body colors.

Behavioral (AP + visual):
- The **gap-bug table**: renders with proper columns, wraps cleanly, **scrolls
  horizontally** in a narrow window (no word-split, no truncation) — the acceptance
  test that defeated every TextKit approach.
- Simple table: compact, no scrollbar.
- Inline code: symmetric chip. Code block, blockquote, lists render.
- Selection + copy of a table cell works (native web-view selection).
- Light + dark.
- Print still works (unchanged path).

## Files

- **Create:** `Sources/MeditKit/MarkdownHTMLRenderer.swift`,
  `Sources/MeditKit/PreviewHTMLTemplate.swift`,
  `Tests/MeditKitTests/MarkdownHTMLRendererTests.swift`,
  `Tests/MeditKitTests/PreviewHTMLTemplateTests.swift`.
- **Modify:** `Sources/MeditKit/EditorViewController.swift` (preview = WKWebView),
  `Package.swift` only if WebKit needs linking (it's a system framework — usually
  just `import WebKit`).
- **Delete (preview-only TextKit table pieces):** `MarkdownTableView.swift`,
  `MarkdownTableAttachment.swift`, `MarkdownTableBuilder.swift` + their tests; the
  inline-code box path + table drawing in `MarkdownPreviewLayoutManager.swift` (if
  the LM is no longer used by the preview — but it's still used by **print**, so keep
  the LM and its code-panel/quote/rule drawing for print).
- **Keep (print path):** `MarkdownRenderer.swift` (`.static`),
  `MarkdownTableRenderer.swift`, `MarkdownPrinter.swift`,
  `MarkdownPreviewLayoutManager.swift`.

## Risks

- **WKWebView load latency / flespecially first load** — debounce + reuse a single
  web view per preview (don't recreate). Set the web view background to the theme
  surface to avoid white flash.
- **swift-markdown HTML coverage** — write our own visitor (full control) rather than
  rely on the library's limited `HTMLFormatter`.
- **Editor parity** — the preview will look different from the TextKit version
  (it's a browser). That's expected and the point; verify it looks good.
- **Scope creep** — keep print on its existing path; don't rewrite everything.

## Out of scope

- Printing via the web view.
- Editing in the preview; live cursor sync; scroll-position sync.
- Remote image loading; JavaScript in the preview.
