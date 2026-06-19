# medit 2.4 — Column / block editing (design)

Build the rectangular ("column"/"block") editing that was deferred from 2.3.
Genuinely useful for scraping aligned terminal output. Ships as **2.4.0**.

## Why this needs a custom model

NSTextView **collapses multiple zero-width selection ranges to a single caret** on
assignment (verified in 2.3). So "a caret on each of N rows at column C" — the
multi-insertion-point case — **cannot** be represented with NSTextView's
`selectedRanges`. Therefore `EditorTextView` must own the column state itself
(anchor, current corner, drawing, keystroke routing) while column mode is active,
independent of `selectedRanges`.

The pure `ColumnSelection` model (built + tested in 2.3) stays the foundation; we
add `replaceBlock` and `pasteBlock` to it.

## Decisions (locked)

- **Enter mode:** **Option-drag** to make a rectangular block (the macOS/Xcode/BBEdit
  convention) **plus** an **Edit ▸ Column Selection Mode** sticky toggle (⌥⌘B) for
  keyboard-only use.
- **Typed-over block (width > 0):** **replace** the rectangle with the typed text
  on every row. Backspace deletes the block.
- **Block ops:** **Copy/Cut** the block (rows joined by `\n`), and **Paste as block**
  (each clipboard line goes to a successive row at the caret column).

## Model additions (`ColumnSelection`, pure, TDD)

```swift
// Replace the block on every row with `string` (delete the rectangle, then insert
// `string` at the left column on each affected row). One operation.
static func replaceBlock(_ string: String, in text:, startLine:, endLine:, startColumn:, endColumn:) -> Edit

// Paste `clipboardLines` as a block at (startLine, column): line 0 → startLine,
// line 1 → startLine+1, … each inserted at `column` (short rows space-padded).
// If there are more clipboard lines than remaining rows, they extend downward only
// if rows exist; otherwise stop at the last line (define: stop — don't create new
// lines in the first cut).
static func pasteBlock(_ clipboardLines: [String], in text:, startLine:, column:) -> Edit
```

Reuse existing `perLineRanges` / `deleteBlock` / `insertIntoBlock` / `copyBlock`.

## View: column state on `EditorTextView`

```swift
struct ColumnBlock {
    var anchorLine: Int; var anchorColumn: Int   // where the block began
    var caretLine: Int;  var caretColumn: Int    // current moving corner
    var topLine: Int { min(anchorLine, caretLine) }
    var bottomLine: Int { max(anchorLine, caretLine) }
    var leftColumn: Int { min(anchorColumn, caretColumn) }
    var rightColumn: Int { max(anchorColumn, caretColumn) }
    var isZeroWidth: Bool { leftColumn == rightColumn }   // multi-caret case
}
private var columnBlock: ColumnBlock?      // non-nil ⇒ column mode active
private var stickyColumnMode = false       // ⌥⌘B keyboard toggle
```

**Column ↔ geometry mapping** (monospace-friendly, works for proportional too):
- `point(forLine:column:)` → use the layout manager: find the line's character
  range (`(string as NSString).lineRange` walking by line index), get the glyph at
  `lineStart + min(column, lineLen)`, `boundingRect(forGlyphRange:1)` gives x/y. For
  columns past a short line's end, extrapolate x by `column - lineLen` × advance
  width. Add `textContainerInset`.
- `lineColumn(at point:)` (hit-testing for the drag) → `characterIndex(for:)` then
  split into (line, column) via line-start offsets. For x beyond the line's text,
  compute the column from x using advance width so you can select a rectangle wider
  than the text (needed to "select to column 40" on short lines).
- A `charAdvance` helper = `font.maximumAdvancement.width` (already used by the
  overwrite caret).

**Mouse:**
- `mouseDown`: if `.option` in `event.modifierFlags` (or `stickyColumnMode`), begin
  a `columnBlock` at the hit (line, column); set `selectedRanges` to the flattened
  per-line ranges (so AppKit's own machinery is coherent) but treat `columnBlock`
  as the source of truth. Else clear `columnBlock` and call `super` (normal click
  exits column mode).
- `mouseDragged`: if a `columnBlock` is active, update `caretLine/caretColumn` from
  the hit point; redraw.
- `mouseUp`: keep the block (so you can then type).

**Keyboard (`keyDown` / `insertText` / `deleteBackward`):** only when `columnBlock`
active.
- Arrows: ↑/↓ change `caretLine` (clamped 0…lastLine); ←/→ change `caretColumn`
  (clamped ≥ 0). **Shift** extends (move only the caret corner, keep anchor); no
  Shift collapses the block to a zero-width caret at the new corner. Redraw.
- `insertText(s)`: if `isZeroWidth` → `insertIntoBlock(s,…)`; else
  `replaceBlock(s,…)`. Apply as one undoable whole-text edit; set the block to a
  zero-width caret just after the inserted text (`caretColumn = leftColumn + len`,
  on all rows top…bottom). Re-flatten `selectedRanges`.
- `deleteBackward`: if `isZeroWidth` and `leftColumn > 0` → delete the single char
  left of the column on every row (`deleteBlock` with cols `left-1…left`), caret to
  `left-1`; else (`width`) → `deleteBlock`, caret to `leftColumn`.
- `copy`: put `copyBlock(…)` on the pasteboard (and a flag/marker so paste knows it
  was a block — actually just split the clipboard on `\n` at paste time).
- `cut`: copy then `deleteBlock`.
- `paste`: `pasteBlock(clipboard.components(separatedBy: "\n"), …)` at the block's
  top-left.
- **Escape** or a plain click: exit column mode (`columnBlock = nil`,
  `stickyColumnMode = false` if it was a one-shot), collapse to a normal caret at
  the current corner.

**Drawing:** override `drawInsertionPoint` is per-caret only; instead draw the
block in `drawRect`-time via a dedicated method called from `draw(_:)` override (or
overlay): for each row top…bottom, compute the per-line rect for `left…right`
(`boundingRect`), and:
- zero-width: draw a thin vertical insertion bar at the column x on each row
  (blink with the same on/off cadence — simplest: draw solid, no blink, like a
  multi-selection highlight).
- width: fill each per-line rect with the selection color at low alpha.
Disable the normal caret while `columnBlock` is active.

**Menu / shortcut:** Edit ▸ **Column Selection Mode** (⌥⌘B) toggles
`stickyColumnMode` via the window controller; `validateMenuItem` shows a checkmark.
When turned on with an existing caret, seed a zero-width `columnBlock` at the caret.

## Testing

- **`ColumnSelectionTests`** (extend): `replaceBlock` (uniform + ragged, width →
  text on each row), `pasteBlock` (fewer/equal/more clipboard lines than rows;
  short-row padding; stop-at-last-line rule).
- **`ColumnGeometryTests`** if feasible headless (line/column ↔ offset round-trips
  using a real layout manager in a hidden text view) — at minimum test the pure
  offset↔(line,column) split helper.
- **`EditorSmokeTests`**: drive the controller's column hooks — begin a block,
  arrow to extend, type (assert text on every row), backspace, copy/cut/paste —
  using **test hooks** that set the `columnBlock` directly (bypassing the
  mouse/geometry, which needs a rendered view). This makes the editing logic
  testable without a live window.
- **AutoPilot / manual:** the actual Option-drag gesture + visual caret are
  verified live by the user (can't be unit-tested).

## File structure

- **Modify:** `ColumnSelection.swift` (+ `replaceBlock`, `pasteBlock`),
  `EditorTextView.swift` (column state + mouse + keyboard + drawing + ops),
  `EditorWindowController.swift` (toggle + validateMenuItem + copy/cut/paste
  routing if needed), `MainMenu.swift` (Edit ▸ Column Selection Mode),
  `ColumnSelectionTests.swift`, `EditorSmokeTests.swift`.
- Possibly a small `ColumnGeometry` helper file if the mapping grows.

## Out of scope (first cut)

- Creating new lines when pasting more clipboard lines than rows (stop at last
  line).
- Mixed proportional-font perfection (works, but column feel is best in monospace —
  fine for medit's use).
- Column selection persisting across an undo of a non-column edit.

## Versioning

Ships as **2.4.0**.
