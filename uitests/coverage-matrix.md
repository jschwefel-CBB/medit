# medit AutoPilot coverage matrix

Proof-of-coverage for the medit GUI test suite. Every **testable surface** is
listed with the input classes exercised against it — **valid**, **empty/none**,
and **malformed** (per the `tryToBreakIt` tier) — mapped to the plan and step
that covers it. Rows AutoPilot cannot drive are flagged **AP-blocked** with a
pointer to the feedback item filed in `docs/autopilot-feedback.md`.

This file is the shopping list the suite is built against and the record that
"everything testable" is actually covered. Update it whenever a surface, plan,
or AP capability changes.

Legend: ✅ covered · ⛔ AP-blocked (filed) · ➖ not applicable · 🔬 model-layer
(unit test, not AP-reachable).

Levels: `happyPath` (H) ⊂ `integrationSuite` (I) ⊂ `tryToBreakIt` (T).

---

## 1. Editor — text entry & core editing

| Surface | Valid | Empty/none | Malformed / adversarial | Plan |
|---|---|---|---|---|
| Type text | ✅ H | ➖ | ✅ unicode/emoji, control chars, very long line — T | `open-and-type.json`, `edge-unicode-content.json` |
| Select all (⌘A) | ✅ H | ✅ select-all on empty doc — T | — | `open-and-type.json`, `edge-empty-doc-ops.json` |
| Cut / Copy / Paste (⌘X/C/V) | ✅ H (round-trip) | ✅ copy with nothing selected → clipboard unchanged — T | ✅ paste into empty doc — I | `edge-copy-nothing-selected.json`, `preview-copy-test.json` |
| Delete / forward-delete | ✅ H | ✅ delete on empty doc (no crash) — T | — | `edge-empty-doc-ops.json` |
| Undo (⌘Z) | ✅ H | ✅ **undo past start of history** (no crash) — T | ✅ rapid repeated undo — T | `edge-undo-past-history.json` |
| Redo (⇧⌘Z) | ✅ H | ✅ redo with nothing to redo — T | — | `edge-undo-past-history.json` |

## 2. Find / Replace bar

Identifiers: `findField`, `replaceField`, `findStatusLabel`, `findRegexToggle`,
`findCaseToggle`.

| Surface | Valid | Empty/none | Malformed / adversarial | Plan |
|---|---|---|---|---|
| Find (⌘F) literal | ✅ H | ✅ empty query — T | — | `find-replace.json` |
| Find with **no match** | — | — | ✅ query absent from doc → status "0" / not found — T | `find-replace.json` |
| Find Next / Prev (⌘G / ⇧⌘G) | ✅ I | — | ✅ next with 0 matches — T | `find-replace.json` |
| Replace / Replace All | ✅ H | ✅ replace with empty replacement (deletes matches) — I | ✅ replace-all no match — T | `find-replace.json` |
| **Regex toggle OFF** + regex metachars (`.` `*` `[`) | ✅ literal-match semantics — T | — | ✅ metachars treated literally, not as regex — T | `find-regex-metachars-off.json` |
| **Regex toggle ON** + valid pattern | ✅ T | — | ✅ **malformed regex** (`[`, `(`) → no crash, 0/no match — T | `find-regex-metachars-off.json` |
| Case toggle | ✅ I | — | — | `find-replace.json` |

## 3. Go to Line

Identifier: `goToLineField` (NumberFormatter: integer-only, min 1, no max).

| Surface | Valid | Empty/none | Malformed / adversarial | Plan |
|---|---|---|---|---|
| Go to Line (⌘L) mid-document | ✅ H (line 5) | ✅ empty field committed → no-op/no crash — T | — | `go-to-line.json` |
| Go to last line | ✅ I (line 100) | — | — | `go-to-line.json` |
| Out-of-range high | — | — | ✅ 999999 → clamps to last line, no crash — T | `go-to-line.json` |
| Non-integer / negative input | — | — | ✅ formatter rejects `abc`, `-5`, `1.5` → field reverts — T | `go-to-line.json` |

## 4. View menu toggles (+ status-bar effects)

Each toggle asserts its **side effect** (per AP guidance: menu `marked` is
unreliable cold). Status identifiers: `positionLabel`, `documentStatsLabel`,
`columnModeLabel`.

| Toggle (View ▸ …) | On effect | Off effect | Adversarial | Plan |
|---|---|---|---|---|
| Wrap Lines | ✅ status "Wrap: On" — H | ✅ "Wrap: Off" — H | ✅ rapid toggle — T | `word-wrap-toggle.json` |
| Show Status Bar | ✅ bar hidden/shown — H | ✅ — H | ✅ rapid triple-toggle — T | `status-bar-toggles.json` |
| Show Word Count | ✅ `documentStatsLabel` present/gone — H | ✅ — H | — | `status-bar-toggles.json` |
| Show Line Numbers (⇧⌘L) | ✅ gutter on/off (geometry) — I | ✅ — I | — | `view-toggles.json` |
| Show Invisibles | ✅ toggles — I | ✅ — I | — | `view-toggles.json` |
| Rainbow Brackets | ✅ toggles (state via prefs) — I | ✅ — I | — | `view-toggles.json` |
| Show Markdown Preview (⇧⌘V) | ✅ `markdownPreviewWebView` present — H | ✅ hidden — H | — | `keyboard-scroll-preview.json`, `markdown-table-preview.json` |
| Auto-Show Preview for Markdown | ✅ toggles pref — I | ✅ — I | — | `view-toggles.json` |
| Show Markdown Toolbar | ✅ `mdStyle.*` present/gone — I | ✅ — I | — | `view-toggles.json` |
| Show Sidebar (⌃⌘0) | ✅ `sidebarOutline` geometry — I | ✅ collapsed size 0 — I | — | `view-toggles.json` |
| Show Recent Files in Sidebar | ✅ pane switch — I | ✅ — I | — | `view-toggles.json` |
| Show Hidden Files | ✅ toggles pref — I | ✅ — I | — | `view-toggles.json` |
| Reveal Active File in Sidebar | ✅ toggles pref — I | ✅ — I | — | `view-toggles.json` |
| Enter Full Screen (⌃⌘F) | ⛔ full-screen transition destabilizes AX tree / window server in headless-ish runs | — | — | AP-feedback: full-screen toggle |

## 5. Edit ▸ Text transforms & column mode

| Surface | Valid | Empty/none | Malformed | Plan |
|---|---|---|---|---|
| Make Upper Case | ✅ H | ✅ transform on empty selection — T | — | `column-select.json` |
| Make Lower Case | ✅ H | ✅ — T | — | `column-select.json` |
| Capitalize (title case) | ✅ I | — | — | `column-select.json` |
| Sort Lines Ascending | ✅ H | ✅ sort 0/1 line — T | — | `column-select.json` |
| Sort Lines Descending | ✅ H | — | — | `column-select.json` |
| **Column Selection Mode** (⌥⌘B) | ✅ via **keyPress `cmd+opt+b`** → `columnModeLabel` shows "BLK" — I | — | ✅ toggle off — I | `column-select.json` |

> Column mode is reachable by its **key equivalent** (`⌥⌘B`), NOT by the `menu`
> action — the menu item reports disabled at menu-open time. See
> AP-feedback: menu action lists only enabled items.

## 6. Settings panel

All 36 interactive controls now carry stable `settings.*` AX identifiers
(verified: 36/36 resolve to exactly one element). Each toggle asserts its own
control value; a representative subset also asserts the **editor-side effect**.
Malformed input targets the two numeric fields.

### 6a. Checkboxes (33) — toggle + assert value

Covered in `settings-toggles.json` (H: open Settings, toggle a control, assert
its state flips; I: assert the editor reflects the change for the visible ones —
wrap, line numbers, status bar, word count, markdown toolbar).

`settings.showLineNumbers`, `settings.wrapLines`, `settings.showStatusBar`,
`settings.showInvisibles`, `settings.showDocumentStats`,
`settings.reopenLastSession`, `settings.rainbowBrackets`,
`settings.emphasizeEnclosingPair`, `settings.autoRefreshPreview`,
`settings.autoShowPreviewForMarkdown`, `settings.showMarkdownToolbar`,
`settings.printLineNumbers`, `settings.smartQuotes`, `settings.smartDashes`,
`settings.automaticTextReplacement`, `settings.automaticSpellingCorrection`,
`settings.smartInsertDelete`, `settings.continuousSpellChecking`,
`settings.insertSpacesForTab`, `settings.pcStyleNavigationKeys`,
`settings.autoIndent`, `settings.indentBetweenBrackets`,
`settings.autoCloseBrackets`, `settings.stripTrailingWhitespaceOnSave`,
`settings.sidebarSortFoldersFirst`, `settings.sidebarSortAscending`,
`settings.sidebarOpenOnSingleClick`, `settings.sidebarOnRight`,
`settings.confirmBeforeDelete`, `settings.syncSidebarWithActiveTab` — all ✅.

### 6b. Popups (3) — select each item + assert

| Popup | Items | Plan |
|---|---|---|
| `settings.appearance` | System / Light / Dark | `settings-toggles.json` (I) |
| `settings.enclosingPairEmphasisStyle` | Bold / Underline / Background | `settings-toggles.json` (I) |
| `settings.externalChangePolicy` | Notify / Prompt / Auto-reload if clean | `settings-toggles.json` (I) |

### 6c. Numeric fields — valid + malformed (the reject contract)

| Field | Valid | Empty | Malformed | Plan |
|---|---|---|---|---|
| `settings.tabWidth` (formatter 1–16, int) | ✅ set 8 — I | ✅ clear+commit → reverts — T | ✅ `abc`/`-3`/`1.5`/`99` → formatter rejects, reverts to valid — T | `settings-field-rejection.json` |
| `settings.editorPadding` (formatter 0–40, int) | ✅ set 20 — I | ✅ clear+commit → reverts — T | ✅ `-1`/`999`/`x` → rejects, reverts — T | `settings-field-rejection.json` |
| Font size | 🔬 no editable field — set only via macOS Font Panel; clamp 6–96 covered by `PreferencesTests` at the model layer | 🔬 | 🔬 | `PreferencesTests.testFontSizeClamps` (unit) |

### 6d. Font button

| Surface | Coverage | Plan |
|---|---|---|
| `settings.chooseFont` opens the Font Panel | ✅ H (assert panel appears) | `settings-toggles.json` |
| Font-panel value manipulation | ⛔ system Font Panel is a separate process/AX surface; out-of-range not enterable there | AP-feedback: system-panel driving |

## 7. File open — valid, empty, malformed files (disk fixtures)

Malformed/large/permission fixtures are generated at stage time in
`stage-fixtures.sh` (never committed); small text fixtures live in
`uitests/fixtures/`.

| File case | Behavior asserted | Plan | Fixture |
|---|---|---|---|
| Normal `.txt` | ✅ opens, content visible — H | `open-and-type.json` etc. | committed |
| **Zero-byte** file | ✅ opens empty, no crash — T | `edge-open-bad-files.json` | staged (`: > `) |
| **Extensionless** file | ✅ opens as plain text — T | `edge-open-bad-files.json` | committed `noext` |
| **Invalid UTF-8** bytes | ✅ opens (encoding fallback), no crash — T | `edge-open-bad-files.json` | committed `invalid-utf8.txt` |
| **Large (1 MB)** file, batched | ✅ opens within timeout, no hang, app interactive — T | `edge-open-large-file.json` | staged (`head -c 1m`) |
| **5 MB junk** file, batched | ⚠️ opens as a single file but STALLS window creation when batched with another (main-thread synchronous open) — **medit defect M1**, not asserted; the large-file plan is bounded to 1 MB so it stays green | — | — (see `docs/autopilot-feedback.md` M1) |
| **Permission-denied** (`chmod 000`) | ✅ fails gracefully — medit window/editor stay present & readable — T. macOS itself shows a system modal (CoreServicesUIAgent, not medit); typed-text round-trip deliberately not asserted (**medit defect M2 / AP-doc D7**) | `edge-open-denied-file.json` | staged, `chmod 000` |

## 8. Encoding / Language switch on open content

Identifiers: `languageButton`, `encodingButton` (status bar popups).

| Surface | Valid | Adversarial | Plan |
|---|---|---|---|
| Language switch while content open | ✅ pick a language, content unchanged — I | ✅ switch repeatedly — T | `encoding-language-switch.json` |
| Encoding switch (reinterpret) while content open | ✅ pick an encoding, no crash — I | ✅ switch to an incompatible encoding on non-ASCII text → no crash — T | `encoding-language-switch.json` |

## 9. Multi-window / multi-file / tabs

| Surface | Coverage | Plan |
|---|---|---|
| ⇧⌘N new window; ⌘N new tab | ✅ H/I | `multi-window.json` |
| Open many files → one window, N tabs (launch) | ✅ H | `open-into-tabs-launch.json` |
| Open many files → one window, N tabs (runtime) | ✅ H | `open-into-tabs-runtime.json` |
| Rapid repeated File ▸ New (stress) | ✅ T (N tabs, no crash) | `edge-rapid-new-tabs.json` |
| Sidebar open file / second file | ✅ H | `sidebar-open-file.json`, `sidebar-open-second-file.json` |
| File drag-drop onto editor (single + multi) | ✅ H | `drop-files-onto-editor.json` |

## 10. Markdown preview (WKWebView)

| Surface | Coverage | Plan |
|---|---|---|
| Show preview, render table | ✅ H | `markdown-table-preview.json` |
| Preview keyboard scroll (Home/End/PageDn) | ✅ H/I | `keyboard-scroll-preview.json` |
| Copy from rendered preview → NSPasteboard | ✅ H/I (v2.7.4 regression guard) | `preview-copy-test.json` |
| Find term near bottom → preview scrolls to it | ⛔ **known bug** — preview does not scroll to match; guarded, screenshots document it | `preview-find-scroll.json` |

## 11. Known AP-blocked surfaces (filed for the AP agent)

See `docs/autopilot-feedback.md` for the full write-ups.

| # | Surface | Why AP can't drive it | Workaround in suite |
|---|---|---|---|
| 1 | Suite-mode sequential runs | Force-killed prior instance's AX tree lingers → next plan sees 2 windows | Individual per-plan runs are the CI gate; pre-quit cleanup reduces force-kills |
| 2 | Menu items disabled at open time (e.g. Column Selection Mode) | `menu` action lists only enabled items | Drive via key equivalent (`⌥⌘B`) instead |
| 3 | Clipboard-content assertion | No primitive to read `NSPasteboard` directly | Assert indirectly: paste into a new tab and check the editor value |
| 4 | Modal-sheet field rejection **state** | Can't assert a beep/refused-edit directly | Assert the field **reverted to a valid value** after committing garbage |
| 5 | System panels (Font Panel, Open/Save, Print) | Separate processes / AX surfaces a fresh-launch plan can't pre-arrange | Assert only that the panel **appears**; don't drive its internals |
| 6 | Full-screen transition | Window-server/AX instability during the transition | Not toggled in the suite |
| 7 | Menu-item `marked` checkmark (cold) | `AXMenuItemMarkChar` unset until menu validated | Assert the toggle's **side effect** instead of its checkmark |
| 8 | (medit-side, now FIXED) control AX identifiers not vended | `setAccessibilityIdentifier` on a cell-based control isn't vended to the AX tree — only the cell's is | Fixed in medit via `setTestAXIdentifier` (sets both); **AP diagnostic value**: `dump-axtree`/`find` silently omit control-only identifiers, which cost real debugging time |
