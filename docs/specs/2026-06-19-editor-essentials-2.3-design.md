# medit 2.3 — Editor Essentials (design)

Four independent gap-analysis features, shipped together as **2.3.0**. Each has a
pure, testable core. Built in priority order.

1. **Session restore** — reopen the last session's files on launch.
2. **Word count** — live document statistics in the status bar.
3. **Sort Lines + Change Case** — Edit-menu text transforms.
4. **Column/block editing** — rectangular selection → multi-row edit (great for
   scraping aligned terminal output).

---

## 1. Session restore (reopen last files)

**Problem:** medit only restores the window *frame*; 2.3's predecessor (2.2.0) set
`window.isRestorable = false` to stop a window-position tug-of-war, which also
disabled macOS's reopen-last-documents. Net: launching medit no longer brings back
the files you had open.

**Approach (B): own it via a pref** — don't re-enable AppKit restoration (that
reintroduces the frame conflict). Persist the open document URLs ourselves and
reopen them on launch. Deterministic, no AppKit fight, mirrors the existing
`windowFrame` pattern.

- New pref `Preferences.reopenLastSession: Bool` (default **true**) and
  `Preferences.lastSessionFiles: [String]` (file paths).
- **Tracking:** maintain the open-file list as documents open/close. Simplest
  reliable source: on app deactivation/termination and whenever a document opens or
  closes, write the current set of `TextDocument.fileURL`s (skip untitled) to
  `lastSessionFiles`. A small `SessionStore` (pure-ish, testable) owns dedupe +
  persistence, like `RecentFilesStore`.
- **Restore:** in `applicationDidFinishLaunching`'s deferred block, BEFORE
  `openUntitledIfNoDocuments`: if `reopenLastSession`, no files were opened at
  launch, nothing was restored, and `lastSessionFiles` is non-empty → open them
  (via the same `openFiles` path), then skip the untitled-open. Guard so it runs
  once.
- **`--reset-state`**: skip restore entirely (the test driver must start blank).
- Settings checkbox under a "General"/"Startup" area: "Reopen last session's files
  at launch" (+ tooltip + ⓘ help).
- Files that no longer exist are silently skipped on reopen.

**Tests:** `SessionStoreTests` (record/dedupe/persist/clear, skip untitled);
`AppDelegate`-level smoke that restore is gated on the pref + `--reset-state`.

## 2. Word count / document statistics (status bar)

A live count of **characters, words, and lines** (and selection count when there's
a selection), shown in the status bar.

- Pure `TextStatistics` enum: `func counts(for text: String, selection: NSRange)
  -> (chars: Int, words: Int, lines: Int, selChars: Int, selWords: Int)`.
  - Words: Unicode-aware split on whitespace/newlines, ignoring empty tokens.
  - Lines: number of line breaks + 1 (empty doc = 0 or 1 — define: empty = 0).
  - Chars: `(text as NSString).length` (UTF-16, matches the rest of the editor).
- `StatusBarView` gains a stats segment: e.g. `120 words · 14 lines · 842 chars`,
  switching to a selection form (`23 of 120 words selected`) when a selection
  exists. Recomputed on `textDidChange` and `selectionDidChange` (debounced/cheap;
  the doc is already in memory).
- New pref `showDocumentStats: Bool` (default true) + View-menu toggle + status-bar
  visibility honored.

**Tests:** `TextStatisticsTests` — empty, single word, multi-line, trailing
newline, selection counts, Unicode (CJK / combining marks counted sanely),
whitespace-only.

## 3. Sort Lines + Change Case (Edit menu)

Standard text munging, operating on the selected lines (or whole document if no
selection).

- Pure `TextTransforms`:
  - `sortLines(_ text:, range:, ascending:, caseInsensitive:) -> (text, range)` —
    sorts the full lines overlapping `range`; stable; preserves a trailing newline.
  - `changeCase(_ text:, range:, to: .upper/.lower/.title) -> (text, range)` —
    transforms the selection (or current word if empty selection, like AppKit's
    Transformations).
- Menu (Edit ▸ Text or a new submenu):
  - **Sort Lines Ascending**, **Sort Lines Descending**
  - **Make Upper Case**, **Make Lower Case**, **Capitalize** (title case)
  - Apply through the text view's undo manager (single undoable edit), reusing the
    same edit-application helper pattern the Markdown style bar uses.
- AX identifiers on the menu items for test/AutoPilot.

**Tests:** `TextTransformsTests` — sort asc/desc, case-insensitive sort, trailing
newline preserved, single-line no-op, change-case on selection vs empty-selection
word, title case word boundaries.

## 4. Column / block (rectangular) editing

Rectangular selection that spans rows and lets you **type / delete across all
selected rows at once** — the terminal-output-scraping tool.

**Reality check:** NSTextView provides Option-drag rectangular *selection* visually,
but does NOT give multi-row simultaneous *editing* out of the box. We implement the
editing behavior on top of a rectangular selection model.

- `ColumnSelection` model (pure, testable): given the text and a rectangular region
  expressed as (startLine, endLine, startColumn, endColumn), compute:
  - the list of per-line `NSRange`s the block covers (clamped to each line's
    length — short lines contribute an empty range at their end), and
  - the result of **inserting** a string into the block (same string on every row)
    and **deleting** the block.
- Enter column mode via a modifier-drag (Option-drag) or a menu/shortcut toggle
  ("Edit ▸ Column Selection Mode", e.g. ⌥⌘B). In column mode, `EditorTextView`:
  - tracks the rectangular region across rows,
  - draws the multi-row selection (highlight each per-line range),
  - on `insertText`, applies the string to every per-line range (bottom-up so
    offsets stay valid), as one undoable edit,
  - on delete/backspace, removes every per-line range (bottom-up),
  - caret behavior: a vertical "ribbon" caret across rows when the block is empty
    (zero width) — typing inserts on every row at that column.
- Keep it scoped: same-string-on-every-row insert + block delete + copy of the
  block (rows joined by `\n`). No per-row independent carets beyond the block (that
  would be multi-cursor, which is a deliberate non-goal).

**Tests:** `ColumnSelectionTests` — per-line ranges over uniform and ragged lines
(short lines), insert-into-block (every row gets the text; short lines padded or
inserted at end per defined rule), delete-block, copy-block text, single-line
degenerate case, empty-block (zero-width) insert across rows.

---

## Versioning & order

Ship together as **2.3.0**. Build order: (1) session restore → (2) word count →
(3) sort/case → (4) column editing. Each lands behind tests; column editing is the
largest and most AppKit-interactive (its pure model is fully tested, the
NSTextView wiring gets smoke + manual verification).

## Out of scope (still deliberate non-goals)

Multi-cursor (independent carets), minimap, macros/scripting, plugin system — all
above medit's tier (per the gap analysis), excluded by explicit decision.

## File structure

- **Create:** `SessionStore.swift`, `TextStatistics.swift`, `TextTransforms.swift`,
  `ColumnSelection.swift` (+ their test files).
- **Modify:** `Preferences.swift` (new prefs), `AppDelegate.swift` (restore on
  launch + track session), `StatusBarView.swift` + `EditorViewController.swift`
  (stats segment), `MainMenu.swift` (Sort/Case items, Column mode),
  `EditorWindowController.swift` (validateMenuItem + actions),
  `EditorTextView.swift` (column-edit behavior),
  `PreferencesWindowController.swift` (reopen-session + stats checkboxes).
