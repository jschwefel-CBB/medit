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
**Captured (16 of 19) — all verified medit-only, no other-window content:**
- `hero.png` / `window-anatomy.png` — editor on a Swift file, Folders sidebar,
  highlighting, status bar.
- `editor.png` / `rainbow-brackets.png` — the code area (crop of hero).
- `sidebar.png` — the Folders file tree (crop of hero).
- `status-bar.png` — the status-bar strip (crop of hero).
- `markdown-preview.png` — README.md rendered (heading rules, table) + the toolbar.
- `markdown-toolbar.png` — the Markdown formatting toolbar (crop of the above).
- `settings.png` — the Settings window (sections + ⓘ help buttons).
- `block-edit.png` — column/block mode on aligned output, BLK pill lit.
- `find-replace.png` — the find/replace bar (Regex + Match Case, match count).
- `find-in-tabs.png` — the Find-in-All-Tabs results panel.
- `recent-files.png` — the sidebar switched to the Recent pane.
- `tabs.png` — a window with three tabs.
- `first-launch.png` — a clean Untitled window.
- `reload-banner.png` — the external-change banner.

These were captured via AP `attach: true` (no relaunch) where a transient state
had to be arranged first, or the **frontmost-gated** method: verify
`frontmost == medit`, read medit's window frame from `dump-axtree --pid`, then
`screencapture -R <that frame>`. **Never full-display** — that risks capturing
other windows (it did, early on), so every capture is bounded to medit's own frame.

**Deferred (3) — open status-bar/menu popups:**
- `text-menu.png` — the Edit ▸ Text submenu open.
- `language-popup.png` — the status-bar language menu open.
- `encoding-menu.png` — the status-bar encoding menu open.

These NSMenus extend **beyond** medit's window frame, so the frontmost-gated
window crop clips them, and a region large enough to include the menu risks
catching adjacent windows — not safe to automate. An open menu's own AX frame
also reported zero-size in the dump, and opening these popups reliably via
automation was flaky (tracked as SC-4 in `../autopilot-feedback.md`). They're
small and the menus are fully described in the manual text; capture by hand (open
the menu, screenshot just the menu) or once AP's transient-menu capture improves.
