# medit — Recent Files sidebar pane (design)

**Goal:** Add a **Recent Files** list to the sidebar. The sidebar shows **either**
the folder tree **or** the recent-files list — never both. You switch between them
with a segmented control at the top of the sidebar and a View-menu item.

## Decisions (from brainstorming)

- **Switcher:** a two-segment control (**Folders | Recent**) pinned at the top of
  the sidebar, **plus** a View-menu item to flip modes.
- **Source:** medit's **own** tracked list — the files you open or save in medit,
  most-recent-first, deduplicated, persisted across launches (independent of the
  system Open Recent menu).
- **Interactions:** click to open (respects "open on single click" pref),
  right-click to **Remove** an item and **Clear All**, **Reveal in Finder**, and
  show the full path (as a subtitle / tooltip).
- **Architecture:** a **separate flat list view** (Option B). The folder outline
  is left untouched; a new `RecentFilesView` is shown/hidden alongside it.

## Architecture

### 1. `RecentFilesStore` (pure-ish model, testable)

`Sources/MeditKit/RecentFilesStore.swift` — tracks the recent list, persisted in
`Preferences` (UserDefaults) as an array of file-path strings (most-recent first).

```swift
public final class RecentFilesStore {
    public static let didChangeNotification = Notification.Name("medit.recentFilesDidChange")
    public init(preferences: Preferences = .shared, maxItems: Int = 30)
    public private(set) var urls: [URL] { get }
    public func record(_ url: URL)     // move-to-front, dedupe by standardized path, cap to maxItems
    public func remove(_ url: URL)
    public func clear()
}
```

- Dedupe by `standardizedFileURL.path`; cap at `maxItems` (default 30).
- Persists via a new `Preferences.recentFilePaths: [String]` (mirrors
  `sidebarRootBookmarks` style — plain UserDefaults array).
- Posts `didChangeNotification` on every mutation so the view refreshes.
- The pure parts (move-to-front, dedupe, cap) are unit-tested over an injected
  `UserDefaults` suite — no AppKit.
- **Recording hook:** call `record(url)` whenever a document with a `fileURL`
  finishes reading (`TextDocument.read(from:ofType:)` → after it has a `fileURL`)
  and on save-as. A single shared `RecentFilesStore` (e.g. `.shared`).

### 2. `RecentFilesView` (the flat list)

`Sources/MeditKit/RecentFilesView.swift` — an `NSView` wrapping an `NSScrollView`
+ `NSTableView` (single column, no header). Each row: filename (primary) + the
containing directory path (secondary, dimmed), with the file's icon
(`NSWorkspace.shared.icon(forFile:)`).

```swift
public protocol RecentFilesViewDelegate: AnyObject {
    func recentFiles(_ view: RecentFilesView, didActivate url: URL)
}
public final class RecentFilesView: NSView {
    public weak var delegate: RecentFilesViewDelegate?
    public func reload()   // pulls from the store
}
```

- AX identifier `recentFilesTable` (for tests/AutoPilot).
- Single- vs double-click open governed by `prefs.sidebarOpenOnSingleClick`
  (reuse the existing pref so it matches the folder pane's behavior).
- A row whose file no longer exists is shown dimmed (and a click offers to remove
  it). Missing files aren't auto-purged on load (keep the list stable) but Remove
  works.
- **Context menu** (`menuNeedsUpdate`): `Open`, `Reveal in Finder`,
  `Remove from Recent`, separator, `Clear Recent Files`.
- Observes `RecentFilesStore.didChangeNotification` → `reload()`.

### 3. Sidebar switcher in `SidebarViewController`

- Add a **`NSSegmentedControl`** (`Folders` | `Recent`) at the top of the sidebar
  container; the existing folder `scrollView`/`outlineView` and the new
  `RecentFilesView` are stacked below it, and only one is visible at a time.
  ```swift
  enum Pane { case folders, recent }
  private var pane: Pane = .folders
  public func setPane(_ pane: Pane)    // segmented control + menu both call this
  public var currentPane: Pane { pane }
  ```
- `setPane` toggles `outlineScrollView.isHidden` / `recentFilesView.isHidden`,
  updates the segmented selection, persists the choice in
  `Preferences.sidebarPane` (so the sidebar reopens in the last-used pane).
- The folder outline and its data source/menus are **unchanged**; only their
  container visibility is toggled.
- `RecentFilesView` delegate → `windowController?.openFile(at:)` (the existing
  open path), so recents open exactly like folder items.
- AX id on the segmented control: `sidebarPaneSwitcher`.

## Menu + preference

- New pref `Preferences.sidebarPane: String` (default `"folders"`), remembers the
  last pane.
- View-menu item **"Show Recent Files in Sidebar"** (or a 2-state pair) →
  `EditorWindowController.toggleSidebarPane(_:)` flips folders⇄recent (and shows
  the sidebar if collapsed). `validateMenuItem` checkmark reflects the current
  pane.
- (No Settings checkbox needed — the segmented control + menu are the controls;
  the pane choice persists on its own.)

## Recording recents

- A shared `RecentFilesStore.shared`.
- `TextDocument.read(from:ofType:)` records `fileURL` once the read succeeds
  (deferred so `fileURL` is set), and `saveAs`/`write` records the new URL.
- Opening from the folder sidebar or via `openFiles(at:)` already goes through
  `NSDocumentController.openDocument` → `read(from:)`, so recording there covers
  drag-open, sidebar-open, and File ▸ Open uniformly.

## Testing

- **`RecentFilesStoreTests`** (headless): record moves-to-front + dedupes by path;
  cap at maxItems drops the oldest; remove; clear; persistence across a fresh
  store on the same defaults; notification posted on mutation.
- **`RecentFilesViewTests` / SidebarSmokeTests**: the view reloads from the store;
  activating a row calls the delegate with the right URL; switching the sidebar
  pane hides the folder outline and shows the recent list (and back); the pane
  choice persists.
- **AutoPilot** (when convenient): open a couple files, switch the sidebar to
  Recent (`sidebarPaneSwitcher`), assert `recentFilesTable` shows them; click one
  to open.

## File structure

- **Create:** `Sources/MeditKit/RecentFilesStore.swift`,
  `Sources/MeditKit/RecentFilesView.swift`,
  `Tests/MeditKitTests/RecentFilesStoreTests.swift`.
- **Modify:** `Sources/MeditKit/Preferences.swift` (`recentFilePaths`,
  `sidebarPane`), `Sources/MeditKit/SidebarViewController.swift` (segmented control
  + pane swap + recent view), `Sources/MeditKit/TextDocument.swift` (record on
  read/save), `Sources/MeditKit/EditorWindowController.swift` (`toggleSidebarPane`
  + validateMenuItem), `Sources/MeditKit/MainMenu.swift` (View-menu item),
  `Tests/MeditKitTests/...` (store + sidebar tests).

## Out of scope

- Pinning/favoriting recents, recent *folders* (vs files), search/filter in the
  recent list. (Could come later.)

## Versioning

Ships as a minor release (number confirmed at ship; likely **2.2.0** if it lands
before split view, else **2.3.0**).
