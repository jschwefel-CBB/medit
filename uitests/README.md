# medit GUI tests (AutoPilot)

These are declarative GUI test plans executed by AutoPilot — the `autopilot`
CLI (`~/repositories/autopilot`). They drive the built medit app via the
macOS Accessibility API.

## Prerequisites
- Build AutoPilot: `(cd ~/repositories/autopilot && swift build)`
- Grant Accessibility permission to the terminal/binary running AutoPilot
  (`autopilot doctor` checks this).
- medit must be installed (so `bundleId` resolves) or its built `.app` path
  supplied via the plan `target.path`.

## Run a plan
```bash
~/repositories/autopilot/.build/debug/autopilot run \
  ~/repositories/medit/uitests/open-and-type.json \
  --artifacts /tmp/medit-uitests
```
Exit codes: 0 pass, 1 test failure, 2 plan error, 3 permission missing.

## Authoring
For the complete plan format — actions, assertions, selectors, hygiene
patterns, and a worked example — see the AutoPilot authoring guide:
`~/repositories/autopilot/docs/AUTHORING.md`
(or https://github.com/jschwefel-CBB/autopilot/blob/main/docs/AUTHORING.md).

Use the MCP `dump_axtree` tool (or read these plans) to discover identifiers.
For inspecting a *running* medit you launched yourself, attach by pid:
`autopilot dump-axtree --pid <pid>` (it attaches rather than launching a new
instance). Element-scoped screenshots and the `captureTarget` step are available
(see AUTHORING.md §12a) — handy for debugging flaky plans against medit's UI.

Tagged controls (AXIdentifier) — current as of v2.4.1:

Editor & status bar
- `editorTextView` — the editing surface (NSTextView)
- `positionLabel` — status-bar line/column text
- `documentStatsLabel` — status-bar word/line/char count
- `columnModeLabel` — status-bar block-mode (`BLK`) pill (empty when off)
- `languageButton`, `encodingButton` — status-bar inline buttons

Find / Go to Line / external change
- `findField`, `replaceField`, `findStatusLabel` — find/replace bar
- `goToLineField` — go-to-line sheet input
- `reloadButton`, `dismissReloadButton`, `reloadBannerLabel` — external-change banner

Sidebar
- `sidebarOutline` — folder file-browser outline view
- `sidebarPaneSwitcher` — Folders | Recent segmented control
- `recentFilesTable` — the Recent Files list

Markdown
- `markdownPreviewWebView` — the rendered Markdown preview (a WKWebView; its
  content shows as an `AXWebArea` in the tree)
- `mdStyle.bold`, `mdStyle.italic`, `mdStyle.strikethrough`, `mdStyle.code`,
  `mdStyle.link`, `mdStyle.heading`, `mdStyle.bullet`, `mdStyle.ordered`,
  `mdStyle.quote`, `mdStyle.codeBlock` — Markdown formatting-toolbar buttons

## Note on state
Plans launch medit with `--reset-state`, which clears its UserDefaults domain
at startup so each run begins from a known baseline.
