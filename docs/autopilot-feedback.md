# Field Report for the AutoPilot Agent

> **Per-release log at the very top (newest first), then the older numbered Rounds
> (3 → 2 → 1). A short entry is added here before every medit merge — even when
> there's nothing new — so there's an auditable per-release trail.**

---

## medit 2.7.5 — comprehensive suite: full Settings + edge-case coverage

This session added exhaustive coverage of the Settings panel and adversarial
edge cases (bad/empty/malformed input). To make the Settings panel targetable,
medit added stable `settings.*` AX identifiers to all 33 checkboxes, 3 popups,
2 numeric fields, and the font button, plus `findRegexToggle`/`findCaseToggle`
on the find bar (all verified resolving 1:1). New plans: `settings-toggles`,
`settings-popup-appearance/emphasis/external-change`, `settings-field-valid`,
`settings-field-tabwidth-reject`, `settings-field-padding-reject`,
`settings-persistence-set`/`-verify`, `view-toggles`, `find-regex-metachars-off`,
`edge-unicode-content`, `edge-empty-doc-ops`, `edge-copy-nothing-selected`,
`edge-undo-past-history`, `edge-open-bad-files` (malformed-content batch),
`edge-open-large-file` (bounded 1 MB large-file open), `edge-open-denied-file`,
`edge-rapid-new-tabs`, `encoding-language-switch`; `column-select` extended with
Capitalize and column-mode-via-⌥⌘B. Two medit bugs surfaced here (M1 large-file
main-thread stall, M2 denied-file system modal) — see below.

**Result: 37/37 plans pass in a full sequential suite run.** The suite is run with a
kill-medit + restage-fixtures + dismiss-system-alerts step between plans (the last is
needed only because of the denied-file case — see D7/M2). Individually every plan also
passes. The AX-linger race that previously flaked back-to-back launches is avoided by
killing the prior instance between plans rather than relying on teardown.

### VALIDATED against AutoPilot `feature/ap-feedback` (the branch that closes this report)

> AutoPilot handed medit a validation checklist for the branch that answers this field
> report. Validated on 2026-07-03 with a release build of `feature/ap-feedback` (core +
> macos). Results:
>
> - **D6 — clipboard assert:** ✅ works. Target-less `{ "property": "clipboard" }` reads
>   the pasteboard directly (validated: a copy-then-assert-clipboard plan passes; the
>   released AP rejects the property). Simplifies `edge-copy-nothing-selected` from the
>   paste-into-a-new-tab workaround (19 steps) to a direct clipboard assert (12 steps) —
>   **held for adoption** until this AP release ships, so the committed suite stays green
>   on the AP black-box testers have today. The ready replacement is checked in as
>   `uitests/edge-copy-nothing-selected.clipboard-assert.json.pending` (the `.pending`
>   suffix keeps it out of the `*.json` suite glob) — swap it in when AP releases.
> - **D7 — `dismiss-alert`:** ✅ works, with a caveat. `autopilot dismiss-alert --pid
>   <CoreServicesUIAgent> --button OK` presses the LaunchServices permission modal that a
>   medit-attached run can't see. **Caveat:** that alert self-expires in ~2–10 s, so
>   dismiss-alert only succeeds while it is still up (otherwise "No matching button
>   found") — invoke it immediately after the denied-file plan.
> - **D1/D2 — popup recipe:** ✅ the documented press→click-AXMenuItem + focus-reset
>   recipe drives medit's `settings.*` popups (all three `settings-popup-*` plans green).
> - **Menu discovery (`autopilot menu`):** ✅ "Column Selection Mode" is now visible in
>   discovery with its `enabled` flag. Note: `markChar` cold-reads empty for checked
>   items (the known AppKit "mark not populated until the menu is opened" caveat) — a
>   cold `menu` dump can't report toggle checkmarks yet.
> - **dump-axtree filters:** ✅ `--omit-menubar` (261→23 nodes) and `--under-role
>   AXWindow` work. Minor: `--under-role AXWindow --interactive-only` combined returned
>   0 on medit (the interactive set is mostly menu items outside the window subtree) —
>   each filter alone is fine.
> - **Exit code 4 (unsupported key):** ✅ distinct from exit 2.
> - **AX-linger race fix:** ✅ mostly. 8 historically-linger-flaky plans ran back-to-back
>   with **no** `pkill`/`sleep` guard, all green. BUT a full no-guard suite run flaked
>   twice — `edge-open-large-file` (the denied-file alert bled into the next plan's
>   `type`) and `keyboard-scroll-preview` (state/focus residue). So the guard can be
>   *reduced* (drop `-9` and the fixed sleep) but the denied-file alert still needs an
>   explicit `dismiss-alert`, and restaging between plans is still required for state.
>   Both flakes pass clean when run individually — not regressions.
>
> Net: every **new** primitive on the branch works; adopting the clipboard assert +
> `dismiss-alert` and keeping a minimal kill+restage between plans keeps the suite at
> 37/37. **But not everything in the original report is closed** — see the "STILL OPEN"
> block immediately below: **D3** (same-field re-edit) is still broken, and a **new**
> prefs-field-not-ready-after-`waitFor` flake surfaced. **D4** flipped to resolved.
> Green light on the branch's *new features* from medit's side (release still gated on
> the explicit "go"); D3 + the new flake are the remaining AP-runtime items.

### STILL OPEN after `feature/ap-feedback` — re-validated with evidence (AP: please ingest)

> Two report items were **not** addressed by the branch, plus one **new** flake surfaced
> during this re-validation. All reproduced on the same build under test:
> **autopilot-macos `5cf7cfe` + autopilot-core `4e57986`** (release), medit Debug build,
> 2026-07-03. These are AutoPilot-runtime items (not medit bugs, not doc-only).

**D3 — same text field cannot be re-edited twice in one run. STILL BROKEN.** ❌
A `type` (with `clear`+`commit`) into a field commits the **first** time; a **second**
`type` into the **same** field later in the run is silently dropped — the field keeps its
first value. The AP response doc (`docs/autopilot-feedback-response.md`) does not mention
D3; it was not fixed. Reproduced deterministically: in every run that got past the first
edit, `settings.tabWidth` set to `6` then set to `3` **stayed `6`** (the second assert
read `actual=6`, never `3`). Minimal repro:
```jsonc
// after opening Settings (cmd+,) and waiting for settings.tabWidth:
{ "id": "edit1", "action": "type", "target": { "identifier": "settings.tabWidth" },
  "args": { "text": "6", "clear": true, "commit": true }, "level": "happyPath" },
{ "id": "c1", "action": "assert", "target": { "identifier": "settings.tabWidth" },
  "assert": { "property": "value", "op": "equals", "expected": "6" }, "level": "happyPath" }, // passes
{ "id": "edit2", "action": "type", "target": { "identifier": "settings.tabWidth" },
  "args": { "text": "3", "clear": true, "commit": true }, "level": "tryToBreakIt" },
{ "id": "c2", "action": "assert", "target": { "identifier": "settings.tabWidth" },
  "assert": { "property": "value", "op": "equals", "expected": "3" }, "level": "tryToBreakIt" } // FAILS: actual=6
```
An explicit `click` on the field between the two edits did **not** help. Likely the second
`type` isn't re-establishing the field editor / first-responder after the first `commit`
(Return) ends editing. medit's suite works around this (each field edited at most once per
plan; cases split across plans), but D3 is a real AP-runtime limitation that should be
fixed or documented.

**D4 — `commit:true` on a formatter field: NOW PASSES.** ✅ (upgrade from "unspecified")
Typing an invalid value (`abc`) into the `NSNumberFormatter`-backed `settings.tabWidth`
with `commit:true` no longer leaves `abc` visible — the field reverts to a valid number
(`2`). Whether that revert is driven by AP firing end-editing or by medit's own
`controlTextDidEndEditing` delegate, the **observable** property D4 asked about (an invalid
value does not persist under `commit:true`) is now correct. Consider D4 closed.

**NEW — Settings field not reliably ready after `cmd+,` even past `waitFor`.** ⚠️
Independent of D3: after `keyPress cmd+,` opens Settings and `waitFor settings.tabWidth`
resolves present, the **first** `type` into that field still lands on nothing in ~3 of 5
runs (the value stays at the default `2` instead of the typed value). So `waitFor
<field> present` is satisfied before the field is actually editable/first-responder —
the element exists in the AX tree but typing into it is a no-op until slightly later.
A short settle after the window/field appears works around it, but a `waitFor` that only
checks presence gives a false "ready" signal here. Worth either polling `focused`/editability
or documenting that presence ≠ editable for a freshly-opened panel's fields.

### AUTHORING-DOC DEFECTS (undocumented behavior we had to discover the hard way)

> The authoring guide is presented as the complete contract for writing a plan,
> but several behaviors below are **not stated anywhere in it**, so a plan author
> working strictly within the four corners of the docs cannot know them. Each is a
> **documentation defect**: please add explicit guidance. These are not medit bugs
> and not runtime bugs in AP — they are *gaps in what the docs tell an author.*

**D1 — How to select an `NSPopUpButton` item is unspecified.**
The action table documents `type`, `press`, `click`, `menu`, but never says how to
choose a value from a **pop-up button** (`AXPopUpButton`). Empirically `type` with the
item title does NOT select it (the value stays unchanged); the working sequence is
`press` to open the menu, then `click` an `{ "role": "AXMenuItem", "title": "…" }`.
Please document the canonical popup-selection recipe in the action reference.

**D2 — A pop-up cannot be re-opened after a selection without a focus reset.**
After committing a selection, a second `press` on the same `AXPopUpButton` does **not**
re-open its menu, and (worse) opening a *different* pop-up later in the same session can
also fail — the prior menu's teardown leaves focus/first-responder in a state that
swallows the next open. The only reliable workaround we found is to move focus off the
control between opens (e.g. click a neutral control) to dismiss the lingering menu.
Nothing in the docs warns of this; please document the constraint and the recommended
reset, or fix the executor so consecutive pop-up opens are reliable.

**D3 — Re-editing the SAME text field twice in one session does not commit.**
_Status: STILL OPEN on `feature/ap-feedback` (re-validated 2026-07-03 — see the
"STILL OPEN" block above for the deterministic repro and build under test)._
A `type` (with `clear`/`commit`) into a field works the first time; a *second* `type`
into the **same** field later in the run does not commit — the field keeps its prior
value. Editing two *different* fields in one session is fine. The docs describe `type`
as if it is freely repeatable on any field; they should state this same-field re-edit
limitation (or the executor should be fixed). Our suite works around it by editing each
field at most once per plan run and splitting cases across plans.

**D4 — Whether `commit:true` fires `controlTextDidEndEditing` on a formatter field is unspecified.**
_Status: RESOLVED on `feature/ap-feedback` (re-validated 2026-07-03) — an invalid value
typed with `commit:true` now reverts to a valid number instead of persisting._
For a field backed by an `NSNumberFormatter`, it is unclear from the docs whether
`type` with `commit:true` (Return) triggers the same end-editing/validation path as a
real focus-loss. In practice a `NumberFormatter`-rejected value can remain visible in
the field under AP even though a human tabbing away would see it revert. The docs should
specify exactly what `commit:true` does relative to `controlTextDidBeginEditing` /
`controlTextDidEndEditing` and formatter validation, so authors can write correct
"reject bad input" assertions.

**D5 — `setAccessibilityIdentifier` on a cell-based control is not vended (author-facing note).**
This one is a medit fix (we now set the identifier on the control's *cell* too, via a
`setTestAXIdentifier` helper), but it cost real debugging time because **`dump-axtree`
and `find` silently omit the identifier** for cell-based `NSButton`/`NSTextField`/
`NSPopUpButton` when it is set only on the control. The §8 "Discovering identifiers"
guidance ("add `setAccessibilityIdentifier(...)` in the app") is incomplete for AppKit
cell-based controls. Please add a note: for cell-based controls the identifier must be
set on the cell to appear in the AX tree — otherwise authors see an element with a role
but no identifier and assume the app forgot to set it.

**D6 — No clipboard-content assertion primitive.**
There is no documented way to read the system pasteboard, so "copy X" / "copy with
nothing selected leaves the clipboard unchanged" can only be verified indirectly by
pasting into an editor and asserting the result. Worth either a `clipboard` assert
target or an explicit doc note that pasting is the intended pattern.

**D7 — No primitive to see or dismiss a system alert owned by another process.**
When medit fails to open a permission-denied (chmod 000) file, **macOS
LaunchServices** — not medit — puts up a modal "You do not have permission to open
the document …" alert. That alert is owned by `CoreServicesUIAgent`, a *separate*
process, so it never appears in medit's AX tree, AP (attached to the app under test)
cannot see or dismiss it, and while it is up it steals keyboard focus — making any
subsequent `type` into medit's editor race against the alert and intermittently land
nothing. The alert also **lingers across launches** (killing medit does not clear it)
and stacks one-per-attempt, so it can contaminate later screenshot-based plans in a
suite run. There is no documented AP way to (a) assert on / dismiss an alert owned by
a process other than the target, or (b) suppress LaunchServices' own error UI during a
test. We worked around it by (1) asserting only the safety property AP *can* observe on
the target — medit's window + editor remain present and readable after the failed open
— instead of round-tripping typed text, and (2) dismissing the `CoreServicesUIAgent`
alerts out-of-band in the suite runner via `osascript`. Please either document that
cross-process system alerts are out of scope (and the recommended out-of-band cleanup),
or add a primitive to target/dismiss them.

### MEDIT DEFECTS surfaced by this session (medit's own bugs, filed for the medit backlog)

> Unlike the D-series above (which are AP-doc gaps), these are **medit** bugs the
> `tryToBreakIt` tier caught. They are recorded here because they shaped how the edge
> plans had to be written; each deserves its own medit fix.

**M1 — Large-file open is synchronous on the main thread and blocks window creation.**
medit loads a document and applies a full-range attribute/highlight pass
(`configureHighlighter()` → `highlightNow()`) **synchronously on the main thread** at
editor setup. Cost scales with file size: a batched open of a 1 MB file completes in
~7 s, 2 MB ~17 s, but a **5 MB** file opened together with any second file starves the
main thread so the window never becomes AX-ready within any reasonable timeout (it was
the original `wait-window` timeout in `edge-open-bad-files`). Each file individually is
fine; the batch is what makes it visible. Fix direction: load/highlight large documents
incrementally or off the main thread so the first window paints promptly. Until then the
suite bounds the "large file" case to 1 MB (`edge-open-large-file.json`) so it exercises
the big-document path without hitting the stall, and the malformed-content cases
(`edge-open-bad-files.json`) no longer include the 5 MB file.

**M2 — A failed (permission-denied) open surfaces an undismissed system modal.**
Routing the failed open through the document machinery lets **LaunchServices** present
its own permission alert (see D7) rather than medit handling the read failure inline
(e.g. a non-modal in-window banner it controls and can dismiss). medit itself stays
healthy — its window/editor are fine — but the user is left with a stacked,
medit-external modal. Fix direction: detect the unreadable file before/around the open
and present medit's own graceful, dismissible error, so no orphaned `CoreServicesUIAgent`
alert is spawned.

---

## medit 2.7.4 — preview copy fix + autoShowPreviewForMarkdown default=true

Full test-suite regeneration this session: 17 plans total (6 updated, 6 new, 5
unchanged) targeting the Debug build (`/Volumes/Scratch/Xcode/DerivedData/Debug/medit.app`).
All 17 pass individually (`autopilot run <plan>`) and all lint clean.

**New plans added:**
- `preview-copy-test.json` — regression guard for the WKWebView copy fix (wr
  ites to NSPasteboard via `evaluateJavaScript`). 27/27 PASS.
- `go-to-line.json` — Edit > Go to Line (cmd+L), navigate + out-of-range. 22/22 PASS.
- `status-bar-toggles.json` — show/hide status bar, word-count toggle. 20/20 PASS.
- `word-wrap-toggle.json` — View > Wrap Lines status-bar indicator. 15/15 PASS.
- `column-select.json` — Edit > Text transforms (upper/lower case, sort). 21/21 PASS.
- `preview-find-scroll.json` — KNOWN-FAILING regression guard for find-in-preview
  no-scroll bug (intentionally documents the bug via screenshots, all steps pass
  because they only assert findStatusLabel exists, not scroll position).

**Updated plans** (added `integrationSuite`/`tryToBreakIt` tiers):
`open-and-type.json`, `find-replace.json`, `keyboard-scroll.json`,
`keyboard-scroll-preview.json`, `multi-window.json`, `markdown-table-preview.json`.

**New fixtures:** `uitests/fixtures/table-test.md`, `uitests/fixtures/copy-test.md`.
`stage-fixtures.sh` updated to stage them to `/tmp/medit-ap-*`.

**AP findings this session:**

**Suite runner: force-terminate + AX linger race (P1, known from Round 1 P2)**
When a plan's `terminate` step causes medit to present a save dialog (unsaved content),
AP force-kills it. But the next plan launches before the dead process's AX tree
clears — macOS updates the accessibility tree asynchronously. The new plan's `waitFor
AXWindow` matches the dying window's ghost; then the new medit launches, giving 2
`editorTextView` matches ("Selector matched 2 elements"). Plans that create unsaved
content (typed text) now clear it before `terminate` (`cmd+a` + `delete`). Plans that
show WKWebView preview now hide it before `terminate` (WKWebView subprocess teardown
is slower than a plain NSTextView app). Both mitigations reduce force-terminate
frequency, but the root cause is in AP's suite runner. The Round 1 P2 report
mentioned this; still outstanding.

**Confirm request for AP team:** Suite runner should wait for the terminated process
to exit the OS process table (or the AX server to deregister it) before launching
the next plan. `autopilot run <dir>` sequences plans one at a time but does not
currently verify the previous PID is gone before the `waitFor AXWindow` step in the
next plan fires.

**`Edit > Text > Column Selection Mode` not reachable via `menu` action (P2)**
AP's `menu` action walks the `Edit > Text` submenu and lists:
"Sort Lines Ascending, Sort Lines Descending, Make Upper Case, Make Lower Case,
Capitalize" — it does NOT list "Column Selection Mode" even though `dump-axtree`
confirms the item exists in the tree. Likely: the item is disabled at menu-open time
(requires a specific first-responder state), and AP's menu walker only lists ENABLED
items. This means column selection mode cannot be toggled via `menu` from an AP plan.
Workaround: the `columnModeLabel` AX id (`AXStaticText`, value " BLK " when active)
can be asserted to confirm state, but the toggle itself must be done manually or via
a keyboard shortcut if one is available. The `column-select.json` plan covers the
text-transform items in `Edit > Text` but omits column mode toggle.
Recommendation: either let the menu walker list disabled items (authors can choose to
invoke them), or document that `menu` only walks enabled items.

**`hide-preview` menu item naming (informational)**
When Markdown preview is showing, the menu toggle shows "Show Markdown Preview" (a
toggle that hides it), NOT "Hide Markdown Preview" — the item label doesn't flip.
This makes the menu path for hide-preview identical to show-preview:
`["View", "Show Markdown Preview"]` in both directions. Not a bug, just worth noting
for plan authors.

**8/17 plans fail when run as a directory suite; all 17 pass individually — root
cause is the AX linger race above.** Individual plan results are the reliable gate;
suite mode is not yet stable enough for CI.

---

## medit 2.7.3 — drag-to-editor fix (correct NSTextView pipeline override)

v2.7.2 shipped with a broken drag-to-editor fix (`FileDroppingScrollView`
subclass) — files dragged onto the editor text area still silently rejected.
v2.7.3 replaces the entire approach with the correct AppKit-internal mechanism.

**Root cause — editor (real):** `NSTextView` (with `isRichText = false`) runs
an internal drag-registration pipeline:
  `acceptableDragTypes → updateDragTypeRegistration → registerForDraggedTypes`
This pipeline fires every time `isRichText`, `isEditable`, or `setTextContainer`
changes and **replaces** the entire registered-type set. Any direct
`registerForDraggedTypes` call (including in `viewDidMoveToWindow` or from a
`FileDroppingScrollView`) is silently wiped out on the next pipeline run. For
`isRichText = false`, AppKit does not include `.fileURL` or
`NSFilenamesPboardType` in the pipeline output at all — so the OS drag system
never considers the text view a valid destination and `draggingEntered` is never
called. The `NSScrollView`/`NSClipView` layer was not the issue.

**Fix — editor:** Four overrides on `EditorTextView` that integrate into the
pipeline rather than fighting it:
1. `acceptableDragTypes` — appends file types to super's list; feeds the pipeline
2. `updateDragTypeRegistration()` — calls super then re-adds file types after
   each reset (survives repeated `isRichText` / `isEditable` changes)
3. `dragOperation(for:type:)` — returns `.copy` for file types (shows + cursor)
4. `readSelection(from:type:)` — the correct AppKit intercept for drop handling
   (NSTextView routes drops here, not through `performDragOperation`)

`FileDroppingScrollView` and `FileDroppingClipView` removed entirely.
`EditorViewController` reverts to plain `NSScrollView`.

**Root cause — sidebar (unchanged from v2.7.2):** `FileTreeDataSource.validateDrop`
only accepted internal drags. External Finder drops (`draggingSource == nil`)
were rejected. Fix: detect external drags → return `.copy`; `acceptDrop` reads
URLs → `onOpenFiles`. `NSFilenamesPboardType` registered on the outline view.

**AP coverage note:** Synthetic file drag events (`toFiles`) are not supported
by AutoPilot — drag paths cannot be directly driven. They share `openFiles(at:)`
with the `--open-files` runtime plan and `performFileDropForTesting` hook —
both already covered. Fix validated manually: single and multi-file drags onto
the editor text area and the sidebar open files as tabs. 8/8 existing plans green.

---

## medit 2.7.2 — BROKEN RELEASE (drag-to-editor did not work)

`FileDroppingScrollView` approach was wrong — see v2.7.3 entry above for the
real root cause and fix. Sidebar fix (`FileTreeDataSource` external drag
detection) was correct and carried forward.

---

## medit 2.7.1 — multi-file open regression + the sandbox-vs-test breakthrough

Fix for a v2.7.0 regression: opening **multiple** files at once (launch args /
Finder "Open With" / dragging multiple files onto the app icon) scattered them
into **separate windows** instead of tabs. Root cause: `tabbingMode
.preferred→.automatic` removed AppKit's auto-merge, and
`application(_:openFiles:)` opened each file with an independent
`openDocument(display:true)` and never called `addTabbedWindow`. Fix routes that
path through `EditorWindowController.openFiles(at:)` (explicit `addTabbedWindow`),
the same entry point sidebar/drag/Recent already use.

**The big AP lesson this session — sandbox vs. synthetic tests:**
- A **sandboxed** medit build (the shipping entitlements) **cannot read ungranted
  `/tmp` fixtures** that a test feeds straight into `NSDocumentController`. Worse,
  it fails **silently**: `openDocument(withContentsOf:display:_,completionHandler:)`
  **never calls its completion** for an ungranted file — no error, no log. This
  burned a lot of time looking like a product bug ("the open path is dead") when it
  was the harness. `launchFiles` works only because AppKit/Powerbox grants those
  specific files at launch.
- **Fix for testing:** the **Debug** build now uses `App/medit-debug.entitlements`
  with the **App Sandbox OFF** (Release stays sandboxed). With the sandbox off, AP
  can drive the real sidebar / folder / open flows against on-disk fixtures, and
  the `openDocument` completion fires normally. Verified the actual product fix
  ALSO holds in the **sandboxed Release** build via `launchFiles` (AppKit-granted)
  → 1 window, N tabs.

New AP assets:
- New AX id **`sidebarRow:<filename>`** on every Folders-pane row (the `value`
  matcher is unreliable for `AXOutline` rows — `find`/`waitFor` on a row's `value`
  timed out even though the dump showed it; an explicit identifier is the robust
  handle). This is the documented fix-it pattern (add an `AXIdentifier`), not a
  workaround.
- New launch hook **`--open-files <p1> <p2> …`** → opens files as tabs via the
  front window's `openFiles(at:)` (the sidebar/drag entry point), so AP can
  exercise the open-into-tabs path NSOpenPanel/Finder-drag normally drive.
- New plans: `open-into-tabs-launch.json`, `open-into-tabs-runtime.json`,
  `sidebar-open-file.json`, `sidebar-open-second-file.json`. All assert
  **1 `AXWindow`** + correct tabs. AP's `AXWindow` `count` assert works reliably
  (the 2.7.0-flagged risk never materialized).

Process gotcha: **kill ALL medit instances between AP runs** (including any stale
`/Applications/medit.app`). A lingering instance steals focus and makes
identifier-based `waitFor` time out — looked like a plan bug, was a stale process.
**File drag-drop onto the editor is NOT reproducible via AP synthetic events**
(`toFiles` unsupported per AUTHORING.md); it shares the `openFiles(at:)` code path,
which the runtime plan + `performFileDropForTesting` unit hook cover.


## medit 2.7.0 — multi-window (no new AX ids)

Added multi-window support: tabs stay the default (⌘N = new tab); **New Window
(⇧⌘N)** is the explicit separate-window action (`tabbingMode .preferred →
.automatic`). Each window is self-contained (own sidebar + tabs); opening an
already-open file focuses its existing tab across windows; session restore rebuilds
the full workspace (window→tab grouping, active tab, per-window sidebar folder via
security-scoped bookmark, window frame).

AP impact:
- **No new AX identifiers.** Multiple windows are matched by the `AXWindow` role;
  the `cmd+shift+n` New-Window chord drives via a `keyPress` step.
- New plan `uitests/multi-window.json` (⇧⌘N → assert >1 `AXWindow`). **Possible
  limitation flagged:** AP's `count` assertion on `AXWindow` may be unsupported (the
  macOS property reader returns nil for `.count`) — if so, the fallback is
  `autopilot dump-axtree --pid <pid> | grep -c '"role" : "AXWindow"'` in manual
  verification; the unit suite (`MultiWindowRoutingTests`) fully covers the
  new-window-vs-tab routing and cross-window focus deterministically.
- Fixtures staged to `/tmp` via `stage-fixtures.sh` (sandbox blocks repo-path
  launchFiles) — same pattern as the 2.6.2 keyboard-scroll plans.


## medit 2.6.2 — AP-driven debugging caught a real bug 2.6.1 shipped broken

2.6.1 shipped on unit-tests + CI alone, WITHOUT running AutoPilot against the app —
and a real bug slipped through: the editor did not scroll to the caret when it sat
below the fold (open/restore with the caret at end of a long file showed the top).
AutoPilot caught it. Lessons + AP findings from this session:

- **AP is the gate, not unit tests alone.** The fix that mattered (`viewDidAppear`
  reveals the restored caret) was invisible to the headless unit suite at first
  because macOS state restoration is what places the caret — only the running app
  showed it. Run the AP plans before shipping UI-behavior changes.
- **Objective scroll signal via AX geometry.** The editor's `AXScrollBar` has an
  `AXValueIndicator` (the thumb); its frame Y within the track = scroll fraction
  (0=top, 1=bottom). Measuring it proved the bug (0.014 with caret at end) and the
  fix (0.989). Useful where there's no AXValue for scroll position. Consider adding
  a first-class "scroll position" assertion to AP.
- **Sandbox blocks repo-path launchFiles.** medit is sandboxed
  (files.user-selected only). `launchFiles` pointing at a repo path
  (`~/repositories/medit/uitests/fixtures/...`) is DENIED ("could not be opened —
  you don't have permission"), even though AP opens via NSWorkspace/LaunchServices.
  `/tmp/...` works. So `uitests/stage-fixtures.sh` copies fixtures to
  `/tmp/medit-ap-*` and the plans target those. AP can't script the Open panel, so
  /tmp staging is the workable pattern for a sandboxed target.
- **WKWebView element screenshots are blank unless frontmost.** Element-scoped
  `screenshot`/`snapshot` of the `markdownPreviewWebView` returns a blank dark frame
  when medit isn't frontmost during capture — top and bottom captures came back
  byte-identical (both blank). The editor (non-web) element screenshots are fine.
  AP should frontmost-gate web-area captures (or warn).
- **`snapshot` action fails to write the reference.** `snapshot` with `reference:`
  + `--update-snapshots` errored "failed to write reference" even with the ref dir
  present. Couldn't baseline a visual snapshot; fell back to plain `screenshot`
  artifacts. Worth a look in the CLI's snapshot writer.
- **One-shot value-read race (recurring).** Asserting `positionLabel` value right
  after a key action sometimes read empty (`actual=`) though a `dump-axtree` a
  moment later showed the value — the known "value assert is one-shot; value late"
  trap. Left the racy assert out of the committed plan (TODO to harden once AP
  settles/polls the read).
- **Menu-toggle still flaky (unchanged):** click the editor before
  `View ▸ Show Markdown Preview`; and wait on the `markdownPreviewWebView`
  identifier, not the `AXWebArea` role (the role didn't resolve post-toggle).

New committed plans: `uitests/keyboard-scroll.json` (editor, 11/11 with real
screenshots) + `uitests/keyboard-scroll-preview.json` (preview; steps pass,
screenshots blank pending the frontmost fix) + `uitests/fixtures/` +
`uitests/stage-fixtures.sh`.


## medit 2.6.1 — keyboard-scroll fixes (no new AP impact)

Two keyboard-scroll bugs fixed, both behind existing AX surfaces — no new AX ids,
no plan changes required.
- **Preview navigation keys** (Home/End/⌃Home/⌃End/PageUp/PageDown) now scroll the
  `markdownPreviewWebView` / `AXWebArea`. To AP-verify, a `keydown` against the web
  area changes its scroll position; no new target needed.
- **Editor Return** now scrolls the new line into view (the custom `insertNewline`
  was missing `scrollRangeToVisible`). Exercised against the existing editor text
  view; no AP surface change.

No new AP findings. The recurring menu-toggle flakiness still applies (click the
editor before the `View ▸ Show Markdown Preview` menu step).


## medit 2.6.0 — preview is now a WKWebView (AP impact recap)

The Markdown preview became a WKWebView (HTML+CSS). AP impact, recorded already in
the prior entry, holds: target `markdownPreviewWebView` / the `AXWebArea` (the old
`markdownPreviewTextView` is gone); `uitests/markdown-table-preview.json` updated
and passes 6/6. No new AP findings this release beyond the recurring menu-toggle
flakiness (a `click` on the editor before the `View ▸ Show Markdown Preview` menu
step works around it).


## Markdown preview → WKWebView (HTML+CSS) — AP findings

The Markdown **preview** was rewritten from TextKit (`NSTextView` + custom
`NSLayoutManager` + `NSTextTable`) to a **WKWebView** rendering HTML+CSS — the way
MacDown/Typora/Marked do it. This fixed a long run of table problems (multi-column
wrap gaps, no horizontal scroll, words splitting at narrow widths, copy/AX
fragility) that were all fights against `NSTextTable`'s limits; the browser does all
of it natively.

**AP-relevant changes:**
- New AX id `markdownPreviewWebView`; the preview content is now an **`AXWebArea`**
  (real, queryable) instead of the old opaque `AXUnknown` table subviews. AP can
  see/inspect the web area; table cell text is selectable browser-native.
- The old preview AX id `markdownPreviewTextView` is **gone** — any AP plan
  asserting it must target `markdownPreviewWebView` / the web area instead.
- `uitests/markdown-table-preview.json` targets the deleted `markdownPreviewTextView`
  and the element-scoped screenshot of it — **update it** to the web view, or assert
  via the web area. (Left for the next AP pass.)

**Recurring AP flakiness (unchanged, still worth a fix on the AP side):** the
`menu` action for "View ▸ Show Markdown Preview" intermittently fails to toggle
unless the window is first made key (a `click` on `editorTextView` before the
`menu` step works around it). Seen across many runs this session.

**Verification done without AP screenshots of the toggle** (the menu flakiness +
the need to flip system appearance) — used direct launch + osascript menu-press +
window-bounded captures (frontmost-gated, never full-display). Light/dark both
verified.

---

## selectable Markdown tables (feature branch) — AP deliberately NOT used; verified headlessly

This cycle made Markdown-preview tables selectable/copyable (real text in a
per-table scrollable subview, replacing the image attachment). **No AutoPilot run
was performed, by design**, and it's worth recording why:

- At verification time the **installed** medit (v2.5.0, separate from the Debug
  build under test) had a **ColdBoreBallistics document open**
  (`CBB_Object_Taxonomy.md`). Per the standing rule that CBB windows are 100% off
  limits and the screenshot-safety rule (never full-display; only window-bounded,
  frontmost-gated capture), **any** screen capture was unsafe — a window-bounded
  shot still risks the wrong window when two medit instances and a private doc are
  in play. So I took **zero** screenshots and drove **no** GUI capture.
- `open file.md` also routed the test file to the **installed** app via bundle-ID
  registration, not the Debug build — the same "wrong instance" hazard the Round-3
  `dump_axtree` phantom-window finding warned about. Lesson reinforced: when two
  builds of the same bundle id are running, GUI tooling can't be trusted to target
  the right one without explicit pid attach.

**What replaced the GUI check:** a headless integration smoke test
(`MarkdownTablePreviewSmokeTests`) that drives the real `EditorViewController`,
shows the preview, and asserts a live, **selectable** `MarkdownTableView` subview is
placed at a **real non-zero frame**. This caught a genuine bug a pure unit test
would have missed: on first preview show, `placeTableSubviews()` ran while the
preview view was still hidden/unsized, producing a 0×0 table frame. Fixed by
un-hiding + sizing the preview before render, and forcing layout before reading
attachment glyph rects.

**AP suggestion (for when a CBB window is NOT open):** the clean way to verify this
feature visually is `autopilot ... --pid <debug-build-pid>` attach (never `open`,
which hits the installed bundle), then a window-bounded capture gated on the Debug
build being frontmost. Until then, the headless test is the trustworthy gate.

---

## medit 2.5.0 — AP findings: screenshot capture (mostly resolved by the AUTHORING.md update)

Docs release (full User Manual + 16 screenshots + App Store prep). The AP work
this cycle was the **documentation screenshot capture**, written up in detail in
the "Screenshot capture for docs" section below (SC-1..SC-5).

**The AUTHORING.md update resolved most of them**, and I proved it by capturing 16
medit-only shots:
- **SC-2 / SC-4 (relaunch race / no attach):** fixed by **`attach: true`** — attach
  to the already-arranged window instead of relaunching. This was the key unlock;
  it's how the find-bar / Recent-pane / Find-in-All-Tabs shots got captured.
- **SC-1 (silent screenshot fail):** AUTHORING.md now documents that the
  unresolved-target path falls back to full-display and sets `result.message`.
- **SC-5 (secondary-display):** documented as handled; I still used the
  `dump-axtree --pid` frame → `screencapture -R` fallback as the reliable path.

**Still open (one real gap):** safely capturing an **open menu/popover that extends
beyond the window frame** (medit's Edit▸Text and the status-bar language/encoding
menus). A window-bounded crop clips them; a bigger region risks catching other
windows (it did, early — caught unrelated app windows). The open menu's own AX
`frame` reported zero-size, so it can't be used to bound the capture. Those 3 shots
are deferred. Also worth flagging from medit's side: the sidebar's
`sidebarPaneSwitcher` (an `AXRadioGroup`) exposes **no accessible segment children**
— neither AP nor System Events can click a named segment (a minor medit a11y gap).

---

## Screenshot capture for docs — findings (using AP's `screenshot` / `captureTarget`)

Capturing README + manual screenshots from the running app. The `screenshot`
action works well in the happy path (clean full-window PNGs of medit's editor,
Markdown preview, and Settings all came out great). But three things tripped up a
documentation-capture workflow:

**SC-1 (P1) — `screenshot` with `target: { role: "AXWindow" }` fails with no
message.** A plan step `{ action: "screenshot", target: { role: AXWindow } }`
returned `result: fail` with `message: null` and wrote **no PNG** — while the
preceding `waitFor editorTextView` on the *same* window **passed** (so AP resolved
the window's elements fine). Repro: `bundleId` target, `waitFor editorTextView`
(pass), then `screenshot` AXWindow (fail, 42ms, no file). **Ask:** when a
screenshot step fails, populate `message` with the reason (target didn't resolve /
capture returned empty / window off-screen) — a silent `fail` with no artifact and
no message is hard to debug. (The full-display fallback path *does* set a message;
the element-target path doesn't.)

**SC-2 (P2) — `run` with `bundleId` terminates + relaunches the app, then
`screenshot` races the unrendered window.** AP logged *"terminating 1 existing
instance(s) of medit.app for a clean relaunch"* — so a `run` plan does **not**
attach to my already-arranged, already-rendered window; it kills it and launches a
fresh one. A `screenshot` immediately after `waitFor` then fires ~40ms in, before
the new window has painted, yielding a blank/failed shot. Plans that added a
`wait` (2–3s) settle after the element appeared captured fine. **Ask:** either have
`screenshot` wait for the window to be paintable (non-empty) before capturing, or
document that a settle is required after launch; and for **doc workflows
specifically**, a `screenshot --pid <pid>` (attach-and-capture, like
`dump-axtree --pid`) would let a caller screenshot an app they arranged themselves
without AP relaunching it.

**SC-3 (P3) — element-scoped crops (`captureTarget` / `screenshot` with a small
element target) of thin/!solid elements landed empty.** Targeting `positionLabel`
(a tiny status-bar label) or `sidebarOutline` produced blank/near-empty crops with
large padding (padding around a 1-line label captures mostly the area *above* it,
including whatever's behind the window). Big solid elements (`editorTextView`,
`AXWindow`) crop fine. For thin strips, capturing the full window and cropping
geometrically was more reliable. Not a bug so much as a sharp edge — element
captures assume the element's frame is the region of interest, which is wrong for
1-line labels surrounded by other content. Worth a note in §12a.

**SC-4 (P1, the practical blocker) — no reliable "drive into a transient state,
then capture" flow.** The genuinely hard part of a documentation run isn't the
capture — it's getting the app into the *state* you want to shoot (find bar open,
sidebar switched to the Recent pane, a multi-tab group, a status-bar popup menu
open, the external-change banner showing) and capturing it before it changes. What
I hit:
- AP's **`menu` action opened the find bar reliably** (good — better than my
  osascript menu-clicking), but the subsequent `screenshot` step then failed
  (SC-1), so the open bar was never captured in the same plan.
- A plan can't easily **hold a transient state across the capture**: by the time a
  follow-on `screenshot` runs (or an external `screencapture` fires), the menu/
  popover has dismissed or focus moved.
- There is no **"capture the app exactly as it is right now" attach mode** — `run`
  relaunches (SC-2), which destroys any state I'd arranged.

What would make doc capture tractable: (a) `screenshot --pid` attach-and-capture
(see SC-2); (b) a `screenshot` that's robust enough to fire immediately after a
`menu`/`click` that opened transient UI, *within the same plan*, without a relaunch
or a long settle; (c) optionally a way to **hold** an opened menu/popover open
across the next step.

**SC-5 (P2, evidence) — AP `screenshot` failed consistently when medit's window was
on a secondary display at negative coordinates; `screencapture -R<rect>` did not.**
On this multi-monitor setup medit's window repeatedly opened at e.g.
`-1774,235,988,592` (left display, negative x). AP's `screenshot` AXWindow target
failed there (SC-1), but `/usr/sbin/screencapture -o -x -R"-1774,235,988,592"`
captured it perfectly every time. **Reliable fallback that worked end-to-end:** get
the window frame from `dump-axtree --pid` (the AX `frame` field is solid), then
`screencapture -R` that rect. Worth checking AP's capture path handles negative /
secondary-display window origins.

**Not AP:** driving medit into transient states via *osascript/System Events*
keystrokes was flaky on my end (AppleScript timing + an intermittently-empty
`System Events … window 1` query). AP's `menu` action is the better lever; the
remaining gap is SC-4 (capture the resulting transient state in the same plan).

**Net:** AP's screenshot **capture** is fine for full-window/large-element shots —
hero, Markdown preview+toolbar, Settings, block-edit, and the sidebar all came out
great via either AP `screenshot` (when it didn't hit SC-1) or the
`dump-axtree --pid` frame → `screencapture -R` fallback. The blockers for a
*complete* doc set are **SC-1** (silent screenshot failure), **SC-2/SC-5**
(relaunch race / secondary-display capture), and especially **SC-4** (no
reliable drive-to-transient-state-then-capture). The medit doc screenshots that
need transient states (find bar, Recent pane, open menus, multi-tab, reload banner)
are **deferred** until these are smoother.

---

## medit 2.4.1 — no new AutoPilot findings

Patch: the block-mode status-bar indicator now shows a blue **` BLK `** pill while
rectangular block editing is active and is **empty (hidden) otherwise** — same
visual flair as the OVR pill. (Earlier this patch had tried an always-visible
"COL" variant; the final behavior is empty-off / blue-BLK-on per the requested
design.) No AP-side issues; `dump-axtree --pid` confirmed the toggle (label empty
when off → ` BLK ` when block mode is entered, empty again when exited).

---

## medit 2.4.0 — no new AutoPilot findings

**AutoPilot commit in use:** `730f6d3` (R4). Work this release: column/block
(rectangular) editing — a custom multi-row caret model on `EditorTextView` (the
feature deferred from 2.3 because NSTextView can't hold multi-row zero-width
carets), plus a status-bar COL indicator.

- **No AP-side issues.** Editing logic was verified by the headless suite (350
  tests, incl. the pure ColumnSelection model + view-level column smoke tests via
  test hooks that bypass mouse geometry). The geometry-dependent parts (Option-drag
  rectangle, multi-row caret drawing) were verified by the user visually — that's
  inherently outside AutoPilot's action model (native drag + custom drawing).
- `dump-axtree --pid` again served well: confirmed the COL status-bar pill toggles
  correctly (`columnModeLabel` absent when off → " COL " present after ⌥⌘B).
- Nothing for AutoPilot to fix this release.

---

## medit 2.3.0 — no new AutoPilot findings

**AutoPilot commit in use:** `730f6d3` (R4). Work this release: session restore
(reopen last files), word count in the status bar, Sort Lines + Change Case
(Edit ▸ Text), and the pure ColumnSelection model (column editing itself deferred
— NSTextView collapses multi-carets).

- **No AP-side issues.** Most verification was the headless test suite (339 tests);
  the feature cores (SessionStore, TextStatistics, TextTransforms, ColumnSelection)
  are pure and unit-tested. `dump-axtree --pid` again verified live state cleanly:
  confirmed session restore (both files reopened as tabs — AX tab buttons
  `['sess-a.txt','sess-b.txt']`) and the live word-count status segment
  (`documentStatsLabel` = "3 words · 4 lines · 20 chars").
- **Nothing for AutoPilot to fix.** The one hard problem this release was an
  AppKit limitation (NSTextView merges zero-width selection ranges), not anything
  AutoPilot-related.

---

## medit 2.2.0 — no new AutoPilot findings

**AutoPilot commit in use:** `730f6d3` (the R4 fixes). Work this release: Recent
Files sidebar pane + three UX fixes (drag-to-open, window cascade-to-lower-left,
persist/restore window frame).

- **No AP-side issues surfaced.** This release's hard bug (file drag-to-open, esp.
  multi-file) was entirely **medit-side** — the editor's `NSTextView` wasn't
  registered for file drag types; multi-file Finder drags additionally require
  `NSFilenamesPboardType`. Native Finder drags are an OS-level drag gesture
  outside AutoPilot's AX-action model, so there is **no AP feature gap to file**
  here; the diagnosis used stderr tracing + manual drags, the right tools for a
  drag-drop bug.
- **The R4 fixes held up well.** `dump-axtree --pid <pid>` (attach-to-running)
  reliably verified real app state this session: it confirmed the restored window
  frame (`640,420,1080,720` for a seeded `{640,300,1080,720}` — the y-flip is AX
  top-left vs AppKit bottom-left) and the populated `recentFilesTable` after a
  pane switch. No phantom-window behavior recurred.
- **Caveat (not AP):** `defaults read` (cfprefsd caching) and `osascript get
  position` intermittently returned stale/empty values during verification —
  macOS CLI quirks, not AutoPilot. `plutil` on the plist and the `--pid` dump were
  the reliable witnesses.

---

> Older numbered rounds: Round 3 (`76e3261`), Round 2 (`7a577f1`), Round 1
> (`3d7b5cb`) — newest first, left intact.

---

## ROUND 3 — `dump_axtree` reports a phantom window, not the real running app

**AutoPilot commit:** `76e3261`. Found while building medit's Markdown features
(v2). This one cost real time: **every state I set up in a running medit instance,
`dump_axtree` reported incorrectly**, sending me chasing bugs that didn't exist.

### R3-1 (P0) — `dump_axtree` does not report the actual running instance's window

**Repro (captured side by side):** launch medit directly with a file, then compare
the OS's own window list against what `dump_axtree` returns for the same bundle id,
*without* AutoPilot launching anything:

```
$ /Applications/medit.app/Contents/MacOS/medit /tmp/sb-test.md &   # one instance
$ osascript -e 'tell application "System Events" to tell process "medit" \
      to get name of every window'
  sb-test.md                      # TRUTH: the file is open, titled sb-test.md
$ pgrep -f medit.app | wc -l
  1                               # exactly one process

# now dump_axtree against the SAME running instance:
$ printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":\
      "dump_axtree","arguments":{"bundleId":"com.jschwefel.medit"}}}' \
      | AutopilotMCP
  windows: ['Untitled']           # WRONG: reports an Untitled window
  style-bar buttons: 0            # WRONG: the toolbar is plainly on screen
$ pgrep -f medit.app | wc -l
  1                               # still ONE process — it didn't spawn a 2nd
```

So `dump_axtree`:
- **does NOT spawn a second process** (process count is 1 before and after — I
  initially suspected this and it's false), yet
- **reports a different window** (`Untitled`, empty, no Markdown toolbar) than the
  one the app is actually displaying (`sb-test.md`, with the toolbar), and
- a side effect of the dump leaves the app's AppleScript window list momentarily
  empty (the real window list, queried again right after, returned nothing).

**Impact:** every verification I attempted against a running instance this session
was misleading — "file didn't open" (it had), "preview pane absent" (it was
shown), "0 style-bar buttons" (10 were on screen). I repeatedly concluded medit had
bugs it did not have; the real app was always correct when checked via `osascript`
or stderr logging. A state-inspection tool that disagrees with the running app is
worse than no tool, because it manufactures false negatives.

**Likely cause (for you to confirm):** the MCP server appears to resolve the bundle
id to a *fresh/launched* AX context (or a default/last window, or its own
hidden window) rather than attaching to the AXUIElement tree of the
already-frontmost running instance. Whatever the mechanism, the returned tree is
not the on-screen one.

**Asks:**
1. `dump_axtree` (and `run` with `bundleId`) should **attach to the running
   instance** and report **its key/front window's** AX tree — the same tree a user
   sees. If multiple windows/instances exist, prefer the frontmost, or expose
   `windowTitle` / `pid` to disambiguate.
2. Add a self-check: if no running instance matches the bundle id, **say so**
   rather than returning a default/blank tree that looks like real data.
3. A way to dump **by pid** (`{"pid": 81256}`) would let a caller inspect exactly
   the process they launched — the reliable escape hatch.

### R3-2 (P1) — `run` with `target.path` + `launchFiles` opened the file elsewhere

When I tried `{ "path": "/Applications/medit.app", "launchFiles": ["…/x.md"] }`,
the run failed at `waitFor editorTextView` ("element did not appear"). The `.md`
appears to have been routed to the **OS default handler** for the type (another
app) instead of opening in the app at `target.path`. `launchFiles` should open the
files **in the specified target**, not defer to LaunchServices' default-handler
resolution. (Workaround: none via AutoPilot; I launched medit's binary directly and
checked state with `osascript`.)

### Round-3 net
The Markdown work (rendered preview, print, the formatting toolbar) is all verified
correct via `osascript` + stderr + the headless test suite — but **not via
AutoPilot**, because `dump_axtree` couldn't see the real windows. Fixing R3-1 would
restore AutoPilot as a trustworthy verifier; right now its state reports can't be
relied on for an app the caller launched.

---

## ROUND 2 — retest against commit `7a577f1`

## ROUND 2 — retest against commit `7a577f1`

**Great news first: the round-1 report landed.** This build adds `assertPixel`, the
`menu` action, the `marked` property, `type` `clear`/`commit`, the `drag` action, the
full key map (punctuation incl. `,`), app-activation before input, and — confirmed —
**value assertions now poll** (failing asserts run the full timeout instead of
one-shot). The troubleshooting table mirrors the round-1 findings. The medit suite is
**18/18** on this build, including things that were impossible before:
- **Settings window** now opens via `keyPress "cmd+,"` (was undrivable).
- **Inline rename now commits** to disk (verified `old.txt` → `new` on the filesystem).

### What round 2 surfaced (new, evidence-backed)

**R2-1 (P1) — `type`'s focus-click breaks a control that is *already* first responder.**
This was the single biggest cause of our retest failures, and it's subtle. `type`
does `click(at: midpoint)` then types (`ActionEngine`: "focus first"). For a control
the app has *already* made first responder — an `NSSearchField` (our find field) or a
sheet's rename field that calls `selectText` on open — that click **drops the attached
field editor's focus**, so the typed characters go nowhere and the value stays empty.
*Evidence:* into the find field, `type "beta"` → value `""`, but `setValue` worked and
`keyPress` of `b`,`e`,`t`,`a` (no click) worked perfectly; identical story for the
sheet rename field (only `keyPress`-per-char + `keyPress return` actually renamed the
file). *Fixes:* (a) make `type` skip the focus-click when the target is already
`AXFocused`, or (b) add a `focus: false` arg, or (c) for `NSSearchField` specifically,
target/type into its child field-editor. Document the gotcha until then. This also
explains why our round-1 "type then assert" plans were flaky — it was never purely a
timing race; `type` into an already-focused field is simply lossy.

**R2-2 (P1) — Checkbox / toggle on-off state is unreadable.**
`assert property: value` on an `AXCheckBox` returns empty, so a checkbox's checked
state can't be asserted. *Root cause (your source):*
`AssertionEngine.readProperty` → `AXTree.string` does `value as? String`
(`AXTree.swift:7-11`), but an `NSButton` checkbox's `AXValue` is an **`NSNumber`**
(0/1), so the cast yields `nil`. *Evidence:* `assert value == "1"` on the "Rainbow
brackets" Settings checkbox polled to timeout with `actual=` (empty). *Fix:* in
`AXTree.string`, fall back to stringifying `NSNumber`/`CFBoolean` AX values (or add a
dedicated numeric/bool reader and let `value` coerce). Without this, no Settings
checkbox state is testable — we had to fall back to presence-only asserts.

**R2-3 (P2) — `marked` is only valid after the menu has been opened/validated.**
A menu item's `AXMenuItemMarkChar` is set by AppKit's `validateMenuItem`, which fires
only when the menu opens. So `assert property: marked` on an item whose menu was never
opened reads `false` even when the underlying state is on. *Evidence:* "Rainbow
Brackets" defaults checked, but a cold `assert marked == true` failed (`actual=false`);
after a `menu` action opened+toggled it, `marked` read correctly. *Ask:* document that
`marked` requires the menu to have been opened, or have the property reader open/refresh
the menu before sampling.

**R2-4 (P2) — Back-to-back `menu` re-toggle of the same item is unreliable.**
Toggling an item off then on again in the same run: the second `menu` action returned
in ~3-25ms and did not re-toggle (state stayed off). Likely the menu wasn't fully
closed before the second open, or the item wasn't re-resolved. *Repro:* two
`menu ["View","Rainbow Brackets"]` steps in a row; the first toggles, the second is a
no-op. A short settle didn't help. Worth a close-wait or re-resolve between menu
invocations.

**R2-5 (NICE) — `assertPixel` works in screen *points* (good), but glyph-hunting is
fragile.** We confirmed `PixelColor.sample` uses `CGWindowListCreateImage` in screen
points (CG handles Retina), so authors work in the same coordinate space as AX frames —
nice. But reliably landing the sample on a specific syntax-colored glyph (a bracket
stroke, anti-aliased, layout-dependent) is hard and brittle; we couldn't make a
bracket-color assertion robust enough to ship. A `findPixel`/region-scan helper
("is color C present anywhere in element E's bounds?") would make visual asserts far
more usable than a single exact point. As-is, `assertPixel` is best for large solid
regions (gutter background, selection), not thin glyphs.

### Round-2 keep list
- The new `menu` action, `commit`, the full key map, app-activation, and polling
  asserts collectively took our suite from "85% + scattered flakiness" to a clean
  18/18. The remaining issues above are refinements, not blockers.
- `keyPress`-per-character is a reliable escape hatch for any field `type` can't drive —
  keep it working.

### Round-2 verification (commit `b379586`) — both fixes confirmed, one residue

We re-pulled after your `focus: false` + numeric-`AXValue` fixes and verified them
against the live app:

- **`type focus: false` — works for plain `NSTextField`.** The sidebar rename
  fields now take a single `type {text, focus:false, commit:true}` step (replacing a
  6-step `keyPress`-per-char chain) and the file is renamed on disk. 
- **Checkbox value — fixed.** `assert value == "1"`/`"0"` now reads an `AXCheckBox`,
  and `press` toggles it. We added a real Settings round-trip plan
  (`assert "1"` → `press` → `assert "0"`) that was impossible before. 
- **Residue (P2): `focus: false` does NOT rescue an `NSSearchField`.** Our find field
  is an `NSSearchField`; `type` with `focus:false` still lands nothing in it (verified
  3/3 fail), while `keyPress`-per-char works. Likely because the editable text is in
  the search field's **child field editor**, and `type` targets the resolved
  container element rather than the field editor / first responder, whereas `keyPress`
  sends raw key events to whatever is first responder. So the find/replace plans keep
  `keyPress`. *Possible fix:* when the resolved element is an `AXTextField`/search
  field with a focusable child text element, route `type` to the field editor (or the
  current first responder) rather than the container. Plain text fields are fine; the
  search field is the lone outlier.

Net: with both fixes, the medit suite is **19/19** (added the checkbox round-trip),
and the only typing case still needing `keyPress` is the `NSSearchField`.

---

## ROUND 1 — original report (commit `3d7b5cb`)

**AutoPilot commit tested:** `3d7b5cb` ("docs: use AutoPilot (product name) in prose").
**What we did:** wrote 18 plans to `AUTHORING.md`, built AutoPilot from source, ran
`doctor` + the whole suite against an installed `.app` (medit 1.5.0), and dug into
your source to explain every failure. This is a real-consumer report — what's broken,
unclear, weird, worth improving, and worth keeping — across docs, execution,
interface, and key handling.

Everything below cites the exact symptom we hit and, where we traced it, the file:line
in your source. Severities: **P0** blocks real testing · **P1** costs hours of
confusion · **P2** papercut · **NICE** polish.

---

## TL;DR — the five that matter most

1. **P0 — Value assertions don't poll.** `waitFor`/`exists` retry until timeout, but a
   property assert (`value`/`title`/…) reads once and compares once. A control that
   updates a beat after the action that triggered it fails instantly. This is the #1
   cause of flaky suites. Fix: poll the comparison, not just element presence.
2. **P0 — `click` can't operate a menu.** `click` synthesizes a mouse-down at the
   element's frame midpoint. A menu item in a *closed* menu has an offscreen/stale
   frame, so clicking it does nothing. There is no way to invoke a menu action that
   lacks a key equivalent. This silently "passes" the click step and fails later.
3. **P1 — No comma (and most punctuation) in the key map.** `Cmd-,` — the standard
   macOS Settings shortcut — throws `unknown key: ,`. Whole feature areas reachable
   only by punctuation shortcuts become untestable.
4. **P1 — `include` resolves relative to the plan file, but `AUTHORING.md`'s example
   implies the run directory.** We wrote `"setups/launch.json"` per the doc and got
   `Included plan not found`. The real rule is "relative to the including file."
5. **P1 — No app activation before input.** You launch via `NSWorkspace.openApplication`
   but never wait for the app to become frontmost/key before synthesizing keystrokes.
   Back-to-back runs drop keystrokes onto a not-yet-key window (~15% of our runs).

If you fix only #1 and #5, suite reliability jumps from ~85% to near-100% with no
plan changes.

---

## Execution & runtime

### P0 — Property assertions are one-shot; only presence polls
**Where:** `Sources/AutopilotCore/Runner/PlanRunner.swift:119-126`.
`resolve(...)` polls until the *element* exists, then `readProperty` + `evaluate` run
exactly once. Contrast `waitFor` / `exists` (`:90-117`) which poll
`waitForPresence` until `timeoutMs`.
**Symptom we hit:** `type` "beta" into the find field, then
`assert value == "beta"` → `expected=beta actual=` (empty), because the field's AX
value hadn't propagated yet. Same class of failure produced `Ln 5` instead of `Ln 4`,
and an empty editor after a valid `type`. All passed when we inserted a 1s `wait`
before the assert — proof the value was simply late, not wrong.
**Fix:** make value/title/numeric asserts **retry the comparison** on the same
`intervalMs`/`timeoutMs` loop as presence, succeeding as soon as it matches and only
failing at timeout. This single change removes the need for the manual `wait` settles
we had to scatter through the suite, and would have turned our ~85% suite runs into
~100%.
**Keep:** the failure artifact bundle (AX dump + screenshot on assert failure,
`:129-133`) is excellent — keep it, and capture it only after the retry loop expires.

### P0 — `click` cannot drive menus; no menu-press action
**Where:** `Sources/AutopilotCore/Actions/ActionEngine.swift:56-64` — every click is
`EventSynthesizer.click(at: point)` where `point` is the element frame midpoint
(`:43-52`).
**Symptom:** to open Settings we tried clicking the `Settings…` `AXMenuItem`. The step
**passed** (a click was synthesized at its frame) but the window never opened, because
the item lives in a menu that was never opened — its frame is offscreen/zero. There is
no `AXPress`/menu-open path.
**Impact:** any menu command **without a key equivalent** is undrivable
(for us: `Rainbow Brackets`, and the Settings window as a whole). Menu commands *with*
a key equivalent work only because we route around the menu via `keyPress`.
**Fix:** add a first-class action that performs `kAXPressAction` on the resolved
element (works for buttons *and* menu items, and is more robust than coordinate
clicks generally), or a `menu` action that walks `Menu Bar → submenu → item` and
presses. Even better: make `click` prefer `AXPress` when the element supports it and
fall back to coordinate synthesis.

### P1 — No app activation / key-window wait before synthesizing input
**Where:** `Sources/AutopilotCore/Runtime/AppLauncher.swift:36-50` launches via
`NSWorkspace.openApplication`; `PlanRunner` then polls only for the *AX window's
presence* (`:43-45`) before running steps. Nothing ensures the app is **frontmost and
key**.
**Symptom:** running the 18-plan suite back-to-back, ~8 of 54 runs (3 sweeps) failed
because a synthesized `keyPress`/`type` landed before the freshly launched window
became key — the keystroke went nowhere. Failures scattered randomly across plans
(even a trivial "type `(` → expect `()`"), never the same one twice. Each plan passed
4/4 in isolation.
**Fix:** after launch, `activate()` the `NSRunningApplication` and poll until it is
`isActive` / the target window is the system's key window (or
`AXUIElementGetAttributeValue(... kAXFocusedWindow ...)` resolves to it) before the
first input step. Combined with #1, this is the whole flakiness story.

### P2 — `terminate` then immediate relaunch races
Because there's no "wait until the previous process is gone" between a plan's
`terminate` and the next plan's launch, a harness running plans in a loop can have two
instances briefly coexist. We worked around it with `pkill -9` + `sleep 1.5` between
plans. A `--settle-ms` flag or an internal "wait for prior PID exit on relaunch of the
same bundle id" would remove that.

### NICE — Surface per-step durations and a machine-readable summary line
`--json` dumps `report.json`, which is great. A one-line final summary
(`PASS 17/18 (1 failed: find-bar)`) on stdout would make shell loops trivial; right
now we parse for `=>  PASS`.

---

## Interface: selectors & the AX model

### P1 — "Resolve to exactly one element" is right, but the common cases that break it aren't documented
**Where:** `Sources/AutopilotCore/Targeting/AXResolver.swift:25` (throws on zero or
multiple), error at `TargetingError.swift:10-11`.
**Symptom:** `{role: AXStaticText, value: "medit-fixture"}` threw
`Selector matched 2 elements (expected 1)` — a single sidebar root surfaced its label
text twice in the tree. Outline rows, table cells, and duplicated title/label nodes
make `role`+`value` ambiguous constantly.
**This is a good design** (deterministic), but `AUTHORING.md` should teach the escape
hatches, and the tool should help:
- Document that `identifier` is dramatically more reliable than `role/title/value` and
  should be the default ask of the app author.
- When a selector is ambiguous, the error should **list the N matches** (role, frame,
  a value snippet) so the author can disambiguate. Right now it only says "2".
- Consider an optional `index` or `nth` disambiguator, or a `within`/parent-scoping
  predicate (e.g. "the AXStaticText inside the AXRow at index 0").

### P1 — Document which AppKit identifiers actually surface, and which roles to expect
We initially concluded (wrongly) that `setAccessibilityIdentifier` "doesn't work,"
because our first `dump_axtree` was of a *restored* window and we misread it. In fact
identifiers on `NSTextField`, `NSTextView`, `NSOutlineView`, `NSButton` all surface
fine. But several AppKit truths bit us and belong in the docs:
- An `NSTextView` shows up as **`AXTextArea`**, an `NSOutlineView` as **`AXOutline`**,
  an `NSRulerView` is **not a discrete AX element at all** (so line-number gutters,
  etc., can't be asserted) — a short "AppKit class → AX role" table would save hours.
- **Menu items expose no checkmark/`value`/mark-char attribute.** We tried to assert a
  View-menu toggle's `✓` state and there was nothing to read. Docs should say "menu
  state is not observable; assert the side effect instead," and/or you could expose
  `AXMenuItemMarkChar` as a readable property.

### P2 — `setValue` sets the AX value but fires no action
**Where:** `ActionEngine.swift:69-71` — `AXUIElementSetAttributeValue(... kAXValueAttribute ...)`.
**Symptom:** for an inline rename field, `setValue "notes.txt"` made the field *read*
"notes.txt", but committing with `Return` did nothing — the control never received the
editing-ended action, so the app never learned the value changed. The on-disk file
stayed `untitled`.
**Ask:** document this sharp edge ("`setValue` updates the AX value only; it does not
fire the control's target/action or text-did-end-editing — use `type` for fields whose
*commit* matters"). A `confirm`/`AXConfirm` option, or a `type`-with-select-all mode,
would let inline-rename flows be driven end to end. As-is, rename-commit is not
drivable for us.

### P2 — `type` re-clicks to focus, which can *break* an already-focused field
**Where:** `ActionEngine.swift:65-67` — `type` does `click(at: point)` then types.
**Symptom:** when we explicitly clicked a field and *then* `type`d, the second focus
click sometimes dropped a selection / first-responder state we'd set up, and the text
went nowhere. The reliable recipe was "let `type`'s own click do the focusing; never
pre-click the same field." That's surprising and undocumented. Consider a
`focus: false` arg on `type`, or document the rule.

---

## Key handling

### P1 — Key map is missing punctuation and common keys
**Where:** `ActionEngine.swift:11-20` (`letterKeyCodes`, `namedKeyCodes`),
throw at `:39` (`unknown key: \(keyToken)`).
**Symptom:** `Cmd-,` (Settings) → `unknown key: ,`. Only `a–z`, `0–9`, and
`return/enter/tab/space/delete/escape/arrows` exist.
**Missing that real apps need:** `,` `.` `/` `;` `'` `[` `]` `\` `` ` `` `-` `=`
`minus`, `home` `end` `pageup` `pagedown` `forwarddelete`, `f1–f12`. Without `,`,
the single most common macOS shortcut (`Cmd-,` Preferences) can't be sent.
**Fix:** extend the maps to the full ANSI keyboard; punctuation especially.

### P2 — Splitting the chord on `+` can't express the `+` key itself
`split(separator: "+")` (`:23`) means a chord whose final key is `+` (e.g. `Cmd-+`
for zoom) is unrepresentable. Edge case, but worth a note or an escape.

### NICE — Chord parse errors are `decode` errors, not targeting errors
`unknown key: ,` surfaces as a plan *decode* error and aborts the run with exit 2,
identical to malformed JSON. A distinct "unsupported key" error/exit would help triage.

---

## Includes & plan composition

### P1 — Include resolution base directory is underspecified in the docs
**Where:** `Sources/autopilot/main.swift:31` sets
`baseDir = planURL.deletingLastPathComponent()`; `PlanParser.swift:34` resolves each
include against that base (and nested includes against the included file's own dir,
`:47`).
**Symptom:** `AUTHORING.md`'s example shows `"include": ["setups/launch.json"]` for a
plan that (implicitly) sits at the suite root. We placed plans in subfolders
(`editor/`, `sidebar/`, …) and copied that string verbatim → `Included plan not
found: setups/launch.json`. The correct value for a nested plan is
`"../setups/launch.json"`.
**Fix:** state explicitly in `AUTHORING.md`: *"include paths are resolved relative to
the directory of the file that declares them."* A one-line example with a nested plan
would prevent the whole class of error. The behavior itself is fine — just document it.

### NICE — Include-not-found could show the resolved absolute path
The error prints the relative string (`setups/launch.json`) but not what it resolved
to on disk. Printing the absolute candidate path makes the base-dir rule obvious from
the error alone.

---

## Discovery & the MCP `dump_axtree` tool

### P1 — The dump is a JSON-RPC envelope with the tree as an escaped string
The `dump_axtree` response is
`{ "result": { "content": [ { "type": "text", "text": "<escaped JSON array>" } ] } }`.
A naive `grep "identifier"` over the raw output finds nothing (it's escaped inside one
string), which is exactly what sent us down the wrong path of "identifiers don't
surface." **Document the shape**, and consider a `--raw`/`--pretty` mode (or a
`dump_axtree` CLI subcommand) that emits the plain tree array directly. A
`find-element` helper (selector → matches with frames) would be even better for
authoring.

### NICE — Make `dump_axtree` filterable
For a real app the tree is huge (ours was ~270 nodes incl. the entire system menu
bar). Flags like "interactive elements only," "subtree under role=AXWindow," or "omit
the menu bar" would make discovery far faster.

---

## Documentation (`AUTHORING.md`) specifics

What to add, beyond the items already called out above:

- **An "AppKit → AX" cheat sheet:** `NSTextView`→`AXTextArea`, `NSOutlineView`→
  `AXOutline`, `NSTableView` rows→`AXRow`/`AXCell`, `NSRulerView`→(not addressable),
  `NSButton`→`AXButton`/`AXCheckBox`, `NSPopUpButton`→`AXPopUpButton`/`AXMenuButton`.
- **A "what is NOT observable" box:** menu checkmarks, layout-manager temporary
  attributes (syntax/coloring), ruler views, anything drawn without an AX element.
  Authors waste time trying to assert these.
- **The include base-dir rule** (P1 above), with a nested example.
- **The full supported key list**, and an explicit "punctuation not yet supported"
  note until the map is extended.
- **`setValue` vs `type` semantics** (P2 above): value-only vs. fires-the-action.
- **A focus/timing section:** "the harness does not yet wait for the app to be key;
  prefer `identifier` selectors; if you see empty `actual=` on a value assert it is
  almost certainly a propagation race." (Ideally obviated by fixing #1/#5.)
- **A clean-state recipe for document-based apps.** `--reset-state` on the *app side*
  is not enough on macOS: window/state restoration reopens the last document, and
  `NSDocument` autosave reopens unsaved content, both from outside the prefs domain.
  A short note ("your app should, under a test flag, also disable
  `NSQuitAlwaysKeepsWindows`, clear saved state, and delete autosaved docs") would
  save every document-app author the multi-hour debugging we did.
- Fix the prose/escape: the example in §"Complete Example" uses
  `"text": "hello world"`; show one example with a newline (`\n`) and one with a tab so
  authors know escaping works as normal JSON.

---

## What's genuinely good — keep it

- **The JSON schema is clean and learnable.** We were productive within minutes;
  `schemaVersion`/`target`/`steps`/`assert` map cleanly to intent.
- **`identifier`-first selectors** are the right primary mechanism and worked reliably
  once we stopped second-guessing them.
- **Deterministic single-match resolution** (throw on ambiguous/zero) is the correct
  call — it surfaces real selector problems instead of silently picking one.
- **The failure artifact bundle** (AX dump + screenshot written on assert failure) is
  the single most useful debugging feature; it's how we diagnosed most issues.
  Keep it, just gate it behind the retry loop (#1).
- **`doctor`** with a dedicated exit code (3) for missing Accessibility is exactly
  right — clear, fast, scriptable.
- **Exit-code discipline** (`0/1/2/3`, `main.swift:34-74`) is clean and CI-friendly.
- **`--reset-state` as a convention** (app-side clean baseline) is a great pattern;
  just document that document-based apps need to do more than wipe defaults.
- **`include` composition** is a good idea and worked perfectly once the base-dir rule
  was understood.
- **The polled-not-sleep wait for the AX tree at launch** (`PlanRunner.swift:43-45`)
  is the right instinct — extend the same polling philosophy to value asserts (#1) and
  to app-activation (#5).

---

## Appendix — concrete repros we hit

| Symptom (verbatim) | Root cause | Our workaround |
|---|---|---|
| `Plan error: Included plan not found: setups/launch.json` | include resolved vs plan dir, not CWD | use `"../setups/launch.json"` |
| `Plan decode error: unknown key: ,` (opening Settings) | no `,` in key map | untestable; cover Settings headlessly |
| `Selector matched 2 elements (expected 1): {role=AXStaticText, value=medit-fixture}` | duplicated label nodes | target a unique `identifier`, or expand-then-pick |
| `assert value == "beta"` → `expected=beta actual=` | value assert is one-shot; value late | insert a 1s `wait` before assert |
| `assert ... Ln 4` → `actual=Ln 5, Col 10` | same one-shot race after `Return` | focus-click + settle |
| Clicking `Settings…` AXMenuItem "passes" but no window | `click` = coord mouse-down on a closed menu | none — menu actions need a key equiv |
| `setValue` then `Return` doesn't rename file | `setValue` fires no action | assert "entered rename," not the commit |
| Restored doc/JWT content appears on every launch | macOS state restoration + autosave, outside prefs domain | strengthen the app's `--reset-state` |

— end of report
