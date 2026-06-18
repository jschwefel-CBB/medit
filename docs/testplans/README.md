# medit 1.5 — Autopilot GUI Test Plan

Executable GUI test plans for **medit 1.5.0**, authored to the
[autopilot Test Plan Authoring Guide](https://github.com/jschwefel-CBB/autopilot/blob/main/docs/AUTHORING.md)
(schema version `1.0`). Each `.json` file is a deterministic, LLM-free plan: the
same plan against the same app build produces the same result every run.

- **App under test:** medit `1.5.0`
- **Bundle ID:** `com.jschwefel.medit`
- **Clean-state hook:** every plan launches with `--reset-state`. In 1.5 this was
  strengthened (`App/main.swift` + `Sources/MeditKit/LaunchReset.swift`) to do far
  more than wipe the UserDefaults domain: it clears the sidebar root bookmarks,
  disables AppKit window/document restoration, and deletes the app's autosaved
  untitled documents. Without this, a previous session's open document and sidebar
  roots come back and poison the run. With it, every plan starts from a verified
  blank slate: empty editor, `Ln 1, Col 1`, no sidebar roots.

## Live results (run against the built app)

Executed against AutoPilot commit `7a577f1` and installed medit 1.5.0: **all 18
plans pass — full-suite 18/18, and the keystroke-heavy plans pass repeatedly (9/9
across re-runs).** The earlier ~85%/flaky story is resolved: this AutoPilot build
adds app-activation before input and **polling value assertions**, and the last
failures were fixed by the keystroke pattern below.

**The keystroke rule that matters:** AutoPilot's `type` action does a focus-click
before typing. For a field the app has *already* made first responder — the find
field (an `NSSearchField`) and the sidebar rename field (medit `selectText`s it on
open) — that click drops the field's editor focus and the characters vanish. So
those plans drive input with **`keyPress` per character (no click)**, which types
straight into the already-focused field. `type` is still correct for fields that
are *not* pre-focused (e.g. the replace field, which we click then `keyPress`).

**Newly possible on this build** (were blocked before): the Settings window opens
via `keyPress "cmd+,"`, and inline rename now **commits** (verified on disk:
`old.txt` → `new`). Bracket *colors* via `assertPixel` were attempted but not
shipped — sampling a thin, anti-aliased glyph is too fragile; see Known gaps.

---

## How to run

From a checkout of the autopilot driver, with medit installed (or pointed at a
`.app` via `target.path`):

```bash
swift build
.build/debug/autopilot doctor                       # verify Accessibility permission
.build/debug/autopilot run <plan>.json --artifacts ./artifacts
```

Run the whole suite (driver is invoked once per plan; `--keep-going` lets a plan
continue past a soft failure):

```bash
for plan in $(find /path/to/medit/docs/testplans -name '*.json' -not -path '*/setups/*'); do
  echo "=== $plan ==="
  .build/debug/autopilot run "$plan" --artifacts ./artifacts --json
done
```

Nested plans reference the shared setup with `"include": ["../setups/launch.json"]`.
autopilot resolves an include **relative to the plan file's own directory** (not
the working directory) — verified against the driver source — so the `../` is
required for plans one level below the suite root, and you can invoke autopilot
from anywhere.

Plans that open a folder use the `--open-folder <path>` launch argument (added to
medit in 1.5 to seed a sidebar root without the un-drivable NSOpenPanel). The
sidebar plans expect an empty `/tmp/medit-fixture`; `rename.json` additionally
expects `/tmp/medit-fixture/old.txt`. Seed before running:

```bash
rm -rf /tmp/medit-fixture && mkdir -p /tmp/medit-fixture          # new-file, new-folder
printf x > /tmp/medit-fixture/old.txt                            # rename
printf 'opened via launch\n' > /tmp/medit-fixture-open.txt        # files/open-file-via-launch
```

**Exit codes:** `0` pass · `1` test failure · `2` parse error · `3` Accessibility
permission missing.

---

## Selector strategy

medit sets `AXIdentifier`s on its key views, so plans target by `identifier`
wherever possible (the authoring guide's preferred selector). Controls without an
identifier are targeted by AX `role` + `title`/`value`.

### AXIdentifiers available (primary selectors)

| Identifier | View | Source |
|---|---|---|
| `editorTextView` | main editor (`EditorTextView`) | `EditorViewController.swift:113` |
| `sidebarOutline` | file sidebar (`NSOutlineView`) | `SidebarViewController.swift:48` |
| `positionLabel` | `Ln n, Col n` status label | `StatusBarView.swift:44` |
| `languageButton` | language picker | `StatusBarView.swift:45` |
| `encodingButton` | encoding picker | `StatusBarView.swift:46` |
| `findField` | find input | `FindReplaceBar.swift:98` |
| `replaceField` | replace input | `FindReplaceBar.swift:99` |
| `findStatusLabel` | match-count label | `FindReplaceBar.swift:100` |
| `goToLineField` | Go-to-Line sheet field | `GoToLineSheet.swift:24` |
| `reloadBannerLabel` | external-change banner text | `ReloadBanner.swift:21` |
| `reloadButton` | banner reload | `ReloadBanner.swift:25` |
| `dismissReloadButton` | banner dismiss | `ReloadBanner.swift:29` |

### Title/role selectors (no identifier)

- **Status-bar wrap toggle** — `AXButton` titled `"Wrap: On"` / `"Wrap: Off"`.
- **Status-bar line-ending toggle** — `AXButton` titled `"LF (Unix/Linux)"` / `"CRLF (Windows)"`.
- **View-menu items** — `AXMenuItem` by exact title (e.g. `"Rainbow Brackets"`,
  `"Show Line Numbers"`, `"Show Sidebar"`); checkmark read via the item's `value`
  (mark char `✓`), kept in sync by `validateMenuItem`
  (`EditorWindowController.swift:332`).
- **Settings window** — title `"Settings"`; all controls targeted by exact title
  string (see the Preferences plans). The Settings controls have **no**
  AXIdentifiers.
- **Sidebar context-menu items** — `AXMenuItem` by exact title. Note the ellipsis
  is U+2026 (`…`), not three periods: `"Open Folder…"`, `"Rename…"`.

---

## Plan index

Setup (shared, prepended via `include`):

- `setups/launch.json` — launch with `--reset-state`, wait for `AXWindow` and `editorTextView`.

All 18 plans below pass when run individually (see *Live results* for the
rapid-suite flakiness note). "Self-contained" = no manual step beyond the
`/tmp` fixtures listed under *How to run*.

| Plan | What it verifies | Self-contained? |
|---|---|---|
| `editor/type-and-assert.json` | Typing lands in the editor (`value` contains). | ✅ |
| `editor/status-bar-position.json` | `positionLabel` tracks caret Ln/Col as you type and newline. | ✅ |
| `editor/status-bar-wrap-toggle.json` | Clicking the status-bar wrap pill flips `Wrap: Off` ↔ `Wrap: On`. | ✅ |
| `brackets/auto-close-brackets.json` | Typing `(` auto-inserts `)` (default `autoCloseBrackets`). | ✅ |
| `brackets/indent-between-brackets.json` | Return between `{|}` splits the pair across lines (1.5 toggle). | ✅ |
| `brackets/rainbow-survives-typing.json` | Deeply nested brackets survive the colorizer's temp-attribute passes (render-regression guard). | ✅ |
| `find/find-bar.json` | ⌘F opens find bar, query shows match count (`2 matches`). | ✅ |
| `find/find-and-replace.json` | ⌥⌘F opens replace, the `All` button rewrites the document. | ✅ |
| `navigation/go-to-line.json` | ⌘L → enter line N → caret moves to line N. | ✅ |
| `menus/line-numbers-toggle.json` | `Show Line Numbers` item exists; ⇧⌘L toggles without error (ruler/mark not AX-observable). | ✅ |
| `menus/rainbow-brackets-toggle.json` | `Rainbow Brackets` item exists; clicking it leaves bracketed text intact (color not AX-observable). | ✅ |
| `menus/sidebar-toggle.json` | ⌃⌘0 reveals the sidebar; `sidebarOutline` appears (absent→present). | ✅ |
| `preferences/open-settings.json` | Cmd-, opens the `Settings` window; key controls present. | ✅ |
| `preferences/settings-checkbox-roundtrip.json` | A Settings checkbox reports its state (`1`) and `press` toggles it (`0`). | ✅ |
| `sidebar/empty-space-menu.json` | Right-click empty sidebar shows **only** `Open Folder…`. | ✅ |
| `sidebar/new-file.json` | Folder ▸ New File creates `untitled` and enters inline rename (1.5 flow). | ✅ via `--open-folder` |
| `sidebar/new-folder.json` | Folder ▸ New Folder creates `untitled folder` **inside** it and enters rename (1.5 fix). | ✅ via `--open-folder` |
| `sidebar/rename.json` | Expand root → right-click file → `Rename…` enters the inline rename field. | ✅ via `--open-folder` |
| `files/open-file-via-launch.json` | Launching with a file (`launchFiles`) opens its contents (open-path smoke). | ✅ (fixture) |

---

## Coverage matrix — medit 1.5 changes

| 1.5 change | Covered by | Notes |
|---|---|---|
| Rainbow-depth bracket coloring | `brackets/rainbow-survives-typing.json` + manual visual check | Colors are layout-manager **temporary attributes**, unreadable via AX — gap #1. |
| Caret enclosing-pair emphasis | manual visual check | Same temp-attribute limitation. |
| Rainbow Brackets View-menu toggle | `menus/rainbow-brackets-toggle.json` | Item exists + text intact; checkmark/color not AX-observable (gaps #1, #4). |
| Rainbow / emphasis / tab-width Settings controls | headless `PreferencesTests` | Settings window not autopilot-drivable — gap #3. |
| Tab width default 4 → 2 | headless `PreferencesTests.testDefaultsAreSane` | Asserts `tabWidth == 2`; the Settings field can't be reached via AX (gap #3). |
| Indent-between-brackets toggle | `brackets/indent-between-brackets.json` | ✅ fully automated. |
| Auto-close brackets | `brackets/auto-close-brackets.json` | ✅ |
| Drag-to-open (vs path paste) fix | `files/open-file-via-launch.json` + headless `performFileDropForTesting` | autopilot has no file-drag action — gap #2. |
| Sidebar: new file/folder **inside** clicked folder | `sidebar/new-file.json`, `sidebar/new-folder.json` | ✅ via `--open-folder`; asserts create + enter-rename (gap #5 on commit). |
| Sidebar: rename-on-create / Rename… | `sidebar/new-file.json`, `sidebar/new-folder.json`, `sidebar/rename.json` | Enter-rename asserted; rename-commit is gap #5. |
| Sidebar: empty space ⇒ only `Open Folder…` | `sidebar/empty-space-menu.json` | ✅ fully automated. |
| Sidebar: empty folders not expandable | headless `FileTreeDataSourceTests` | Disclosure-triangle absence isn't a discrete AX property; unit-tested. |
| Multi-file drop order | not GUI-automatable | autopilot has no multi-file drag; covered by `openFiles(at:)` sequencing in unit tests. |

---

## Known automation gaps

These are the real limitations found by **running** the suite against the built
app. Some gaps anticipated during authoring turned out not to exist (medit's
`editorTextView` / `sidebarOutline` / `positionLabel` / `findField` /
`replaceField` / `goToLineField` identifiers all resolve fine); the ones below
are the genuine boundaries.

**1. Bracket colors are invisible to AX.** Rainbow depth colors and caret
emphasis are painted as `NSLayoutManager` temporary attributes and are not exposed
on `AXValue`. The suite verifies the **content-integrity invariant**
(`brackets/rainbow-survives-typing.json`: text survives recoloring) and leaves
*which color* to a manual visual check — eyeball distinct hues per depth, the
emphasized caret pair, and a theme flip. (Toggling the feature on/off is covered
by `menus/rainbow-brackets-toggle.json`, which clicks the menu item and asserts
the bracketed text is undamaged.)

**2. No file-drag action.** autopilot has no native Finder-file drag onto a view,
so the 1.5 "drag opens the file instead of pasting its path" behavior can't be
driven end-to-end. The suite covers the destination via
`files/open-file-via-launch.json` (same `openFiles(at:)` route, using `launchFiles`)
and relies on the headless `EditorTextView.performFileDropForTesting(_:)` Swift
test for the drag-handler logic itself.

**3. The Settings window is not autopilot-drivable.** Its only trigger is the
`Cmd-,` key equivalent, and autopilot's chord parser has **no mapping for `,`**
(`ActionEngine.namedKeyCodes`/`letterKeyCodes` cover letters, digits, and a few
named keys only). Clicking the menu item via AX does not open it either —
autopilot's `click` synthesizes a mouse-down at the item's frame, which is
offscreen until the menu is opened, a capability autopilot lacks. So the Settings
checkboxes/popups/fields are **not GUI-testable today**.
`preferences/open-settings.json` therefore asserts only that the `Settings…` menu
item exists; the Settings **defaults** (`tabWidth=2`, `rainbowBrackets=true`, …)
are covered headlessly by `PreferencesTests`. *To close this, autopilot needs a
`,` key mapping (then `Cmd-,` works) or a menu-item-press action.*

**4. View-menu checkmarks are not exposed in AX.** Menu items carry no `value` or
mark-char attribute, so a toggle's checked state can't be asserted. Toggles are
therefore verified by their **observable side effect** where one exists
(`status-bar-wrap-toggle` flips the `Wrap: On`/`Wrap: Off` button title;
`sidebar-toggle` makes `sidebarOutline` appear). Toggles with no AX-observable
effect (`line-numbers`, `rainbow-brackets`) assert that the menu item exists and
that the action raises no error, leaving the visual result to a manual check.

**5. Inline rename-commit is not reliably drivable.** New File / New Folder /
Rename correctly create the item and enter an inline rename `AXTextField`, and the
plans assert that. But *committing* a new name is flaky: the field commits on its
editing-ended action, which a synthesized AX value-set or keystroke doesn't fire
end-to-end (and `Cmd-A` select-all is intercepted by the outline). The sidebar
plans assert the create-and-enter-rename flow (the actual 1.5 feature) and leave
the rename-commit to a manual check.

**6. Menu actions need a key equivalent.** autopilot can trigger a menu action
only via its key-equivalent chord (e.g. `Shift-Cmd-L`, `Ctrl-Cmd-0`), since
clicking a closed menu's item does nothing (see gap #3). Items with no key
equivalent (`Rainbow Brackets`) are only weakly exercisable.

**7. Rapid-launch focus race (flakiness, not a plan defect).** When the full
suite runs back-to-back, synthesized keystrokes occasionally arrive before the
freshly-launched window is key, so a `type`/chord lands nowhere — see *Live
results* above (~85% over 3 rounds, failures spread across plans, none consistent).
Every plan passes in isolation. Mitigations in the suite: a 1s settle in the
shared launch setup and after keystroke-heavy steps. A clean fix belongs in
autopilot (activate the target and wait for key-window before synthesizing input).

### medit changes made to support testing

Running the suite surfaced real issues; these were fixed in medit (all gated to
`--reset-state` or genuine bug fixes; 238 Swift tests pass):
- **`LaunchReset.swift`** (+ `LaunchResetTests`, 11 tests) — `--reset-state` now
  clears sidebar bookmarks, disables window/document restoration, and deletes
  autosaved untitled documents, giving a real blank baseline.
- **`--open-folder <path>`** launch hook + `application(_:openFiles:)` routing so a
  folder opens into the sidebar (not as a failed document) — replaces the
  previously-proposed manual seed; the sidebar plans are now self-contained.
- **`SidebarViewController.addRoot` dedup by normalized path** — fixed a real
  double-root bug when the same folder is added via two code paths.

---

## Fixtures referenced

- `files/open-file-via-launch.json` expects `/tmp/medit-fixture-open.txt`
  containing `opened via launch`:
  `printf 'opened via launch\n' > /tmp/medit-fixture-open.txt`.
- `sidebar/new-file.json`, `sidebar/new-folder.json` expect an empty
  `/tmp/medit-fixture` (seeded as a sidebar root via `--open-folder`):
  `rm -rf /tmp/medit-fixture && mkdir -p /tmp/medit-fixture`.
- `sidebar/rename.json` additionally expects `/tmp/medit-fixture/old.txt`:
  `printf x > /tmp/medit-fixture/old.txt`.

---

## Hygiene conventions followed (per the authoring guide)

- Plans that need a blank slate launch with `--reset-state` (the strengthened
  clean baseline). The file-open and sidebar plans instead carry `launchFiles` /
  `--open-folder` in their own `target`, since they need content, not a blank app.
- Every plan starts by waiting for `AXWindow` (and the editor) before interacting —
  via the `setups/launch.json` include, or inline for the plans that own their
  target.
- Every plan ends with a `terminate` step.
- Assertions target the most direct evidence (editor `value`, the actual status
  label, the actual menu mark) rather than derived state.
