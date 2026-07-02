# medit GUI tests (AutoPilot)

These are declarative GUI test plans executed by AutoPilot — the installed
`autopilot` CLI. They drive the built medit app via the macOS Accessibility API.

AutoPilot is a third-party tool installed on this machine; treat it as a
black box on your `PATH`. You do not build it and you do not reference its
source tree.

## Prerequisites
- **AutoPilot ≥ 3.1.0, installed via Homebrew** and on your `PATH` as
  `autopilot` (`/opt/homebrew/bin/autopilot`). Install/update with:
  ```bash
  brew tap jschwefel-CBB/autopilot && brew install autopilot   # or: brew upgrade autopilot
  ```
  The Homebrew install also ships the `AutopilotDragSource.app` file-drop
  helper alongside the binary, so `drop-files-onto-editor.json` works with no
  extra setup. Older AutoPilot **cannot run these plans** — see "What changed"
  below.
- Grant Accessibility permission to the terminal running `autopilot`
  (`autopilot doctor` checks this).
- medit must be installed (so `bundleId` resolves) or its built `.app` path
  supplied via the plan `target.path`.

## What changed (AutoPilot upgrade — read if plans suddenly fail to parse)
AutoPilot core 3.0.0 made two breaking changes that this suite now depends on:

1. **Schema `1.1` + required `level`.** Every plan must declare
   `"schemaVersion": "1.1"` and give every step a `"level"`
   (`happyPath` ⊂ `integrationSuite` ⊂ `tryToBreakIt`). A step without `level` is
   **rejected at parse** (exit code 2). All plans here have been migrated; keep
   `level` on every new step.
2. **Real file drag-and-drop** is now supported via `drag` + `toFiles` (3.1.0) —
   see below. This replaced the old "file drag is not supported" behavior.

If a plan errors with *"missing required field `level`"* or *"unsupported
schemaVersion"*, your `autopilot` binary is too old — `brew upgrade autopilot`.

## Run a plan
```bash
autopilot run uitests/open-and-type.json --artifacts /tmp/medit-uitests
```
`run` is the default subcommand. Exit codes: 0 pass, 1 test failure,
2 plan error, 3 permission missing. (There is no `--version` flag; use
`autopilot doctor` as the health check.)

Some plans need committed fixtures staged into `/tmp` first: run
`zsh uitests/stage-fixtures.sh` before `keyboard-scroll*.json`, `multi-window.json`, the
`open-into-tabs-*.json` plans, the `sidebar-open*.json` plans, and
`drop-files-onto-editor.json`.

## Real file drag-and-drop (`drop-files-onto-editor.json`)
This plan drags real files onto `editorTextView` via `drag` + `toFiles`, firing
medit's actual AppKit drop path (`public.file-url` + `NSFilenamesPboardType` →
`openFiles(at:)`) — the regression guard for the `.fileURL`-only multi-file bug.

```json
{ "action": "drag", "level": "happyPath",
  "target": { "identifier": "editorTextView" },
  "args": { "toFiles": ["/tmp/medit-ap-open-a.txt", "/tmp/medit-ap-open-b.txt"] } }
```

Requirements specific to this plan:
- **The `AutopilotDragSource.app` helper** must sit next to the `autopilot`
  binary. The Homebrew install ships it there automatically (AutoPilot resolves
  the `/opt/homebrew/bin/autopilot` symlink to its Cellar dir, where the helper
  lives). Override with the `AUTOPILOT_DRAG_SOURCE` env var if needed. Without
  it the drop step fails with *"could not locate AutopilotDragSource helper."*
- **A real display + Accessibility — it cannot run headless.** AutoPilot becomes
  the drag *source* (a real `NSDraggingSession`) and steers the physical cursor;
  a headless session has no cursor/window server to route the drop.
- Run against the **Debug (sandbox-off) build** like the other file-open plans, so
  the dropped files are readable.

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
- `drop-files-onto-editor.json` — a **real** Finder-style file drag-and-drop: drags
  two files onto `editorTextView` via AutoPilot's `drag` + `toFiles`, so medit's
  actual AppKit drop handlers fire (`public.file-url` + `NSFilenamesPboardType`) →
  `openFiles(at:)`. Both open as tabs in one window. Regression guard for the
  `.fileURL`-only multi-file bug (multi-file drops fired no events unless
  `NSFilenamesPboardType` was also registered). Needs the AutoPilot **drag-source
  helper** (`AutopilotDragSource.app`, shipped next to `autopilot` by Homebrew),
  a real display, and Accessibility — a file drop cannot run headless. Like every
  plan here it uses `schemaVersion "1.1"` with a `level` on every step (required
  by AutoPilot ≥ 3.1.0).

### Test-only launch hooks (`LaunchReset`)

- `--reset-state` — clean preferences/state baseline.
- `--open-folder <dir>` — seed a sidebar root without NSOpenPanel.
- `--open-files <p1> <p2> …` — open files as tabs via the front window's
  `openFiles(at:)` (the sidebar/drag entry point); stops at the next `--flag`.

## Authoring
For the complete plan format — actions, assertions, selectors, hygiene
patterns, and a worked example — see the AutoPilot authoring guide:
https://github.com/jschwefel-CBB/autopilot-macos/blob/main/docs/AUTHORING.md
The `drag` + `toFiles` file-drop reference is §14a there.

Use `autopilot dump-axtree` to discover identifiers. For inspecting a *running*
medit you launched yourself, attach by pid:
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
