# Markdown Tables — NSTextTable Rewrite Design

**Date:** 2026-06-21
**Status:** Approved (spike-verified)
**Supersedes:** the table-rendering parts of `2026-06-20-selectable-markdown-tables-design.md`

## Problem

The current Markdown-table preview renders each table **row as a single
tab-separated paragraph** (`MarkdownTableLayout.attributedRows`), positioned with
`NSTextTab` stops and drawn by a custom `drawTableRow` in
`MarkdownPreviewLayoutManager`, then embedded as a live `MarkdownTableView`
subview via a `MarkdownTableAttachmentCell`.

This has a **structural defect**: an `NSParagraphStyle` has exactly one
`headIndent`, so when cells in more than one column wrap, every wrapped line
resumes at that single x-position. Wrapped text from different columns cannot sit
side-by-side — it stacks into one column, leaving large **hollow vertical gaps**
under the columns that didn't wrap. No padding/line-height tuning fixes this; it is
inherent to the single-paragraph-per-row model.

Secondary problems caused by the subview approach:
- The embedded `MarkdownTableView` is an opaque `AXUnknown` in the accessibility
  tree; AutoPilot cannot target it, and selection/copy relied on a fragile
  `MarkdownPreviewTextView.hitTest` override.
- A web of fragile geometry code: tab stops, `headIndent`, `baselineOffset`,
  center tabs, `placeTableSubviews`, viewport-resize repositioning, per-row grid
  drawing in the layout manager.

## Goal

Markdown tables render as **real, selectable, copyable text** where **each cell
wraps independently and correctly side-by-side** (no hollow gaps), with a
distinct header, per-cell borders, and comfortable padding — using AppKit's
native table mechanism.

## Approach: NSTextTable

Rebuild tables on **`NSTextTable` / `NSTextTableBlock`** — AppKit's first-class
text-table support. Each cell is an `NSTextTableBlock` (its row/column position)
attached as a **paragraph attribute** (`paragraphStyle.textBlocks = [block]`); the
cell's attributed string (ending in `\n`) is appended to the table's attributed
string. The text system lays out the grid, wrapping each cell independently within
its own block rectangle.

### Spike verification (done 2026-06-21)

Proven in the **exact TextKit-1 stack** the preview uses (`NSLayoutManager`
subclass; `textLayoutManager == nil`):
- A long cell wrapped to multiple line fragments **within its column** while
  neighboring single-line cells stayed at the top of the row — **no hollow gap**.
- The row grew to the tallest cell; short rows stayed compact.
- Header background shading, per-cell borders, and padding all rendered.
- Output is real text in a selectable `NSTextView`.

### Why this is simpler (net code removed)

The table becomes **inline attributed text** in the preview's own text view, so the
entire subview/placement layer is deleted:
- **Delete:** `MarkdownTableView`, `MarkdownPreviewTextView` (the hitTest
  override), `MarkdownTableAttachmentCell`, `MarkdownTablePlacement`,
  `placeTableSubviews`, the preview viewport-resize observer, and the `tableSubviews`
  state in `EditorViewController`.
- **Delete:** `MarkdownTableLayout` (tab stops, dividers, center tabs,
  `headIndent`, `baselineOffset`, row-height math).
- **Delete:** the `tableRow` / `tableColumns` / `tableHeader` drawing path in
  `MarkdownPreviewLayoutManager` (`drawTableRow` + the `Kind.tableRow` case and the
  `tableFirstColFill` palette field) — borders/shading are now per-cell block
  properties, not custom-drawn.
- **Keep:** `MarkdownRenderer.renderCell` (inline-styled cell content),
  `CBBColors`, the inline-code styling.

Selection/copy "just works" because the table is ordinary text in the preview's
`NSTextView` — this also resolves the copy/accessibility problem the subview
approach created.

## Component design

### `MarkdownTableBuilder` (new) — `Sources/MeditKit/MarkdownTableBuilder.swift`

Pure(ish) builder that turns parsed cells + theme into the table's
`NSAttributedString` using `NSTextTable`.

- `static func attributedTable(header: [NSAttributedString], rows: [[NSAttributedString]], theme: MarkdownRenderer.Theme) -> NSAttributedString`
- Internals:
  - `let table = NSTextTable(); table.numberOfColumns = columnCount`
  - `table.setContentWidth(_:type:)` — bound the table to the available content
    width so cells wrap rather than overflow (see "Width" below).
  - For each cell: build an `NSTextTableBlock(table:startingRow:rowSpan:1:
    startingColumn:columnSpan:1)`, set:
    - `block.setBorderColor(borderColor)` + `setWidth(1, .absoluteValueType, for: .border)`
    - `block.setWidth(cellPadding, .absoluteValueType, for: .padding)` (≈8–10pt)
    - header row: `block.backgroundColor = CBBColors.steel`; header text color
      `CBBColors.blue` (bold, applied to the cell string)
    - header cells: center alignment (`paragraphStyle.alignment = .center`); body
      cells: `.left`
  - Append each cell's attributed string (content + `\n`) with its block-bearing
    paragraph style.
- Ragged rows: pad missing trailing cells with empty cells. Empty table
  (`columnCount == 0`): emit nothing.

### Width handling

`NSTextTable.setContentWidth` (or per-block width layers) controls how wide the
table lays out. Decision (matches the user's "grow then wrap" intent):
- Let columns size to content up to a **max table width = the preview's available
  content width**. When total content exceeds that, `NSTextTable` wraps cells
  (each independently) — which is exactly what we want, and what the spike showed.
- A table never forces horizontal scroll in this model; it wraps. (This replaces
  the previous "wide table scrolls horizontally" behavior. If a non-wrapping wide
  table is ever wanted, that's a follow-up — out of scope here.)

### `MarkdownRenderer.visitTable`

- `.interactive` mode: append the `NSTextTableBlock`-based attributed table
  (inline) instead of an attachment. No subview, no attachment cell.
- `.static` mode (print): keep the existing `MarkdownTableRenderer` image **or**
  switch print to the same NSTextTable output. **Decision:** keep the image for
  print initially (it already prints correctly after the print-height fix); revisit
  only if the two looking different is a problem. This keeps the rewrite scoped to
  the on-screen path.

### `EditorViewController`

- Remove `tableSubviews`, `placeTableSubviews`, `previewViewportChanged`, the
  scroll-frame observer, and the table-subview placement call in `renderPreview`.
- The preview text view can revert from `MarkdownPreviewTextView` back to a plain
  `NSTextView` (the hitTest override is no longer needed) — or keep the subclass as
  a no-op; **decision:** revert to plain `NSTextView` to remove dead code.

### `MarkdownPreviewLayoutManager`

- Remove the `Kind.tableRow` case, `drawTableRow`, the `tableColumns` /
  `tableHeader` attribute handling, and the `tableFirstColFill` palette field.
  Code panels, quote bars, heading rules, and thematic breaks are unaffected.

## Data flow (new)

```
Markdown → MarkdownRenderer.visitTable (interactive)
  → MarkdownTableBuilder.attributedTable(header, rows, theme)
      → NSTextTable + per-cell NSTextTableBlock paragraph attrs
  → appended inline into the preview's NSAttributedString
preview NSTextView lays out the table natively (cells wrap independently);
selection + copy work because it is ordinary text.
print path: unchanged (.static image), already correct.
```

## Visual spec (carry over what the user approved)

- **Header:** Cold Bore Steel (`#4a9fc8`) background band; bold dark Cold Bore
  Blue (`#0a2351`) text; **centered** per cell.
- **Body:** transparent/preview surface; left-aligned text; inline code in steel
  with a snug background (existing inline-code styling).
- **Borders:** thin, subtle (separator-style: ~`white@16%` dark / `black@14%`
  light) on every cell — via `NSTextBlock` border layer.
- **Padding:** ~8–10pt per cell via the block padding layer (no baselineOffset /
  line-height hacks — `NSTextTable` centers/pads natively).
- **No first-column shading** (the user disliked it).
- Light + dark both correct (colors are appearance-aware; verify both).

## Testing

Unit-testable (pure builder):
- column count from header/rows (incl. ragged padding, empty-table guard).
- header row carries the header background + centered alignment; body rows do not.
- the produced attributed string contains a `textBlocks` paragraph attribute per
  cell with the right row/column.
- cell text is the rendered inline content (selectable real text).

Behavioral (AP + PDF):
- **The gap repro** (`/tmp/gap.md` — multiple wrapping columns) renders with cells
  wrapping side-by-side and **no hollow gaps**. (This is the acceptance test.)
- simple narrow table looks comfortable (rows not cramped, not bloated).
- selection + copy of cell text works (now ordinary text; AP can also target the
  preview text view directly).
- light mode + dark mode both correct.
- print still renders tables correctly (unchanged static path; PDF check).

## Files

- **Create:** `Sources/MeditKit/MarkdownTableBuilder.swift`
- **Create:** `Tests/MeditKitTests/MarkdownTableBuilderTests.swift`
- **Modify:** `Sources/MeditKit/MarkdownRenderer.swift` (`visitTable` interactive
  branch → builder; static branch unchanged).
- **Modify:** `Sources/MeditKit/EditorViewController.swift` (remove subview
  placement + observers + state; plain preview NSTextView).
- **Modify:** `Sources/MeditKit/MarkdownPreviewLayoutManager.swift` (remove the
  table-row drawing path + `tableFirstColFill`).
- **Delete:** `Sources/MeditKit/MarkdownTableView.swift`,
  `Sources/MeditKit/MarkdownTableLayout.swift`,
  `Sources/MeditKit/MarkdownTableAttachment.swift`.
- **Delete/trim tests:** `MarkdownTableLayoutTests`, `MarkdownTableViewTests`,
  `MarkdownTableAttachmentTests`, `MarkdownTablePreviewSmokeTests` (replace with
  builder + new behavioral coverage).
- **Keep:** `MarkdownTableRenderer.swift` (print `.static` path),
  `MarkdownPrinterHeightTests`, `MarkdownPrinterTableModeTests`,
  `MarkdownRendererTableModeTests` (adjust the interactive assertion: tables are now
  inline text blocks, not a `MarkdownTableAttachmentCell`).

## Risks

- **`setContentWidth` vs. available width:** getting the table to wrap at the
  preview's content width (and re-wrap on window resize) needs the content width to
  track the text container. Since the table is now inline text in the preview's own
  container, normal text re-layout on resize handles this — but verify resize
  re-wraps cleanly via AP.
- **Print parity:** print keeps the image renderer, so print tables look slightly
  different from screen (gray vs. steel header). Accepted; called out.
- **Migration churn:** several files deleted and tests rewritten; do it
  incrementally (builder + tests first, then wire `visitTable`, then delete the old
  path), verifying via AP at each step.

## Out of scope

- Editing tables in the preview (read-only).
- Resizable/draggable columns; sorting.
- Non-wrapping wide tables with horizontal scroll (this design wraps instead).
- Converting print to NSTextTable (keep the image renderer for now).
