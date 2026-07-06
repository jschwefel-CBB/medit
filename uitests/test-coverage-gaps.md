# medit — test coverage gaps & abuse-case backlog

_A working TODO of tests we're **missing**, places existing tests could be **more thorough**,
and **abuse/adversarial** cases not yet exercised. Companion to `coverage-matrix.md` (which
records what IS covered)._

Built from an exhaustive source audit (2026-07-04) of every menu/shortcut, editor/document/
preference behavior, and the preview/sidebar/status/find surfaces, **cross-referenced against
the AP plans and ~440 unit tests**. Line refs are to the primary implementation site.

> **✅ INTEGRATED (through 2026-07-05, medit v2.8.0)** — the drivable GUI gaps below now have
> suite plans, running on the RELEASED AutoPilot 3.2.1:
> - **A1 (partial)** in-place Save → `save-in-place.json` _(Save-As panel still blocked)_
> - **A2** external-change reload banner (Reload + Dismiss) → `reload-banner.json` _(via AP `exec`)_
> - **A3** sidebar context-menu New File → `sidebar-context-newfile.json`
> - **A4** go-to-line out-of-range reject-and-beep → strengthened in `go-to-line.json`
>   _(and its wrong "clamps to last line" description was corrected in `coverage-matrix.md`)_
> - **A5** overwrite (type-over) mode: Insert key, type-over, **paste-over**, click INS/OVR pill
>   → `overwrite-mode.json` _(via AP `insert` key + the medit paste/click fixes + `modeLabel` AX id)_
> - **B1** editor input behaviors (auto-close brackets, auto-indent, literal-Tab-not-remapped)
>   → `editor-behaviors.json`
> - **B2** markdown toolbar buttons insert (bold/italic/code) → `markdown-toolbar-insert.json`
> - **D4 / find-scroll** find match-count + editor scrolls to a far match → `find-scroll.json`
> - **D6** clipboard assert adopted directly in `edge-copy-nothing-selected.json` _(AP ≥ 3.2)_
>
> **Still open** (AP-blocked or not yet built): **A6/A7** Find-in-All-Tabs / Print
> (separate-process panels — assert-appears only), **D2** line-ending picker _(now has the
> `lineEndingButton` AX id — a plan can be written)_, plus everything in §C/§D/§E not listed
> above (depth/abuse cases). The §F medit fixes are done except where noted.

**Central finding.** The **model layer is very well unit-tested** (bracket logic, indenter,
keyboard-nav, column model, text search/stats/transforms/hygiene, encoding detection, line
endings, markdown render/print, sessions, file-tree, recent files, file-system ops). The gaps
are almost entirely in **GUI/integration wiring** (does a pref/menu/button actually produce its
observable effect through the real UI?) and in **adversarial abuse** of happy-path-only surfaces.
GUI plans should verify the wiring, **not** re-test the pure logic (see §E).

Legend: **[GAP]** no test at all · **[THIN]** driven but under-asserted · **[ABUSE]** adversarial
case to add · **[FIX]** needs a small medit change (usually a missing AX id) to be testable ·
**[UNIT✓]** model is unit-tested but the end-to-end UI path is not.

---

## A. Whole features with ZERO GUI coverage (highest value)

### A1. Save / Save As / Revert — the entire persistence path  [GAP] [UNIT✓]
No plan sends `⌘S`, `⇧⌘S`, or drives Revert (verified: the only `cmd+…` keystrokes in the suite
are `cmd+shift+[`, `cmd+shift+z`, `cmd+shift+n` — never `cmd+s`). Everything that only happens on
save is GUI-unverified end-to-end:
- **Save** modified doc → disk bytes updated; edited/dirty indicator clears. `TextDocument.data(ofType:)` pulls the freshest live editor text first. `TextDocument.swift:120-134`
- **Save As** to a new path → new URL recorded into Recent Files. `TextDocument.swift:105-111`, `MainMenu.swift:97-99`
- **Revert to Saved** → re-reads disk, pushes fresh text into editor. `TextDocument.swift:182-186`, `MainMenu.swift:101-102`
- **Strip-trailing-whitespace-on-save** + **ensure-final-newline** — changes on-disk bytes only, NOT the live buffer (a test must read the saved file). `TextHygiene` unit-tested; no round-trip GUI test. `TextDocument.swift:129-131`
- **Encoding round-trips on save**; **BOM preserved** (UTF-8) / always-emitted (UTF-16/32); **line endings normalized** to the doc's ending. `TextDocument.swift:132-133`
- **Save never disturbs caret/selection** (builds output from a local copy). `TextDocument.swift:126-133`
- Blocker: Save/Save As uses the system Save panel (separate-process — AP can assert it appears but can't drive it). A `--save-to <path>` test hook (mirroring the existing `--open-files`) would make the whole round-trip drivable headlessly → **[FIX candidate]**.

### A2. External-change → Reload banner — the flow is never triggered  [GAP] [UNIT✓]
`settings-popup-external-change.json` only cycles the **policy popup** (Notify/Prompt/Auto-reload);
it never makes a real on-disk change, so the banner never appears. The banner + its AX-id'd
controls (`reloadButton`, `dismissReloadButton`, `reloadBannerLabel`) and the whole
`ExternalChangeResolver`/`DirectoryWatcher`/`ReloadBanner` path are GUI-untested. `TextDocument.swift:188-275`, `EditorViewController.swift:140-144`
- Open a `/tmp` fixture, rewrite it on disk mid-plan → **Notify** policy → assert banner appears (`reloadBannerLabel`).
- Click **Reload** → editor shows new on-disk content; banner gone. Click **Dismiss** → banner collapses, buffer kept.
- **Auto-reload if clean**: external change, no local edits → silent reload, no banner.
- **[ABUSE]** external change *with unsaved local edits* (conflict) → Prompt policy modal, no data loss.
- **[ABUSE]** external **delete** of the open file → "moved or deleted" banner (`TextDocument.swift:195-212`); external **rename**; file replaced with different encoding/line-endings.
- **[ABUSE]** genuine-change guard: touch the file (mtime bump, same bytes) → assert NO banner (self-save/touch false-positive suppression, `TextDocument.swift:188-264`).

### A3. Sidebar context menu — file-system commands, all untested  [GAP] [UNIT✓]
Right-click on a sidebar row exposes **New File, New Folder, Rename…, Move to Trash, Reveal in
Finder, Remove Folder from Sidebar** (`SidebarViewController.swift:464-500`, handlers `:515-622`).
No plan drives any of them. These mutate the real filesystem via `FileSystemOperations` (11 unit
tests) but the menu→action→tree wiring is GUI-unverified. Targetable via `rightClick` on
`sidebarRow:<name>` then the context-menu item.
- New File → untitled created in the clicked folder, selected, inline-rename pre-filled. New Folder likewise.
- Rename… → tree updates. **[ABUSE]** rename to empty / with `/` / to a colliding name → rejected (`FileSystemOperations` rejects these).
- Move to Trash → with `confirmBeforeDelete` on, assert the **confirm prompt**; off → immediate trash. `SidebarViewController.swift:590-602`
- Reveal in Finder; Remove Folder from Sidebar (root rows only).
- **[ABUSE]** delete/rename a file **externally** while the tree is open → DirectoryWatcher refresh keeps expansion. `SidebarViewController.swift:309-338`

### A4. Go to Line sheet — no test at all (only the offset math is unit-tested)  [GAP]
`go-to-line.json` exists and IS a solid plan — BUT the audit flags that the *sheet-level* behavior
has no **unit** coverage (only `TextLocator` math is unit-tested), so the GUI plan is the sole
guard. Confirm the plan covers, and add if missing: **out-of-range → beep + sheet stays open**
(this is reject-and-beep, NOT clamp-to-last-line — `GoToLineSheet.swift:57-66`; the coverage-matrix
currently mis-describes it as "clamps to last line" — **fix that row**). Also **⌃G** as an alternate
trigger (no menu item, `EditorTextView.swift:96-100`).

### A5. Overwrite / type-over mode (Insert key) — whole feature untested via GUI  [GAP] [FIX]
`pcStyleNavigationKeys` on → **Insert key toggles overwrite mode**: typing replaces the char under
the caret, and the caret draws as a filled block; status shows an " OVR " pill. `EditorTextView.swift:112-117, 250-287`
- Type into a doc, press Insert, type → assert the next char is **replaced**, not inserted.
- Press Insert again → back to insert mode. Toggle `pcStyleNavigationKeys` off → overwrite resets. `EditorViewController.swift:648`
- **[FIX]** `StatusBarView.modeLabel` (" OVR ") has **no AX id** — add one to assert the indicator directly; else assert via editor content.

### A6. Find in All Tabs (⇧⌘F) — cross-tab search untested  [GAP]
`EditorWindowController.findInAllTabs:` → `FindInTabsCoordinator` panel. No plan drives it. `EditorWindowController.swift:568`

### A7. Print (⌘P) & Page Setup (⇧⌘P) — untested  [GAP] [UNIT✓]
No plan sends `⌘P`. Markdown docs print the rendered path, others plain-text with optional line
numbers + filename header (`printLineNumbers` pref). Print math is unit-tested (`MarkdownPrinter*`);
the panel + the `printLineNumbers` effect are GUI-unverified. (System Print panel is separate-process
— assert it appears at minimum.) `TextDocument.swift:66-79`

### A8. Jump to Selection (⌘J)  [GAP]
`centerSelectionInVisibleArea:` — scroll the selection into view. Untested. `MainMenu.swift` Find menu.

---

## B. Behaviors that ARE toggled but whose EFFECT is never asserted  [THIN] [UNIT✓]

The settings plans flip these checkboxes and assert the **checkbox state**; no plan verifies the
**editor actually behaves** that way. Each is unit-tested at the model layer but the pref→editor
wiring is GUI-unverified. (All the editor prefs below default *on* except the smart-substitution
family, which defaults *off* — gedit-like, diverging from macOS defaults, so easy to miss.)

### B1. Editor input behaviors
- **autoCloseBrackets**: type `(` `[` `{` → assert closer auto-inserted + caret between; type opener with a selection → assert it **wraps** the selection; type over an existing closer → assert no duplicate. `EditorTextView.swift:215-248`
- **indentBetweenBrackets**: `{` then Return with caret between `{|}` → assert 3 lines with an indented middle line, caret on it. `EditorTextView.swift:176-196`
- **autoIndent**: Return after an indented line → assert the leading whitespace carries; after a line ending in `{`/`:` → assert +1 level. `EditorTextView.swift:164-208`
- **insertSpacesForTab** + **tabWidth**: the *auto-indent* insertion uses spaces vs `\t` and N = tabWidth. **Important subtlety to pin with a test:** a **literal Tab keypress is NOT remapped** — `insertSpacesForTab`/`tabWidth` affect only auto-indent insertion and tab *render* width, not pressing Tab (no `insertTab` override). Assert both the auto-indent whitespace kind AND that a literal Tab still inserts `\t`. `EditorTextView.swift:198`, `EditorViewController.swift:505-517`
- **tabWidth render width**: assert the tab stop advance changes with tabWidth (geometry). `EditorViewController.swift:505-517`
- **smartQuotes** (`"`/`'` → curly), **smartDashes** (`--` → en/em dash), **automaticTextReplacement**, **automaticSpellingCorrection**, **smartInsertDelete**, **continuousSpellChecking** (red squiggle). `EditorViewController.swift:111-116`
- **pcStyleNavigationKeys**: Home/End = line vs document start/end; assert via caret position (`positionLabel`) with the pref on vs off; Shift+Home/End extends selection; ⌃Home/⌃End = doc start/end. `EditorTextView.swift:119-135`
- **editorPadding**: assert `textContainerInset` changes the layout inset (geometry). `EditorViewController.swift:120-121, 662-663`

### B2. Markdown toolbar buttons don't verify insertion  [THIN]
`view-toggles.json` checks `mdStyle.*` button **presence** only (verified: 0 clicks). The buttons
**have AX ids** (`mdStyle.bold`, `.italic`, … `mdStyle.<action>`, `MarkdownStyleBar.swift:113`) so
they're targetable. Add: with a selection, click each → assert the markdown wraps/prefixes:
bold `**…**`, italic `*…*`, strikethrough, code (backticks), link, heading, bullet, ordered, quote,
codeBlock. **[ABUSE]** apply to an empty selection; apply twice (toggle off?); at start/end of doc.
(`MarkdownEditingTests` covers the model; the button→editor path is GUI-unverified.)

### B3. Emphasize-enclosing-pair + its style popup  [THIN]
`emphasizeEnclosingPair` on + caret inside a pair → the innermost pair is emphasized; the
`enclosingPairEmphasisStyle` popup picks Bold/Underline/Background. Toggled in settings but the
**visual emphasis effect** (and the three style variants) is never asserted (would need
`assertRegion`/`snapshot` on the pair). `EditorViewController.swift:620-621`

### B4. View-menu toggles under-assert their effect  [THIN]
`view-toggles.json` = 28 steps, **1 assert**. It toggles but rarely asserts the effect. Add
per-toggle effect assertions: line-numbers **gutter geometry** (and that an **empty doc hides the
gutter**, `EditorViewController.swift:569-586`), invisibles **glyphs** rendered, rainbow-bracket
**colors**, sidebar **geometry**, toolbar presence. Prefer AX geometry / `assertRegion` over a bare
screenshot.

---

## C. Existing plans that drive but under-verify (assert-thinness sweep)  [THIN]

From the per-plan assert audit:
- **`keyboard-scroll-preview.json`** — **0 asserts.** Before/after screenshots only; nothing fails
  if the preview stops scrolling. The editor sibling `keyboard-scroll.json` asserts the scrollbar
  `AXValueIndicator` fraction — add an equivalent objective preview-scroll assertion (web-area
  scroll position, or `assertRegion`/`snapshot` diff of top vs bottom).
- **`markdown-table-preview.json`** — **0 asserts.** Waits for the web area + screenshots; never
  verifies the **table rendered**. Add a `snapshot`/`assertRegion` on the table region.
- **`open-into-tabs-launch.json` / `-runtime.json`** — 6 steps, 1 assert each (only "one window").
  Also assert **tab count == N** and each file's content loaded.
- **`view-toggles.json`** — see B4.
- Broadly: wherever a plan only screenshots, prefer an objective assertion (AX value/geometry,
  `assertRegion`, `snapshot`) so a regression actually fails.

---

## D. Depth & abuse cases within surfaces that have happy-path coverage  [ABUSE]

### D1. Encoding — Reinterpret-as vs Convert-to are DISTINCT ops, conflated in coverage
`encoding-language-switch.json` clicks `encodingButton` but does not distinguish the two menus.
They differ: **Reinterpret as…** re-decodes the *original bytes* as a new encoding (fixes a wrong
auto-detect; changes the visible text); **Convert to…** keeps the text and only changes the *save*
encoding. `TextDocument.swift:150-165`, `StatusBarView.swift:192-208`. Cover both distinctly, plus
**[ABUSE]**: reinterpret UTF-8 as Latin-1 then back (data integrity), on a doc with a BOM, on invalid
bytes. Selectable set is exactly UTF-8 / UTF-16 / ISO Latin-1 / ASCII (`EncodingCatalog.swift`).

### D2. Line-ending picker — untargetable + uncovered  [FIX] [GAP]
`StatusBarView.lineEndingButton` switches LF/CRLF/Classic Mac and normalizes the buffer live, but
it is the **one status-bar control with no `setAccessibilityIdentifier`** (positionLabel,
documentStatsLabel, languageButton, encodingButton, columnModeLabel all have ids; lineEndingButton
does not — verified). **[FIX]** add `lineEndingButton.setAccessibilityIdentifier("lineEndingButton")`.
Then cover: switch LF↔CRLF↔CR → assert the button label + that a subsequent save writes the chosen
ending (ties to A1). `StatusBarView.swift:210-221`, `TextDocument.swift:168-177`

### D3. Language picker — full list + edge items
`encoding-language-switch.json` switches language, but per-item coverage of the language list
(`LanguageCatalog`, incl. Auto-Detect / Plain Text / "All Languages…") and the re-highlight +
markdown-toolbar-visibility side effect (`EditorViewController.swift:205-211`) is thin.

### D4. Find/Replace bar depth  [ABUSE]
The search **engine** is fully unit-tested (`TextSearchTests`), but the **bar UI** behaviors are
GUI-thin. Add: **wrap-around** (find-next past the last match wraps to first; find-prev before first
wraps to last — `EditorViewController.swift:838-842`, unit-untested branch); **match-count label
text** ("N matches"/"Not found"/"Bad regex" on `findStatusLabel`); **replace-one guard** (only
replaces if the selection exactly matches); **seed-from-selection** when opening the bar; Return in
the find field does **live update, NOT find-next** (only chevrons / ⌘G advance) — pin this
expectation. Note: **find-in-selection does not exist** (`EditorViewController.swift:829,869` always
search the whole string) — flag as a code+test gap if desired.

### D5. Sidebar depth (beyond the context menu in A3)  [ABUSE]
`sidebar-open-file` / `-second-file` cover basic open. Missing GUI coverage for: single-click vs
double-click open per `sidebarOpenOnSingleClick`; folders-first / ascending **sort order** effect;
**show-hidden-files** effect; **sidebar-on-right** live reorder; **sync/reveal active file**
(expand-to + select on tab switch); **Recent pane** (populate, open from it, **dim missing files**,
clear, Recent context menu); **empty folder**; **empty sidebar** → choose-folder prompt;
security-scoped-bookmark restore after relaunch. **[ABUSE]** very large folder / thousands of entries;
symlink loop; permission-denied directory; drag-drop **into** the sidebar (internal move file→folder,
and external files→open — vs onto the editor, which IS covered).

### D6. Session restore / multi-window depth  [UNIT✓]
`WindowSession`/`SessionStore` are unit-tested and headless XCTest deadlocks on window display, so
this is AP territory — yet only `--reset-state` + single-window basics are GUI-exercised. Add: quit
with **N windows × M tabs + per-window sidebar root** → relaunch (no reset) → assert the full
workspace restored (windows, tabs, active tab, sidebar folder, frames). **[ABUSE]** restore when a
previously-open file was deleted/moved (skipped gracefully); corrupt session data; legacy flat-session
migration. `AppDelegate.swift:65-128`

### D7. Column / block selection depth  [ABUSE]
`ColumnSelectionTests` (13 unit) + `column-select.json` are strong. Add GUI **[ABUSE]**: column-select
across lines of differing lengths, across an empty line; type/replace in column mode (insert on every
row vs replace-block); **column copy/cut/paste** (rows joined by `\n`, paste distributes per-row);
**undo of a column edit** as one unit; Escape exits column mode; arrows move/extend the block.
`EditorTextView.swift:546-590`

### D8. "Already open" & tab lifecycle  [ABUSE]
`AlreadyOpenFocusTests` (unit) + `multi-window` (GUI) partially cover. Add GUI: open an already-open
file (from sidebar / Recent / launch) → focuses the existing tab across windows, no duplicate; the
**lone-pristine-untitled cleanup** (open a file next to a blank Untitled → the blank tab is trimmed,
`AppDelegate.swift:249-264`); AppKit's auto-inserted tab menu items (Show Next/Previous Tab, Move Tab
to New Window, Merge All Windows); **close a dirty tab → save prompt**; close window with multiple
dirty tabs; ⌘W behavior.

---

## E. Cross-cutting abuse / robustness  [ABUSE]

- **Very long single line** (~MB, no newlines): typing, wrap toggle, find, caret nav, column select.
- **Huge line count** beyond the bounded 1 MB large-file test (M1 = the known main-thread stall;
  extend once M1 is fixed and document the boundary).
- **Input storms**: hold-repeat a key; paste a huge clipboard; rapid tab open/close/switch (partly
  `edge-rapid-new-tabs`); rapid preview show/hide; rapid settings toggling; rapid find-next spam.
- **Adversarial content**: NUL bytes, RTL override / bidi, combining marks, zero-width joiners,
  control chars (`edge-unicode-content` covers *some* — extend). Mixed line endings (CRLF+LF) in one
  file → detection + normalization on save.
- **Undo/redo across operation types**: undo a find-replace-all, a column edit, a case transform, a
  markdown-toolbar insert, an auto-close, an auto-indent — each should be a single undo unit
  (`EditorTextView` wraps them in `shouldChangeText`/`didChangeText`); assert one ⌘Z reverts each.
- **Clipboard abuse**: copy a huge selection; paste **RTF / image / binary** into the plain-text
  editor (should land as plain text or be rejected, `isRichText=false`); copy from preview → paste
  into editor (partly `preview-copy-test`).
- **Filesystem / permissions**: open a **read-only** file, edit, save → graceful failure; file on an
  unmounted-then-remounted volume; save to a full / read-only location; open a file that disappears
  mid-edit (ties to A2).
- **Preview link security** (unit-untested, `EditorViewController.swift:935-950`): a rendered `http`
  link opens externally + cancels in-page nav; a `file:`/`data:` link does **nothing**. Hard to drive
  headlessly (external open) but worth an attempt or an explicit note.

---

## F. Small medit changes needed to make gaps testable  [FIX]

1. **`lineEndingButton` AX id** — add `setAccessibilityIdentifier("lineEndingButton")` (cell-aware if
   needed) so the line-ending picker is targetable (D2).
2. **`modeLabel` (INS/OVR) AX id** — add one so overwrite mode's indicator is assertable (A5).
3. **`--save-to <path>` launch hook** — mirror the existing `--open-files`/`--open-folder` test hooks
   so Save/Save-As round-trips (encoding, BOM, line-ending, whitespace-strip) are drivable without the
   separate-process system Save panel (A1). Optional but unlocks the biggest gap.

---

## G. What NOT to duplicate (already covered by ~440 unit tests)
Do **not** re-test the pure model in GUI plans — verify the UI **wiring** to it instead:
bracket matching/depth, indenter, keyboard navigator, column-selection model, text
search/statistics/transforms/positions/locator, text hygiene, encoding detection + catalog,
line-ending detect/normalize, shebang/language maps, markdown HTML + print renderers + markdown
editing, session codec + legacy migration, file-tree + data source, recent-files store, file-system
operations, preferences defaults/persistence, launch-reset parsing. `EditorSmokeTests` (61 tests)
already drives real controllers for many show/hide + engine paths — lean on it for logic, use AP for
the true GUI-integration and abuse cases above.
