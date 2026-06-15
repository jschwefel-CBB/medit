# medit 1.1.0 — PC-standard Home / End / Insert keys

## Goal

Make medit's Home, End, and Insert keys behave the way they do on
Windows/Linux (non-Apple) systems, including modifier combinations. macOS
defaults differ significantly (Home/End jump to start/end of document; there is
no overwrite mode), so this is a deliberate behavioral change, exposed as a
preference that is **on by default**.

## Behavior

When the "PC-style navigation keys" preference is ON:

### Home / End

| Combo | Action |
|-------|--------|
| Home | caret → first character of the **visual line** |
| End | caret → last character of the visual line |
| Shift+Home | extend selection to line start |
| Shift+End | extend selection to line end |
| Ctrl+Home | caret → start of document |
| Ctrl+End | caret → end of document |
| Ctrl+Shift+Home | extend selection to document start |
| Ctrl+Shift+End | extend selection to document end |

"Visual line" means the line as displayed. For an unwrapped document this is the
logical line (between newlines). When word wrap is on, Home/End act on the
displayed (wrapped) line fragment the caret is in — matching what the user sees.

### Insert

| Combo | Action |
|-------|--------|
| Insert | toggle insert ↔ overwrite mode |
| Shift+Insert | paste |
| Ctrl+Insert | copy |

In **overwrite mode**, typing a character replaces the character to the right of
the caret (within the current line) instead of inserting; at end-of-line it
appends normally. The caret is drawn as a **block** to signal overwrite mode.

### State and preference

- Overwrite mode is **per-window** and **resets to insert on launch**. It is not
  persisted.
- "PC-style navigation keys" is a **Preference, default ON**. When OFF, Home/End
  fall back to macOS-native behavior (document start/end) and the Insert key is
  not specially handled (overwrite mode is unavailable).

## Architecture

Three focused units.

### 1. `KeyboardNavigator` (new, pure logic — fully unit-tested)

The testable core. No AppKit drawing or view state. Given the text, the current
selection, and a decoded key command, it returns the resulting selection range.

```
enum NavCommand { case lineStart, lineEnd, docStart, docEnd }

KeyboardNavigator.newSelection(
    in text: String,
    current: NSRange,        // current selection (caret if length 0)
    command: NavCommand,
    extend: Bool,            // true = Shift held: keep anchor, move active end
    lineRangeProvider: (NSRange) -> NSRange   // injected: logical or visual line range
) -> NSRange
```

- For line commands, the caller injects how to find the current line's range
  (logical line via `NSString.lineRange(for:)`, or visual-line range via the
  layout manager when wrap is on). This keeps `KeyboardNavigator` free of AppKit
  while still supporting wrapped lines.
- `extend == true` keeps the selection anchor and moves the active end (Shift).
- `extend == false` collapses to a caret at the target.
- Boundary math (empty document, empty line, last line without trailing newline,
  caret already at target) lives here and is tested exhaustively.

### 2. `EditorTextView: NSTextView` (new)

The only place that touches AppKit key handling and drawing.

- `keyDown(with:)`: when PC-nav is enabled and the event is Home
  (`NSHomeFunctionKey`), End (`NSEndFunctionKey`), or Insert
  (`NSInsertFunctionKey`), handle it; otherwise call `super` so all other keys
  behave normally.
- Home/End: decode modifiers → `NavCommand` + `extend`; obtain the line-range
  provider (visual when `textContainer.widthTracksTextView`, else logical); call
  `KeyboardNavigator`; apply with `setSelectedRange(_:)` and
  `scrollRangeToVisible(_:)`.
- Insert: toggle `isOverwriteMode`; Shift+Insert → `paste(_:)`; Ctrl+Insert →
  `copy(_:)`.
- Overwrite typing: override `insertText(_:replacementRange:)`. When
  `isOverwriteMode`, the caret is collapsed, and not at end-of-line, set the
  replacement range to the one character to the right so the new text overwrites
  it. Routed through `shouldChangeText`/`didChangeText` so undo and the
  highlighter behave.
- Block caret: override `drawInsertionPoint(in:color:turnedOn:)` to fill a
  character-width rect when `isOverwriteMode`; otherwise call `super`.
- `isOverwriteMode` is a stored property, default `false`, per instance (per
  window). Changing it triggers a caret redraw.

### 3. `Preferences` (existing — extend)

Add `pcStyleNavigationKeys: Bool` (default `true`), following the exact pattern of
`wrapLines` / `showLineNumbers` (registered default + change notification). Add a
checkbox to the Preferences window. `EditorTextView` reads it (and reacts to the
change notification, like the editor already does).

## Editor integration

`EditorViewController.loadView()` currently builds the editor via
`NSTextView.scrollableTextView()`. To use `EditorTextView`, replicate the
factory's known-good setup (the recipe that fixed the earlier invisible-text bug)
but instantiate `EditorTextView` for the document view:

- Create the `NSScrollView`, create the `EditorTextView` with the content-size
  frame, configure `minSize`/`maxSize`/resizable flags and the text container
  exactly as the factory does, then `scrollView.documentView = editorTextView`.
- This is the one risky spot (hand-assembling the text view). It is covered by
  the existing editor smoke tests (text renders, ruler doesn't cover it, find bar
  reserves no space) plus a new "text is visible with EditorTextView" assertion,
  all run headlessly so the developer's live window is never touched.

## Testing

- **`KeyboardNavigatorTests`** (pure, like `TextSearchTests`): every combo —
  Home/End plain, +Shift, +Ctrl, +Ctrl+Shift — across cases: middle of line,
  already at line start/end, empty line, first/last line, empty document,
  multi-line selection collapse, document boundaries. Injects a logical
  line-range provider so it runs without AppKit.
- **Editor smoke tests** (headless, existing harness): the editor still renders
  with `EditorTextView`; overwrite mode replaces the right-hand character;
  toggling overwrite flips the flag and requests a caret redraw without crashing.
- All tests run via `swift test` — no app launch, no interference with a running
  instance.

## Out of scope

- Remapping any keys other than Home/End/Insert.
- Persisting overwrite mode across launches.
- Changing macOS-native behavior of other navigation keys (PageUp/Down,
  arrows, etc.).

## Release

Ships as **medit 1.1.0** (new backward-compatible feature, SemVer minor). Bump
`CFBundleShortVersionString` and `MARKETING_VERSION` to 1.1.0; tag `v1.1.0` after
implementation and verification.
