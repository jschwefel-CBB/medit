# medit GUI tests (AutoPilot)

These are declarative GUI test plans executed by [AutoPilot](https://github.com/jschwefel-CBB/autopilot-macos) —
the `autopilot` CLI (`/opt/homebrew/bin/autopilot`). They drive the built medit app via the
macOS Accessibility API.

## Prerequisites
- **AutoPilot ≥ 3.1.2** installed via Homebrew: `/opt/homebrew/bin/autopilot`
  (includes the `AutopilotDragSource.app` helper bundled in the Homebrew tarball).
  Run `autopilot --version` to confirm the version.
- Grant **Accessibility** permission to the terminal running AutoPilot
  (`autopilot doctor` checks both Accessibility and Screen Recording).
- A **real display** is required (AutoPilot drives keyboard/mouse via AX; headless
  sessions have no cursor/window server).
- **Debug build** at `/Volumes/Scratch/Xcode/DerivedData/Debug/medit.app` — build
  via `xcodebuild -scheme medit -configuration Debug` or open the Xcode project.
- For plans that use fixture files (`keyboard-scroll*.json`, `multi-window.json`,
  `open-into-tabs*.json`, `sidebar-open*.json`, `drop-files-onto-editor.json`,
  `preview-copy-test.json`, `go-to-line.json`, `preview-find-scroll.json`,
  `markdown-table-preview.json`): stage fixtures first:
  ```bash
  cd uitests && ./stage-fixtures.sh
  ```

## Run a plan
```bash
autopilot run uitests/open-and-type.json --artifacts /tmp/medit-uitests
```
Exit codes: 0 pass, 1 test failure, 2 plan error, 3 permission missing.

## Run the full suite
`autopilot run` takes a single plan path (no built-in directory runner), so loop:
```bash
uitests/stage-fixtures.sh                       # stage fixtures once up front
for plan in uitests/*.json; do
  autopilot run "$plan" --artifacts "/tmp/medit-uitests/$(basename "$plan" .json)"
  # after edge-open-denied-file.json, dismiss the CoreServicesUIAgent alert (see below)
done
```
**Note:** All plans pass when run individually. `autopilot run` takes a single plan
path (there is no built-in directory runner), so drive the suite from a shell loop.
The AX-linger race that used to flake back-to-back launches is **fixed** in AutoPilot
as of `feature/ap-feedback` (`AppLauncher` now waits for prior instances to leave the
process table before the next launch), so a plain kill + restage between plans is enough
— the old `pkill -9` + fixed `sleep` guard is no longer needed for linger.

**One caveat for `edge-open-denied-file.json`:** a failed permission-denied open makes
macOS LaunchServices (process `CoreServicesUIAgent`, *not* medit) put up a modal alert
that can steal focus from the *next* plan (it self-expires after a few seconds, but the
next plan may start first). Dismiss it out-of-band right after that plan. With the AP
**you have installed today**, use `osascript`:
```bash
osascript -e 'tell application "System Events" to tell process "CoreServicesUIAgent"
  repeat while (count of windows) > 0
    try
      click button "OK" of window 1
    end try
  end repeat
end tell'
```
Once AutoPilot **`feature/ap-feedback`** is released, the first-class equivalent is
`autopilot dismiss-alert --pid $(pgrep -x CoreServicesUIAgent) --button OK` (it attaches
to the alert's owning process — something a target-attached `run` cannot do). Both are
runner-side conveniences; no plan depends on either.
See `docs/autopilot-feedback.md` (medit 2.7.5 entry, defect D7/M2) for the full write-up.

## Schema and level requirements
All plans use `"schemaVersion": "1.1"` with a required `"level"` on every step:
- `happyPath` — the expected flow with valid input
- `integrationSuite` — features working together, cumulative (happyPath ⊂ integrationSuite)
- `tryToBreakIt` — adversarial / boundary input (integrationSuite ⊂ tryToBreakIt)

A step without `level` is rejected at parse (exit code 2). Run `autopilot lint uitests/` to validate.

## Plans

### Editor and basic editing
- **`open-and-type.json`** — type, select-all, replace, undo, delete-all; basic editing
  round-trip. happyPath → tryToBreakIt.
- **`find-replace.json`** — find bar, next, open replace bar, type replacement, no-match
  adversarial. happyPath → tryToBreakIt.
- **`go-to-line.json`** — Edit > Go to Line (menu, cmd+L), navigate to line 5, navigate
  to line 100; out-of-range (999999) is **rejected (beep) with the sheet kept open** —
  NOT clamped/navigated — then Escape closes it. Requires staged `long.txt`.
  happyPath → tryToBreakIt.
- **`editor-behaviors.json`** — pref-driven editor input effects, asserted on the real
  editor (not just the settings checkbox): auto-close brackets (`(`→`()`, nested `([])`),
  auto-indent on Return (leading whitespace carries), and literal Tab is NOT remapped to
  spaces (inserts a real `\t`). happyPath → tryToBreakIt.
- **`save-in-place.json`** — Save (⌘S) on a titled document writes in place with NO system
  panel and the app stays interactive (content kept, typing still lands); repeat save also
  stays interactive. (Save As uses the system panel — separate process, not covered.)
  happyPath → tryToBreakIt.
- **`overwrite-mode.json`** — overwrite (type-over) mode end-to-end: the `insert` key
  toggles the INS/OVR status pill (`modeLabel`), typing then replaces (`ABCDEF`→`XYCDEF`),
  **pasting** in OVR also replaces (`PQCDEF`, via `exec` pbcopy), and **clicking** the
  INS/OVR pill toggles the mode. Requires AutoPilot ≥ 3.2 (`insert` key + `exec`).
  happyPath → integrationSuite.
- **`reload-banner.json`** — external-change reload flow: `exec` overwrites the open file
  on disk mid-plan → the reload banner (`reloadBannerLabel`) appears; **Reload** loads the
  new content; a second change → **Dismiss** collapses the banner but keeps the editor's
  content. Requires AutoPilot ≥ 3.2 (`exec`). happyPath → tryToBreakIt.
- **`find-scroll.json`** — find match-count label AND the editor **scrolls** to a match
  below the fold: types a 40-line doc, finds a bottom marker, presses ⌘G, asserts the
  caret/view reach line 40 (find-scroll in the *preview* is a separate known bug — see
  `preview-find-scroll.json`). happyPath → integrationSuite.
- **`keyboard-scroll.json`** — editor caret scroll: End to bottom, Home to top, PageDown/Up.
  Requires staged `long.txt`. happyPath → tryToBreakIt.
- **`word-wrap-toggle.json`** — View > Wrap Lines toggle; status-bar button changes
  "Wrap: Off" ↔ "Wrap: On". Types a long line (integrationSuite). happyPath → integrationSuite.
- **`column-select.json`** — Edit > Text transforms: Make Upper Case, Make Lower Case,
  Sort Lines Ascending/Descending. Note: "Column Selection Mode" still cannot be
  *invoked* via `menu` when it is disabled at menu-open time, but it is now **visible in
  discovery** — `autopilot menu <medit> --pid <pid> --path Edit` lists it with its
  `enabled` flag (AutoPilot `feature/ap-feedback`), so you no longer have to guess. The
  column-mode toggle itself is driven via ⌥⌘B. happyPath → tryToBreakIt.
- **`status-bar-toggles.json`** — show/hide status bar, word count toggle, rapid triple-
  toggle stability. happyPath → tryToBreakIt.

### Multi-window and multi-file
- **`multi-window.json`** — ⇧⌘N opens a second window; ⌘N (File > New) stays in the same
  window as a new tab. Requires staged `mw-a.txt`. happyPath → integrationSuite.
- **`open-into-tabs-launch.json`** — opening files at launch (launch args / Finder "Open
  With") produces ONE window with tabs, not separate windows. Requires staged fixtures.
- **`open-into-tabs-runtime.json`** — opening files at runtime via `--open-files` (the
  sidebar/drag entry point) produces ONE window, N tabs. Requires staged fixtures.
- **`sidebar-open-file.json`** — expand a folder in the Folders pane, double-click a file,
  assert it opens. Requires staged `open-folder/`. happyPath.
- **`sidebar-open-second-file.json`** — open a second file from the sidebar after the first;
  both must be tabs in one window. happyPath.
- **`sidebar-context-newfile.json`** — right-click the folder root in the sidebar, choose
  **New File** from the context menu, accept the rename dialog, assert a new `untitled` row
  appears (a real file-system op driven through the UI). Creates `untitled` in the staged
  `/tmp/medit-ap-folder` (regenerated each run). happyPath.
- **`drop-files-onto-editor.json`** — real Finder-style file drag via `drag` + `toFiles`:
  drags two files onto `editorTextView`, fires AppKit drop handlers
  (`public.file-url` + `NSFilenamesPboardType` → `openFiles(at:)`). Requires
  `AutopilotDragSource.app` next to `autopilot`, a real display, and Accessibility.
  happyPath.

### Markdown preview
- **`keyboard-scroll-preview.json`** — preview keyboard scroll: End to bottom, Home back
  to top, PageDown. Requires staged `long.md`. happyPath → integrationSuite.
- **`markdown-table-preview.json`** — open a Markdown file with a table, show preview,
  wait for WKWebView/AXWebArea, screenshot. Requires staged `table-test.md`. happyPath.
- **`markdown-toolbar-insert.json`** — the Markdown formatting toolbar buttons actually
  INSERT markdown (not just present): opens a `.md`, hides the auto-preview to reach the
  editor, selects a word and clicks `mdStyle.bold` → `**word**`, `mdStyle.italic` →
  `*word*`, `mdStyle.code` → `` `word` ``. Requires staged `long.md`. happyPath → integrationSuite.
- **`preview-copy-test.json`** — regression guard for the v2.7.4 WKWebView copy fix:
  cmd+a → cmd+c in preview → paste into a new tab → assert pasted content reaches
  NSPasteboard. Requires staged `copy-test.md`. happyPath → integrationSuite.
- **`preview-find-scroll.json`** — KNOWN-FAILING regression guard for the find-in-preview
  no-scroll bug: opens long.md, shows preview, opens find bar, types a term near the
  bottom. The findStatusLabel shows a match but the preview does NOT scroll to it (the
  known bug). Screenshots document the bug. All steps are `tryToBreakIt`. Will start
  truly passing when the bug is fixed. Requires staged `long.md`.

### Settings panel
The Settings/Preferences window's interactive controls carry stable `settings.*`
AXIdentifiers (set on the control's *cell* too — see the tagged-controls table). These
plans open Settings with `cmd+,` and drive it. Each field is edited at most once per
plan (see `docs/autopilot-feedback.md` D3) and popups are selected via press-then-click
an `AXMenuItem` (D1) with a focus reset between opens (D2).
- **`settings-toggles.json`** — every checkbox toggles and every popup selects each of
  its values. happyPath → tryToBreakIt.
- **`settings-popup-appearance.json`** — appearance popup cycles System/Light/Dark.
- **`settings-popup-emphasis.json`** — enclosing-pair emphasis popup cycles
  Bold/Underline/Background.
- **`settings-popup-external-change.json`** — external-change popup cycles
  Notify/Prompt/Auto-reload.
- **`settings-field-valid.json`** — the numeric fields (tab width, editor padding)
  accept valid input. happyPath → integrationSuite.
- **`settings-field-tabwidth-reject.json`** — tab-width field rejects non-numeric input
  (tryToBreakIt: the stored value stays safe).
- **`settings-field-padding-reject.json`** — text-padding field rejects negative input
  (tryToBreakIt).
- **`settings-persistence-set.json`** + **`settings-persistence-verify.json`** — a
  two-part pair proving settings survive quit/relaunch: part 1 changes settings then
  quits; part 2 relaunches (WITHOUT `--reset-state`) and asserts the changes persisted.
  Run set before verify.

### View, find, encoding
- **`view-toggles.json`** — View menu toggles: sidebar, markdown toolbar, and their
  menu-checkmark state. happyPath → integrationSuite.
- **`find-regex-metachars-off.json`** — regex metacharacters are treated literally when
  regex is off, and a malformed pattern is handled gracefully when regex is on.
  Requires staged `regex-metachars.txt`. happyPath → tryToBreakIt.
- **`encoding-language-switch.json`** — switch the status-bar language and encoding on
  open content (via `click` on the status-bar buttons). happyPath → integrationSuite.

### Edge cases (adversarial / malformed input — `tryToBreakIt`)
- **`edge-unicode-content.json`** — unicode and emoji content opens and can be edited.
  Requires staged `unicode-content.md`.
- **`edge-empty-doc-ops.json`** — editing operations (select-all, copy, undo, …) on an
  empty (zero-byte) document degrade gracefully.
- **`edge-copy-nothing-selected.json`** — copy with nothing selected leaves the clipboard
  unchanged. Verified **directly** with AutoPilot's target-less `clipboard` assertion
  (AP ≥ 3.2, closes D6) — no more paste-into-a-new-tab round-trip.
- **`edge-undo-past-history.json`** — undo past the beginning of history is graceful (no
  crash, no corruption).
- **`edge-rapid-new-tabs.json`** — rapid repeated File ▸ New (tab-creation stress).
- **`edge-open-bad-files.json`** — opens three malformed-CONTENT files together in one
  launch (zero-byte, extensionless, invalid-UTF-8); medit opens all without crashing and
  stays interactive. (The 5 MB case was split out — see M1 below.) Requires staged
  fixtures.
- **`edge-open-large-file.json`** — opens a bounded large file (1 MB, ~19k lines)
  alongside a second file; the window comes up and the app stays interactive without
  hanging. Bounded at 1 MB deliberately: medit's file open is synchronous on the main
  thread, so a 5 MB+ file batched with another stalls window creation
  (`docs/autopilot-feedback.md` medit defect **M1**). Requires staged fixtures.
- **`edge-open-denied-file.json`** — opening a permission-denied (chmod 000) file fails
  gracefully: medit's window + editor stay present and readable. Asserts only that
  safety property — NOT typed-text round-trip — because a failed open makes macOS
  LaunchServices put up a modal alert (owned by `CoreServicesUIAgent`, not medit) that
  steals focus and cannot be dismissed via AP (`docs/autopilot-feedback.md` D7 / M2).
  See the suite-runner caveat above for dismissing the lingering alerts. Requires staged
  fixtures.

## The Debug build is NOT sandboxed (test-only)
The Debug build uses `App/medit-debug.entitlements` with the **App Sandbox disabled**,
so AutoPilot can drive real file-open flows against `/tmp` fixtures. A sandboxed build
silently fails to read ungranted fixture paths (the `openDocument` completion never fires).
The **shipping Release** build keeps the sandbox ON — never ship Debug entitlements.

## Test-only launch hooks
- `--reset-state` — clears UserDefaults at startup for a known-baseline run.
- `--open-folder <dir>` — seeds a sidebar root without NSOpenPanel.
- `--open-files <p1> <p2> …` — opens files as tabs via the front window's `openFiles(at:)`.

## Authoring
For the complete plan format — actions, assertions, selectors, hygiene patterns, and
a worked example — run `autopilot docs authoring` (or `autopilot docs --open`).
The `drag` + `toFiles` file-drop reference is §14a in the authoring doc.

Use `autopilot dump-axtree <app-path>` to discover identifiers, or attach to a
running instance by pid: `autopilot dump-axtree --pid <pid>`.

## Tagged controls (AXIdentifier) — current as of v2.7.5

### Editor & status bar
| Identifier | Element | Notes |
|---|---|---|
| `editorTextView` | NSTextView | main editing surface |
| `positionLabel` | AXStaticText | status-bar "Ln N, Col M" |
| `documentStatsLabel` | AXStaticText | status-bar "N words · N lines · N chars" |
| `columnModeLabel` | AXStaticText | status-bar " BLK " pill (empty when off) |
| `languageButton` | AXPopUpButton | status-bar language selector |
| `encodingButton` | AXPopUpButton | status-bar encoding selector |

### Find / Go to Line / reload banner
| Identifier | Element | Notes |
|---|---|---|
| `findField` | NSSearchField | find/replace bar search input |
| `replaceField` | NSTextField | find/replace bar replace input |
| `findStatusLabel` | AXStaticText | "N of M" match count |
| `findRegexToggle` | NSButton (cell) | find bar regex toggle (id set on cell) |
| `findCaseToggle` | NSButton (cell) | find bar case-sensitivity toggle (id set on cell) |
| `goToLineField` | NSTextField | Go to Line sheet input |
| `reloadButton` | AXButton | external-change reload banner |
| `dismissReloadButton` | AXButton | external-change dismiss button |
| `reloadBannerLabel` | AXStaticText | external-change message text |

### Settings / Preferences window (v2.7.5)
All 36 interactive controls in the Preferences window carry a `settings.<key>`
identifier, set on the control's **cell** as well (cell-based `NSButton`/`NSTextField`/
`NSPopUpButton` do not vend a control-only identifier — see `docs/autopilot-feedback.md`
D5). Discover the full set with `autopilot dump-axtree --pid <pid>` after `cmd+,`.
| Identifier | Element | Notes |
|---|---|---|
| `settings.<checkbox>` | AXCheckBox | 33 checkboxes, e.g. `settings.wrapLines`, `settings.showLineNumbers`, `settings.rainbowBrackets`, `settings.reopenLastSession` |
| `settings.appearance` | AXPopUpButton | System / Light / Dark |
| `settings.enclosingPairEmphasisStyle` | AXPopUpButton | Bold / Underline / Background |
| `settings.externalChangePolicy` | AXPopUpButton | Notify / Prompt / Auto-reload |
| `settings.tabWidth` | AXTextField | numeric (formatter-backed) |
| `settings.editorPadding` | AXTextField | numeric (formatter-backed) |
| `settings.chooseFont` | AXButton | opens the font panel |

### Sidebar
| Identifier | Element | Notes |
|---|---|---|
| `sidebarOutline` | NSOutlineView | Folders-pane file browser |
| `sidebarRow:<filename>` | AXTextField | per-row label, e.g. `sidebarRow:notes.txt` |
| `sidebarPaneSwitcher` | AXRadioGroup | Folders \| Recent segmented control |
| `recentFilesTable` | NSTableView | Recent Files list |

### Markdown
| Identifier | Element | Notes |
|---|---|---|
| `markdownPreviewWebView` | WKWebView (AXGroup) | rendered Markdown preview |
| `mdStyle.bold` … `mdStyle.codeBlock` | AXButton | Markdown toolbar buttons |

### Tab close button
| Identifier | Element | Notes |
|---|---|---|
| `_closeButton` | AXButton | tab close button (title "Close tab") |
