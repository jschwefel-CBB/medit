# Selectable Markdown Tables Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Markdown-preview tables render as real, selectable, copyable text in their own horizontally-scrollable subview, while prose keeps wrapping to the window and print keeps a static full-width grid.

**Architecture:** Replace the image attachment in `MarkdownRenderer.visitTable` with a TextKit-1 `NSTextAttachmentCell` that reserves the table's intrinsic size and carries the table's structured cell data. The preview view controller scans the rendered text for these cells and positions a live `MarkdownTableView` (a scrollable, selectable `NSTextView` that draws its own grid via `MarkdownPreviewLayoutManager`) at each attachment's glyph rect, re-placing on every render and on resize. A `tableMode` flag lets the printer keep the existing static `MarkdownTableRenderer` image.

**Tech Stack:** Swift 6.3, AppKit, TextKit 1 (`NSLayoutManager` subclass), swift-markdown (`Markdown` module), SwiftPM (`MeditKit` package), XCTest.

## Global Constraints

- macOS 14+ (`Package.swift`: `.macOS(.v14)`); universal builds (`x86_64 arm64`).
- TextKit 1 only: the preview is built around an explicit `NSLayoutManager`
  (`MarkdownPreviewLayoutManager`); `textView.textLayoutManager` is `nil`.
  `NSTextAttachmentViewProvider` is **not consulted** in this setup — use
  `NSTextAttachmentCell` and `cellSize()` for layout (spike-confirmed).
- `MarkdownRenderer` stays a pure value type: it must not construct or hold AppKit
  views. It emits attachment cells carrying data; live views are built by the
  preview view controller at display time.
- Column width cap: **280pt** (matches `MarkdownTableRenderer.maxColumnWidth`).
  Min column width: **36pt**. Cell padding: **12pt** horizontal, **6pt** vertical
  (match `MarkdownTableRenderer`'s constants).
- Follow existing patterns: tables reuse `MarkdownPreviewLayoutManager`'s
  `Kind.tableRow` / `.tableColumns` / `.tableHeader` decoration path (currently dead
  code) inside each table view.
- Git identity for commits: `jschwefel@coldboreballisticsllc.com` (already the
  configured default — do **not** override with `-c`). End commit messages with the
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` trailer.
- Run the full suite with `swift test` from the repo root.

---

### Task 1: Pure table layout helpers (`MarkdownTableLayout`)

Compute column widths, row heights, and divider positions for a table — the pure
math, no views — so the table view and its tests share one source of truth.

**Files:**
- Create: `Sources/MeditKit/MarkdownTableLayout.swift`
- Test: `Tests/MeditKitTests/MarkdownTableLayoutTests.swift`

**Interfaces:**
- Consumes: nothing (pure, foundational).
- Produces:
  - `struct MarkdownTableLayout`
  - `static func columnWidths(header: [NSAttributedString], rows: [[NSAttributedString]]) -> [CGFloat]`
    — inner content widths per column, clamped to `[minColumnWidth, maxColumnWidth]`
    (NOT including padding).
  - `static func dividerXs(columnWidths: [CGFloat]) -> [CGFloat]` — x-positions of
    the vertical dividers (cumulative padded column widths), excluding the outer
    left/right borders. Padded width = inner width + `2 * cellPaddingX`.
  - `static func rowHeight(_ row: [NSAttributedString], columnWidths: [CGFloat]) -> CGFloat`
    — max wrapped cell height across the row, + `2 * cellPaddingY`.
  - `static func totalWidth(columnWidths: [CGFloat]) -> CGFloat` — sum of padded
    column widths + 1 (right border).
  - Public constants: `maxColumnWidth: CGFloat = 280`, `minColumnWidth: CGFloat = 36`,
    `cellPaddingX: CGFloat = 12`, `cellPaddingY: CGFloat = 6`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/MeditKitTests/MarkdownTableLayoutTests.swift
import XCTest
import AppKit
@testable import MeditKit

final class MarkdownTableLayoutTests: XCTestCase {
    private func cell(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: 15)])
    }

    func testColumnWidthsClampToMinAndMax() {
        let header = [cell("A"), cell("B")]                 // narrow -> min
        let longText = String(repeating: "wide ", count: 100)
        let rows = [[cell("x"), cell(longText)]]            // 2nd col exceeds max
        let widths = MarkdownTableLayout.columnWidths(header: header, rows: rows)
        XCTAssertEqual(widths.count, 2)
        XCTAssertEqual(widths[0], MarkdownTableLayout.minColumnWidth, accuracy: 0.5)
        XCTAssertEqual(widths[1], MarkdownTableLayout.maxColumnWidth, accuracy: 0.5)
    }

    func testDividerXsAreCumulativePaddedWidths() {
        let widths: [CGFloat] = [50, 80]
        let xs = MarkdownTableLayout.dividerXs(columnWidths: widths)
        // One interior divider, after the first padded column.
        let firstPadded = 50 + 2 * MarkdownTableLayout.cellPaddingX
        XCTAssertEqual(xs, [firstPadded])
    }

    func testRowHeightGrowsWhenCellWraps() {
        let widths: [CGFloat] = [MarkdownTableLayout.maxColumnWidth]
        let oneLine = MarkdownTableLayout.rowHeight([cell("short")], columnWidths: widths)
        let manyLines = MarkdownTableLayout.rowHeight(
            [cell(String(repeating: "word ", count: 200))], columnWidths: widths)
        XCTAssertGreaterThan(manyLines, oneLine)
    }

    func testTotalWidthSumsPaddedColumnsPlusBorder() {
        let widths: [CGFloat] = [50, 80]
        let total = MarkdownTableLayout.totalWidth(columnWidths: widths)
        let expected = (50 + 24) + (80 + 24) + 1
        XCTAssertEqual(total, expected, accuracy: 0.5)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MarkdownTableLayoutTests`
Expected: FAIL — `cannot find 'MarkdownTableLayout' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/MeditKit/MarkdownTableLayout.swift
import AppKit

/// Pure geometry for a Markdown table: column widths (content-fit, clamped),
/// per-row heights (with cell wrapping), and vertical-divider x-positions. Shared
/// by `MarkdownTableView` and its tests so layout math has one source of truth.
public enum MarkdownTableLayout {
    public static let maxColumnWidth: CGFloat = 280
    public static let minColumnWidth: CGFloat = 36
    public static let cellPaddingX: CGFloat = 12
    public static let cellPaddingY: CGFloat = 6

    /// Inner content width per column (excludes padding), clamped to [min, max].
    public static func columnWidths(header: [NSAttributedString],
                                    rows: [[NSAttributedString]]) -> [CGFloat] {
        let columnCount = max(header.count, rows.map(\.count).max() ?? 0)
        guard columnCount > 0 else { return [] }
        var widths = [CGFloat](repeating: minColumnWidth, count: columnCount)
        for row in ([header] + rows) {
            for (i, cell) in row.enumerated() where i < columnCount {
                let w = min(maxColumnWidth, ceil(cell.size().width))
                widths[i] = max(widths[i], w)
            }
        }
        return widths
    }

    /// Padded column width = inner width + horizontal padding on both sides.
    private static func paddedWidth(_ inner: CGFloat) -> CGFloat { inner + cellPaddingX * 2 }

    /// X-positions of interior vertical dividers (cumulative padded widths),
    /// excluding the outer left (0) and right borders.
    public static func dividerXs(columnWidths: [CGFloat]) -> [CGFloat] {
        guard columnWidths.count > 1 else { return [] }
        var xs: [CGFloat] = []
        var x: CGFloat = 0
        for w in columnWidths.dropLast() {
            x += paddedWidth(w)
            xs.append(x)
        }
        return xs
    }

    /// Max wrapped cell height across a row (at each column's inner width) + padding.
    public static func rowHeight(_ row: [NSAttributedString],
                                 columnWidths: [CGFloat]) -> CGFloat {
        var h: CGFloat = 0
        for (i, cell) in row.enumerated() where i < columnWidths.count {
            let bounds = cell.boundingRect(
                with: NSSize(width: columnWidths[i], height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading])
            h = max(h, ceil(bounds.height))
        }
        return h + cellPaddingY * 2
    }

    /// Total table width: sum of padded column widths + 1 for the right border.
    public static func totalWidth(columnWidths: [CGFloat]) -> CGFloat {
        columnWidths.reduce(0) { $0 + paddedWidth($1) } + 1
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MarkdownTableLayoutTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MeditKit/MarkdownTableLayout.swift Tests/MeditKitTests/MarkdownTableLayoutTests.swift
git commit -m "feat: pure layout helpers for Markdown tables

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Attributed-string builder for a table's rows (`MarkdownTableLayout.attributedRows`)

Build the tab-separated, decoration-tagged `NSAttributedString` that a table view's
text storage will hold. Pure (no view), so it is unit-testable. This is what makes
the dormant `MarkdownPreviewLayoutManager` table-drawing path fire.

**Files:**
- Modify: `Sources/MeditKit/MarkdownTableLayout.swift`
- Test: `Tests/MeditKitTests/MarkdownTableLayoutTests.swift`

**Interfaces:**
- Consumes: `MarkdownTableLayout.columnWidths`, `.dividerXs` (Task 1);
  `MarkdownBlockAttribute` (`Kind.tableRow`, `.tableColumns`, `.tableHeader`,
  `.blockKind`) from `MarkdownPreviewLayoutManager.swift`.
- Produces:
  - `static func attributedRows(header: [NSAttributedString], rows: [[NSAttributedString]], columnWidths: [CGFloat], theme: MarkdownRenderer.Theme) -> NSAttributedString`
    — one line per row, cells joined by `\t`, each row terminated by `\n`. The header
    row carries `MarkdownBlockAttribute.tableHeader`; every row carries
    `MarkdownBlockAttribute.blockKind = Kind.tableRow.rawValue` and
    `.tableColumns = dividerXs` (as `[NSNumber]`). Each row's paragraph style has
    left tab stops at the cumulative padded column widths and
    `lineBreakMode = .byWordWrapping` (so a too-long cell wraps).

- [ ] **Step 1: Write the failing test**

```swift
// add to MarkdownTableLayoutTests.swift
func testAttributedRowsTagsHeaderAndColumns() {
    let theme = MarkdownTableLayoutTests.testTheme()
    let header = [cell("H1"), cell("H2")]
    let rows = [[cell("a"), cell("b")]]
    let widths = MarkdownTableLayout.columnWidths(header: header, rows: rows)
    let attr = MarkdownTableLayout.attributedRows(
        header: header, rows: rows, columnWidths: widths, theme: theme)

    // Two lines (header + 1 body), each terminated by \n -> 2 newlines.
    XCTAssertEqual(attr.string.filter { $0 == "\n" }.count, 2)
    // Cells are tab-separated.
    XCTAssertTrue(attr.string.contains("H1\tH2"))

    // First char of the header row is tagged as a table row AND a header.
    let kind = attr.attribute(MarkdownBlockAttribute.blockKind, at: 0, effectiveRange: nil) as? Int
    XCTAssertEqual(kind, MarkdownBlockAttribute.Kind.tableRow.rawValue)
    XCTAssertNotNil(attr.attribute(MarkdownBlockAttribute.tableHeader, at: 0, effectiveRange: nil))
    let cols = attr.attribute(MarkdownBlockAttribute.tableColumns, at: 0, effectiveRange: nil) as? [NSNumber]
    XCTAssertEqual(cols?.count, MarkdownTableLayout.dividerXs(columnWidths: widths).count)

    // The body row is a table row but NOT a header.
    let bodyStart = attr.string.distance(from: attr.string.startIndex,
        to: attr.string.range(of: "a\t")!.lowerBound)
    XCTAssertNil(attr.attribute(MarkdownBlockAttribute.tableHeader, at: bodyStart, effectiveRange: nil))
}

// Shared theme factory for tests in this file.
extension MarkdownTableLayoutTests {
    static func testTheme() -> MarkdownRenderer.Theme {
        MarkdownRenderer.Theme(
            baseFont: NSFont.systemFont(ofSize: 15),
            monoFont: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            foreground: .labelColor, secondary: .secondaryLabelColor,
            codeBackground: .clear, headingColor: .labelColor,
            quoteBarColor: .gray, tableBorderColor: .separatorColor,
            linkColor: .linkColor, isDark: false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MarkdownTableLayoutTests/testAttributedRowsTagsHeaderAndColumns`
Expected: FAIL — `type 'MarkdownTableLayout' has no member 'attributedRows'`.

- [ ] **Step 3: Write minimal implementation**

```swift
// append to Sources/MeditKit/MarkdownTableLayout.swift, inside the enum
public static func attributedRows(header: [NSAttributedString],
                                  rows: [[NSAttributedString]],
                                  columnWidths: [CGFloat],
                                  theme: MarkdownRenderer.Theme) -> NSAttributedString {
    let dividers = dividerXs(columnWidths: columnWidths)
    let dividerNumbers = dividers.map { NSNumber(value: Double($0)) }
    // Tab stops sit one padding-inset past each divider so cell text starts after
    // the left border + padding. The first cell starts at cellPaddingX.
    var stops: [NSTextTab] = []
    var x: CGFloat = cellPaddingX
    stops.append(NSTextTab(textAlignment: .left, location: x))
    for w in columnWidths.dropLast() {
        x += w + cellPaddingX * 2
        stops.append(NSTextTab(textAlignment: .left, location: x))
    }

    func rowParagraph() -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.tabStops = stops
        p.defaultTabInterval = 0
        p.lineBreakMode = .byWordWrapping
        p.firstLineHeadIndent = cellPaddingX
        p.headIndent = cellPaddingX
        return p
    }

    func line(_ cells: [NSAttributedString], isHeader: Bool) -> NSAttributedString {
        let out = NSMutableAttributedString()
        // Leading tab so the first cell aligns to the first tab stop (after border).
        for (i, cell) in cells.enumerated() {
            if i > 0 { out.append(NSAttributedString(string: "\t")) }
            out.append(cell)
        }
        out.append(NSAttributedString(string: "\n"))
        let full = NSRange(location: 0, length: out.length)
        let para = rowParagraph()
        out.addAttribute(.paragraphStyle, value: para, range: full)
        out.addAttribute(MarkdownBlockAttribute.blockKind,
                         value: MarkdownBlockAttribute.Kind.tableRow.rawValue, range: full)
        out.addAttribute(MarkdownBlockAttribute.tableColumns, value: dividerNumbers, range: full)
        if isHeader {
            out.addAttribute(MarkdownBlockAttribute.tableHeader, value: true, range: full)
        }
        return out
    }

    let result = NSMutableAttributedString()
    result.append(line(header, isHeader: true))
    for row in rows { result.append(line(row, isHeader: false)) }
    return result
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MarkdownTableLayoutTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MeditKit/MarkdownTableLayout.swift Tests/MeditKitTests/MarkdownTableLayoutTests.swift
git commit -m "feat: build tagged attributed rows for Markdown table views

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: The scrollable selectable table view (`MarkdownTableView`)

A self-contained `NSView` holding a horizontally-scrollable, read-only, selectable
`NSTextView` whose own `MarkdownPreviewLayoutManager` draws the grid + header
shading. This is the live view the preview embeds per table.

**Files:**
- Create: `Sources/MeditKit/MarkdownTableView.swift`
- Test: `Tests/MeditKitTests/MarkdownTableViewTests.swift`

**Interfaces:**
- Consumes: `MarkdownTableLayout` (Tasks 1–2); `MarkdownPreviewLayoutManager`,
  `MarkdownRenderer.Theme`.
- Produces:
  - `final class MarkdownTableView: NSView`
  - `init(header: [NSAttributedString], rows: [[NSAttributedString]], theme: MarkdownRenderer.Theme)`
  - `var intrinsicTableSize: NSSize { get }` — the table's full (scrollable) content
    size: `totalWidth` × sum of row heights + 1.
  - The inner text view is exposed for tests as
    `let textView: NSTextView` (read-only selectable).

- [ ] **Step 1: Write the failing test**

```swift
// Tests/MeditKitTests/MarkdownTableViewTests.swift
import XCTest
import AppKit
@testable import MeditKit

final class MarkdownTableViewTests: XCTestCase {
    private func cell(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: 15)])
    }
    private func theme() -> MarkdownRenderer.Theme { MarkdownTableLayoutTests.testTheme() }

    func testTableViewHoldsSelectableRealText() {
        let v = MarkdownTableView(header: [cell("Name"), cell("Qty")],
                                  rows: [[cell("Apples"), cell("5")]], theme: theme())
        XCTAssertTrue(v.textView.isSelectable)
        XCTAssertFalse(v.textView.isEditable)
        // The cell text is real characters in the storage (not an image).
        XCTAssertTrue(v.textView.string.contains("Apples"))
        XCTAssertTrue(v.textView.string.contains("Qty"))
    }

    func testIntrinsicSizeMatchesLayout() {
        let header = [cell("A"), cell("B")]
        let rows = [[cell("a"), cell("b")], [cell("c"), cell("d")]]
        let v = MarkdownTableView(header: header, rows: rows, theme: theme())
        let widths = MarkdownTableLayout.columnWidths(header: header, rows: rows)
        let expectedWidth = MarkdownTableLayout.totalWidth(columnWidths: widths)
        XCTAssertEqual(v.intrinsicTableSize.width, expectedWidth, accuracy: 1.0)
        XCTAssertGreaterThan(v.intrinsicTableSize.height, 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MarkdownTableViewTests`
Expected: FAIL — `cannot find 'MarkdownTableView' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/MeditKit/MarkdownTableView.swift
import AppKit

/// A Markdown table rendered as real, selectable text in a horizontally-scrollable
/// view. Reuses `MarkdownPreviewLayoutManager` so the grid + header shading draw the
/// same way the rest of the preview's block decorations do. Embedded in the preview
/// as the view backing a `MarkdownTableAttachmentCell`.
public final class MarkdownTableView: NSView {
    public let textView: NSTextView
    private let scrollView = NSScrollView()
    private let tableLayoutManager = MarkdownPreviewLayoutManager()
    private let storage = NSTextStorage()
    public let intrinsicTableSize: NSSize

    public init(header: [NSAttributedString], rows: [[NSAttributedString]],
                theme: MarkdownRenderer.Theme) {
        let widths = MarkdownTableLayout.columnWidths(header: header, rows: rows)
        let attr = MarkdownTableLayout.attributedRows(
            header: header, rows: rows, columnWidths: widths, theme: theme)
        let totalWidth = MarkdownTableLayout.totalWidth(columnWidths: widths)
        var totalHeight: CGFloat = 1   // bottom border
        for row in ([header] + rows) {
            totalHeight += MarkdownTableLayout.rowHeight(row, columnWidths: widths)
        }
        self.intrinsicTableSize = NSSize(width: totalWidth, height: totalHeight)

        // TextKit-1 stack: a non-tracking container sized to the full table width so
        // the table can exceed the visible frame and scroll horizontally.
        storage.addLayoutManager(tableLayoutManager)
        let container = NSTextContainer(
            size: NSSize(width: totalWidth, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        tableLayoutManager.addTextContainer(container)
        let tv = NSTextView(frame: NSRect(origin: .zero, size: intrinsicTableSize),
                            textContainer: container)
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.isHorizontallyResizable = true
        tv.isVerticallyResizable = true
        tv.maxSize = NSSize(width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        tv.textContainerInset = .zero
        self.textView = tv

        super.init(frame: NSRect(origin: .zero, size: intrinsicTableSize))

        tableLayoutManager.palette = MarkdownPreviewLayoutManager.Palette(
            codePanel: .clear, quoteBar: theme.quoteBarColor, rule: theme.tableBorderColor,
            tableBorder: theme.tableBorderColor, tableHeaderFill: theme.codeBackground)
        tv.textStorage?.setAttributedString(attr)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = tv
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MarkdownTableViewTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MeditKit/MarkdownTableView.swift Tests/MeditKitTests/MarkdownTableViewTests.swift
git commit -m "feat: scrollable selectable MarkdownTableView

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Table attachment cell carrying data + size (`MarkdownTableAttachmentCell`)

A TextKit-1 `NSTextAttachmentCell` that (a) reserves the table's intrinsic size via
`cellSize()` so the preview reserves the right line fragment, and (b) carries the
table's structured data + theme so the preview can build the live view. The renderer
emits this; it builds **no** view itself (keeps `MarkdownRenderer` pure).

**Files:**
- Create: `Sources/MeditKit/MarkdownTableAttachment.swift`
- Test: `Tests/MeditKitTests/MarkdownTableAttachmentTests.swift`

**Interfaces:**
- Consumes: `MarkdownTableLayout`, `MarkdownTableView`, `MarkdownRenderer.Theme`.
- Produces:
  - `final class MarkdownTableAttachmentCell: NSTextAttachmentCell`
  - `init(header: [NSAttributedString], rows: [[NSAttributedString]], theme: MarkdownRenderer.Theme)`
  - stored: `let header`, `let rows`, `let theme`, `let tableSize: NSSize`.
  - `override func cellSize() -> NSSize` returns `tableSize`.
  - `override func cellBaselineOffset() -> NSPoint` returns `NSPoint(x: 0, y: 0)`.
  - `override func draw(withFrame:in:)` is a no-op (the live subview draws).
  - `func makeTableView() -> MarkdownTableView` — builds a fresh live view from the
    stored data (called by the preview, never by the renderer).

- [ ] **Step 1: Write the failing test**

```swift
// Tests/MeditKitTests/MarkdownTableAttachmentTests.swift
import XCTest
import AppKit
@testable import MeditKit

final class MarkdownTableAttachmentTests: XCTestCase {
    private func cell(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: 15)])
    }
    private func theme() -> MarkdownRenderer.Theme { MarkdownTableLayoutTests.testTheme() }

    func testCellSizeMatchesTableIntrinsicSize() {
        let header = [cell("A"), cell("B")]
        let rows = [[cell("a"), cell("b")]]
        let c = MarkdownTableAttachmentCell(header: header, rows: rows, theme: theme())
        let v = c.makeTableView()
        XCTAssertEqual(c.cellSize().width, v.intrinsicTableSize.width, accuracy: 1.0)
        XCTAssertEqual(c.cellSize().height, v.intrinsicTableSize.height, accuracy: 1.0)
    }

    func testMakeTableViewCarriesData() {
        let c = MarkdownTableAttachmentCell(
            header: [cell("Name")], rows: [[cell("Bob")]], theme: theme())
        XCTAssertTrue(c.makeTableView().textView.string.contains("Bob"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MarkdownTableAttachmentTests`
Expected: FAIL — `cannot find 'MarkdownTableAttachmentCell' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/MeditKit/MarkdownTableAttachment.swift
import AppKit

/// TextKit-1 attachment cell standing in for a Markdown table in the preview's text
/// flow. It reserves the table's intrinsic size (so the line fragment is the right
/// height) and carries the structured cell data + theme; the live, scrollable
/// `MarkdownTableView` is built on demand by the preview view controller. Keeping the
/// view out of the renderer lets `MarkdownRenderer` stay a pure value type.
public final class MarkdownTableAttachmentCell: NSTextAttachmentCell {
    public let header: [NSAttributedString]
    public let rows: [[NSAttributedString]]
    public let theme: MarkdownRenderer.Theme
    public let tableSize: NSSize

    public init(header: [NSAttributedString], rows: [[NSAttributedString]],
                theme: MarkdownRenderer.Theme) {
        self.header = header
        self.rows = rows
        self.theme = theme
        let widths = MarkdownTableLayout.columnWidths(header: header, rows: rows)
        var h: CGFloat = 1
        for row in ([header] + rows) { h += MarkdownTableLayout.rowHeight(row, columnWidths: widths) }
        self.tableSize = NSSize(width: MarkdownTableLayout.totalWidth(columnWidths: widths), height: h)
        super.init()
    }

    @available(*, unavailable)
    public required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func cellSize() -> NSSize { tableSize }
    public override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: 0) }
    public override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) { /* live subview draws */ }

    /// Build a fresh live table view from the carried data.
    public func makeTableView() -> MarkdownTableView {
        MarkdownTableView(header: header, rows: rows, theme: theme)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MarkdownTableAttachmentTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MeditKit/MarkdownTableAttachment.swift Tests/MeditKitTests/MarkdownTableAttachmentTests.swift
git commit -m "feat: table attachment cell carrying data and intrinsic size

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Renderer table mode + emit the interactive attachment

Give `MarkdownRenderer` a `tableMode` and make `visitTable` emit the interactive
attachment cell (preview) or the existing static image (print). Default
`.interactive`.

**Files:**
- Modify: `Sources/MeditKit/MarkdownRenderer.swift` (the `MarkdownRenderer` struct's
  `init`, the private `AttributedStringBuilder`'s stored `theme`/new `tableMode`,
  and `visitTable` at lines 260–279).
- Test: `Tests/MeditKitTests/MarkdownRendererTableModeTests.swift`

**Interfaces:**
- Consumes: `MarkdownTableAttachmentCell` (Task 4); `MarkdownTableRenderer.image`
  (existing, unchanged).
- Produces:
  - `enum MarkdownRenderer.TableMode { case interactive, static }`
  - `MarkdownRenderer.init(theme: Theme, tableMode: TableMode = .interactive)`
  - `visitTable` emits an `NSTextAttachment` whose `attachmentCell` is a
    `MarkdownTableAttachmentCell` in `.interactive` mode, or whose `image` is the
    `MarkdownTableRenderer` image in `.static` mode.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/MeditKitTests/MarkdownRendererTableModeTests.swift
import XCTest
import AppKit
@testable import MeditKit

final class MarkdownRendererTableModeTests: XCTestCase {
    private func theme() -> MarkdownRenderer.Theme { MarkdownTableLayoutTests.testTheme() }
    private let md = """
    | Name | Qty |
    | ---- | --- |
    | Apples | 5 |
    """

    /// Find the first attachment in a rendered string.
    private func firstAttachment(_ s: NSAttributedString) -> NSTextAttachment? {
        var found: NSTextAttachment?
        s.enumerateAttribute(.attachment, in: NSRange(location: 0, length: s.length)) { v, _, stop in
            if let a = v as? NSTextAttachment { found = a; stop.pointee = true }
        }
        return found
    }

    func testInteractiveModeEmitsTableAttachmentCell() {
        let r = MarkdownRenderer(theme: theme(), tableMode: .interactive)
        let out = r.render(md)
        let att = firstAttachment(out)
        XCTAssertNotNil(att)
        XCTAssertTrue(att?.attachmentCell is MarkdownTableAttachmentCell)
        // Real cell text is carried, not rasterized.
        let cell = att?.attachmentCell as? MarkdownTableAttachmentCell
        XCTAssertTrue(cell?.makeTableView().textView.string.contains("Apples") ?? false)
    }

    func testStaticModeEmitsImageAttachment() {
        let r = MarkdownRenderer(theme: theme(), tableMode: .static)
        let out = r.render(md)
        let att = firstAttachment(out)
        XCTAssertNotNil(att?.image)
        XCTAssertFalse(att?.attachmentCell is MarkdownTableAttachmentCell)
    }

    func testDefaultModeIsInteractive() {
        let out = MarkdownRenderer(theme: theme()).render(md)
        XCTAssertTrue(firstAttachment(out)?.attachmentCell is MarkdownTableAttachmentCell)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MarkdownRendererTableModeTests`
Expected: FAIL — `extra argument 'tableMode' in call` (init has no such parameter).

- [ ] **Step 3: Write minimal implementation**

In `Sources/MeditKit/MarkdownRenderer.swift`:

3a. Add the mode enum and thread it through the public type. Replace the
`private let theme` / `init` block (lines 32–33) region:

```swift
    public enum TableMode { case interactive, `static` }

    private let theme: Theme
    private let tableMode: TableMode
    public init(theme: Theme, tableMode: TableMode = .interactive) {
        self.theme = theme
        self.tableMode = tableMode
    }

    public func render(_ markdown: String) -> NSAttributedString {
        let document = Document(parsing: markdown)
        var builder = AttributedStringBuilder(theme: theme, tableMode: tableMode)
        return builder.build(document)
    }
```

3b. In `private struct AttributedStringBuilder`, add the stored mode next to `theme`
(near line 45) and its init (line 55):

```swift
    let theme: MarkdownRenderer.Theme
    let tableMode: MarkdownRenderer.TableMode
```

```swift
    init(theme: MarkdownRenderer.Theme,
         tableMode: MarkdownRenderer.TableMode = .interactive) {
        self.theme = theme
        self.tableMode = tableMode
    }
```

3c. Replace the body of `visitTable` (lines 269–272, the image+attachment lines)
with a mode branch. The cell-collection lines above it stay unchanged:

```swift
        let attachment = NSTextAttachment()
        switch tableMode {
        case .interactive:
            attachment.attachmentCell = MarkdownTableAttachmentCell(
                header: headerCells, rows: rows, theme: theme)
        case .static:
            let image = MarkdownTableRenderer.image(header: headerCells, rows: rows, theme: theme)
            attachment.image = image
            attachment.bounds = NSRect(origin: .zero, size: image.size)
        }
```

(Leave the `let para = bodyParagraph(...)`, `attStr`, and `out.append(...)` lines
that follow exactly as they are.)

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MarkdownRendererTableModeTests`
Expected: PASS (3 tests). Also run `swift test` to confirm no regression in existing
renderer tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/MeditKit/MarkdownRenderer.swift Tests/MeditKitTests/MarkdownRendererTableModeTests.swift
git commit -m "feat: renderer table mode (interactive cell vs static image)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Printer uses static mode

Point the Markdown printer at `.static` so paper keeps the full-width drawn grid
(the image), unaffected by the new interactive preview path.

**Files:**
- Modify: `Sources/MeditKit/MarkdownPrinter.swift:55`
- Test: `Tests/MeditKitTests/MarkdownPrinterTableModeTests.swift`

**Interfaces:**
- Consumes: `MarkdownRenderer.init(theme:tableMode:)` (Task 5).
- Produces: no new API; behavior change only (printer renders tables as images).

- [ ] **Step 1: Write the failing test**

This test inspects the printer's *own* operation — driving the real code path, so it
fails until the printer is switched to `.static`. (The printer's text view is
`op.view`; `MarkdownPrinter.operation` builds it. `printTheme()` is internal, but the
test goes through `operation(forMarkdown:)`, so no access change is needed.)

```swift
// Tests/MeditKitTests/MarkdownPrinterTableModeTests.swift
import XCTest
import AppKit
@testable import MeditKit

final class MarkdownPrinterTableModeTests: XCTestCase {
    func testPrinterOperationRendersStaticTable() {
        let op = MarkdownPrinter.operation(forMarkdown: "| A | B |\n| - | - |\n| 1 | 2 |")
        let tv = op.view as? NSTextView
        XCTAssertNotNil(tv)
        var att: NSTextAttachment?
        tv?.textStorage?.enumerateAttribute(.attachment,
            in: NSRange(location: 0, length: tv?.textStorage?.length ?? 0)) { v, _, stop in
            if let a = v as? NSTextAttachment { att = a; stop.pointee = true }
        }
        XCTAssertNotNil(att?.image, "printer should rasterize tables to a static grid")
        XCTAssertFalse(att?.attachmentCell is MarkdownTableAttachmentCell)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MarkdownPrinterTableModeTests`
Expected: FAIL — `att?.image` is nil because the printer still uses the default
interactive renderer (which emits a `MarkdownTableAttachmentCell`, not an image).

- [ ] **Step 3: Write minimal implementation**

In `Sources/MeditKit/MarkdownPrinter.swift`, change line 55 from:

```swift
        textView.textStorage?.setAttributedString(MarkdownRenderer(theme: theme).render(markdown))
```

to:

```swift
        textView.textStorage?.setAttributedString(
            MarkdownRenderer(theme: theme, tableMode: .static).render(markdown))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MarkdownPrinterTableModeTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MeditKit/MarkdownPrinter.swift Tests/MeditKitTests/MarkdownPrinterTableModeTests.swift
git commit -m "feat: print Markdown tables as static grid

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Embed live table subviews in the preview

Wire the live `MarkdownTableView`s into the preview: after each render, find every
`MarkdownTableAttachmentCell`, build its view, and position it at its attachment's
glyph rect; reposition on resize. This is the integration that makes tables visible
and interactive on screen.

**Files:**
- Modify: `Sources/MeditKit/EditorViewController.swift` (the `renderPreview()` method
  at line 454; add a subview-placement pass + a stored array of placed views; hook
  the preview scroll view's resize).

**Interfaces:**
- Consumes: `MarkdownTableAttachmentCell.makeTableView()` (Task 4); the preview's
  `previewTextView` and `previewLayoutManager` (existing stored properties).
- Produces: internal behavior only. New private members:
  - `private var tableSubviews: [NSView] = []`
  - `private func placeTableSubviews()`

- [ ] **Step 1: Write the failing test**

This is view-integration code; assert the placement logic via a focused unit test
that drives the same helper against a constructed text view. Add a testable seam: a
free function that, given a layout manager + text view, returns the attachment glyph
rects and their cells. Put it in `MarkdownTableAttachment.swift` so it is unit-pure.

```swift
// add to Tests/MeditKitTests/MarkdownTableAttachmentTests.swift
func testEnumerateTableAttachmentsReturnsCellAndRect() {
    let theme = MarkdownTableLayoutTests.testTheme()
    let storage = NSTextStorage()
    let layout = MarkdownPreviewLayoutManager()
    storage.addLayoutManager(layout)
    let container = NSTextContainer(size: NSSize(width: 600, height: .greatestFiniteMagnitude))
    layout.addTextContainer(container)
    let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: container)

    let rendered = MarkdownRenderer(theme: theme, tableMode: .interactive)
        .render("intro\n\n| A | B |\n| - | - |\n| 1 | 2 |\n\noutro")
    tv.textStorage?.setAttributedString(rendered)
    layout.ensureLayout(for: container)

    let placements = MarkdownTablePlacement.placements(in: tv)
    XCTAssertEqual(placements.count, 1)
    XCTAssertTrue(placements[0].cell.makeTableView().textView.string.contains("1"))
    XCTAssertGreaterThan(placements[0].rect.height, 0)
    XCTAssertGreaterThan(placements[0].rect.width, 0)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MarkdownTableAttachmentTests/testEnumerateTableAttachmentsReturnsCellAndRect`
Expected: FAIL — `cannot find 'MarkdownTablePlacement' in scope`.

- [ ] **Step 3a: Add the pure placement helper**

Append to `Sources/MeditKit/MarkdownTableAttachment.swift`:

```swift
/// Locates `MarkdownTableAttachmentCell`s in a laid-out preview text view and the
/// glyph rect each occupies, so the preview can position live table subviews. Pure
/// w.r.t. the text view's existing layout (no mutation).
public enum MarkdownTablePlacement {
    public struct Placement {
        public let cell: MarkdownTableAttachmentCell
        public let rect: NSRect   // in text-view coordinates (text container origin applied)
    }

    public static func placements(in textView: NSTextView) -> [Placement] {
        guard let layout = textView.layoutManager,
              let container = textView.textContainer,
              let storage = textView.textStorage else { return [] }
        let origin = textView.textContainerOrigin
        var result: [Placement] = []
        storage.enumerateAttribute(.attachment,
            in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let att = value as? NSTextAttachment,
                  let cell = att.attachmentCell as? MarkdownTableAttachmentCell else { return }
            let glyphRange = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layout.boundingRect(forGlyphRange: glyphRange, in: container)
            rect.origin.x += origin.x
            rect.origin.y += origin.y
            result.append(Placement(cell: cell, rect: rect))
        }
        return result
    }
}
```

- [ ] **Step 3b: Run the unit test to verify it passes**

Run: `swift test --filter MarkdownTableAttachmentTests`
Expected: PASS (3 tests).

- [ ] **Step 3c: Wire placement into the preview**

In `Sources/MeditKit/EditorViewController.swift`:

Add stored property near the other preview members (e.g. just after the
`previewTextView` declaration — find it with
`grep -n "previewTextView" Sources/MeditKit/EditorViewController.swift`):

```swift
    private var tableSubviews: [NSView] = []
```

At the end of `renderPreview()` (right after the existing
`tv.textContainerInset = NSSize(width: 24, height: 20)` line), force layout and place
the subviews:

```swift
        // Embed live, selectable table subviews over their attachment slots.
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        placeTableSubviews()
```

Add the placement method (anywhere in the class, e.g. right after `renderPreview()`):

```swift
    /// Tear down and re-place the live `MarkdownTableView`s for the current render.
    private func placeTableSubviews() {
        guard let tv = previewTextView else { return }
        tableSubviews.forEach { $0.removeFromSuperview() }
        tableSubviews.removeAll()
        for placement in MarkdownTablePlacement.placements(in: tv) {
            let view = placement.cell.makeTableView()
            // Clamp the visible frame to the available content width so a wide table
            // shows its own horizontal scroller instead of widening the preview.
            let available = tv.bounds.width - tv.textContainerInset.width * 2
            var frame = placement.rect
            frame.size.width = min(frame.size.width, max(available, 0))
            view.frame = frame
            view.autoresizingMask = []
            tv.addSubview(view)
            tableSubviews.append(view)
        }
    }
```

Reposition on resize: find where the preview reacts to width changes. The editor uses
`scrollViewContentDidResize()` for the source view; the preview re-renders on the
same notifications via `schedulePreviewRefresh()`. To reposition tables on a plain
resize (no text change), observe the preview scroll view's frame. Add, inside
`makePreview()` (after `previewScrollView = sv`), a bounds-change observer:

```swift
        sv.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(previewViewportChanged),
            name: NSView.frameDidChangeNotification, object: sv)
        sv.postsFrameChangedNotifications = true
```

And the handler (near `placeTableSubviews()`):

```swift
    @objc private func previewViewportChanged() {
        guard isShowingPreview, previewTextView != nil else { return }
        placeTableSubviews()
    }
```

- [ ] **Step 4: Build and run the app to verify visually**

Run: `swift build` then launch the built app via the project's run path
(`grep -rn "xcodebuild" docs/ | head` for the exact invocation; the standard one is
`xcodebuild -scheme medit -configuration Debug build` then open the built `.app`).
Open a Markdown file containing a table, switch to preview, and confirm:
- table text can be selected with the mouse and copied (Cmd-C) to paste real text;
- a table wider than the window shows a horizontal scrollbar and scrolls;
- prose above/below still wraps to the window.

Expected: all three behaviors hold.

- [ ] **Step 5: Commit**

```bash
git add Sources/MeditKit/MarkdownTableAttachment.swift Sources/MeditKit/EditorViewController.swift Tests/MeditKitTests/MarkdownTableAttachmentTests.swift
git commit -m "feat: embed live selectable table subviews in Markdown preview

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: Full-suite regression + AP screenshot verification

Confirm nothing regressed and capture the selectable/scrollable behavior the way the
project documents features.

**Files:**
- Modify (if needed): `docs/autopilot-feedback.md` (per the standing rule, update
  before any merge — even if "nothing new").
- Reference: `uitests/README.md` (AP tagged controls; `markdownPreviewTextView`).

**Interfaces:** none (verification task).

- [ ] **Step 1: Run the full test suite**

Run: `swift test`
Expected: all tests pass, including the four new test files
(`MarkdownTableLayoutTests`, `MarkdownTableViewTests`, `MarkdownTableAttachmentTests`,
`MarkdownRendererTableModeTests`, `MarkdownPrinterTableModeTests`).

- [ ] **Step 2: Manual selection + copy check**

With the app running on a table-containing Markdown file in preview mode:
- drag-select inside a table → the selection highlight appears over real text;
- Cmd-C, then paste into the editor → the pasted text is the cell contents (tab- or
  newline-separated), NOT empty and NOT an image placeholder.

Expected: real text round-trips.

- [ ] **Step 3: Wide-table horizontal-scroll check**

Open a Markdown file with a table whose columns exceed the window width. In preview:
- the table shows a horizontal scrollbar (autohiding) and scrolls to reveal
  off-screen columns;
- narrowing the window keeps prose wrapping while the table scroller remains.

Expected: independent horizontal scroll; prose unaffected.

- [ ] **Step 4: Update AP findings doc**

Append an entry to `docs/autopilot-feedback.md` recording this change and any AP
observations (or "nothing new") per the standing pre-merge rule. Use the existing
entry format in that file (read the last entry first:
`tail -40 docs/autopilot-feedback.md`).

- [ ] **Step 5: Commit**

```bash
git add docs/autopilot-feedback.md
git commit -m "docs: AP findings for selectable Markdown tables

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## After all tasks

Use **superpowers:finishing-a-development-branch** to verify tests, then present
merge/PR options. This feature ships as its own version bump following the standing
medit release flow (branch → PR → CI → `--admin` merge → tag → universal build →
GitHub Release); the release itself is a separate step the user drives.
