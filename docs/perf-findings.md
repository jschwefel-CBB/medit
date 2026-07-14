# medit performance findings (2026-07-14)

Profiling pass to locate the slow code, for the speed-up pass. Measured on this
machine, **arm64 Release build**, via the `--profile` launch flag (`PerfLog`, dormant
otherwise). Timings are wall-clock, main thread.

## ✅ Speed-up pass results (same day, causes 1–3 fixed)

All three root causes below were fixed and re-measured (same machine, same files,
same probes). Unit suite 430/430 green; `preview-edit-ops-noop.json` 20/20 after.

| Metric | Before | After |
|---|---|---|
| Empty new tab: `tab.highlighterInit` | 30–73 ms | **0.01 ms** (shared engine) |
| Empty new tab: `tab.viewDidLoad.total` | 38–97 ms | **10.8 ms** |
| Open: main-thread block from tokenize | 478–1613 ms (froze the window) | **0 ms** (tokenize on background queue) |
| Open large MD: `preview.renderBody` calls | 3 × ~77 ms | **1 ×** (~94 ms; memoized on source text) |
| Open large Swift: `tab.viewDidLoad.total` | n/a (window frozen ~1.7 s) | 580 ms (see new finding below) |

**How each was fixed** (`SyntaxHighlightingController.swift`, `EditorViewController.swift`):
1. One process-wide `HighlightEngine` (highlight.js JSContext) on a serial background
   queue; tokenize runs there with a generation guard + snapshot-equality check, and
   only attribute application (95–116 ms) touches the main thread. Stale results are
   dropped; the plain fallback stays synchronous so unhighlighted docs are unchanged.
2. Tabs no longer construct an engine — `SyntaxHighlightingController.init` just
   records config; the shared engine is themed lazily per tokenize (no-op when the
   global theme is unchanged).
3. `renderBody` memoized on an owned copy of its source text (`lastRenderedSource`);
   it is a pure function of the text, so the appearance-observer / settings /
   show-time calls with identical text now hit the cache.

**Honest trade-offs / caveats:**
- Colors now *arrive* after the window opens (e.g. ~2.3 s on the 470 KB Swift file)
  instead of the window freezing for 1.7 s. Standard editor behavior, but visible.
- Tokenize wall-time measured *higher* on the background queue (1613→2309 ms Swift,
  478→658 ms MD) — likely efficiency-core scheduling at `.userInitiated`, possibly
  run variance. It no longer blocks anything, but a follow-up could test
  `.userInteractive` QoS if colors feel late.
- `highlight.applyAttrs` (95–116 ms, main thread) still lands as one hitch when
  colors arrive on very large files. Chunking it is a possible follow-up.

## ✅ Bracket-colorizer finding — FIXED (follow-up pass, same day)

**Was:** `tab.bracketColorizer` = 365 ms (470 KB Swift) main thread at open (the
table below's "negligible 0.03 ms" was measured on an EMPTY tab — the synchronous
tokenize had been masking the large-file cost), **plus** ~135 ms on EVERY caret
move (`updateCaretEmphasis` substring'd/`Array(text)`-materialized the document up
to three times per move), **plus** the scan re-ran 3× at open.

**Now (measured, same file/probes):**
| Metric | Before | After |
|---|---|---|
| `tab.bracketColorizer` at open (main thread) | 365 ms | **0.04 ms** (scan on background queue) |
| `bracket.caretEmphasis` per caret move | ~135 ms | **0–2.7 ms** (computed from cached hits) |
| Depth scans at open | 3 × 75–123 ms | **1 × ~72 ms**, background (in-flight coalescing) |
| Conversion map (`bracket.utf16map`) | 94 ms per refresh | **deleted** (scanner emits UTF-16 offsets in its single pass) |
| `tab.viewDidLoad.total`, 470 KB Swift | 580 ms | **210 ms** (residual ≈ initial text layout, unattributed) |

**How** (`BracketDepthScanner.swift`, `BracketMatcher.swift`, `BracketColorizer.swift`):
- Scanner emits `utf16Offset` alongside the character offset in the same pass — the
  colorizer paints NSRanges directly, no O(n) map, no per-character String allocs.
- Scan memoized on an owned source copy AND moved to a serial background queue with
  the highlighter's snapshot/generation/equality pattern; duplicate in-flight scans
  for the same text coalesce. Cache-hit repaints (appearance flip) stay synchronous.
- Caret emphasis computed from the cached hit list (binary search + sparse hit walk)
  instead of walking the text — provably equivalent to `BracketMatcher` (it only
  ever inspects bracket characters; pinned by an every-caret-position equivalence
  test, `testColorizerHitWalkAgreesWithMatcherAtEveryCaret`). Stale cache (edit
  debounce window) → emphasis skips for ≤150 ms rather than painting wrong offsets.
- `BracketMatcher.enclosingPair` rewritten to a lazy `String.Index` walk (no
  `Array(text)`), with new multibyte coverage the old tests never had.

Unit suite 433/433; `preview-edit-ops-noop.json` 20/20. Remaining open-time cost on
huge files: ~200 ms unattributed (likely initial text layout) + the async color
arrival documented above — candidates for a future pass, not currently offenders.

## Test files
- `470 KB` Swift (5000 lines) — highlighter path
- `366 KB` Markdown (21000 lines) — preview + highlighter path
- empty untitled document — new-tab path

## Measurements

| Path | Operation | Time | Notes |
|---|---|---|---|
| Open large Swift | `highlight.tokenize` | **1613 ms** | highlight.js, whole document, main thread |
| | `highlight.applyAttrs` | 116 ms | enumerate + setAttributes over whole doc |
| | `file.decode` | 0.08 ms | negligible |
| | `file.detectLineEndings` | 1.83 ms | negligible |
| Open large Markdown | `highlight.tokenize` | **478 ms** | whole document |
| | `preview.renderBody` | 86 / 77 / 76 ms | **fires 3× on open** — redundant |
| | `highlight.applyAttrs` | 57 ms | |
| | `file.decode` | 0.61 ms | negligible |
| New (empty) tab | `tab.highlighterInit` | **30–73 ms** | constructs highlighter + loads theme PER TAB |
| | `tab.viewDidLoad.total` | 38–97 ms | highlighterInit is ~75–80% of it |
| | `configureRuler` / `bracketColorizer` | 0.01–0.03 ms | negligible |

## Root causes (ranked by impact)

### 1. Syntax highlighting re-tokenizes the WHOLE document, on the main thread — on open AND every edit
`SyntaxHighlightingController.highlightNow()` calls `highlighter.highlight(code, as:)`
on the **entire** `textStorage.string` every time. It is invoked:
- once at open (`configureHighlighter` → `highlightNow`), and
- on **every text change**, via `scheduleHighlight()` from the edit paths
  (`EditorViewController.swift:396, 420, 1286`), debounced but still whole-document.

At 478–1613 ms for a large file, this is the open hang, the typing lag, and most of
the general sluggishness — one root cause. **Fix direction:** highlight only the
visible/edited range (incremental), and/or move tokenization off the main thread
(apply attributes back on main). This is the single highest-leverage change.
`Sources/MeditKit/SyntaxHighlightingController.swift:81`.

### 2. Highlighter is constructed per tab (engine + theme not shared)
`configureHighlighter()` builds a fresh `SyntaxHighlightingController` for every tab
(`EditorViewController.swift:872`), 30–73 ms each even for an empty document — the
"slow new tabs" symptom. The variance suggests the highlight.js engine / theme
(`atom-one-dark`) is reloaded per instance rather than cached process-wide.
**Fix direction:** share one highlighter engine / cached compiled theme across tabs;
construct per-tab state lazily and cheaply.

### 3. Preview `renderBody` runs 3× on open
`renderPreview()` → `MarkdownHTMLRenderer.renderBody` runs three times on open
(~77 ms each = ~230 ms wasted). Likely: initial show + the `effectiveAppearance`
observer + a scheduled refresh all firing. **Fix direction:** coalesce/guard the
open-time renders so the body renders once; the existing `lastRenderedBody` guard
covers the innerHTML write but not the `renderBody` call itself.
`Sources/MeditKit/EditorViewController.swift:671`.

### NOT a cause: file I/O
`file.decode` and `file.detectLineEndings` are sub-2 ms even on 470 KB. The "slow to
open" feeling is the synchronous highlight (cause 1), NOT reading the file. Do not
spend effort on the read path.

## How to reproduce
```
# build a profiling app
cd App && xcodebuild -project medit.xcodeproj -scheme medit -configuration Release \
  -derivedDataPath /tmp/medit-profile-build -arch arm64 build CODE_SIGNING_ALLOWED=NO
codesign --force --deep --sign - /tmp/medit-profile-build/Build/Products/Release/medit.app
# run against a file, capture stderr
/tmp/medit-profile-build/Build/Products/Release/medit.app/Contents/MacOS/medit \
  --profile --reset-state /path/to/large.swift 2>&1 | grep '\[perf\]'
```
`PerfLog.measure(...)` wraps any expression; add more probes as needed. All probes are
no-ops without `--profile`.
