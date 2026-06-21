# Selectable Markdown Tables — Design

**Date:** 2026-06-20
**Status:** Approved (pending spec review)

## Problem

In the Markdown preview, table content cannot be highlighted or copied. The rest
of the preview is selectable (the preview text view is created with
`isSelectable = true`, `EditorViewController.swift:421`), but tables are the
exception.

**Cause.** `MarkdownRenderer.visitTable` (`MarkdownRenderer.swift:260`) rasterizes
each table into an `NSImage` via `MarkdownTableRenderer.image(...)` and inserts it
as an `NSTextAttachment`. To TextKit, an image attachment is a single opaque glyph:
the cell text is painted into the bitmap as pixels, not characters. There is nothing
for the text system to select, and Copy yields the attachment placeholder, never the
cell text. This is inherent to the image approach.

## Goal

Tables in the Markdown preview render as **real, selectable, copyable text**, while
prose keeps wrapping to the window width and a table wider than the window is fully
reachable via its own horizontal scroller.

## Why a subview (spike findings)

The preview uses TextKit 1 (a `MarkdownPreviewLayoutManager: NSLayoutManager`
subclass). Two spikes against this exact setup established a hard constraint:

- With `container.widthTracksTextView = true` (or any fixed container width = the
  viewport), a table paragraph whose tab stops extend past the viewport is **clipped
  to the container width** — `usedRect` never exceeds the viewport, so off-screen
  columns are unreachable and no horizontal scroll appears.
- With a wide/infinite container (the editor's no-wrap model), the table fits but
  **prose stops wrapping to the window** — it wraps at the wide width instead.

TextKit 1 has **no per-paragraph container width**. Therefore a single shared text
view cannot simultaneously wrap prose to the window and let a table overflow it.
Delivering the chosen behavior ("prose wraps + wide table fully reachable")
**requires each table to live in its own text view** with its own container and its
own horizontal scroller.

## Approach

Render each table as its own embedded, horizontally-scrollable read-only
`NSTextView`, carried in the preview through a **view-providing text attachment**.

- The main preview text view is unchanged: prose wraps to the window as today.
- Each table becomes one attachment whose view is a `MarkdownTableView`. That view
  holds the table laid out as tab-stop columns with grid + header shading, drawn by
  the existing `MarkdownPreviewLayoutManager` decoration path (`Kind.tableRow`,
  `.tableColumns`, `.tableHeader` — the dormant code that nothing currently emits).
- Cells are real text → selectable and copyable. Selection inside a table is
  independent of the prose selection (separate text views), which matches how
  embedded-table editors (GitHub, Bear) behave. This is acceptable and expected.

### Cell width and wrapping

- Each column width = max content width in that column, **capped at ~280pt** (the
  cap the image renderer used: `MarkdownTableRenderer.maxColumnWidth`).
- Long cell text **wraps within the cell** onto multiple lines; the row grows
  taller. (Each table now has its own container, so per-cell wrapping is available —
  this restores what the image bought and the tab-stop path alone lacked.)
- The table view's horizontal scroller appears only when the **total** column width
  exceeds the available preview width (`autohidesScrollers = true`). One long cell no
  longer forces horizontal scroll because that column is capped + wraps.

## Components

### `MarkdownTableView` (new) — `Sources/MeditKit/MarkdownTableView.swift`

An `NSView` subclass composed of:
- an `NSScrollView` (`hasHorizontalScroller = true`, `hasVerticalScroller = false`,
  `autohidesScrollers = true`, no border),
- a read-only `NSTextView` (`isEditable = false`, `isSelectable = true`,
  `drawsBackground = false`) using a `MarkdownPreviewLayoutManager` so the grid +
  header shading draw exactly as the rest of the preview's decorations do,
- a non-width-tracking text container sized to the computed table width so the table
  can exceed the visible frame and scroll.

Construction input is the table's structured cell data (header cells + body rows as
`[NSAttributedString]`, already inline-styled) plus the `MarkdownRenderer.Theme`.
The view:
1. computes per-column widths (cap + content fit) and per-row heights (cell wrap),
2. builds an `NSAttributedString` of tab-separated rows terminated by `\n`, each row
   carrying `Kind.tableRow` (`blockKind`), the column-divider x-positions
   (`.tableColumns`, as `[NSNumber]`), and `.tableHeader` on the header row,
3. sets the container width to the total table width and lays out,
4. exposes `intrinsicTableSize` (total width, total height) so the attachment can
   size its line fragment.

Pure helpers (column widths, row heights, divider positions) live as `static`
functions on the type or a free `MarkdownTableLayout` enum so they are unit-testable
without constructing the view.

### View-providing attachment in `MarkdownRenderer.visitTable`

`visitTable` stops emitting the image. For the **interactive (preview)** mode it
emits an `NSTextAttachment` whose attachment cell is view-providing: it vends a
`MarkdownTableView` built from the parsed cells + theme, sized to the table's
intrinsic size, capped to the preview's content width for the visible frame.

To keep `MarkdownRenderer` a pure value type that knows nothing about live view
construction, the attachment carries the structured cell data (header + rows +
theme); the `MarkdownTableView` is built by the attachment cell at display time. The
renderer does not hold or mutate AppKit view state.

### Render mode: interactive vs. static

`MarkdownRenderer` gains a table render mode so the same walker serves both screen
and paper:

- `.interactive` (default for the preview) → view-providing attachment
  (`MarkdownTableView`).
- `.static` (used by `MarkdownPrinter`) → a **static drawn grid**: reuse the existing
  `MarkdownTableRenderer.image(...)` as the attachment image, OR draw the cells flat
  to a full page-width grid. Paper cannot scroll, so a static, full-width grid with
  cells wrapped to fit is correct for print.

The mode is a parameter on the renderer (e.g. `MarkdownRenderer(theme:tableMode:)`,
default `.interactive`). `MarkdownPrinter.operation(forMarkdown:)` constructs the
renderer with `.static`.

### `MarkdownTableRenderer` — kept, repurposed

The image renderer is **not deleted**. It already draws a static flat grid, which is
exactly what the print path needs. It is retained and used only by the `.static`
table mode. (Revision from the initial sketch, which proposed deleting it — print
needs it.)

## Data flow

```
Markdown source
  └─ MarkdownRenderer(theme:, tableMode:)
       ├─ visitTable (interactive) ─→ view-providing attachment
       │      carries (header, rows, theme)
       │      └─ at display: MarkdownTableView (scrollable, selectable)
       └─ visitTable (static, print) ─→ MarkdownTableRenderer.image attachment
NSAttributedString → preview NSTextView (prose wraps; tables are subviews)
                   → printer NSTextView (tables are static grids)
```

## Error / edge handling

- **Empty table / zero columns:** `columnCount == 0` → emit nothing (or an empty
  line); never construct a zero-size view. (Mirror the existing
  `MarkdownTableRenderer` guard.)
- **Ragged rows** (fewer cells than the header): pad missing cells with empty
  attributed strings, as the image renderer does today.
- **Appearance change (light/dark):** the preview re-renders on appearance change
  (`renderPreview()` rebuilds the attributed string), so table subviews are rebuilt
  with the new theme. No incremental recoloring needed.
- **Preview resize:** the visible width passed to the table view updates so the
  table's scroller appears/hides correctly; the table's intrinsic (scrollable) width
  is independent of the preview width.

## Testing

Unit-testable pure logic (no view construction):
- column-width computation: content fit, the ~280pt cap, the minimum width,
  per-side padding.
- row-height computation with cell wrapping at the capped column width.
- column-divider x-positions match the cumulative column widths.
- header-row detection sets `.tableHeader`; body rows do not.
- ragged-row padding; empty-table guard.

Integration / behavioral (AP + manual):
- a table in the preview is selectable and Copy yields the cell text (not a
  placeholder).
- a table wider than the window shows a horizontal scroller and scrolls; prose above
  and below still wraps to the window.
- print output shows a static full-width grid (no scroller, cells wrapped).
- light/dark appearance both render correct grid + header shading.

## Files

- **Create:** `Sources/MeditKit/MarkdownTableView.swift` (the scrollable
  selectable table view + pure layout helpers).
- **Create:** `Tests/MeditKitTests/MarkdownTableLayoutTests.swift` (pure layout
  helper tests).
- **Modify:** `Sources/MeditKit/MarkdownRenderer.swift` — add `tableMode`;
  rewrite `visitTable` to branch interactive vs. static.
- **Modify:** `Sources/MeditKit/MarkdownPrinter.swift` — construct the renderer
  with `.static`.
- **Keep, repurpose:** `Sources/MeditKit/MarkdownTableRenderer.swift` (now the
  `.static` print path only).
- **Reuse, unchanged:** `Sources/MeditKit/MarkdownPreviewLayoutManager.swift`
  (its `drawTableRow` / `tableColumns` / `tableHeader` path is finally exercised,
  now inside each table's own view).

## Out of scope

- Editing tables in the preview (the preview is read-only; this is WYSIWYG-view
  scope, not editing).
- Resizable / draggable column widths.
- Sorting or interacting with table data beyond select + copy + scroll.
```
