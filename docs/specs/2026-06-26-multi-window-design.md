# Multi-Window medit — Design Spec

**Date:** 2026-06-26
**Status:** Approved (brainstorm complete; ready for implementation planning)
**Baseline:** v2.6.2 (`main` @ `812d07b`)

## Problem

medit behaves like a single window. `EditorWindowController` creates its window
with `tabbingMode = .preferred`, which makes AppKit auto-merge every new document's
window into the existing window's tab group. Combined with `File ▸ New`
(`NSDocumentController.newDocument`), New Tab, sidebar opens, and drag-drop all
routing into the one tab group, the user can never get a second top-level window.

medit is already NSDocument-based (`TextDocument`) and already has working tab
support (`addTabbedWindow`, `newTabFromMenu`, per-window `SidebarViewController`).
The fix is to stop forcing everything into one window, while keeping tabs as the
default day-to-day behavior.

## Goal

Let the user have more than one window, **without** changing the default
tab-centric workflow. Tabs remain the default; a new window is an explicit action.

## Section 1 — Window model

Default = tabs. New window = explicit.

| Action | Behavior |
|---|---|
| **File ▸ New** (⌘N) | new **tab** in the current window (default) |
| **File ▸ New Tab** (⌘T) | new tab in the current window |
| **File ▸ New Window** (⇧⌘N) | **new separate window** — the one explicit multi-window action (menu item to be ADDED) |
| Open dialog / Recent / sidebar click / drag a new file | new **tab** in the current window (unless already open → §3) |
| Window ▸ Merge All Windows / drag a tab out of the tab bar | native AppKit; work for free |

**Mechanism:**
- `EditorWindowController` window `tabbingMode`: `.preferred` → `.automatic`. This
  stops the forced auto-merge so a window created by **New Window** stays separate;
  it also follows the system "Prefer tabs when opening documents" setting.
- Add a **File ▸ New Window** menu item (⇧⌘N — currently unused in `MainMenu.swift`)
  that creates an unattached top-level window (a new untitled document whose window
  is NOT added to any existing tab group).
- Rewire **File ▸ New** (⌘N) off `NSDocumentController.newDocument(_:)` onto the
  new-tab path (`openNewTab`-equivalent) so it adds a tab to the current window
  instead of a window.
- All other default open paths (Open, Recent, sidebar, drag) continue to route
  through the existing tab logic (`openNewTab` / `addTabbedWindow`).

Net: launch and everyday use are identical to today (one window, tabs); a second
window appears only when the user picks **New Window**.

## Section 2 — The sidebar is always bound to its own window

Principle (user, emphatic): **the sidebar is ALWAYS bound to the window it is part
of.** Each window is fully self-contained.

- Each window owns its **own sidebar** (folder browser + Recent pane) and its **own
  tab set**. There is no global/shared sidebar reaching across windows.
- A **sidebar click opens the file as a tab in that same window** (sidebar stays
  put). Unchanged from today's `openFile(at:)` → `openFiles(at:)` "THIS window"
  path.
- **Open Folder** populates the sidebar of the invoking window only.
- A **New Window** starts with an **empty folder pane** (the user picks a folder via
  Open Folder) but the **Recent pane is populated** from the app-wide store.

**Grounding (mostly already true):** `SidebarViewController` already holds a
`weak var windowController: EditorWindowController?` (per-window), and
`RecentFilesStore.shared` is app-level (backed by `Preferences`/UserDefaults), so
Recent is naturally shared and the folder browser is naturally per-window. This
section largely *falls out* of §1 once windows are no longer trapped in one tab
group; minimal new code.

## Section 3 — Opening an already-open file focuses it (no duplicate)

One document = one view (standard macOS; avoids two editors fighting over one file
on disk).

- Triggered via **Open dialog, Recent Files, a sidebar click in any window, or
  drag-drop**: if the file is already open **anywhere**, bring its window forward
  and **select its tab**; do not open a duplicate.
- Holds **across windows**: if `a.txt` is a tab in Window A and the user clicks
  `a.txt` in Window B's sidebar, focus jumps to Window A's tab.

**Grounding (mostly already built):** `openNext` already does this within a window
— `NSDocumentController.shared.document(for: url)` →
`windowControllers.first?.window` → `makeKeyAndOrderFront`. Because
`NSDocumentController` is app-global, the lookup already finds the document
regardless of which window holds it, so cross-window focusing largely falls out.
Work: ensure every entry path (Open, Recent, sidebar, drag) goes through the
existing-document check, and that the correct **tab** within the found window is
selected (not merely the window raised).

## Section 4 — Session restore: full workspace restore

Restore the workspace **exactly as left**: window→tab grouping, each window's
sidebar folder, the active tab, and window frames.

**Why this is real work:** today `SessionStore` persists a **flat list of file
URLs** (`prefs.lastSessionFiles: [String]`) and medit **deliberately opts out of
macOS state restoration** ("explicit control of window placement"), so grouping is
NOT free from AppKit — we own it.

**Persisted structure** (per window, window order preserved):
```
session = [
  { tabs: [path, …],          // ordered documents (file URLs only; untitled skipped)
    activeTab: path,           // which tab was frontmost
    sidebarFolderBookmark: Data?,  // security-scoped bookmark of the window's open folder (nil = none)
    frame: "x,y,w,h" },        // window position/size
  …
]
```
Stored in `Preferences` (JSON-encoded). The sidebar folder is persisted as a
**security-scoped bookmark** (not a bare path) — reusing the bookmark mechanism
`SidebarViewController` already implements (resolve / refresh-when-stale / store)
— so the sandbox can reach the folder on relaunch.

**Snapshot** (replaces today's flat `snapshotSession`): walk `NSApp.windows` / tab
groups; per window, capture ordered tab file URLs, the selected tab, the sidebar's
folder bookmark, and `window.frame`.

**Restore** (replaces today's flat loop in `reopenLastSessionIfEnabled`): for each
saved window — create a window, open `tabs[0]` as the window and the rest as tabs
in order, select `activeTab`, set the sidebar folder from its bookmark, apply the
saved frame. The §3 "focus existing if already open" rule applies during restore so
duplicates can't appear.

**Graceful degradation:** missing files are skipped (a window with zero surviving
files is not created); a missing/inaccessible `sidebarFolderBookmark` → empty folder
pane; an off-screen `frame` → AppKit `constrainFrameRect` clamps it onto a visible
screen.

**Migration:** an existing flat `lastSessionFiles` (pre-multi-window) is restored as
**one window of tabs**, then superseded by the grouped format.

## Section 5 — Testing

**Unit tests (deterministic, headless):**
- New-window vs new-tab routing: ⌘N adds a tab to the current window's tab group;
  ⇧⌘N creates a separate window (assert window / tab-group counts).
- Already-open focus: opening an open file returns the existing document/window with
  no duplicate (`NSDocumentController.documents.count` unchanged; the found window is
  the original).
- Session model round-trip: encode a multi-window/multi-tab session → decode →
  identical structure (tabs order, activeTab, sidebarFolderBookmark, frame); and
  migration from the old flat `lastSessionFiles` → one grouped window.

**AutoPilot (real app — the gate; per the 2.6.2 lesson, run before shipping):**
- Committed `uitests/multi-window.json`: launch → ⇧⌘N → assert two `AXWindow`s;
  ⌘N → assert a tab added (not a second window); open an already-open file → assert
  it still has a single window/tab (focus, not duplicate).
- Fixtures staged to `/tmp` via a staging script (the sandbox blocks opening
  repo-path `launchFiles`). Any element screenshots are frontmost-gated.

## Scope guardrails (YAGNI)

- Persist only the four items in §4 (tabs, activeTab, sidebar folder, frame). No
  per-window zoom level, scroll position beyond what the editor already restores, or
  inter-window relationships.
- No change to the document/file model, save logic, or the editor itself — this is
  purely windowing + session persistence.

## Files expected to change

- `Sources/MeditKit/EditorWindowController.swift` — `tabbingMode`; New Window action;
  ⌘N → tab path; keep `openNewTab` / `openFiles` / `openNext`.
- `Sources/MeditKit/MainMenu.swift` — add **File ▸ New Window** (⇧⌘N); confirm
  ⌘N (New) and ⌘T (New Tab) wiring.
- `Sources/MeditKit/AppDelegate.swift` — new-window vs reopen/restore paths;
  grouped snapshot/restore.
- `Sources/MeditKit/SessionStore.swift` — extend from flat URL list to the grouped
  per-window structure (+ migration).
- `Sources/MeditKit/SidebarViewController.swift` — expose the current folder
  bookmark for snapshot, and set it on restore (reuse existing bookmark code).
- `Sources/MeditKit/Preferences.swift` — storage for the grouped session.
- Tests: new unit tests (routing, focus, session round-trip + migration);
  `uitests/multi-window.json` + fixtures + staging.
