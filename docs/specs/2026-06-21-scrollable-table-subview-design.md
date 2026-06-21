# Scrollable Table Subviews — Design (Path B)

**Date:** 2026-06-21
**Status:** Approved (spike-verified)
**Builds on:** `2026-06-21-nstexttable-rewrite-design.md` (keeps the NSTextTable
builder; changes only *where* the table is rendered).

## Problem

Inline NSTextTable tables (current) are real selectable text and fixed the
hollow-gap bug — but inline tables **always shrink to the viewport width** (verified:
NSTextTable ignores min-width and never overflows). At a narrow viewport a column
can become narrower than its longest word, and `.byWordWrapping` then **splits the
word mid-character** (`Iden/tif/ier`). The user requires words never split and
nothing truncated; the only way to honor that is to let a too-wide table keep its
natural width and **scroll horizontally** — which an inline text table cannot do.

## Goal

Each Markdown table renders in its own **horizontally-scrollable view**:
- A table that fits the viewport shows **no scrollbar**, sized to content (grows
  only if needed — already correct via the builder's absolute widths).
- A table wider than the viewport keeps its **natural width**, never splitting words
  or truncating, with an **autohiding horizontal scrollbar** to reach the rest.
- The table remains **selectable, copyable, and AX-visible** (AutoPilot can target
  it) — *without* the opaque-`AXUnknown` problem the previous subview attempt had.

## Key spike findings (de-risking)

1. **NSTextTable always fits its container** — no min-width, no overflow inline.
   Hence the subview (a separate scroll view) is required.
2. **A subview of an `NSTextView` is AX-orphaned** — `preview.accessibilityChildren()`
   returns 0 for added subviews → the `AXUnknown` problem. (This is why the previous
   attempt's copy/AX were fragile.)
3. **A sibling of the preview (child of a plain `NSView` container) IS a real AX
   child** — spike showed `container.accessibilityChildren()` returns both the
   preview text view AND the table view. **This is the fix:** parent tables to a
   shared document container, NOT to the text view.
4. In a wide container, an NSTextTable lays out at its full natural width (cells on
   one line) — so the table view, given an unbounded-width container, holds the
   natural width and the scroll view scrolls it.

## Architecture

The preview's scroll view gets a **flipped document container** (`NSView`) as its
`documentView`, holding the preview **text view** (prose, pinned to fill width and
sized to content height) **plus** each table as a **sibling** `MarkdownTableView`.

```
previewScrollView (vertical)
  └─ documentView = PreviewDocumentView (flipped NSView)
       ├─ previewTextView   (prose; width = container, height = content)
       └─ MarkdownTableView × N   (siblings, positioned at each table's slot)
```

- The preview text view reserves a vertical slot per table via an **attachment**
  whose `cellSize` = the table's on-screen height (the scrollable view's height,
  i.e. table height + scrollbar allowance when present). Prose flows around it.
- The view controller positions each `MarkdownTableView` at its attachment's slot
  (x = text inset, y = slot top, width = available viewport width, height = slot),
  re-positioning on render and on viewport resize.

Because the table views are **siblings of the text view in the document container**
(spike-proven), they are real AX/responder elements: clicks reach them, selection +
copy work, and AutoPilot can target `markdownTableTextView`.

### `MarkdownTableView` (re-introduced) — `Sources/MeditKit/MarkdownTableView.swift`

- An `NSView` containing an `NSScrollView` (`hasHorizontalScroller = true`,
  `hasVerticalScroller = false`, `autohidesScrollers = true`, no border, transparent)
  whose `documentView` is a read-only selectable `NSTextView`.
- The text view's storage = `MarkdownTableBuilder.attributedTable(...)` (KEEP the
  builder — it already produces correct lossless layout with absolute column
  widths). The text view's container is **non-width-tracking, sized to the table's
  natural width** so the table never shrinks/wraps/splits — the scroll view scrolls
  it instead.
- `intrinsicTableSize` = the laid-out table's natural width × height.
- AX: `setAccessibilityIdentifier("markdownTableTextView")` on the text view;
  the container exposes the text view (`accessibilityRole = .group`, label
  "markdown table") so AX sees a real element (spike #3).
- `hitTest` routes clicks into the text view so selection works across the whole
  table area.

### Attachment for the vertical slot

`MarkdownRenderer.visitTable` (interactive) emits an `NSTextAttachment` whose
`NSTextAttachmentCell.cellSize` reserves the table's **height** (and full available
width) in the prose flow. The cell carries the parsed cells + theme; the view
controller builds the live `MarkdownTableView` from it and positions it at the
attachment's glyph rect. (This mirrors the earlier attachment approach but with the
table parented to the document container, not the text view.)

### `EditorViewController`

- Build the **document container** as the scroll view's `documentView`; pin the
  preview text view inside it (fill width, content height).
- `placeTableSubviews()`: for each table attachment, build a `MarkdownTableView`,
  set its frame to (x: text inset, y: attachment slot top, width: viewport content
  width, height: table height), add it to the **document container** (sibling of the
  text view), and track for teardown.
- Reposition on render and on a viewport-resize observer.

## Width / scroll behavior (the whole point)

- The `MarkdownTableView`'s inner text container is **natural-width** (the table's
  full content width). So the table lays out losslessly: words never split,
  nothing truncated.
- The `MarkdownTableView`'s on-screen **frame width = the available viewport width**.
  If natural width ≤ frame width → no scroll, no scrollbar (autohide). If natural
  width > frame width → horizontal scrollbar, scroll to reach the rest.
- "Grow only if needed" still holds: a small table's natural width is small, so its
  frame content is small and it doesn't stretch.

## Tradeoffs (accepted)

- **Re-introduces the subview layer** deleted in the NSTextTable rewrite
  (`MarkdownTableView`, attachment, placement, resize observer). Accepted to get
  lossless wide tables + horizontal scroll.
- **Copy/AX:** mitigated by the sibling-parenting fix (spike #3) — tables are real
  AX elements this time, not opaque `AXUnknown`. This is the key improvement over
  the previous subview attempt.
- A horizontal scrollbar appears inside the reading view for wide tables (autohide).

## Testing

Unit: `MarkdownTableView` builds, holds natural width, text is selectable; the
builder tests stay as-is (lossless layout).

Behavioral (AP):
- **Wide table, wide window:** table at natural width, no scrollbar, no word splits.
- **Wide table, narrow window:** table keeps natural width, **horizontal scrollbar
  appears**, NO word splitting, NO truncation, NO hollow gaps.
- **Small table:** compact, no scrollbar.
- **Selection/copy:** drag-select a cell + ⌘C yields cell text (AP can target
  `markdownTableTextView`, confirming it's a real AX element — the regression check
  vs. the old AXUnknown).
- Light + dark; print unaffected (static image path).

## Files

- **Create/restore:** `Sources/MeditKit/MarkdownTableView.swift` (scrollable,
  AX-visible), `Sources/MeditKit/MarkdownTableAttachment.swift` (slot-reserving
  attachment + placement helper), `Sources/MeditKit/PreviewDocumentView.swift`
  (flipped container).
- **Modify:** `MarkdownRenderer.visitTable` (interactive → slot attachment carrying
  the builder output / cell data; static unchanged), `EditorViewController`
  (document-container preview + placement + resize), `MarkdownTableViewTests`,
  `MarkdownRendererTableModeTests` (interactive = attachment again).
- **Keep:** `MarkdownTableBuilder` (the layout is correct — only the host changes).

## Out of scope

- Editing tables; resizable columns; sorting.
- Vertical scroll within a table (tables are as tall as content).
- Converting print to scrollable (print stays the static image).
