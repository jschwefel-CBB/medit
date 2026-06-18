# medit 1.5 — Rainbow-Depth Brackets Implementation Plan

> **For agentic workers:** Implement task-by-task. Steps use checkbox (`- [ ]`) syntax. TDD for pure logic; build + live-verify AppKit. DRY, YAGNI, frequent commits.

**Goal:** Always-on depth coloring of every bracket (shared-stack, VS Code style) via layout-manager temporary attributes that survive the syntax highlighter, plus innermost-enclosing-pair emphasis at the caret, with 3 toggles.

**Architecture:** A pure `BracketDepthScanner` (text → `[BracketHit]`) + an AppKit `BracketColorizer` that paints depth colors and caret emphasis as `NSLayoutManager` temporary attributes (an overlay layer independent of the highlighter's text-storage colors). `EditorViewController` owns the colorizer and drives it from the text/selection/appearance hooks. Reuses `BracketMatcher` for the enclosing-pair lookup.

**Tech Stack:** Swift 6, AppKit (classic NSLayoutManager TextKit), XCTest.

**Branch:** `feature/rainbow-brackets-1.5` (created; the spec commit is already on it).

---

## Task 1: `BracketDepthScanner` (pure scanner)

**Files:**
- Create: `Sources/MeditKit/BracketDepthScanner.swift`
- Create: `Tests/MeditKitTests/BracketDepthScannerTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import MeditKit

final class BracketDepthScannerTests: XCTestCase {

    private func depths(_ s: String) -> [Int] {
        BracketDepthScanner.scan(s).map(\.depth)
    }

    func testNestedSameFamilyDepths() {
        // ( ( ) )  -> 0 1 1 0
        XCTAssertEqual(depths("(())"), [0, 1, 1, 0])
    }

    func testMixedFamiliesShareDepth() {
        // ( [ { } ] )  -> 0 1 2 2 1 0
        XCTAssertEqual(depths("([{}])"), [0, 1, 2, 2, 1, 0])
    }

    func testAdjacentClosers() {
        // { { } }  -> 0 1 1 0
        XCTAssertEqual(depths("{{}}"), [0, 1, 1, 0])
    }

    func testStrayCloserIsUnmatched() {
        let hits = BracketDepthScanner.scan(")")
        XCTAssertEqual(hits.count, 1)
        XCTAssertTrue(hits[0].unmatched)
        XCTAssertFalse(hits[0].isOpen)
        XCTAssertEqual(hits[0].depth, 0)
    }

    func testFamilyMismatchCloserIsUnmatched() {
        // ( ]  -> '(' open depth 0; ']' mismatches '(' so unmatched, stack not popped
        let hits = BracketDepthScanner.scan("(]")
        XCTAssertEqual(hits.count, 2)
        XCTAssertTrue(hits[0].isOpen); XCTAssertFalse(hits[0].unmatched); XCTAssertEqual(hits[0].depth, 0)
        XCTAssertFalse(hits[1].isOpen); XCTAssertTrue(hits[1].unmatched)
    }

    func testUnclosedOpenerKeepsDepthNotUnmatched() {
        // ( (  -> both openers, depths 0,1, neither flagged unmatched (mid-typing tolerance)
        let hits = BracketDepthScanner.scan("((")
        XCTAssertEqual(hits.map(\.depth), [0, 1])
        XCTAssertFalse(hits.contains { $0.unmatched })
    }

    func testEmptyAndNoBrackets() {
        XCTAssertTrue(BracketDepthScanner.scan("").isEmpty)
        XCTAssertTrue(BracketDepthScanner.scan("no brackets here").isEmpty)
    }

    func testOffsetsAreCharacterOffsets() {
        // "a(b)c" -> '(' at char 1, ')' at char 3
        let hits = BracketDepthScanner.scan("a(b)c")
        XCTAssertEqual(hits.map(\.offset), [1, 3])
    }

    func testMultibyteOffsets() {
        // An emoji before a bracket: offsets are CHARACTER offsets, not UTF-16 units.
        // "😀(x)" -> '(' at char 1, ')' at char 3
        let hits = BracketDepthScanner.scan("😀(x)")
        XCTAssertEqual(hits.map(\.offset), [1, 3])
        XCTAssertEqual(hits.map(\.kind), ["(", ")"])
    }

    func testKindAndIsOpenRecorded() {
        let hits = BracketDepthScanner.scan("[]")
        XCTAssertEqual(hits[0].kind, "["); XCTAssertTrue(hits[0].isOpen)
        XCTAssertEqual(hits[1].kind, "]"); XCTAssertFalse(hits[1].isOpen)
    }

    func testLargeInputSanity() {
        let s = String(repeating: "(a)", count: 5000)
        let hits = BracketDepthScanner.scan(s)
        XCTAssertEqual(hits.count, 10000)
        XCTAssertTrue(hits.allSatisfy { $0.depth == 0 && !$0.unmatched })
    }
}
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter BracketDepthScannerTests`
Expected: compile failure (no such type).

- [ ] **Step 3: Implement the scanner**

```swift
import Foundation

/// One bracket found in the text, with its nesting depth. Pure value type —
/// no AppKit. `depth` is 0 for the outermost pair; the colorizer cycles it %6.
public struct BracketHit: Equatable {
    public let offset: Int        // character offset into the String
    public let kind: Character    // one of ( ) [ ] { }
    public let isOpen: Bool
    public let depth: Int
    public let unmatched: Bool    // stray closer or family mismatch

    public init(offset: Int, kind: Character, isOpen: Bool, depth: Int, unmatched: Bool) {
        self.offset = offset; self.kind = kind; self.isOpen = isOpen
        self.depth = depth; self.unmatched = unmatched
    }
}

/// Classifies every ()[]{} in `text` with a shared nesting depth (one stack
/// across all three families). Tolerant of mismatches so coloring stays stable
/// while the user is mid-typing: a stray/family-mismatched closer is flagged
/// `unmatched` (depth 0) and does not pop; unclosed openers keep their depth.
public enum BracketDepthScanner {

    private static let openers: [Character: Character] = [")": "(", "]": "[", "}": "{"]
    private static let openSet: Set<Character> = ["(", "[", "{"]
    private static let closeSet: Set<Character> = [")", "]", "}"]

    public static func scan(_ text: String) -> [BracketHit] {
        var hits: [BracketHit] = []
        var stack: [(kind: Character, depth: Int)] = []
        var offset = 0
        for ch in text {
            if openSet.contains(ch) {
                let depth = stack.count
                stack.append((ch, depth))
                hits.append(BracketHit(offset: offset, kind: ch, isOpen: true, depth: depth, unmatched: false))
            } else if closeSet.contains(ch) {
                if let top = stack.last, top.kind == openers[ch] {
                    stack.removeLast()
                    hits.append(BracketHit(offset: offset, kind: ch, isOpen: false, depth: top.depth, unmatched: false))
                } else {
                    // Empty stack or different family on top: unmatched, don't pop.
                    hits.append(BracketHit(offset: offset, kind: ch, isOpen: false, depth: 0, unmatched: true))
                }
            }
            offset += 1
        }
        return hits
    }
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `swift test --filter BracketDepthScannerTests`
Expected: PASS (all cases).

- [ ] **Step 5: Commit**

```bash
git add Sources/MeditKit/BracketDepthScanner.swift Tests/MeditKitTests/BracketDepthScannerTests.swift
git commit -m "Add BracketDepthScanner: shared-stack bracket depth classification"
```

---

## Task 2: Enclosing-pair helper in `BracketMatcher`

**Files:**
- Modify: `Sources/MeditKit/BracketMatcher.swift`
- Create/Modify: `Tests/MeditKitTests/BracketMatcherTests.swift` (add cases)

- [ ] **Step 1: Read the current `BracketMatcher`** to reuse its scan style.

Run: open `Sources/MeditKit/BracketMatcher.swift` (≈58 lines). It already has `matchingOffset(in:at:)` and a private depth-counting `match(_:at:)`. Keep both.

- [ ] **Step 2: Write failing tests** (append to `BracketMatcherTests.swift`)

```swift
func testEnclosingPairInOpenSpace() {
    // "f( a, [ b ] )"  caret between b and ] -> innermost enclosing is the [ ] pair.
    // indices: f0 (1  space2 a3 ,4 space5 [6 space7 b8 space9 ]10 space11 )12
    let text = "f( a, [ b ] )"
    let pair = BracketMatcher.enclosingPair(in: text, at: 9) // just after 'b'
    XCTAssertEqual(pair?.open, 6)
    XCTAssertEqual(pair?.close, 10)
}

func testEnclosingPairFallsToOuter() {
    let text = "f( a, [ b ] )"
    // caret right after ']' (offset 11) is NOT inside [ ]; innermost enclosing is ( ).
    let pair = BracketMatcher.enclosingPair(in: text, at: 11)
    XCTAssertEqual(pair?.open, 1)
    XCTAssertEqual(pair?.close, 12)
}

func testEnclosingPairNoneAtTopLevel() {
    XCTAssertNil(BracketMatcher.enclosingPair(in: "abc def", at: 3))
    XCTAssertNil(BracketMatcher.enclosingPair(in: "", at: 0))
}

func testEnclosingPairInnermostWhenNested() {
    // "((x))" caret at offset 2 (the x) -> innermost enclosing is inner ( ) = 1..3
    let pair = BracketMatcher.enclosingPair(in: "((x))", at: 2)
    XCTAssertEqual(pair?.open, 1)
    XCTAssertEqual(pair?.close, 3)
}
```

- [ ] **Step 3: Run, verify fail**

Run: `swift test --filter BracketMatcherTests`
Expected: FAIL (no `enclosingPair`).

- [ ] **Step 4: Implement `enclosingPair`** (add to the `BracketMatcher` enum)

```swift
/// The innermost bracket pair that strictly encloses `offset` (caret position
/// between characters). Returns the opener/closer character offsets, or nil if
/// the caret is not inside any balanced pair. Shared across families.
public static func enclosingPair(in text: String, at offset: Int) -> (open: Int, close: Int)? {
    let chars = Array(text)
    guard offset >= 0, offset <= chars.count else { return nil }

    let openers: Set<Character> = ["(", "[", "{"]
    let closers: [Character: Character] = [")": "(", "]": "[", "}": "{"]

    // Scan left from the caret, tracking how many closers we've stepped over;
    // the first opener that isn't cancelled by a seen closer is our enclosing opener.
    var pendingClose = 0
    var openIndex = -1
    var openKind: Character = "("
    var i = offset - 1
    while i >= 0 {
        let c = chars[i]
        if closers[c] != nil {
            pendingClose += 1
        } else if openers.contains(c) {
            if pendingClose == 0 { openIndex = i; openKind = c; break }
            pendingClose -= 1
        }
        i -= 1
    }
    guard openIndex >= 0 else { return nil }

    // Scan right from the caret for the matching closer of openKind, honoring nesting.
    let wantClose: Character = openKind == "(" ? ")" : (openKind == "[" ? "]" : "}")
    var depth = 0
    var j = offset
    while j < chars.count {
        let c = chars[j]
        if c == openKind {
            depth += 1
        } else if c == wantClose {
            if depth == 0 { return (openIndex, j) }
            depth -= 1
        }
        j += 1
    }
    return nil
}
```

> Note: this matches only same-`openKind` nesting on the right scan, which is a simplification but correct for well-formed code and good enough for caret emphasis. The left scan uses a generic closer/opener counter so any family cancels, which is what "innermost enclosing" needs.

- [ ] **Step 5: Run tests, verify pass**

Run: `swift test --filter BracketMatcherTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/MeditKit/BracketMatcher.swift Tests/MeditKitTests/BracketMatcherTests.swift
git commit -m "BracketMatcher: add innermost enclosing-pair lookup"
```

---

## Task 3: Depth colors + emphasis-style enum

**Files:**
- Modify: `Sources/MeditKit/EditorColors.swift`
- Modify: `Sources/MeditKit/Preferences.swift` (enum only here; the 3 prefs come in Task 5)

- [ ] **Step 1: Read `EditorColors.swift`** to match the appearance-aware `NSColor` idiom (it currently defines `foreground`).

- [ ] **Step 2: Add the depth palette + unmatched color** to `EditorColors`

```swift
/// Rainbow-bracket depth palette (cycled %6) plus the unmatched-bracket color.
/// Appearance-aware, mirroring `foreground`.
public static let bracketDepthColors: [NSColor] = [
    dynamic(light: NSColor(srgbRed: 0.72, green: 0.52, blue: 0.04, alpha: 1),   // gold
            dark:  NSColor(srgbRed: 0.95, green: 0.80, blue: 0.35, alpha: 1)),
    dynamic(light: NSColor(srgbRed: 0.52, green: 0.25, blue: 0.70, alpha: 1),   // violet
            dark:  NSColor(srgbRed: 0.78, green: 0.62, blue: 0.95, alpha: 1)),
    dynamic(light: NSColor(srgbRed: 0.13, green: 0.43, blue: 0.85, alpha: 1),   // blue
            dark:  NSColor(srgbRed: 0.45, green: 0.72, blue: 0.99, alpha: 1)),
    dynamic(light: NSColor(srgbRed: 0.12, green: 0.55, blue: 0.24, alpha: 1),   // green
            dark:  NSColor(srgbRed: 0.50, green: 0.85, blue: 0.55, alpha: 1)),
    dynamic(light: NSColor(srgbRed: 0.80, green: 0.45, blue: 0.10, alpha: 1),   // orange
            dark:  NSColor(srgbRed: 0.98, green: 0.70, blue: 0.40, alpha: 1)),
    dynamic(light: NSColor(srgbRed: 0.05, green: 0.55, blue: 0.55, alpha: 1),   // teal
            dark:  NSColor(srgbRed: 0.40, green: 0.85, blue: 0.85, alpha: 1)),
]

public static let bracketUnmatchedColor: NSColor =
    dynamic(light: NSColor(srgbRed: 0.70, green: 0.30, blue: 0.30, alpha: 1),
            dark:  NSColor(srgbRed: 0.85, green: 0.45, blue: 0.45, alpha: 1))

/// Color for a bracket at the given nesting depth (cycles through the palette).
public static func bracketColor(forDepth depth: Int) -> NSColor {
    bracketDepthColors[((depth % bracketDepthColors.count) + bracketDepthColors.count) % bracketDepthColors.count]
}
```

If `EditorColors` doesn't already have a `dynamic(light:dark:)` helper, add it (matching how `foreground` is built — likely `NSColor(name:nil) { $0.isDark ? dark : light }` using the existing `NSAppearance.isDark`):

```swift
/// Appearance-resolving color: picks `dark` under a dark effective appearance.
static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
    NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
    }
}
```

- [ ] **Step 3: Add the emphasis-style enum** to `Preferences.swift` (top-level, beside `AppAppearance`)

```swift
/// How the caret's enclosing bracket pair is emphasized.
public enum EnclosingPairEmphasisStyle: String, CaseIterable {
    case bold
    case underline
    case background
}
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: success.

- [ ] **Step 5: Commit**

```bash
git add Sources/MeditKit/EditorColors.swift Sources/MeditKit/Preferences.swift
git commit -m "Add bracket depth palette + EnclosingPairEmphasisStyle enum"
```

---

## Task 4: `BracketColorizer` (AppKit overlay)

**Files:**
- Create: `Sources/MeditKit/BracketColorizer.swift`

- [ ] **Step 1: Implement the colorizer**

```swift
import AppKit

/// Paints rainbow-depth bracket colors and caret-pair emphasis as layout-manager
/// TEMPORARY attributes — an overlay that layers over the syntax highlighter's
/// text-storage colors and is never clobbered by it. The owner drives refresh()
/// on text change and updateCaretEmphasis() on selection change.
public final class BracketColorizer {

    private weak var textView: NSTextView?
    public var emphasizeEnclosingPair = true
    public var emphasisStyle: EnclosingPairEmphasisStyle = .bold

    /// Ranges (UTF-16) currently carrying caret emphasis, so we can clear them.
    private var emphasisRanges: [NSRange] = []
    private var refreshScheduled = false

    public init(textView: NSTextView) {
        self.textView = textView
    }

    private var layoutManager: NSLayoutManager? { textView?.layoutManager }

    // MARK: Depth coloring

    /// Recompute and repaint all depth colors (debounced ~0.15s, like the highlighter).
    public func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.refreshScheduled = false
            self?.refresh()
        }
    }

    /// Immediate repaint (used on appearance flip / initial apply).
    public func refresh() {
        guard let textView, let lm = layoutManager else { return }
        let text = textView.string
        let full = NSRange(location: 0, length: (text as NSString).length)
        lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)

        let hits = BracketDepthScanner.scan(text)
        guard !hits.isEmpty else { reapplyEmphasis(); return }

        // Map character offsets to UTF-16 ranges in one pass.
        let ns = text as NSString
        // Build a character-index -> utf16 location map lazily via String.Index.
        let scalars = Array(text)
        var utf16Locations = [Int](repeating: 0, count: scalars.count + 1)
        var loc = 0
        for (i, ch) in scalars.enumerated() {
            utf16Locations[i] = loc
            loc += String(ch).utf16.count
        }
        utf16Locations[scalars.count] = loc

        for hit in hits {
            guard hit.offset < scalars.count else { continue }
            let start = utf16Locations[hit.offset]
            let len = String(scalars[hit.offset]).utf16.count
            let r = NSRange(location: start, length: len)
            guard NSMaxRange(r) <= ns.length else { continue }
            let color = hit.unmatched ? EditorColors.bracketUnmatchedColor
                                      : EditorColors.bracketColor(forDepth: hit.depth)
            lm.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: r)
        }
        reapplyEmphasis()
    }

    // MARK: Caret emphasis

    public func updateCaretEmphasis() {
        clearEmphasis()
        guard emphasizeEnclosingPair, let textView, let lm = layoutManager else { return }
        let text = textView.string
        let sel = textView.selectedRange()
        // Convert the UTF-16 caret location to a character offset.
        let charOffset = (text as NSString).substring(to: min(sel.location, (text as NSString).length)).count
        guard let pair = BracketMatcher.enclosingPair(in: text, at: charOffset) else { return }

        let scalars = Array(text)
        func utf16Range(forChar idx: Int) -> NSRange? {
            guard idx >= 0, idx < scalars.count else { return nil }
            var loc = 0
            for k in 0..<idx { loc += String(scalars[k]).utf16.count }
            let len = String(scalars[idx]).utf16.count
            return NSRange(location: loc, length: len)
        }
        let ranges = [pair.open, pair.close].compactMap(utf16Range(forChar:))
        let ns = text as NSString
        for r in ranges where NSMaxRange(r) <= ns.length {
            applyEmphasis(to: r, lm: lm)
            emphasisRanges.append(r)
        }
    }

    private func applyEmphasis(to r: NSRange, lm: NSLayoutManager) {
        switch emphasisStyle {
        case .bold:
            if let base = textView?.font,
               let bold = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask) as NSFont? {
                lm.addTemporaryAttribute(.font, value: bold, forCharacterRange: r)
            }
        case .underline:
            lm.addTemporaryAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, forCharacterRange: r)
        case .background:
            // Subtle wash using the bracket's own depth color at low alpha.
            if let fg = lm.temporaryAttribute(.foregroundColor, atCharacterIndex: r.location,
                                              effectiveRange: nil) as? NSColor {
                lm.addTemporaryAttribute(.backgroundColor, value: fg.withAlphaComponent(0.18), forCharacterRange: r)
            }
        }
    }

    private func clearEmphasis() {
        guard let lm = layoutManager else { emphasisRanges.removeAll(); return }
        for r in emphasisRanges {
            lm.removeTemporaryAttribute(.font, forCharacterRange: r)
            lm.removeTemporaryAttribute(.underlineStyle, forCharacterRange: r)
            lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: r)
        }
        emphasisRanges.removeAll()
    }

    private func reapplyEmphasis() { updateCaretEmphasis() }

    // MARK: Teardown

    /// Remove every temporary attribute this colorizer applies (on toggle-off).
    public func clear() {
        guard let textView, let lm = layoutManager else { return }
        let full = NSRange(location: 0, length: (textView.string as NSString).length)
        lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
        lm.removeTemporaryAttribute(.font, forCharacterRange: full)
        lm.removeTemporaryAttribute(.underlineStyle, forCharacterRange: full)
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
        emphasisRanges.removeAll()
    }
}
```

> Perf note: `refresh()` rebuilds a per-character UTF-16 offset map (O(n)); the per-call `utf16Range` in `updateCaretEmphasis` is O(n) but runs only for 2 brackets and only on caret moves. Acceptable for typical files; revisit only if profiling shows lag.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add Sources/MeditKit/BracketColorizer.swift
git commit -m "Add BracketColorizer: temporary-attribute depth overlay + caret emphasis"
```

---

## Task 5: Preferences for the 3 toggles

**Files:**
- Modify: `Sources/MeditKit/Preferences.swift`
- Modify: `Tests/MeditKitTests/PreferencesTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
func testRainbowBracketDefaultsAndPersist() {
    XCTAssertTrue(prefs.rainbowBrackets)
    XCTAssertTrue(prefs.emphasizeEnclosingPair)
    XCTAssertEqual(prefs.enclosingPairEmphasisStyle, .bold)
    prefs.rainbowBrackets = false
    prefs.emphasizeEnclosingPair = false
    prefs.enclosingPairEmphasisStyle = .underline
    let r = Preferences(defaults: defaults)
    XCTAssertFalse(r.rainbowBrackets)
    XCTAssertFalse(r.emphasizeEnclosingPair)
    XCTAssertEqual(r.enclosingPairEmphasisStyle, .underline)
}

func testEmphasisStyleRoundTripsAllCases() {
    for style in EnclosingPairEmphasisStyle.allCases {
        prefs.enclosingPairEmphasisStyle = style
        XCTAssertEqual(Preferences(defaults: defaults).enclosingPairEmphasisStyle, style)
    }
}
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter PreferencesTests`
Expected: FAIL.

- [ ] **Step 3: Add keys** (in `Preferences.Key`)

```swift
static let rainbowBrackets = "rainbowBrackets"
static let emphasizeEnclosingPair = "emphasizeEnclosingPair"
static let enclosingPairEmphasisStyle = "enclosingPairEmphasisStyle"
```

- [ ] **Step 4: Register defaults**

```swift
Key.rainbowBrackets: true,
Key.emphasizeEnclosingPair: true,
Key.enclosingPairEmphasisStyle: EnclosingPairEmphasisStyle.bold.rawValue,
```

- [ ] **Step 5: Add properties**

```swift
// MARK: Rainbow brackets
public var rainbowBrackets: Bool {
    get { defaults.bool(forKey: Key.rainbowBrackets) }
    set { defaults.set(newValue, forKey: Key.rainbowBrackets); didChange() }
}
public var emphasizeEnclosingPair: Bool {
    get { defaults.bool(forKey: Key.emphasizeEnclosingPair) }
    set { defaults.set(newValue, forKey: Key.emphasizeEnclosingPair); didChange() }
}
public var enclosingPairEmphasisStyle: EnclosingPairEmphasisStyle {
    get { EnclosingPairEmphasisStyle(rawValue: defaults.string(forKey: Key.enclosingPairEmphasisStyle) ?? "") ?? .bold }
    set { defaults.set(newValue.rawValue, forKey: Key.enclosingPairEmphasisStyle); didChange() }
}
```

- [ ] **Step 6: Run tests, verify pass**

Run: `swift test --filter PreferencesTests`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/MeditKit/Preferences.swift Tests/MeditKitTests/PreferencesTests.swift
git commit -m "Add rainbow-bracket preferences (master, emphasis, style)"
```

---

## Task 6: Wire the colorizer into `EditorViewController`

**Files:**
- Modify: `Sources/MeditKit/EditorViewController.swift`

- [ ] **Step 1: Add a stored property** next to `highlighter`:

```swift
private var bracketColorizer: BracketColorizer?
```

- [ ] **Step 2: Add `configureBracketColorizer()`** (near `configureHighlighter()`):

```swift
private func configureBracketColorizer() {
    if prefs.rainbowBrackets {
        let colorizer = bracketColorizer ?? BracketColorizer(textView: textView)
        colorizer.emphasizeEnclosingPair = prefs.emphasizeEnclosingPair
        colorizer.emphasisStyle = prefs.enclosingPairEmphasisStyle
        bracketColorizer = colorizer
        colorizer.refresh()
    } else {
        bracketColorizer?.clear()
        bracketColorizer = nil
    }
}
```

- [ ] **Step 3: Call it from `viewDidLoad`** — after the highlighter is configured (so storage colors exist first; the overlay sits on top):

```swift
configureBracketColorizer()
```

- [ ] **Step 4: Drive it from text + selection hooks.** In `textDidChange(_:)` add:

```swift
bracketColorizer?.scheduleRefresh()
```
In `textViewDidChangeSelection(_:)`, replace the explanatory comment with the real call:

```swift
public func textViewDidChangeSelection(_ notification: Notification) {
    updateStatusBar()
    bracketColorizer?.updateCaretEmphasis()
}
```

- [ ] **Step 5: Re-resolve on appearance flip.** In the `effectiveAppearance` KVO observer (where the highlighter theme is updated), add:

```swift
self.bracketColorizer?.refresh()
```

- [ ] **Step 6: React to preference changes.** In `preferencesChanged()` add (after the other editor applies):

```swift
configureBracketColorizer()
```

- [ ] **Step 7: Re-overlay after a full reload.** In `reloadFromDocument()` add (the highlighter restarts there, but temp attrs are independent — still refresh to recolor new text):

```swift
bracketColorizer?.refresh()
```

- [ ] **Step 8: Build + full test suite**

Run: `swift build && swift test`
Expected: success; all pass (no regressions).

- [ ] **Step 9: Add a smoke test** to `EditorSmokeTests.swift`:

```swift
func testRainbowBracketsApplyTemporaryColorAndClearOnDisable() {
    let prefs = Preferences(defaults: UserDefaults(suiteName: "medit.smoke.\(UUID().uuidString)")!)
    prefs.rainbowBrackets = true
    let doc = TextDocument(); doc.setTextForTesting("f(x){y}")
    let wc = EditorWindowController(document: doc, preferences: prefs)
    _ = wc.window
    wc.loadViewIfNeededForTesting()
    guard let editor = wc.editorForTesting, let tv = wc.focusedTextView,
          let lm = tv.layoutManager else { return XCTFail("no editor") }

    editor.refreshBracketColorizerForTesting()
    // The '(' at offset 1 should carry a temporary foreground color.
    let attr = lm.temporaryAttribute(.foregroundColor, atCharacterIndex: 1, effectiveRange: nil)
    XCTAssertNotNil(attr, "bracket should have a depth color overlay")

    // Disabling clears the overlay.
    prefs.rainbowBrackets = false
    editor.applyPreferencesForTesting()
    let cleared = lm.temporaryAttribute(.foregroundColor, atCharacterIndex: 1, effectiveRange: nil)
    XCTAssertNil(cleared, "overlay should be cleared when rainbow brackets is off")
}
```

Add the two needed test hooks to `EditorViewController` (near the other `...ForTesting` hooks):

```swift
func refreshBracketColorizerForTesting() { bracketColorizer?.refresh() }
func applyPreferencesForTesting() { preferencesChanged() }
```

- [ ] **Step 10: Run the smoke test + full suite**

Run: `swift test`
Expected: PASS, all green (render-regression guard included).

- [ ] **Step 11: Commit**

```bash
git add Sources/MeditKit/EditorViewController.swift Tests/MeditKitTests/EditorSmokeTests.swift
git commit -m "Wire BracketColorizer into the editor (text/selection/appearance/prefs)"
```

---

## Task 7: View-menu toggle + Settings controls

**Files:**
- Modify: `Sources/MeditKit/MainMenu.swift`
- Modify: `Sources/MeditKit/EditorWindowController.swift`
- Modify: `Sources/MeditKit/PreferencesWindowController.swift`

- [ ] **Step 1: Add the View-menu item** in `MainMenu.viewMenuItem()` (after "Show Invisibles" / near the sidebar items; no key equivalent):

```swift
let rainbow = NSMenuItem(title: "Rainbow Brackets",
                         action: #selector(EditorWindowController.toggleRainbowBrackets(_:)), keyEquivalent: "")
menu.addItem(rainbow)
```

- [ ] **Step 2: Add the action + validateMenuItem case** in `EditorWindowController`:

```swift
@IBAction public func toggleRainbowBrackets(_ sender: Any?) {
    prefs.rainbowBrackets.toggle()
    // preferencesChanged() in each editor reconfigures the colorizer.
}
```
In `validateMenuItem(_:)`:
```swift
case #selector(toggleRainbowBrackets(_:)):
    menuItem.state = prefs.rainbowBrackets ? .on : .off
```

> Name is `toggleRainbowBrackets` (no AppKit collision — verified against the `toggleSidebar`/NSSplitViewController lesson from 1.4).

- [ ] **Step 3: Add Settings controls** to `PreferencesWindowController` Editor section. Add stored props:

```swift
private var rainbowBracketsCheck: NSButton!
private var emphasizePairCheck: NSButton!
private var emphasisStylePopup: NSPopUpButton!
```
Create them in `buildUI()`:
```swift
rainbowBracketsCheck = check("Rainbow brackets", #selector(checkChanged))
emphasizePairCheck = check("Emphasize enclosing pair at caret", #selector(checkChanged))
emphasisStylePopup = NSPopUpButton(frame: .zero, pullsDown: false)
emphasisStylePopup.addItems(withTitles: ["Bold", "Underline", "Background"])
emphasisStylePopup.target = self
emphasisStylePopup.action = #selector(emphasisStyleChanged)
```
Add to the Editor section in the RowStacker (after `showInvisiblesCheck`, before the padding row, or grouped sensibly):
```swift
stack.add(rainbowBracketsCheck, indent: checkIndent)
stack.add(emphasizePairCheck, indent: checkIndent)
stack.addRow(label: label("Enclosing-pair emphasis:"), control: emphasisStylePopup, controlWidth: 140)
```

- [ ] **Step 4: Write-back + sync.** In `checkChanged`:
```swift
prefs.rainbowBrackets = rainbowBracketsCheck.state == .on
prefs.emphasizeEnclosingPair = emphasizePairCheck.state == .on
```
Add an action:
```swift
@objc private func emphasisStyleChanged(_ sender: Any?) {
    switch emphasisStylePopup.indexOfSelectedItem {
    case 1: prefs.enclosingPairEmphasisStyle = .underline
    case 2: prefs.enclosingPairEmphasisStyle = .background
    default: prefs.enclosingPairEmphasisStyle = .bold
    }
}
```
In `syncFromPrefs()`:
```swift
rainbowBracketsCheck.state = prefs.rainbowBrackets ? .on : .off
emphasizePairCheck.state = prefs.emphasizeEnclosingPair ? .on : .off
switch prefs.enclosingPairEmphasisStyle {
case .bold: emphasisStylePopup.selectItem(at: 0)
case .underline: emphasisStylePopup.selectItem(at: 1)
case .background: emphasisStylePopup.selectItem(at: 2)
}
```

- [ ] **Step 5: Build + full suite**

Run: `swift build && swift test`
Expected: success, all pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/MeditKit/MainMenu.swift Sources/MeditKit/EditorWindowController.swift Sources/MeditKit/PreferencesWindowController.swift
git commit -m "Surface rainbow brackets: View-menu toggle + Settings controls"
```

---

## Task 8: Bump to 1.5.0

**Files:**
- Modify: `App/Info.plist`
- Modify: `App/medit.xcodeproj/project.pbxproj`

- [ ] **Step 1:** Set `CFBundleShortVersionString` to `1.5.0` in `App/Info.plist` and both `MARKETING_VERSION = 1.5.0;` in `project.pbxproj`.

- [ ] **Step 2: Build universal Release**

Run:
```bash
cd App && xcodebuild -project medit.xcodeproj -scheme medit -configuration Release \
  -derivedDataPath .build-xcode ARCHS="x86_64 arm64" ONLY_ACTIVE_ARCH=NO clean build
```
Expected: `** BUILD SUCCEEDED **`; `lipo -archs …/medit` → `x86_64 arm64`.

- [ ] **Step 3: Commit**

```bash
git add App/Info.plist App/medit.xcodeproj/project.pbxproj
git commit -m "Bump to 1.5.0"
```

---

## Task 9: Live verification + ship

- [ ] **Step 1: Full test suite** — `swift test`, all green.

- [ ] **Step 2: Install universal build + live-test** (quit running medit; copy to /Applications; re-sign; launch):
  - Open a file with nested brackets → brackets are **colored by depth**, cycling through 6 colors; deeper nesting steps through the palette.
  - Colors **survive typing** (debounced recolor) and **theme flip** (light/dark) without flicker; survive syntax highlighting (they overlay it).
  - Move the caret inside a pair → the **innermost enclosing pair** is emphasized in the chosen style; moving out re-targets the outer pair; no flicker.
  - A stray `)` shows the **unmatched** (gray-red) color.
  - **Toggles:** View → Rainbow Brackets off → all coloring clears; on → returns. Settings: emphasis off → no bold/underline/tint but depth colors remain; style popup (Bold/Underline/Background) changes the emphasis appearance live.
  - Regression: editor still renders text normally; sidebar, line numbers, wrap, status bar all still work.

- [ ] **Step 2.5:** Fix anything found; re-run build/tests.

- [ ] **Step 3: Finish the branch** — use `superpowers:finishing-a-development-branch`: push branch, open PR to `main`, let CI run, merge via admin bypass (ruleset needs a review the solo owner can't self-give). After merge: fast-forward local `main`, build the universal Release from `main`, tag `v1.5.0`, package `medit-1.5.0-macos-universal.zip`, create the GitHub Release as Latest with notes covering rainbow brackets + toggles.

---

## Self-review notes

- **Type consistency:** `BracketHit` fields, `BracketDepthScanner.scan`, `BracketMatcher.enclosingPair` (returns `(open:Int, close:Int)?`), `EditorColors.bracketColor(forDepth:)` / `bracketDepthColors` / `bracketUnmatchedColor`, `BracketColorizer` API (`scheduleRefresh`/`refresh`/`updateCaretEmphasis`/`clear`, `emphasizeEnclosingPair`, `emphasisStyle`), and the 3 prefs (`rainbowBrackets`/`emphasizeEnclosingPair`/`enclosingPairEmphasisStyle`) are used identically across Tasks 1–7.
- **Offset model:** scanner and `enclosingPair` work in CHARACTER offsets; the colorizer converts to UTF-16 `NSRange` for temp attributes, guarded by `testMultibyteOffsets`. Consistent throughout.
- **Coexistence:** depth/emphasis are temporary attributes only — never text-storage writes — so the highlighter never clobbers them and toggle-off `clear()` fully removes them.
- **No placeholder steps:** every code step has concrete code; colors have concrete sRGB values (tunable live in Task 9 but not blank).
- **Menu collision:** `toggleRainbowBrackets` chosen to avoid the AppKit selector clash that bit `toggleSidebar` in 1.4.
- **Asset name:** release zip is `…-universal.zip` (matches 1.4.1).
