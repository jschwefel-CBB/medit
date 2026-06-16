# medit 1.4 — Sidebar file browser (multi-root)

## Goal

Add an optional, multi-root file browser sidebar so the user can navigate and
manage files from within medit. The sidebar is **off by default** and, when off,
imposes **zero overhead** — no directory reads, no file watching — so medit
behaves exactly as it does today unless the user opts in.

Ships as **medit 1.4.0** (backward-compatible feature, SemVer minor). Built as
several independently-committable pieces; version bump + tag when complete.

## Hard requirements

- **Optional & default-off.** View → Show Sidebar + **⌘⌃0** toggles it. When
  hidden: the split pane collapses to zero width AND the sidebar controller tears
  down its watchers and releases its trees. medit must look and behave identically
  to today with the sidebar off.
- **Multi-root.** The sidebar shows a list of root folders, each with its own
  lazily-loaded tree, expansion state, and file watcher.
- **Editor rendering must not regress.** Restructuring the window to host a split
  view must keep the existing render-regression smoke tests green.

## Behavior summary

- **Roots:** defaults to the parent folder of the file in the active tab
  (computed, not persisted). **File → Open Folder…** pins a chosen directory as a
  root; additional folders can be added (one at a time), each becoming a top-level
  root. **Remove Folder from Sidebar** (root context menu) removes a root.
- **Open behavior:** by default **single-click selects** (highlights in the
  sidebar, opens nothing) and **double-click opens** the file in a normal permanent
  tab (or focuses the tab if already open). A `sidebarOpenOnSingleClick` toggle
  makes single-click open instead. (No preview tabs — see "Decisions".)
- **File management** (right-click): New File, New Folder, Rename, Delete (to
  Trash; confirmation gated by `confirmBeforeDelete`), Reveal in Finder, and
  **drag-to-move** within the tree. Internal moves only (no Finder drag-in for 1.4).
- **Hidden files:** excluded by default; **View → Show Hidden Files**
  (`showHiddenFiles`, default off) reveals dotfiles.
- **Sizing & placement:** resizable split via `NSSplitViewController`; draggable
  divider; width remembered (NSSplitView autosave). The sidebar is on the left by
  default; `sidebarOnRight` moves it to the right.
- **Sorting:** folders-first then case-insensitive alphabetical by default;
  `sidebarSortFoldersFirst` and `sidebarSortAscending` make this configurable
  (mixed list / Z→A).
- **Sync:** changes made through the sidebar refresh the affected subtree;
  external changes (Finder/other apps) are caught by each root's `DirectoryWatcher`
  and refresh the same way. A file open in a tab that gets deleted is already
  handled by 1.3's reload-on-external-change.

## Architecture

The window's content view controller changes from the editor directly to an
`NSSplitViewController` with two children: the sidebar (left, collapsible) and the
existing editor (right).

```
NSWindow
└── NSSplitViewController  (was: EditorViewController directly)
    ├── SidebarViewController   (left pane, collapsible, default collapsed)
    └── EditorViewController    (right pane — unchanged internally)
```

### New units (focused, most pure-tested)

- **`FileTreeNode`** (pure, tested) — wraps a `URL`; knows `isDirectory`; children
  are **lazy** (read from disk only on first expansion) then cached; a watcher
  event invalidates the cache. Provides the sorted, filtered child list.
- **`FileTreeDataSource`** (`NSOutlineViewDataSource` + delegate) — bridges nodes
  to the `NSOutlineView`. Handles the multi-root level: `item == nil` → the array
  of root nodes; a directory node → its lazy children. Row view = workspace icon +
  name; root rows emphasized.
- **`FileSystemOperations`** (pure logic, tested) — create/rename/move/trash with
  conflict detection. UI-free so the rules are headless-testable.
- **`DirectoryWatcher`** — per-root `DispatchSource.makeFileSystemObjectSource`
  monitor; fires a main-thread callback to refresh the affected node. One per root;
  started/stopped as roots are added/removed and as the sidebar is shown/hidden.
- **`SidebarViewController`** — hosts the `NSOutlineView` in a scroll view; owns
  the `roots: [FileTreeNode]`, the watchers, the context menu, and drag-drop; opens
  files via `NSDocumentController`.
- **`SidebarState`** — persistence of visibility, width, root paths, expansion
  set, show-hidden (in `Preferences`/session).

### Optionality is structural

When `showSidebar` is false: the split view collapses the sidebar pane to zero and
`SidebarViewController` stops/releases all `DirectoryWatcher`s and drops its
`FileTreeNode` trees. Turning it on lazily rebuilds trees and starts watchers.
This is enforced (teardown), not merely visual hiding.

## File tree model & data source

- **Lazy children:** a directory enumerates via
  `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:[.isDirectoryKey], options:)`
  with `.skipsHiddenFiles` toggled by `showHiddenFiles`. Result cached on the node;
  invalidated on watcher events for that directory.
- **Sort:** folders before files; within each group, case-insensitive name compare.
- **Hidden files:** filtered out unless `showHiddenFiles`.
- **Multi-root in the data source:** `outlineView(_:numberOfChildrenOfItem:)` with
  `nil` returns `roots.count`; `child(_:ofItem:)` with `nil` returns `roots[index]`.
  For a node, it returns the node's sorted/filtered children. `isItemExpandable` =
  node.isDirectory.

### Pure-tested vs AppKit

- **Pure/tested** (headless over temp dirs): `FileTreeNode.sortedChildren`
  (folders-first, case-insensitive), the hidden-file filter, `FileSystemOperations`
  conflict logic.
- **Data source** (headless): build over a temp tree, assert child counts/items
  including the root level.
- **AppKit (smoke-tested only)**: outline rendering, expansion, selection,
  drag-drop gestures, the live watcher callback.

## File operations, drag-to-move, external sync

`FileSystemOperations` (pure, tested) is the single path for mutations:

- **New File / New Folder:** create inside the selected folder (or the selected
  file's parent); auto-name on collision (`untitled`, `untitled 2`, …); return the
  new URL.
- **Rename:** validate (non-empty, no `/`, not a collision) → `FileManager.moveItem`.
  Returns an error reason on conflict for the UI.
- **Delete:** `FileManager.trashItem` (recoverable; never a hard delete), after a
  confirmation prompt.
- **Move (drag-drop):** `moveItem` with a collision check; **reject** moving a
  folder into its own descendant, dropping onto a non-folder, or a name collision
  (prompt to replace or cancel).

Drag-to-move uses the outline view's drag data-source methods
(`pasteboardWriterForItem`, `validateDrop`, `acceptDrop`). Drops from outside medit
(Finder) are **out of scope for 1.4**.

Opening files: `NSDocumentController.shared.openDocument(withContentsOf:)` reuses
the existing tab group; an already-open file is focused rather than reopened.

After any op (internal or external via watcher): refresh the affected parent node
and reload that subtree, preserving expansion/selection where possible.

## Open behavior (no preview tabs)

- **Single-click:** selects/highlights the row in the sidebar; opens nothing.
- **Double-click:** opens the file in a normal permanent tab, or focuses the
  existing tab.

(Preview tabs — single-click-to-preview/italic/replace — were considered but
**dropped for 1.4**: AppKit's `NSDocument` tab model has no clean in-place content
swap, so the behavior would require close-and-reopen with flicker risk. The simple
select/double-click-open model is predictable and friction-free; preview tabs may
be revisited later.)

## State, persistence, optionality

Per the project principle **"anything that can reasonably be a toggle should be a
toggle,"** every sidebar behavior that users might want differently is exposed as a
preference (with a sensible default). View-ish toggles go in the **View menu**
(quick access, like Show Line Numbers); the rest go in **Settings**. All are stored
in `Preferences`/session.

| Key | Default | Surfaced |
|-----|---------|----------|
| `showSidebar` | **false** | View → Show Sidebar (⌘⌃0) |
| `sidebarWidth` | (autosaved) | split divider, remembered |
| `showHiddenFiles` | false | View → Show Hidden Files |
| `syncSidebarWithActiveTab` | true | View → Reveal Active File in Sidebar |
| `sidebarSortFoldersFirst` | true | Settings — Sidebar |
| `sidebarSortAscending` | true | Settings — Sidebar |
| `sidebarOpenOnSingleClick` | false | Settings — Sidebar |
| `sidebarOnRight` | false | Settings — Sidebar |
| `confirmBeforeDelete` | true | Settings — Sidebar |
| sidebar root paths | (active file's parent until pinned) | Open Folder… / Remove Folder |
| expansion set | best-effort restore (expanded paths per root) | — |

### What each toggle controls

- **`showHiddenFiles`** — include dotfiles in the tree (re-filters + reloads).
- **`syncSidebarWithActiveTab`** — when you switch tabs, auto-expand and scroll the
  tree to reveal/select the active file (if it's under a root).
- **`sidebarSortFoldersFirst`** — folders before files vs. a single
  case-insensitive list mixing files and folders.
- **`sidebarSortAscending`** — A→Z vs. Z→A within the sort.
- **`sidebarOpenOnSingleClick`** — open the file on single-click instead of the
  default double-click. (Default keeps single-click = select, double-click = open.)
- **`sidebarOnRight`** — place the sidebar pane on the right of the editor instead
  of the left (just swaps the split items / divider side).
- **`confirmBeforeDelete`** — show the Trash confirmation prompt; off = trash
  immediately (still to Trash, never a hard delete).

Each of the sort/click toggles, when changed, re-applies to the live outline view
(re-sort + reload, or rebind the click behavior). `sidebarOnRight` swaps the split
view item order. These are plumbed through `Preferences.didChangeNotification`
(which the sidebar observes), exactly like the editor observes pref changes today.

View toggles follow the existing `toggleLineNumbers`/`toggleStatusBar` pattern
(action + checkmark validation in `EditorWindowController`). Settings toggles
follow the `PreferencesWindowController` checkbox pattern (now in a scrollable
window, so the added rows are fine). `File → Open Folder…` uses an `NSOpenPanel`
restricted to directories.

### Hardcoded (deliberately NOT toggles)

A footgun or a single-correct-answer behavior stays fixed: deletion always goes to
**Trash** (never a "permanently delete" option); moving a folder into its own
descendant is always **rejected** (correctness, not preference); lazy loading and
file-watching are implementation details with no user-facing choice.

## Testing strategy

- **Pure logic** (`FileTreeNode` sort/filter, `FileSystemOperations`): exhaustive
  XCTest over temp directories — create-with-collision auto-naming, rename
  validation/conflict, move-into-descendant rejection, trash, folders-first sort,
  hidden filter. These carry the correctness weight and run headless.
- **Data source** (headless): `FileTreeDataSource` over a temp tree — child
  counts/items at the root level and within directories, `isItemExpandable`.
- **Sidebar smoke tests** (headless): build `SidebarViewController` over a temp
  dir; toggle visibility and assert watchers are torn down + trees released when
  hidden; assert the editor still renders with the split view in place
  (render-regression guard retained).
- **Not unit-tested** (verified manually): the live `DirectoryWatcher` FS callback
  and drag-drop gestures (timing/UI). Their decision logic (move validation) is
  tested.
- All via `swift test`; no app launch in any test. NEVER create a `superpowers/`
  path (pre-commit hook blocks it); specs live in `docs/specs/`, plans in
  `docs/plans/`.

## Decisions (resolved during brainstorming)

- Multi-root from the start (not single-root-then-migrate) — the end goal in one
  release.
- Sidebar default OFF, zero-overhead when hidden — a hard requirement.
- Resizable split (NSSplitViewController), remembered width.
- Full file management incl. internal drag-to-move; Finder drag-in deferred.
- No preview tabs (single-click selects, double-click opens) — avoids
  document-model friction.
- Hidden files off by default with a View toggle.

## Commit breakdown (independently-committable)

1. `FileTreeNode` (lazy children; configurable sort via `foldersFirst` +
   `ascending`; hidden filter) + tests covering all sort/filter combinations.
2. `FileSystemOperations` (create/rename/move/trash + conflict logic) + tests.
3. `FileTreeDataSource` (outline data source incl. multi-root level) + tests.
4. Window restructuring: `NSSplitViewController` hosting editor + an (empty,
   collapsed) `SidebarViewController`; `showSidebar` pref + View → Show Sidebar
   (⌘⌃0); `sidebarOnRight` placement; render-regression smoke test that the editor
   still renders with the split view in place.
5. `SidebarViewController` outline view: render the roots tree; click-to-open
   behavior gated by `sidebarOpenOnSingleClick` (default: single=select,
   double=open) via NSDocumentController; default root = active file's parent;
   `showHiddenFiles` + the sort toggles re-apply live.
6. `DirectoryWatcher` + wire external-change refresh; `syncSidebarWithActiveTab`
   (reveal active file on tab switch); teardown on hide (zero overhead) + sidebar
   smoke test asserting teardown.
7. File ops UI: context menu (New File/Folder, Rename, Delete→Trash with
   `confirmBeforeDelete`, Reveal in Finder) routed through `FileSystemOperations`,
   with tree refresh.
8. Drag-to-move within the tree (validateDrop/acceptDrop) + Open Folder… / Remove
   Folder (multi-root management) + root-path persistence.
9. Settings "Sidebar" section: the non-view toggles (`sidebarSortFoldersFirst`,
   `sidebarSortAscending`, `sidebarOpenOnSingleClick`, `sidebarOnRight`,
   `confirmBeforeDelete`) + the View-menu toggles (Show Hidden Files, Reveal Active
   File in Sidebar) with checkmark validation. (Preference plumbing for each lands
   alongside the commit that first uses it; this commit completes the UI surface.)
10. Version bump to 1.4.0 + README + tag (tag gated on user).

## Out of scope (→ later)

Preview tabs; Finder drag-in/drag-out; the color scheme picker (1.5); rainbow
bracket highlight; wrap-toggle-in-status-bar; snippets; plugins; multi-cursor;
LSP.
