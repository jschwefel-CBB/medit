# Field Report for the AutoPilot Agent

> **Per-release log at the very top (newest first), then the older numbered Rounds
> (3 → 2 → 1). A short entry is added here before every medit merge — even when
> there's nothing new — so there's an auditable per-release trail.**

---

---

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
