# Multi-File Open → Tabs (v2.7.1 fix) — Design

**Status:** approved-for-implementation
**Date:** 2026-06-28
**Author:** medit session

## Problem

User-reported (post-2.7.0): dragging **multiple** files onto medit (the app
icon / Dock), or opening multiple files at once via Finder "Open With" or at
launch, scatters them into **separate windows** instead of opening them as tabs
in one window. The user also reported sidebar opens and repeat drags "not
working" after the first open — symptoms of the same window-scatter (focus lands
on a scattered window; the next action targets the wrong/background window).

## Root cause

v2.7.0 changed `EditorWindowController` `window.tabbingMode` from `.preferred`
to `.automatic` so that an explicit **New Window (⇧⌘N)** stays a separate window.

`.preferred` had a side effect every multi-file open path silently relied on:
AppKit **force-merged** newly shown windows that share a `tabbingIdentifier`
into the existing tab group. Under `.automatic`, AppKit only follows the system
"Prefer tabs" pref and does **not** force-merge — so any open path that shows a
document window **without explicitly calling `addTabbedWindow`** now yields a
separate window.

- `EditorWindowController.openFiles(at:)` → `openNext(...)` **does** call
  `addTabbedWindow` explicitly → still correct (verified: 3 files → 1 window,
  3 tabs). This backs the **sidebar single-click, editor file-drop, and Recent**
  paths.
- `AppDelegate.application(_:openFiles:)` opens each file with an independent
  `NSDocumentController.openDocument(display: true)` and **never** calls
  `addTabbedWindow` — it relied entirely on `.preferred` auto-merge. This is the
  regression. It is the path AppKit uses for: launching with multiple file
  arguments, Finder **Open With** of multiple files, and **dragging multiple
  files onto the app icon / Dock**.

(A long detour during diagnosis found that a sandboxed test build cannot read
ungranted `/tmp` fixtures, so `openDocument`'s completion silently never fires
for those — a **test-harness** artifact, not a product bug. Fixed for testing by
a Debug-only sandbox-off entitlement; see Testing.)

## Fix

Route `application(_:openFiles:)`'s document opens through the **front editor
window's `openFiles(at:)`** — the one tabbing implementation that already works —
instead of N independent `openDocument(display:true)` calls. Directories keep
going to the sidebar as before. This fixes the bug at the right altitude (one
open-into-tabs mechanism, no per-call-site special casing) and makes every
default open path (launch, Finder, app-icon drag, sidebar, editor drop, Recent)
consistent: **files open as tabs in the front window; only ⇧⌘N makes a new
window.**

Behavior preserved:
- A lone pristine **Untitled** is still replaced by the first opened file
  (`closePristineUntitledDocuments`), so opening files doesn't leave a stray
  blank tab.
- Already-open files still focus their existing tab (`focusIfAlreadyOpen`), no
  duplicates.
- ⌘T New Tab and ⇧⌘N New Window are unchanged.
- `tabbingMode` stays `.automatic` (⇧⌘N stays separate).

## Components touched

- `Sources/MeditKit/AppDelegate.swift` — `application(_:openFiles:)` collects the
  non-directory paths and opens them via the front window's `openFiles(at:)`
  (creating an untitled host window first if none exists), then replaces a lone
  pristine untitled. Directories still route to `openFolderInFrontWindow`.
- (No change to `EditorWindowController.openFiles`/`openNext` — already correct.)

## Testing

**Test infrastructure (durable):**
- New **Debug-only** entitlement `App/medit-debug.entitlements` with the App
  Sandbox **disabled**, referenced only by the Debug build configuration. The
  shipping (Release) build keeps `medit.entitlements` with the sandbox ON. This
  lets the GUI test driver (AutoPilot) drive the real sidebar/drag/open flows
  against on-disk fixtures without per-file security-scope grants a synthetic
  test cannot satisfy.
- New stable AX identifier on sidebar file rows: `sidebarRow:<filename>` (the
  `value` matcher proved unreliable for outline rows).
- New launch hook `--open-files <paths…>` (`LaunchReset.requestedFilesToOpen`):
  opens files as tabs via the **same `openFiles(at:)`** entry point the sidebar
  and editor-drag use — so AP can exercise the open-into-tabs path that
  NSOpenPanel / Finder-drag normally drive but AP cannot.

**AutoPilot regression plans (`uitests/`):** cover every open permutation —
- multi-file at launch via `launchFiles` (the `application(_:openFiles:)` path) →
  asserts **1 window**, N+1 tabs (was N separate windows — the regression).
- multi-file via `--open-files` (the `openFiles`/`openNext` path) → 1 window,
  N tabs.
- sidebar: expand folder, double-click a file → editor shows its contents
  (1 window).
- open-then-open-more sequence (mirrors "D&D of 1, then open more") → all tabs,
  1 window.
- ⇧⌘N still makes a separate window (existing `multi-window.json`, unchanged).

**Unit tests:** `LaunchReset.requestedFilesToOpen` parsing; editor file-drop
pasteboard parsing already covered by `performFileDropForTesting`.

## Out of scope

- Recent Files persistence of security-scoped bookmarks (sandbox re-grant on a
  later launch) — a separate latent issue, not part of this regression.
