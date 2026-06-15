# medit 1.2 — Editing-comfort polish

## Goal

Add the small, gedit-expected editing conveniences that make daily use nicer:
Go to Line, a status bar, auto-indent + bracket assistance, and trailing-
whitespace hygiene. Each feature is independently useful, behind a preference or
View toggle where appropriate, and lands as its own commit.

These are the "Strong fits" tier; the "Good fits" (sidebar file browser, reload-
on-external-change, encoding/line-ending picker) are deferred to 1.3.

## Scope and commit breakdown

Six feature commits + one release commit:

1. **Go to Line** — ⌘L / ⌃G, modal sheet.
2. **Status bar** — Ln/Col, language, encoding, INS/OVR; View toggle (default on).
3. **Auto-indent + bracket matching + auto-close** — two preferences (default on);
   bracket-match highlight always on; auto-close brackets only (not quotes).
4a. **Strip trailing whitespace + ensure final newline on save** — preference,
    default on.
4b. **Show Invisibles** — View toggle, default off.
5. **Version bump to 1.2.0 + README + tag v1.2.0.**

Targets macOS 14+. All verification is headless `swift test` / scratch
`xcodebuild` — never launches or reinstalls the app (a live instance may run).

---

## Feature 1: Go to Line

### Behavior
- A small modal sheet attached to the active editor window: one number field,
  **Go** (default button, Return) and **Cancel** (Esc).
- On Go: parse the integer. If it's a valid 1-based line (`1...lineCount`), move
  the caret to the **start of that line**, `scrollRangeToVisible`, and flash via
  `showFindIndicator(for:)`. Then dismiss.
- Out of range (≤ 0, > line count) or non-numeric → **NSSound.beep()**, no-op,
  and the sheet stays open to let the user correct the value.

### Menu
- One **Edit → Go to Line…** menu item showing **⌘L** as its key equivalent
  (⌘L is currently unused; Show Line Numbers is ⇧⌘L).
- **⌃G** also triggers the action without a duplicate menu item: catch it in the
  responder chain (e.g. the editor's `keyDown`/`performKeyEquivalent` recognizes
  ⌃G and calls the same `goToLine(_:)`), keeping the menu clean.
- Action routed to `EditorViewController` via the responder chain (like the
  existing find actions).

### Logic (pure, tested)
- `TextLocator.characterIndex(forLine line: Int, in text: String) -> Int?` —
  returns the UTF-16 offset of the start of 1-based `line`, or `nil` if out of
  range. Mirrors the existing `TextSearch.lineNumber(for:in:)` style.
- Tests: line 1, a middle line, the last line, last line of a file with/without
  a trailing newline, line 0/negative → nil, line > count → nil, empty document
  (line 1 → 0, line 2 → nil).

### Files
- Create `Sources/MeditKit/TextLocator.swift` + `Tests/.../TextLocatorTests.swift`.
- Create `Sources/MeditKit/GoToLineSheet.swift` (the sheet controller/view).
- Modify `EditorViewController.swift` (the `@objc goToLine(_:)` action + present).
- Modify `MainMenu.swift` (Edit menu items).

---

## Feature 2: Status bar

### Layout
The editor container currently stacks `[find/replace bar] / [scroll view]`. Add a
status bar pinned at the bottom: `[find/replace bar] / [scroll view] / [status bar]`.

### Contents (left → right)
`Ln 12, Col 4`  ·  `Swift` (or `Plain Text`)  ·  `UTF-8`  ·  `INS` (or `OVR`).
Position left-aligned; language/encoding/mode trailing.

### Live updates
- **Ln/Col**: recomputed on selection change (`textViewDidChangeSelection`) and on
  edits. 1-based: line = (newlines before caret) + 1; col = caret − lineStart + 1.
- **Language**: `LanguageMap.language(forURL:)` of the document's file; "Plain
  Text" when nil (untitled/unknown).
- **Encoding**: a display name for `TextDocument.fileEncoding` (e.g. "UTF-8",
  "UTF-16", "ISO Latin-1").
- **INS/OVR**: reflects `EditorTextView.isOverwriteMode`; flips live. The editor
  notifies the status bar when overwrite mode changes.

### Toggle
- **View → Show Status Bar** menu item, default on, with checkmark validation.
- Preference `showStatusBar: Bool` (default true), same pattern as
  `showLineNumbers`/`wrapLines`.
- When off, the status bar collapses to zero height via an activated 0-height
  constraint (the same technique used for the find bar gap fix).

### Logic (pure, tested)
- `TextPosition.lineColumn(forOffset offset: Int, in text: String) -> (line: Int, column: Int)`
  — 1-based line and column. Tests: start of doc (1,1), within first line, after
  a newline (next line, col 1), end of a multi-line doc, offset clamped to length,
  empty doc.
- A small encoding→display-name mapping (can live with the status bar or in
  `TextEncodingDetector`); tested for the encodings medit detects.

### Files
- Create `Sources/MeditKit/TextPosition.swift` + `Tests/.../TextPositionTests.swift`.
- Create `Sources/MeditKit/StatusBarView.swift` (dumb display view).
- Modify `EditorViewController.swift` (host the bar, push updates, selection hook).
- Modify `EditorTextView.swift` (notify on overwrite-mode change — e.g. a callback
  closure the editor sets).
- Modify `Preferences.swift` (+ `showStatusBar`), `PreferencesTests.swift`.
- Modify `MainMenu.swift` (View → Show Status Bar) and `EditorWindowController.swift`
  (toggle action + validation, like toggleLineNumbers).

---

## Feature 3: Auto-indent + bracket matching + auto-close

All three live in `EditorTextView`. Two new preferences (default on);
bracket-match highlight is always on (subtle, read-only).

### 3a. Auto-indent (preference `autoIndent`, default on)
- On Return: compute the leaving line's leading whitespace. If that line's last
  non-whitespace character is an opener (`{` or `:`), append one indent level —
  a tab, or `tabWidth` spaces when `insertSpacesForTab` is true.
- Insert `"\n" + indent` in one `shouldChangeText`/`didChangeText` step (single
  undo). When off, Return behaves natively (super).

### 3b. Bracket-match highlight (always on)
- When the caret is adjacent to `(` `)` `[` `]` `{` `}`, find the partner via a
  depth-counting scan and briefly highlight it (a temporary background-color
  attribute removed after a short delay, or `showFindIndicator(for:)`).
- Updates on selection change. Brackets only — never quotes.

### 3c. Auto-close brackets (preference `autoCloseBrackets`, default on)
- Typing an opener `(` `[` `{` inserts the matching closer, caret left between
  them. If there is a selection, wrap it: `([{` + selection + `)]}`.
- Typing a closer `)` `]` `}` when the next character is exactly that closer
  **skips over** it (moves caret past) instead of inserting a duplicate.
- **Quotes are never auto-closed** (avoids the `don't` contraction problem). You
  type both quotes yourself; skip-over and highlight do not apply to quotes.
- Each operation is one undo step. When off, typing behaves natively.

### Logic (pure, tested)
- `Indenter.indent(forNewLineAfter line: String, tabWidth: Int, useSpaces: Bool) -> String`
  — leading whitespace + optional extra level. Tests: no indent, spaces indent,
  tab indent, line ending in `{`, line ending in `:`, trailing-whitespace-only
  line, empty line.
- `BracketMatcher.matchingOffset(in text: String, at offset: Int) -> Int?` —
  given a caret adjacent to a bracket, return the partner's offset (depth-aware),
  or nil. Tests: simple pair, nested, unbalanced (nil), caret not on a bracket
  (nil), partner before vs after caret.
- The GUI behaviors (insert pair, skip-over, highlight) are covered by headless
  smoke tests in `EditorSmokeTests` (synthesize key events / call `insertText`).

### Files
- Create `Sources/MeditKit/Indenter.swift`, `Sources/MeditKit/BracketMatcher.swift`
  + their test files.
- Modify `EditorTextView.swift` (Return handling, `insertText` pair/skip logic,
  selection-change highlight, the two pref flags).
- Modify `EditorViewController.swift` (push the prefs into the text view; react in
  `preferencesChanged`).
- Modify `Preferences.swift` (+ `autoIndent`, `autoCloseBrackets`),
  `PreferencesTests.swift`.
- Modify `PreferencesWindowController.swift` (two checkboxes).

---

## Feature 4a: Strip trailing whitespace + ensure final newline on save

### Behavior
- Preference `stripTrailingWhitespaceOnSave: Bool`, **default true**.
- The transform runs in `TextDocument.data(ofType:)` on the string **before**
  encoding — so it cleans the bytes written to disk without disturbing the live
  editor text or the caret.
- Transform: (1) remove trailing spaces/tabs from every line; (2) ensure the file
  ends with exactly one `\n` — add if missing, and collapse multiple trailing
  blank lines at EOF to a single newline.
- Consequence (acceptable, standard): immediately after save the editor text and
  the on-disk bytes can differ by the stripped whitespace; the document is not
  re-marked edited. This mirrors common editors that strip on the saved copy.

### Logic (pure, tested)
- `TextHygiene.cleaned(_ text: String, stripTrailing: Bool, ensureFinalNewline: Bool) -> String`
  — Tests: trailing spaces removed, trailing tabs removed, mixed
  trailing whitespace, interior whitespace untouched, leading indentation
  untouched, no-final-newline gets one, already-one-newline unchanged, multiple
  trailing blank lines collapse to one, empty string, content with only
  whitespace lines, CRLF line endings handled (don't corrupt `\r\n`).

### Files
- Create `Sources/MeditKit/TextHygiene.swift` + `Tests/.../TextHygieneTests.swift`.
- Modify `TextDocument.swift` (`data(ofType:)` applies the transform when the
  preference is on).
- Modify `Preferences.swift` (+ `stripTrailingWhitespaceOnSave`),
  `PreferencesTests.swift`.
- Modify `PreferencesWindowController.swift` (checkbox).

---

## Feature 4b: Show Invisibles

### Behavior
- **View → Show Invisibles** menu item, default off; preference
  `showInvisibles: Bool` (default false).
- When on, render whitespace as faint markers: space → `·` (middot), tab → `⟶`,
  with trailing whitespace emphasized. Drawn at the layout-manager level so it
  overlays without altering the document text.

### Implementation
- Subclass `NSLayoutManager` (or use the existing layout manager) and override
  `drawGlyphs(forGlyphRange:at:)` to additionally draw markers for whitespace
  glyphs in the current line fragments, using a faint color
  (`.tertiaryLabelColor`). Toggled by the `showInvisibles` flag + `needsDisplay`.

### Fallback (documented honesty)
- Rendering every space across wrapped lines while the syntax highlighter is
  setting character attributes is the fiddly part. If full-space rendering
  interacts badly with the highlighter or wrapping, **reduce scope to trailing
  whitespace + tabs only** (the higher-value, less-noisy subset) rather than
  every space. This is an acceptable v1.2 outcome; note it in the commit if taken.

### Logic (pure, tested where possible)
- The "which positions are whitespace markers" decision is mostly inherent to the
  glyphs; there is little pure logic to extract. Verify via a headless smoke test
  that toggling `showInvisibles` flips the flag and triggers a redraw without
  crashing, and that the editor still renders text (guard the invisible-text
  regression).

### Files
- Create `Sources/MeditKit/InvisiblesLayoutManager.swift` (or extend the editor's
  layout manager).
- Modify `EditorViewController.swift` (install/toggle), `EditorTextView.swift` if
  the layout manager must be swapped at construction.
- Modify `Preferences.swift` (+ `showInvisibles`), `PreferencesTests.swift`.
- Modify `MainMenu.swift` / `EditorWindowController.swift` (View → Show Invisibles
  + validation).

---

## Cross-cutting: preferences & menus

New preferences (all follow the existing `Key` + `registerDefaults` + property +
`didChange()` pattern, with `PreferencesTests` coverage):

| Preference | Default | Surfaced in |
|------------|---------|-------------|
| `showStatusBar` | true | View menu + Settings (optional) |
| `autoIndent` | true | Settings checkbox |
| `autoCloseBrackets` | true | Settings checkbox |
| `stripTrailingWhitespaceOnSave` | true | Settings checkbox |
| `showInvisibles` | false | View menu |

View-menu toggles (Show Status Bar, Show Invisibles) follow the
`toggleLineNumbers` pattern in `EditorWindowController` with checkmark
validation. Settings checkboxes follow the existing `PreferencesWindowController`
pattern (property + buildUI + syncFromPrefs + checkChanged), re-anchoring the
layout as needed.

## Testing strategy

- **Pure logic** (`TextLocator`, `TextPosition`, `Indenter`, `BracketMatcher`,
  `TextHygiene`): exhaustive XCTest like `TextSearch`/`KeyboardNavigator` — these
  carry the correctness weight and run instantly, headless.
- **Editor behaviors** (auto-indent, auto-close, skip-over, overwrite, status-bar
  updates): headless smoke tests in `EditorSmokeTests` that construct a window,
  drive `insertText`/synthesized key events, and assert text/selection/flag
  outcomes — the same approach that already covers overwrite mode and the Insert
  key.
- **Render regression**: every feature that touches the editor view (status bar,
  invisibles, layout-manager changes) must keep the existing render smoke tests
  green (text visible, non-zero frame, ruler doesn't cover text, find bar reserves
  no space). This guards the invisible-text class of bug.
- All via `swift test`. No app launch in any test.

## Release

Ship as **medit 1.2.0** (backward-compatible features, SemVer minor). Final commit
bumps `CFBundleShortVersionString` and `MARKETING_VERSION` to 1.2.0, updates the
README (features + shortcuts: Go to Line, status bar, auto-indent, auto-close,
strip-on-save, Show Invisibles), then tags `v1.2.0` after verification. Tagging
and any reinstall are gated on the user (a live instance may be running).

## Out of scope (→ 1.3)

Sidebar file browser; reload-on-external-change; explicit encoding/line-ending
picker; snippets; plugins; multi-cursor; LSP/autocomplete.
