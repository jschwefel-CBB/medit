# medit performance findings (2026-07-14)

Profiling pass to locate the slow code, for the speed-up pass. Measured on this
machine, **arm64 Release build**, via the `--profile` launch flag (`PerfLog`, dormant
otherwise). Timings are wall-clock, main thread.

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
