# medit 1.5 — Rainbow-Depth Bracket Highlighting (Design)

**Date:** 2026-06-16
**Status:** Approved (brainstormed)
**Version target:** 1.5.0

## Goal

Always-on depth coloring of every bracket in the editor (VS Code "Bracket Pair Colorization" style): each `()[]{}` is tinted by its nesting depth using a cycling 6-color palette, with the innermost pair *enclosing the caret* additionally emphasized. The feature is fully optional and configurable.

## Decisions (from brainstorming)

- **Philosophy:** always-on depth coloring (every bracket, all the time), with caret-pair emphasis layered on top — not caret-pair-only.
- **Coexistence with the syntax highlighter:** depth colors are painted as **layout-manager temporary attributes** (an overlay layer), independent of the highlighter's text-storage colors. The highlighter rewrites storage freely; the overlay survives until the colorizer itself invalidates it. This is the decoupling that avoids the flicker that sank the earlier caret-flash attempt.
- **Depth model:** **shared** across all three bracket families (one stack) — `([{` → depths 0,1,2. This is the de-facto standard (VS Code, JetBrains, Sublime, Vim/Emacs rainbow plugins).
- **Caret emphasis:** the **innermost enclosing pair** (the pair surrounding the caret), recomputed on every caret move — constant "which block am I in" feedback.
- **Colors:** a fixed, curated built-in 6-color palette with light + dark variants in `EditorColors`; theme-derived colors are deferred to the future color-scheme picker.
- **Performance scope:** **whole-document** scan on each (debounced) change — always correct; fast for typical files.
- **Toggles (3):** master `rainbowBrackets` (default ON); `emphasizeEnclosingPair` (default ON); `enclosingPairEmphasisStyle` (Bold / Underline / Background, default Bold).
- **Strings/comments:** brackets inside string/comment tokens are **not** excluded (a `)` in `"smiley :)"` gets tinted). Cosmetic-only; excluding them would re-couple to the highlighter's token spans. Possible follow-up, out of scope for 1.5.

## Tech stack

Swift 6 / AppKit, classic `NSLayoutManager` TextKit path (medit already uses a custom `NSRulerView` and `InvisiblesLayoutManager`, so `setTemporaryAttributes(_:forCharacterRange:)` is fully supported). No new dependencies. TDD for the pure scanner + enclosing-pair logic + preferences; AppKit overlay smoke-tested headlessly and verified live.

---

## Architecture

Two new units, split pure-vs-AppKit exactly like the existing `BracketMatcher` (pure) / editor (AppKit) division.

### `BracketDepthScanner` (pure, no AppKit) — new file
Single function that classifies every bracket with its nesting depth.

```swift
public struct BracketHit: Equatable {
    public let offset: Int        // character offset in the String
    public let kind: Character    // one of ( ) [ ] { }
    public let isOpen: Bool
    public let depth: Int         // 0 = outermost; cycled %6 at paint time
    public let unmatched: Bool    // stray closer / family mismatch
}

public enum BracketDepthScanner {
    public static func scan(_ text: String) -> [BracketHit]
}
```

**Algorithm** — one linear pass, one shared stack of `(kind, depth)`:
- **Opener** (`(` `[` `{`): `depth = stack.count`; push `(kind, depth)`; emit hit (not unmatched).
- **Closer** (`)` `]` `}`): if stack top is the *same-family* opener → pop, emit closer at the popped depth (not unmatched). If stack empty OR top is a different family → emit closer `unmatched: true, depth: 0`, **do not pop** (tolerant of mismatched families).
- **EOF:** brackets still on the stack were already emitted with their depth; left as-is (NOT marked unmatched — the user is likely mid-typing, so unclosed openers keep their depth color for stable coloring).
- **Family** = bracket shape: parentheses `()`, square `[]`, curly `{}`. A closer matches an opener only within the same family.
- **Shared depth:** the single stack spans all families, so depth reflects total nesting regardless of family mix.

### `BracketColorizer` (AppKit) — new file
Owns the overlay and the caret emphasis. Holds weak refs to the `NSTextView` and its `NSLayoutManager`.

- `refresh()` — run `BracketDepthScanner.scan` on the current text; for each hit, apply `.foregroundColor` (the depth color, or the unmatched color) as a **temporary attribute** over the bracket's 1-char range. Temporary attributes layer over the highlighter's storage colors and are never clobbered by it. Debounced (~0.15s) like the highlighter.
- `updateCaretEmphasis()` — find the innermost enclosing pair (via a `BracketMatcher` enclosing-pair helper); clear the previous emphasis ranges; apply the configured emphasis style (`.font` bold / `.underlineStyle` / `.backgroundColor`) as temporary attributes to the two 1-char ranges. Surgical (2 ranges) — frequent, cheap, no full repaint.
- `clear()` — remove all temporary attributes the colorizer added over the full range (on toggle-off or teardown).
- Resolves the palette against the view's effective appearance; re-resolves on light/dark flip.

### Enclosing-pair helper (in `BracketMatcher`)
Add a function that, given a caret offset, scans **outward** for the nearest unbalanced opener before the caret and its matching closer after — returning both offsets (or nil). Reuses the existing matching logic; the existing `matchingOffset(in:at:)` stays for adjacency.

### Data flow
```
edit            ─▶ textDidChange              ─▶ colorizer.refresh()           (debounced)
caret move      ─▶ textViewDidChangeSelection ─▶ colorizer.updateCaretEmphasis()
highlighter run ─▶ (no coupling — temp attrs survive the storage rewrite)
theme/appearance flip ─▶ colorizer.refresh()  (re-resolve palette)
toggle off      ─▶ colorizer.clear()
```
The colorizer is owned by `EditorViewController` next to `highlighter`, created/destroyed in `configureBracketColorizer()` gated on `rainbowBrackets`.

---

## Colors

Six depth colors + an unmatched color, appearance-aware (following the existing `EditorColors` `NSColor(name:) { appearance in … }` idiom). Tuned for mutual contrast and against both backgrounds; exact hex finalized in the plan.

| Depth % 6 | Light | Dark |
|---|---|---|
| 0 | gold/amber | soft gold |
| 1 | violet | lavender |
| 2 | blue | sky blue |
| 3 | green | mint |
| 4 | orange | peach |
| 5 | teal | cyan |
| unmatched | desaturated red-gray | desaturated red-gray |

## Caret emphasis

When `emphasizeEnclosingPair` is on, the innermost enclosing pair gets one style (on top of its depth color), all via temporary attributes so they layer and clear cleanly:
- **Bold** — bold variant of the editor font (`.font`).
- **Underline** — `.underlineStyle`.
- **Background** — subtle `.backgroundColor` wash of the pair's depth color.

On caret move: clear previous emphasis ranges → compute new enclosing pair → apply. No full repaint.

---

## Preferences, toggles & menu

| Pref | Type | Default | Surfaced |
|---|---|---|---|
| `rainbowBrackets` | Bool | true | View menu "Rainbow Brackets" + Settings (Editor) checkbox |
| `emphasizeEnclosingPair` | Bool | true | Settings (Editor) checkbox |
| `enclosingPairEmphasisStyle` | enum `.bold`/`.underline`/`.background` | .bold | Settings (Editor) popup |

`EnclosingPairEmphasisStyle` is a `String`-backed enum (like `AppAppearance`/`ExternalChangePolicy`) for clean defaults round-tripping.

**Application points (`EditorViewController`):**
- `configureBracketColorizer()` — create/destroy by `rainbowBrackets`; called from `viewDidLoad` + `preferencesChanged()`.
- `textDidChange` → `colorizer?.refresh()`.
- `textViewDidChangeSelection` → `colorizer?.updateCaretEmphasis()` (fills the hook the old feature left a comment in).
- existing `effectiveAppearance` KVO → also `colorizer?.refresh()`.
- `preferencesChanged()` re-reads all three prefs.

**Menu:** "Rainbow Brackets" in the View menu, no key equivalent; action `toggleRainbowBrackets` on `EditorWindowController` (distinct name to avoid an AppKit selector collision — the lesson from 1.4's `toggleSidebar`/`NSSplitViewController` clash); `validateMenuItem` checkmark bound to `rainbowBrackets`.

**Settings:** the Editor section gains a "Rainbow brackets" checkbox, an "Emphasize enclosing pair at caret" checkbox, and an "Enclosing-pair emphasis" popup (Bold / Underline / Background), appended via the existing RowStacker.

---

## Testing

- **`BracketDepthScannerTests`** (pure): nested same-family depths; mixed families share one depth (`([{`→0,1,2); stray closer flagged unmatched; unclosed opener keeps depth; empty/no-bracket; adjacent brackets (`}}`); multibyte/emoji offsets; large-input sanity.
- **Enclosing-pair helper tests** (pure): caret in open space → innermost surrounding pair; caret at top with no enclosure → nil; nested → innermost; adjacency unaffected.
- **`PreferencesTests`**: the 3 new prefs default (true/true/.bold) and persist; enum round-trips all cases.
- **`EditorSmokeTests`**: with `rainbowBrackets` on + bracketed text, ≥1 bracket range has a non-nil temporary `.foregroundColor`; toggling off clears temp attributes; the render-regression guard (text still visible) stays green.
- **Live:** depth colors visible and cycling; emphasis follows the caret in the chosen style; colors survive typing/highlighting/theme-flip without flicker; each toggle behaves; no lag.

## File map

- *Create* `Sources/MeditKit/BracketDepthScanner.swift` — pure scanner + `BracketHit`.
- *Create* `Sources/MeditKit/BracketColorizer.swift` — temp-attribute overlay + caret emphasis.
- *Modify* `Sources/MeditKit/EditorColors.swift` — 6 depth colors + unmatched, appearance-aware.
- *Modify* `Sources/MeditKit/BracketMatcher.swift` — enclosing-pair (scan-outward) helper.
- *Modify* `Sources/MeditKit/EditorViewController.swift` — own/configure colorizer; wire textDidChange, textViewDidChangeSelection, appearance KVO, preferencesChanged.
- *Modify* `Sources/MeditKit/Preferences.swift` — 3 prefs + `EnclosingPairEmphasisStyle` enum.
- *Modify* `Sources/MeditKit/PreferencesWindowController.swift` — Editor-section controls.
- *Modify* `Sources/MeditKit/MainMenu.swift` + `EditorWindowController.swift` — View-menu toggle + validateMenuItem.
- *Modify* test files as above.
- *Modify* `App/Info.plist` + `App/medit.xcodeproj/project.pbxproj` — bump to 1.5.0.

## Risks & mitigations

1. **Temporary attributes / TextKit version** — medit uses the classic `NSLayoutManager` path (custom ruler, `InvisiblesLayoutManager`), where `setTemporaryAttributes` is fully supported (not the TextKit 2 viewport path). Low risk; correct stack.
2. **Per-keystroke churn** — debounce `refresh()` (~0.15s) like the highlighter; keep the frequent `updateCaretEmphasis()` surgical (2 ranges, only the outward walk).
3. **Character vs UTF-16 ranges** — the scanner uses `String` character offsets; temp attributes need `NSRange` (UTF-16). The applier converts carefully; a multibyte test guards it.
4. **Toggle-off must fully clear** — explicit `clear()` over the whole range removes both depth and emphasis temp attributes on disable/teardown.

## Out of scope (1.5)

- String/comment-aware bracket exclusion (cosmetic; would re-couple to highlighter tokens).
- Theme-derived bracket colors (belongs with the color-scheme picker).
- Visible-range-only optimization (whole-document is fast enough; revisit only if huge-file lag appears).
