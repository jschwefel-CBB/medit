# Documentation images

Screenshots for the [README](../../README.md) and the
[User Manual](../MANUAL.md). Each is referenced from a `<!-- SCREENSHOT: … -->`
placeholder in the docs describing exactly what to capture.

## Capture method (what works)

The reliable recipe, given AutoPilot's current screenshot behavior (see the
screenshot findings in `../autopilot-feedback.md`):

1. Launch medit into the desired state (`--open-folder <dir> <file…>`, with prefs
   pre-set in `~/Library/Preferences/com.jschwefel.medit.plist`).
2. Get the window frame from the AX tree:
   `autopilot dump-axtree --pid <pid>` → the `AXWindow` node's `frame` (`x,y,w,h`).
3. Capture exactly that rect: `screencapture -o -x -R"<x,y,w,h>" out.png`.

This is robust on multi-monitor setups (where AP's own `screenshot` action and
`osascript … window 1` both proved flaky). Conventions: clean window (no stray
sidebar roots / recents), Retina where available, light mode unless a dark-mode
shot is called for.

## Status

**Captured (good):**
- `hero.png` — editor on a Swift file, Folders sidebar, highlighting, status bar.
- `markdown-preview.png` — README.md rendered (heading rules, bold/italic, table)
  with the Markdown formatting toolbar visible. (Also serves the toolbar shot.)
- `settings.png` — the Settings window (Editor/Brackets/Markdown sections, ⓘ help).
- `block-edit.png` — column/block mode on aligned process output, BLK pill lit.

**Deferred** (need the app driven into a *transient* state, which the current
capture flow can't reliably hold for a shot — tracked as SC-4 in
`../autopilot-feedback.md`):
- `find-replace.png` — the find/replace bar open with Regex + Match Case toggles.
- `find-in-tabs.png` — Find-in-All-Tabs results across documents.
- `tabs.png` — a window with several tabs.
- `text-menu.png` — the Edit ▸ Text submenu open.
- `recent-files.png` — the sidebar switched to the Recent pane.
- `language-popup.png` / `encoding-menu.png` — status-bar popups open.
- `reload-banner.png` — the external-change banner showing.
- `first-launch.png`, `window-anatomy.png`, `editor.png`,
  `rainbow-brackets.png`, `status-bar.png`, `sidebar.png` — straightforward
  full-window or crop shots; capture in the next pass.

When AP's screenshot/transient-state flow improves (or by hand), capture the
deferred shots into this directory; the doc `![](images/…)` references will then
resolve. No doc edits needed.
