# Multi-Window medit — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let medit have more than one window — tabs stay the default (⌘N), a new window is an explicit action (⇧⌘N) — with each window self-contained and the full workspace restored on relaunch.

**Architecture:** Stop forcing every document into one tab group (`tabbingMode .preferred → .automatic`) and add an explicit New Window command. Each window is already structurally per-window (`EditorWindowController` owns its `EditorViewController` + `SidebarViewController`); the work is (a) routing menu/open actions to tab-vs-window correctly, (b) focusing an already-open document across windows, and (c) replacing the flat single-frame/single-session persistence with a grouped per-window session (tabs, active tab, sidebar folders, frame).

**Tech Stack:** Swift 6 / AppKit, local SwiftPM package `MeditKit` + thin Xcode app target. NSDocument-based (`TextDocument`/`NSDocumentController`). Tests: XCTest (headless) + AutoPilot GUI plans (`uitests/`). macOS 14+.

## Global Constraints

- Spec: `docs/specs/2026-06-26-multi-window-design.md` is the source of truth.
- Default = tabs: **File ▸ New (⌘N) = new tab**, **File ▸ New Tab (⌘T) = new tab**, **File ▸ New Window (⇧⌘N) = new separate window** (only explicit window path).
- Open dialog / Recent / sidebar click / drag a new file = **new tab** in the current window, unless already open → focus existing.
- The sidebar is ALWAYS bound to its own window. A New Window starts with an empty folder pane; the Recent pane is app-wide.
- Already-open file (any trigger, across windows) → focus its existing window + tab; never duplicate.
- Session restore rebuilds: per window → ordered tabs, active tab, sidebar folder(s) (security-scoped bookmark), window frame. Graceful degradation; migrate the old flat `lastSessionFiles` → one window of tabs.
- `tabbingMode .preferred → .automatic`. medit keeps `window.isRestorable = false` and manages frames itself.
- Git author `jschwefel@coldboreballisticsllc.com` (configured; never `-c`). Branch `feature/multi-window`. Never push to main; merges are admin-merges via the release flow.
- Build numbers from git commit count (`scripts/set-build-number.sh`); feature version bump likely **2.7.0** at release.
- Run `swift test` AND the AutoPilot plans before shipping (the 2.6.2 lesson).

---

## File Structure

- `Sources/MeditKit/EditorWindowController.swift` — window `tabbingMode`; add `openNewWindow()`; rename the semantics of the existing tab actions; expose per-window snapshot accessors (tabs, active tab, sidebar roots, frame).
- `Sources/MeditKit/MainMenu.swift` — add **File ▸ New Window** (⇧⌘N); point **New** (⌘N) at the new-tab selector; keep **New Tab** (⌘T).
- `Sources/MeditKit/SidebarViewController.swift` — expose `currentRootBookmarks` (read) and `setRoots(fromBookmarks:)` (write) so session restore can snapshot/restore a window's folders, reusing the existing bookmark resolve/persist code.
- `Sources/MeditKit/WindowSession.swift` (**new**) — the pure, Codable per-window session model + the encode/decode + migration logic. No AppKit. Unit-tested in isolation.
- `Sources/MeditKit/SessionStore.swift` — switch from flat `[URL]` to `[WindowSession]`; keep a `migrateFlatSession()` path.
- `Sources/MeditKit/Preferences.swift` — add a `sessionWindows` JSON-backed pref; keep `lastSessionFiles` readable for migration only.
- `Sources/MeditKit/AppDelegate.swift` — snapshot walks windows → `[WindowSession]`; restore rebuilds windows/tabs/active/sidebar/frame.
- Tests: `Tests/MeditKitTests/WindowSessionTests.swift`, `Tests/MeditKitTests/MultiWindowRoutingTests.swift`, `Tests/MeditKitTests/AlreadyOpenFocusTests.swift`.
- `uitests/multi-window.json` + `uitests/fixtures/` + reuse `uitests/stage-fixtures.sh`.

---

## Task 1: Window model — tabs default, explicit New Window

**Files:**
- Modify: `Sources/MeditKit/EditorWindowController.swift:32` (tabbingMode), and the New-tab/New-window action methods (around `:261-336`)
- Modify: `Sources/MeditKit/MainMenu.swift:67-70` (File menu items)
- Test: `Tests/MeditKitTests/MultiWindowRoutingTests.swift`

**Interfaces:**
- Produces: `EditorWindowController.openNewWindow()` — creates a new untitled document and shows its window as a SEPARATE top-level window (NOT added to any tab group). `@IBAction func newWindowFromMenu(_:)` wraps it.
- Produces: `@IBAction func newTabFromMenu(_:)` (exists) and `newWindowForTab(_:)` (exists) remain the tab path.
- Consumes: nothing from later tasks.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/MeditKitTests/MultiWindowRoutingTests.swift
import XCTest
import AppKit
@testable import MeditKit

final class MultiWindowRoutingTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }

    private func freshController() -> EditorWindowController {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "medit.mw.\(UUID().uuidString)")!)
        let doc = TextDocument()
        doc.setTextForTesting("")
        let wc = EditorWindowController(document: doc, preferences: prefs)
        _ = wc.window
        wc.loadViewIfNeededForTesting()
        wc.window?.makeKeyAndOrderFront(nil)
        return wc
    }

    func testNewWindowCreatesSeparateTopLevelWindow() throws {
        let wc = freshController()
        let beforeGroupCount = wc.window?.tabGroup?.windows.count ?? 1
        wc.openNewWindow()
        // The new window must NOT have joined this window's tab group.
        let afterGroupCount = wc.window?.tabGroup?.windows.count ?? 1
        XCTAssertEqual(afterGroupCount, beforeGroupCount,
                       "New Window must not add a tab to the current window's tab group")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MultiWindowRoutingTests/testNewWindowCreatesSeparateTopLevelWindow`
Expected: FAIL — `openNewWindow` does not exist (compile error), OR the new window joins the tab group because `tabbingMode == .preferred`.

- [ ] **Step 3: Change tabbingMode to .automatic**

In `EditorWindowController.swift:32`, change:

```swift
window.tabbingMode = .preferred         // stack documents as native tabs
```
to:
```swift
// .automatic: follow the system "Prefer tabs" setting and DON'T force-merge new
// windows into an existing tab group, so an explicit New Window stays separate.
// Tabs are still the default for ⌘N/Open/sidebar (those call addTabbedWindow).
window.tabbingMode = .automatic
```

- [ ] **Step 4: Add openNewWindow() + menu wrapper**

In `EditorWindowController.swift`, next to `openNewTab()` (around `:318`), add:

```swift
/// Explicit New Window (⇧⌘N): open a new untitled document in its OWN top-level
/// window — NOT added to any tab group. Tabs remain the default elsewhere.
public func openNewWindow() {
    do {
        let newDoc = try NSDocumentController.shared.openUntitledDocumentAndDisplay(false)
        if newDoc.windowControllers.isEmpty { newDoc.makeWindowControllers() }
        // Deliberately do NOT call addTabbedWindow — this stays a separate window.
        newDoc.windowControllers.first?.window?.makeKeyAndOrderFront(nil)
    } catch {
        NSApp.presentError(error)
    }
}

/// Menu hook for File ▸ New Window.
@IBAction public func newWindowFromMenu(_ sender: Any?) { openNewWindow() }
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter MultiWindowRoutingTests/testNewWindowCreatesSeparateTopLevelWindow`
Expected: PASS.

- [ ] **Step 6: Rewire the File menu**

In `MainMenu.swift:67-70`, replace:

```swift
menu.addItem(withTitle: "New",
             action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
menu.addItem(withTitle: "New Tab",
             action: #selector(EditorWindowController.newWindowForTab(_:)), keyEquivalent: "t")
```
with:
```swift
// ⌘N = new TAB (tabs are the default). ⌘T = new tab too (explicit). New Window
// (⇧⌘N) is the only path that makes a separate window.
menu.addItem(withTitle: "New",
             action: #selector(EditorWindowController.newTabFromMenu(_:)), keyEquivalent: "n")
menu.addItem(withTitle: "New Tab",
             action: #selector(EditorWindowController.newWindowForTab(_:)), keyEquivalent: "t")
let newWindow = NSMenuItem(title: "New Window",
                           action: #selector(EditorWindowController.newWindowFromMenu(_:)), keyEquivalent: "n")
newWindow.keyEquivalentModifierMask = [.command, .shift]
menu.addItem(newWindow)
```

- [ ] **Step 7: Add a routing test for ⌘N = tab and run the full suite**

Append to `MultiWindowRoutingTests`:

```swift
func testNewTabAddsToCurrentWindowTabGroup() throws {
    let wc = freshController()
    let before = wc.window?.tabGroup?.windows.count ?? 1
    wc.newTabFromMenu(nil)
    let after = wc.window?.tabGroup?.windows.count ?? 1
    XCTAssertEqual(after, before + 1, "New Tab must add a tab to the current window's tab group")
}
```

Run: `swift test`
Expected: all tests pass (377 prior + the 2 new = 379).

- [ ] **Step 8: Commit**

```bash
git add Sources/MeditKit/EditorWindowController.swift Sources/MeditKit/MainMenu.swift Tests/MeditKitTests/MultiWindowRoutingTests.swift
git commit -m "feat: tabs default + explicit New Window (⇧⌘N); tabbingMode .automatic"
```

---

## Task 2: Focus an already-open file across windows (no duplicate)

**Files:**
- Modify: `Sources/MeditKit/EditorWindowController.swift` — add a static helper `focusIfAlreadyOpen(_:) -> Bool`; route `openNext` (`:286`) and any open entry through it.
- Test: `Tests/MeditKitTests/AlreadyOpenFocusTests.swift`

**Interfaces:**
- Produces: `static func focusIfAlreadyOpen(_ url: URL) -> Bool` on `EditorWindowController` — if a `TextDocument` for `url` is already open in any window, raise that window, select that document's tab, and return `true`; else `false`.
- Consumes: nothing.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/MeditKitTests/AlreadyOpenFocusTests.swift
import XCTest
import AppKit
@testable import MeditKit

final class AlreadyOpenFocusTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }

    func testOpeningAlreadyOpenFileReturnsTrueAndDoesNotDuplicate() throws {
        // Write a temp file, open it once via the document controller.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("medit-focus-\(UUID().uuidString).txt")
        try "hello".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let openExp = expectation(description: "open")
        NSDocumentController.shared.openDocument(withContentsOf: tmp, display: true) { _, _, _ in openExp.fulfill() }
        wait(for: [openExp], timeout: 5)
        let countAfterFirstOpen = NSDocumentController.shared.documents.count

        // Asking to focus it should succeed and NOT create a second document.
        let focused = EditorWindowController.focusIfAlreadyOpen(tmp)
        XCTAssertTrue(focused, "an already-open file should be focusable")
        XCTAssertEqual(NSDocumentController.shared.documents.count, countAfterFirstOpen,
                       "focusing must not open a duplicate document")

        // Cleanup: close the doc so other tests start clean.
        NSDocumentController.shared.document(for: tmp)?.close()
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AlreadyOpenFocusTests`
Expected: FAIL — `focusIfAlreadyOpen` does not exist.

- [ ] **Step 3: Implement focusIfAlreadyOpen**

In `EditorWindowController.swift`, add (near `openNext`):

```swift
/// If `url` is already open in any window, raise that window, select the
/// document's tab, and return true. Used by every open path (Open dialog,
/// Recent, sidebar, drag, session restore) so a file is never opened twice —
/// one document, one view (standard macOS). `NSDocumentController` is app-global,
/// so this finds the document regardless of which window holds it.
@discardableResult
public static func focusIfAlreadyOpen(_ url: URL) -> Bool {
    guard let doc = NSDocumentController.shared.document(for: url),
          let win = doc.windowControllers.first?.window else { return false }
    // Select the tab within its group, then raise the window.
    win.tabGroup?.selectedWindow = win
    win.makeKeyAndOrderFront(nil)
    return true
}
```

- [ ] **Step 4: Route the in-window open path through it**

In `openNext` (`:292-298`), replace the existing inline already-open check:

```swift
if let existing = NSDocumentController.shared.document(for: url),
   let w = existing.windowControllers.first?.window {
    w.makeKeyAndOrderFront(nil)
    openNext(&rest, after: w)
    return
}
```
with:
```swift
// Already open anywhere? Focus it (select its tab + raise its window), then
// continue with the rest of the batch.
if EditorWindowController.focusIfAlreadyOpen(url) {
    let w = NSDocumentController.shared.document(for: url)?.windowControllers.first?.window
    openNext(&rest, after: w)
    return
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter AlreadyOpenFocusTests`
Expected: PASS.

- [ ] **Step 6: Run the full suite**

Run: `swift test`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/MeditKit/EditorWindowController.swift Tests/MeditKitTests/AlreadyOpenFocusTests.swift
git commit -m "feat: focus an already-open file across windows instead of duplicating"
```

---

## Task 3: The grouped session model (WindowSession) — pure + Codable

**Files:**
- Create: `Sources/MeditKit/WindowSession.swift`
- Test: `Tests/MeditKitTests/WindowSessionTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct WindowSession: Codable, Equatable {
      public var tabPaths: [String]          // ordered document file paths (untitled excluded)
      public var activeTabPath: String?      // which tab was frontmost
      public var sidebarFolderBookmarks: [Data]  // security-scoped bookmarks of the window's sidebar roots
      public var frame: String               // NSStringFromRect of the window frame
  }
  public enum SessionCodec {
      public static func encode(_ windows: [WindowSession]) -> Data
      public static func decode(_ data: Data) -> [WindowSession]
      public static func migrateFlat(_ paths: [String]) -> [WindowSession]  // old flat list → one window of tabs
  }
  ```
- Consumes: nothing (pure model; no AppKit).

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/MeditKitTests/WindowSessionTests.swift
import XCTest
@testable import MeditKit

final class WindowSessionTests: XCTestCase {
    func testRoundTripPreservesStructure() {
        let windows = [
            WindowSession(tabPaths: ["/a.txt", "/b.txt"], activeTabPath: "/b.txt",
                          sidebarFolderBookmarks: [Data([1, 2, 3])], frame: "{{0, 0}, {800, 600}}"),
            WindowSession(tabPaths: ["/c.md"], activeTabPath: "/c.md",
                          sidebarFolderBookmarks: [], frame: "{{100, 100}, {500, 400}}"),
        ]
        let decoded = SessionCodec.decode(SessionCodec.encode(windows))
        XCTAssertEqual(decoded, windows)
    }

    func testMigrateFlatProducesOneWindowOfTabs() {
        let flat = ["/a.txt", "/b.txt", "/c.md"]
        let windows = SessionCodec.migrateFlat(flat)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].tabPaths, flat)
        XCTAssertNil(windows[0].activeTabPath)
        XCTAssertTrue(windows[0].sidebarFolderBookmarks.isEmpty)
    }

    func testDecodeOfGarbageReturnsEmpty() {
        XCTAssertEqual(SessionCodec.decode(Data([0xFF, 0x00])), [])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter WindowSessionTests`
Expected: FAIL — `WindowSession` / `SessionCodec` not defined.

- [ ] **Step 3: Implement the model**

```swift
// Sources/MeditKit/WindowSession.swift
import Foundation

/// One window's persisted session: its ordered tabs, which tab was frontmost, the
/// security-scoped bookmarks of the folders open in its sidebar, and its frame.
/// Pure value type — no AppKit — so it round-trips and is unit-tested in isolation.
public struct WindowSession: Codable, Equatable {
    public var tabPaths: [String]
    public var activeTabPath: String?
    public var sidebarFolderBookmarks: [Data]
    public var frame: String

    public init(tabPaths: [String], activeTabPath: String?,
                sidebarFolderBookmarks: [Data], frame: String) {
        self.tabPaths = tabPaths
        self.activeTabPath = activeTabPath
        self.sidebarFolderBookmarks = sidebarFolderBookmarks
        self.frame = frame
    }
}

/// Encode/decode the grouped session, and migrate the pre-multi-window flat list.
public enum SessionCodec {
    public static func encode(_ windows: [WindowSession]) -> Data {
        (try? JSONEncoder().encode(windows)) ?? Data()
    }

    public static func decode(_ data: Data) -> [WindowSession] {
        (try? JSONDecoder().decode([WindowSession].self, from: data)) ?? []
    }

    /// Old sessions stored a flat list of file paths (one global window of tabs).
    /// Restore them as exactly that: a single window holding all those tabs.
    public static func migrateFlat(_ paths: [String]) -> [WindowSession] {
        guard !paths.isEmpty else { return [] }
        return [WindowSession(tabPaths: paths, activeTabPath: nil,
                              sidebarFolderBookmarks: [], frame: "")]
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter WindowSessionTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MeditKit/WindowSession.swift Tests/MeditKitTests/WindowSessionTests.swift
git commit -m "feat: WindowSession grouped session model + flat-list migration"
```

---

## Task 4: Persist the grouped session in Preferences + SessionStore

**Files:**
- Modify: `Sources/MeditKit/Preferences.swift` — add `sessionWindows: Data` (Key + accessor + default); keep `lastSessionFiles` for migration.
- Modify: `Sources/MeditKit/SessionStore.swift` — store/read `[WindowSession]`; migrate flat once.
- Test: `Tests/MeditKitTests/WindowSessionTests.swift` (extend)

**Interfaces:**
- Consumes: `WindowSession`, `SessionCodec` (Task 3).
- Produces:
  ```swift
  // SessionStore
  public var windows: [WindowSession] { get }       // reads sessionWindows; if empty, migrates lastSessionFiles
  public func record(_ windows: [WindowSession])     // writes sessionWindows
  public func clear()
  ```

- [ ] **Step 1: Write the failing test**

```swift
// append to WindowSessionTests.swift
func testSessionStoreRoundTripAndFlatMigration() {
    let defaults = UserDefaults(suiteName: "medit.session.\(UUID().uuidString)")!
    let prefs = Preferences(defaults: defaults)
    let store = SessionStore(preferences: prefs)

    // Flat-only legacy state migrates to one window.
    prefs.lastSessionFiles = ["/x.txt", "/y.txt"]
    XCTAssertEqual(store.windows.map(\.tabPaths), [["/x.txt", "/y.txt"]])

    // Recording grouped windows supersedes the flat list.
    let grouped = [WindowSession(tabPaths: ["/x.txt"], activeTabPath: "/x.txt",
                                 sidebarFolderBookmarks: [], frame: "{{0, 0}, {800, 600}}")]
    store.record(grouped)
    XCTAssertEqual(store.windows, grouped)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WindowSessionTests/testSessionStoreRoundTripAndFlatMigration`
Expected: FAIL — `SessionStore.windows` / `record([WindowSession])` not defined.

- [ ] **Step 3: Add the Preferences storage**

In `Preferences.swift`, in the `Key` enum (near `:69`) add:

```swift
static let sessionWindows = "sessionWindows"
```
In the registered-defaults dictionary (near `:118`) add:
```swift
Key.sessionWindows: Data(),
```
With the other accessors (near `:286`) add:
```swift
public var sessionWindows: Data {
    get { defaults.data(forKey: Key.sessionWindows) ?? Data() }
    set { defaults.set(newValue, forKey: Key.sessionWindows); didChange() }
}
```

- [ ] **Step 4: Rewrite SessionStore over the grouped model**

Replace the body of `SessionStore.swift` with (keeping the `shared`/`init(preferences:)` shape):

```swift
import Foundation

/// Persists the per-window session (tabs, active tab, sidebar folders, frame) so
/// the full workspace reopens on next launch. Independent of macOS state
/// restoration (medit opts out to keep explicit window control). Migrates the old
/// flat `lastSessionFiles` list to one window of tabs on first read.
public final class SessionStore {
    public static let shared = SessionStore()
    private let prefs: Preferences
    public init(preferences: Preferences = .shared) { self.prefs = preferences }

    /// The saved windows. If the grouped store is empty but a legacy flat list
    /// exists, migrate it to a single window of tabs.
    public var windows: [WindowSession] {
        let grouped = SessionCodec.decode(prefs.sessionWindows)
        if !grouped.isEmpty { return grouped }
        return SessionCodec.migrateFlat(prefs.lastSessionFiles)
    }

    /// Replace the saved session with these windows.
    public func record(_ windows: [WindowSession]) {
        prefs.sessionWindows = SessionCodec.encode(windows)
    }

    public func clear() {
        prefs.sessionWindows = Data()
        prefs.lastSessionFiles = []
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter WindowSessionTests/testSessionStoreRoundTripAndFlatMigration`
Expected: PASS.

- [ ] **Step 6: Fix callers of the old SessionStore API**

`AppDelegate.snapshotSession()` (`:80`) and `reopenLastSessionIfEnabled()` (`:61`) reference `SessionStore.shared.files` / `record([URL])`, which no longer exist. They are rewritten in Task 6; to keep the build green now, temporarily make `snapshotSession` a no-op and `reopenLastSessionIfEnabled` read `SessionStore.shared.windows.first?.tabPaths` as URLs. Run `swift build` and fix any remaining compile errors in `AppDelegate.swift` until it builds.

Run: `swift build`
Expected: Build complete.

- [ ] **Step 7: Run the full suite**

Run: `swift test`
Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/MeditKit/Preferences.swift Sources/MeditKit/SessionStore.swift Tests/MeditKitTests/WindowSessionTests.swift Sources/MeditKit/AppDelegate.swift
git commit -m "feat: persist grouped per-window session; migrate flat list"
```

---

## Task 5: Sidebar folder snapshot/restore accessors

**Files:**
- Modify: `Sources/MeditKit/SidebarViewController.swift` — add `currentRootBookmarks` (read) and `setRoots(fromBookmarks:)` (write), reusing existing bookmark code.
- Modify: `Sources/MeditKit/EditorWindowController.swift` — expose `sidebarRootBookmarks` and `restoreSidebarRoots(_:)` that forward to the sidebar.
- Test: covered indirectly by Task 6's restore test; add a direct accessor test here.

**Interfaces:**
- Produces (SidebarViewController):
  ```swift
  public var currentRootBookmarks: [Data]        // bookmarks for the roots currently shown
  public func setRoots(fromBookmarks: [Data])     // resolve + show these roots (reuses restoreRootsFromBookmarks logic)
  ```
- Produces (EditorWindowController):
  ```swift
  public var sidebarRootBookmarks: [Data]
  public func restoreSidebarRoots(_ bookmarks: [Data])
  ```

- [ ] **Step 1: Write the failing test**

```swift
// Tests/MeditKitTests/MultiWindowRoutingTests.swift (append)
func testSidebarRootBookmarksRoundTripThroughWindowController() throws {
    let prefs = Preferences(defaults: UserDefaults(suiteName: "medit.sb.\(UUID().uuidString)")!)
    let doc = TextDocument(); doc.setTextForTesting("")
    let wc = EditorWindowController(document: doc, preferences: prefs)
    _ = wc.window; wc.loadViewIfNeededForTesting()

    // Bookmark a real temp folder, restore it, read it back.
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("medit-sb-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let bm = try dir.bookmarkData(options: [.withSecurityScope])

    wc.restoreSidebarRoots([bm])
    XCTAssertEqual(wc.sidebarRootBookmarks.count, 1,
                   "the window's sidebar should report one restored root")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MultiWindowRoutingTests/testSidebarRootBookmarksRoundTripThroughWindowController`
Expected: FAIL — `restoreSidebarRoots` / `sidebarRootBookmarks` not defined.

- [ ] **Step 3: Add the sidebar accessors**

In `SidebarViewController.swift`, add (the resolve loop mirrors `restoreRootsFromBookmarks` at `:174`; the write mirrors `persistRoots` at `:244`):

```swift
/// Security-scoped bookmarks of the roots currently shown (for session snapshot).
public var currentRootBookmarks: [Data] {
    dataSource.roots.compactMap { try? $0.url.bookmarkData(options: [.withSecurityScope]) }
}

/// Replace the shown roots with the ones these bookmarks resolve to (session
/// restore). Reuses the same resolve/refresh-stale path as restoreRootsFromBookmarks.
public func setRoots(fromBookmarks bookmarks: [Data]) {
    var restored: [FileTreeNode] = []
    for data in bookmarks {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { continue }
        accessedRootURLs.insert(url)
        restored.append(FileTreeNode(url: url))
    }
    dataSource.roots = restored
    if active { startWatchers(); outlineView.reloadData() }
}
```

- [ ] **Step 4: Forward from EditorWindowController**

In `EditorWindowController.swift`, add:

```swift
/// The sidebar folders open in THIS window (for session snapshot).
public var sidebarRootBookmarks: [Data] { sidebar.currentRootBookmarks }

/// Restore THIS window's sidebar folders from saved bookmarks.
public func restoreSidebarRoots(_ bookmarks: [Data]) {
    sidebar.setRoots(fromBookmarks: bookmarks)
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter MultiWindowRoutingTests/testSidebarRootBookmarksRoundTripThroughWindowController`
Expected: PASS.

- [ ] **Step 6: Run the full suite + commit**

Run: `swift test`
Expected: all pass.

```bash
git add Sources/MeditKit/SidebarViewController.swift Sources/MeditKit/EditorWindowController.swift Tests/MeditKitTests/MultiWindowRoutingTests.swift
git commit -m "feat: per-window sidebar root bookmark snapshot/restore accessors"
```

---

## Task 6: Snapshot + restore the workspace (AppDelegate wiring)

**Files:**
- Modify: `Sources/MeditKit/AppDelegate.swift` — `snapshotSession()` walks windows → `[WindowSession]`; `reopenLastSessionIfEnabled()` rebuilds windows/tabs/active/sidebar/frame.
- Modify: `Sources/MeditKit/EditorWindowController.swift` — add `tabDocumentURLs` + `activeTabURL` + `applyFrame(_:)` helpers used by snapshot/restore.
- Test: `Tests/MeditKitTests/MultiWindowRoutingTests.swift` (snapshot-shape test; full GUI restore is covered by the AutoPilot plan in Task 7).

**Interfaces:**
- Consumes: `WindowSession`, `SessionStore` (Tasks 3–4), `sidebarRootBookmarks`/`restoreSidebarRoots` (Task 5), `focusIfAlreadyOpen` (Task 2), `openNewWindow` (Task 1).
- Produces (EditorWindowController):
  ```swift
  public var tabDocumentURLs: [URL]   // file URLs of this window's tabs, in tab order (untitled excluded)
  public var activeTabURL: URL?       // file URL of the frontmost tab in this window
  public func applyFrame(_ frameString: String)  // setFrame(clampToScreen(...)) if valid
  ```

- [ ] **Step 1: Write the failing test (snapshot shape)**

```swift
// MultiWindowRoutingTests.swift (append)
func testWindowExposesItsTabURLsForSnapshot() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("medit-snap-\(UUID().uuidString).txt")
    try "x".write(to: tmp, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: tmp); NSDocumentController.shared.document(for: tmp)?.close() }

    let openExp = expectation(description: "open")
    NSDocumentController.shared.openDocument(withContentsOf: tmp, display: true) { _, _, _ in openExp.fulfill() }
    wait(for: [openExp], timeout: 5)

    let wc = NSDocumentController.shared.document(for: tmp)?
        .windowControllers.first as? EditorWindowController
    XCTAssertEqual(wc?.tabDocumentURLs.map(\.lastPathComponent), [tmp.lastPathComponent])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MultiWindowRoutingTests/testWindowExposesItsTabURLsForSnapshot`
Expected: FAIL — `tabDocumentURLs` not defined.

- [ ] **Step 3: Add window tab/frame accessors**

In `EditorWindowController.swift`:

```swift
/// File URLs of this window's tabs, in left-to-right tab order (untitled skipped).
public var tabDocumentURLs: [URL] {
    let group = window?.tabGroup?.windows ?? (window.map { [$0] } ?? [])
    return group.compactMap { w in
        (w.windowController as? EditorWindowController)?.textDocument.fileURL
    }
}

/// File URL of the frontmost tab in this window's group.
public var activeTabURL: URL? {
    (window?.tabGroup?.selectedWindow?.windowController as? EditorWindowController)?
        .textDocument.fileURL ?? textDocument.fileURL
}

/// Apply a saved frame string (clamped onto a visible screen); ignore if invalid.
public func applyFrame(_ frameString: String) {
    guard !frameString.isEmpty, let window else { return }
    let frame = NSRectFromString(frameString)
    guard frame.width >= EditorWindowController.minWindowSize.width,
          frame.height >= EditorWindowController.minWindowSize.height else { return }
    window.setFrame(clampToScreen(frame), display: true)
}
```

> Note: `textDocument` is `private let` (`:9`). Change it to `let` (drop `private`) so the group walk can read sibling controllers' documents. Update the declaration at `:9` from `private let textDocument` to `let textDocument`.

- [ ] **Step 4: Run the snapshot-shape test to verify it passes**

Run: `swift test --filter MultiWindowRoutingTests/testWindowExposesItsTabURLsForSnapshot`
Expected: PASS.

- [ ] **Step 5: Rewrite snapshotSession over windows**

In `AppDelegate.swift`, replace `snapshotSession()` (`:80`):

```swift
@objc private func snapshotSession() {
    // One WindowSession per editor tab-group. Walk each unique tab group once.
    var seenGroups = Set<ObjectIdentifier>()
    var windows: [WindowSession] = []
    for window in NSApp.windows {
        guard let wc = window.windowController as? EditorWindowController else { continue }
        let groupKey = ObjectIdentifier(window.tabGroup ?? window)
        guard seenGroups.insert(groupKey).inserted else { continue }
        let tabs = wc.tabDocumentURLs.map(\.path)
        guard !tabs.isEmpty else { continue }   // skip a group with only untitled docs
        windows.append(WindowSession(
            tabPaths: tabs,
            activeTabPath: wc.activeTabURL?.path,
            sidebarFolderBookmarks: wc.sidebarRootBookmarks,
            frame: NSStringFromRect(window.frame)))
    }
    SessionStore.shared.record(windows)
}
```

- [ ] **Step 6: Rewrite restore over windows**

Replace `reopenLastSessionIfEnabled()` (`:61`):

```swift
private func reopenLastSessionIfEnabled() {
    guard Preferences.shared.reopenLastSession,
          NSDocumentController.shared.documents.isEmpty else { return }
    let windows = SessionStore.shared.windows
    guard !windows.isEmpty else { return }
    didOpenFilesAtLaunch = true
    for win in windows { restoreOneWindow(win) }
}

/// Open one saved window: its tabs in order, then select the active tab, set the
/// sidebar folders, and apply the frame. Missing files are skipped; a window with
/// no surviving files is not created.
private func restoreOneWindow(_ session: WindowSession) {
    let urls = session.tabPaths
        .map { URL(fileURLWithPath: $0) }
        .filter { FileManager.default.fileExists(atPath: $0.path) }
    guard let first = urls.first else { return }

    NSDocumentController.shared.openDocument(withContentsOf: first, display: true) { doc, _, error in
        if let error { NSApp.presentError(error) }
        guard let wc = doc?.windowControllers.first as? EditorWindowController else { return }
        // Remaining files become tabs in THIS window.
        for url in urls.dropFirst() {
            if EditorWindowController.focusIfAlreadyOpen(url) { continue }
            wc.openFiles(at: [url])
        }
        wc.restoreSidebarRoots(session.sidebarFolderBookmarks)
        wc.applyFrame(session.frame)
        if let active = session.activeTabPath {
            EditorWindowController.focusIfAlreadyOpen(URL(fileURLWithPath: active))
        }
    }
}
```

> Note: each restored window after the first must NOT merge into the previous one. Because Task 1 set `tabbingMode = .automatic`, separate `openDocument` calls create separate windows by default — the per-window `openFiles(at:)` calls add tabs only within their own window. Verify this in the AutoPilot plan (Task 7).

- [ ] **Step 7: Build + run the full suite**

Run: `swift build && swift test`
Expected: Build complete; all tests pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/MeditKit/AppDelegate.swift Sources/MeditKit/EditorWindowController.swift Tests/MeditKitTests/MultiWindowRoutingTests.swift
git commit -m "feat: snapshot + restore the full multi-window workspace"
```

---

## Task 7: AutoPilot GUI gate + manual verification

**Files:**
- Create: `uitests/multi-window.json`
- Create: `uitests/fixtures/mw-a.txt`, `uitests/fixtures/mw-b.txt`
- Modify: `uitests/stage-fixtures.sh` (stage the new fixtures to `/tmp`)
- Build: the Debug app at `/Volumes/Scratch/Xcode/DerivedData/Debug/medit.app`

**Interfaces:** none (test asset).

- [ ] **Step 1: Add fixtures + staging**

```bash
printf 'multi-window fixture A\n' > uitests/fixtures/mw-a.txt
printf 'multi-window fixture B\n' > uitests/fixtures/mw-b.txt
```
Append to `uitests/stage-fixtures.sh` the two new files (copy to `/tmp/medit-ap-mw-a.txt`, `/tmp/medit-ap-mw-b.txt`), mirroring the existing `for f in …; do cp …` pattern.

- [ ] **Step 2: Write the AutoPilot plan**

Create `uitests/multi-window.json` (sandbox: the app can only open `/tmp` launch files; New Window via the ⇧⌘N key chord on the editor):

```json
{
  "schemaVersion": "1.0",
  "name": "multi-window: New Window makes a 2nd window; New Tab does not",
  "comment": "Verifies the multi-window model in the real app. Requires the Debug build; fixtures staged to /tmp by stage-fixtures.sh (sandbox blocks repo-path launchFiles).",
  "target": {
    "path": "/Volumes/Scratch/Xcode/DerivedData/Debug/medit.app",
    "launchFiles": ["/tmp/medit-ap-mw-a.txt"]
  },
  "defaults": { "timeoutMs": 8000, "retryIntervalMs": 150 },
  "steps": [
    { "id": "wait-window", "action": "waitFor", "target": { "role": "AXWindow" }, "args": { "present": true } },
    { "id": "wait-editor", "action": "waitFor", "target": { "identifier": "editorTextView" }, "args": { "present": true } },
    { "id": "focus-editor", "action": "click", "target": { "identifier": "editorTextView" } },
    { "id": "new-window", "action": "keyPress", "target": { "identifier": "editorTextView" }, "args": { "keys": "cmd+shift+n" } },
    { "id": "settle-window", "action": "wait", "args": { "seconds": 1 } },
    { "id": "two-windows", "action": "assert", "target": { "role": "AXWindow" }, "assert": { "property": "count", "op": "greaterThan", "expected": "1" } },
    { "id": "quit", "action": "terminate" }
  ]
}
```

> If AutoPilot's `count` assertion on `AXWindow` is unavailable (it reads `nil` for `.count` on the macOS property reader), fall back to capturing the window count via `dump-axtree` during manual verification (Step 4) and keep this plan as the launch+New-Window smoke (drop the `two-windows` assert, keep `terminate`).

- [ ] **Step 3: Lint + run the plan against the Debug build**

```bash
xcodebuild -project App/medit.xcodeproj -scheme medit -configuration Debug \
  -derivedDataPath /Volumes/Scratch/Xcode/DerivedData/medit-debug build
./uitests/stage-fixtures.sh
AP=/Users/jschwefel/repositories/autopilot/.build/debug/autopilot
$AP lint uitests/multi-window.json
$AP run uitests/multi-window.json --artifacts /tmp/medit-uitests
```
Expected: lint ok; RESULT pass.

- [ ] **Step 4: Manual multi-window verification (dump-axtree window count)**

```bash
# After the plan (or a manual launch), confirm 2 windows exist:
pkill -x medit; sleep 1
open -a /Volumes/Scratch/Xcode/DerivedData/Debug/medit.app /tmp/medit-ap-mw-a.txt; sleep 2
PID=$(pgrep -x medit | head -1)
$AP dump-axtree --pid "$PID" | grep -c '"role" : "AXWindow"'   # expect 1
# Then press ⇧⌘N in the app and re-dump; expect 2.
```
Confirm: ⇧⌘N adds a window; ⌘N (and sidebar/Open) adds a tab; opening an already-open file focuses it; quitting and relaunching restores the window/tab layout.

- [ ] **Step 5: Commit**

```bash
git add uitests/multi-window.json uitests/fixtures/mw-a.txt uitests/fixtures/mw-b.txt uitests/stage-fixtures.sh
git commit -m "test: AutoPilot multi-window gate (New Window vs New Tab) + fixtures"
```

---

## Task 8: Docs, version bump, AP feedback, ship

**Files:**
- Modify: `App/Info.plist` (version → 2.7.0), then `scripts/set-build-number.sh`
- Modify: `docs/autopilot-feedback.md` (per-release entry before merge)
- Modify: `uitests/README.md` (note the new `multi-window.json` + tagged controls if any changed)

- [ ] **Step 1: Update uitests/README.md** — add `multi-window.json` to the plan list; no new AX identifiers were added (windows are matched by role), so the tagged-controls list is unchanged.

- [ ] **Step 2: Add the AP feedback entry**

In `docs/autopilot-feedback.md`, add a `## medit 2.7.0 — multi-window` entry at the top (newest first): note that multi-window matched by `AXWindow` role (no new AX ids), the `cmd+shift+n` New-Window chord works via `keyPress`, and any `AXWindow` `count`-assertion limitation found in Task 7.

- [ ] **Step 3: Bump version + build number**

```bash
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 2.7.0" App/Info.plist
git add App/Info.plist docs/autopilot-feedback.md uitests/README.md
git commit -m "docs: 2.7.0 multi-window — version bump + AP findings + uitests README"
./scripts/set-build-number.sh
git add App/Info.plist App/medit.xcodeproj/project.pbxproj
git commit -m "chore: stamp build number for 2.7.0"
```

- [ ] **Step 4: Full verification before shipping**

```bash
swift test                               # expect all pass
./scripts/set-build-number.sh >/dev/null # idempotent check
AP=/Users/jschwefel/repositories/autopilot/.build/debug/autopilot
./uitests/stage-fixtures.sh && $AP run uitests/multi-window.json --artifacts /tmp/medit-uitests
```
Expected: tests pass; AP plan passes.

- [ ] **Step 5: Ship via the release flow (REQUIRES the user's explicit "go")**

Per the project release flow — do NOT tag/release without the user's go:
`git push -u origin feature/multi-window` → open PR → CI green → `gh pr merge N --merge --admin` → sync main → tag `v2.7.0` on main HEAD → universal `xcodebuild clean build ARCHS="x86_64 arm64" ONLY_ACTIVE_ARCH=NO` → `codesign --force --deep --sign -` → `ditto -c -k --sequesterRsrc --keepParent` → `gh release create v2.7.0 … --latest` → install to `/Applications`. Delete the merged branch.

---

## Self-Review

**1. Spec coverage:**
- §1 Window model → Task 1 ✓ (tabbingMode, ⌘N=tab, ⇧⌘N=New Window, ⌘T=tab).
- §2 Sidebar per-window + New Window empty folder pane / app-wide Recent → falls out of Task 1 (separate windows) + Task 5 (per-window root accessors); Recent is already app-global (`RecentFilesStore.shared`), no task needed. ✓
- §3 Already-open focus across windows → Task 2 ✓.
- §4 Full workspace restore (tabs, active tab, sidebar folder bookmark, frame; degradation; migration) → Tasks 3 (model+migration), 4 (persistence), 5 (sidebar bookmarks), 6 (snapshot+restore+frame). ✓
- §5 Testing (unit + AutoPilot) → unit tests in Tasks 1–6; AutoPilot in Task 7. ✓

**2. Placeholder scan:** No TBD/TODO/"handle edge cases"; every code step shows real code; the two `> Note` callouts give concrete fallbacks (AXWindow count assertion; `textDocument` visibility), not deferrals.

**3. Type consistency:** `WindowSession`/`SessionCodec` (Task 3) used unchanged in Tasks 4 & 6. `focusIfAlreadyOpen` (Task 2) reused in Task 6. `sidebarRootBookmarks`/`restoreSidebarRoots` (Task 5) used in Task 6 snapshot/restore. `tabDocumentURLs`/`activeTabURL`/`applyFrame` defined in Task 6 and used in the same task's AppDelegate wiring. `openNewWindow` (Task 1) referenced by the New-Window menu and AutoPilot chord.

**Known risk flagged for the implementer:** the AutoPilot `AXWindow` `count` assertion may be unsupported by the current CLI property reader (returns nil for `.count`) — Task 7 Step 2 gives the fallback (dump-axtree window count in manual verification). This does not block the unit-test gate, which fully covers routing/focus/session logic.
