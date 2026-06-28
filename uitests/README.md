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

Some plans need committed fixtures staged into `/tmp` first: run
`./stage-fixtures.sh` before `keyboard-scroll*.json`, `multi-window.json`, the
`open-into-tabs-*.json` plans, and the `sidebar-open*.json` plans.

### The Debug build is NOT sandboxed (test-only)

The **Debug** build configuration uses `App/medit-debug.entitlements`, which
**disables the App Sandbox**, so AutoPilot can drive the real sidebar / folder
/ drag / open flows against on-disk fixtures. A sandboxed process needs a
per-file security-scope grant (via NSOpenPanel / Powerbox / a Finder drag) that
a synthetic test cannot supply, so a sandboxed Debug build silently fails to
read ungranted `/tmp` fixtures (the `openDocument` completion never even fires).
The **shipping Release** build keeps `App/medit.entitlements` with the sandbox
**ON** — never ship the Debug entitlements. All AP plans here target the Debug
build at `/Volumes/Scratch/Xcode/DerivedData/Debug/medit.app`.

### Multi-window / open-into-tabs plans

- `multi-window.json` — ⇧⌘N opens a **separate** window (matched by `AXWindow`
  role + `count`). Tabs stay the default for every other open path.
- `open-into-tabs-launch.json` — opening several files **at launch** (the
  `application(_:openFiles:)` path AppKit uses for launch args / Finder "Open
  With" / dragging multiple files onto the app icon) lands them as **tabs in one
  window**, not separate windows. Regression guard for the v2.7.0 bug where
  `tabbingMode .preferred→.automatic` stopped the auto-merge.
- `open-into-tabs-runtime.json` — opening several files at **runtime** via
  `--open-files` exercises `EditorWindowController.openFiles(at:)`, the same
  entry point the sidebar single-click / editor file-drop / Recent list use →
  one window, N tabs.
- `sidebar-open-file.json` — expand a folder in the Folders pane, double-click a
  file, assert it opens (regression for "can't open from the Folders pane").
- `sidebar-open-second-file.json` — open a **second** file from the sidebar after
  the first; both must be tabs in one window (regression for "can't open any
  after the first").

### Test-only launch hooks (`LaunchReset`)

- `--reset-state` — clean preferences/state baseline.
- `--open-folder <dir>` — seed a sidebar root without NSOpenPanel.
- `--open-files <p1> <p2> …` — open files as tabs via the front window's
  `openFiles(at:)` (the sidebar/drag entry point); stops at the next `--flag`.

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
- `sidebarRow:<filename>` — a file/folder row's label, e.g. `sidebarRow:notes.txt`
  (the outline-row text field carries this stable identifier; the AX `value`
  matcher proved unreliable for outline rows, so target rows by this identifier)
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
