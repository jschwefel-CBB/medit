# medit v2 — Markdown support, Phase 3: Style Bar (design)

**Goal:** A formatting toolbar for Markdown documents. Clicking a button wraps or
prefixes the current selection/line with the corresponding Markdown syntax (and
toggles it off if already applied). You still edit the raw `.md` source; the bar
writes the syntax so you don't have to type it.

**Phase 2 (source syntax-highlighting / split view) was skipped** per the user.

## Scope

- A horizontal **style bar** across the top of the editor (above the reload
  banner), shown **only for Markdown documents** (gated on
  `document?.highlightLanguage == "markdown"`), collapsing to zero height
  otherwise — mirrors the find-bar show/hide pattern.
- Buttons (first cut): **Bold, Italic, Strikethrough, Inline code, Link**
  (inline wrap/unwrap), and **Heading, Bullet list, Numbered list, Quote, Code
  block** (line prefix/wrap). Each is a toggle: applying when not present,
  removing when already present.
- Operates on the live `NSTextView` via its text storage + selection, using the
  undo manager so every action is a single undoable edit.
- A View-menu toggle ("Show Markdown Toolbar") + a pref to remember visibility.

## Architecture

Three units:

### 1. `MarkdownEditing` (pure logic — fully testable, the bulk)

`Sources/MeditKit/MarkdownEditing.swift`

Pure string transforms over `(text, selectedRange)` → `(newText, newSelectedRange)`.
No AppKit. Each returns the edited string and where the selection should land.

```swift
public enum MarkdownEditing {
    public struct Edit: Equatable {
        public var text: String
        public var selectedRange: NSRange
    }
    // Inline: wrap selection in `marker` (e.g. "**"); if already wrapped, unwrap.
    public static func toggleInline(_ text: String, _ range: NSRange, marker: String) -> Edit
    // Link: wrap selection as [sel](url) with caret placed in the url slot.
    public static func insertLink(_ text: String, _ range: NSRange) -> Edit
    // Line prefix: prepend `prefix` (e.g. "# ", "> ", "- ") to each selected line;
    // remove it if every selected line already has it. Ordered lists number 1., 2.…
    public static func toggleLinePrefix(_ text: String, _ range: NSRange, prefix: LinePrefix) -> Edit
    // Fenced code block: wrap selected lines in ``` fences (toggle).
    public static func toggleCodeBlock(_ text: String, _ range: NSRange) -> Edit
}
```

`LinePrefix` covers `heading(level)`, `bullet`, `ordered`, `quote`.

**Toggle semantics (so a second click undoes):**
- Inline: if the selection is already surrounded by `marker` (inside or just
  outside), remove it; else wrap. Empty selection → insert the marker pair with
  the caret between (`**|**`).
- Line prefix: compute the affected line range; if ALL non-empty lines already
  start with the prefix, strip it; else add it. Selection expands to cover the
  edited lines.

### 2. `MarkdownStyleBar` (the view)

`Sources/MeditKit/MarkdownStyleBar.swift` — an `NSView` (height ~28) with an
`NSStackView` of `NSButton`s (SF Symbols: `bold`, `italic`, `strikethrough`,
`curlybraces`/`chevron.left.forwardslash.chevron.right` for code, `link`,
`textformat.size` for heading, `list.bullet`, `list.number`, `text.quote`,
`curlybraces.square` for code block). Each button calls a delegate action. AX
identifiers on each (`mdStyle.bold`, …) for tests/AutoPilot. Collapses to 0
height when hidden (like `FindReplaceBar`).

```swift
public protocol MarkdownStyleBarDelegate: AnyObject {
    func styleBar(_ bar: MarkdownStyleBar, didInvoke action: MarkdownStyleBar.Action)
}
public final class MarkdownStyleBar: NSView {
    public enum Action { case bold, italic, strikethrough, code, link,
                              heading, bullet, ordered, quote, codeBlock }
}
```

### 3. Wiring in `EditorViewController`

- Add `markdownStyleBar` + `styleBarHeightConstraint` to the container, pinned at
  the **top** (above the reload banner; banner's top now meets the style bar's
  bottom). Show/hide by toggling the height constraint (0 ↔ 28) + `isHidden`,
  exactly like the find bar.
- Visibility: shown when the doc is Markdown AND the pref `showMarkdownToolbar`
  is on. Re-evaluated on load, language change, and `preferencesChanged`.
- The delegate maps each `Action` to a `MarkdownEditing` call, applies it to the
  text view through the undo manager:
  ```swift
  let edit = MarkdownEditing.toggleInline(tv.string, tv.selectedRange(), marker: "**")
  tv.shouldChangeText(in: NSRange(location: 0, length: (tv.string as NSString).length), replacementString: edit.text) // register undo
  tv.textStorage?.replaceCharacters(in: fullRange, with: edit.text)
  tv.didChangeText()
  tv.setSelectedRange(edit.selectedRange)
  ```
  (Use the minimal changed sub-range where practical so undo is tight and the
  syntax highlighter doesn't reflow the whole document.)

## Menu + preference + Settings

- `Preferences.showMarkdownToolbar` (Bool, default **true**).
- View-menu item **"Show Markdown Toolbar"** → `EditorWindowController.toggleMarkdownToolbar(_:)`,
  with a `validateMenuItem` checkmark, **gated/disabled for non-Markdown docs**.
- Settings checkbox under the **Markdown** section ("Show formatting toolbar"),
  with a tooltip + ⓘ help (the existing guards require both).

## Out of scope (Phase 3)

- Source-side syntax highlighting / split view (was Phase 2 — skipped).
- Table builder UI, image insert dialog — the first cut wraps/prefixes text only;
  a `Table`/`Link`-with-dialog can come later.
- WYSIWYG hiding of the syntax markers (the bar writes literal Markdown; markers
  stay visible — consistent with "direct editing using Markdown syntax").

## Testing

- **`MarkdownEditingTests`** (headless, the core): for each transform, assert the
  resulting text and selection — wrap, unwrap (toggle off), empty-selection
  caret placement, multi-line prefix add/remove, ordered-list numbering, code
  block toggle. Pure value tests.
- **`EditorSmokeTests`**: the style bar shows for a Markdown doc and is
  hidden/zero-height for a non-Markdown doc; invoking an action through the
  controller changes the document text as expected; toggling the View-menu item
  flips visibility.
- **AutoPilot** plan: open a `.md`, select text, click `mdStyle.bold`, assert the
  editor value gained `**…**`.

## File structure

- **Create:** `Sources/MeditKit/MarkdownEditing.swift`,
  `Sources/MeditKit/MarkdownStyleBar.swift`,
  `Tests/MeditKitTests/MarkdownEditingTests.swift`.
- **Modify:** `EditorViewController.swift` (bar + wiring + actions),
  `EditorWindowController.swift` (toggle + validateMenuItem),
  `MainMenu.swift` (View-menu item), `Preferences.swift`
  (`showMarkdownToolbar`), `PreferencesWindowController.swift` (Settings
  checkbox), `EditorSmokeTests.swift`.

## Versioning

Ships as **2.1.0** (additive minor) when complete.
