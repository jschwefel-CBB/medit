# Sidebar File Browser (1.4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional, default-OFF, multi-root file browser sidebar (resizable split, full file management, lots of toggles) that imposes zero overhead when hidden and never regresses editor rendering.

**Architecture:** The window's content view controller becomes an `NSSplitViewController` hosting a `SidebarViewController` (collapsible, default collapsed) and the existing `EditorViewController`. Correctness lives in pure value types (`FileTreeNode` sort/filter, `FileSystemOperations` conflict logic, `FileTreeDataSource`) tested exhaustively over temp directories; the AppKit pieces (outline view, `DirectoryWatcher`, drag-drop) are smoke-tested with the render-regression guard retained.

**Tech Stack:** Swift, AppKit, XCTest, local SwiftPM package `MeditKit`.

**SAFETY (every task):** A live instance of medit may be running. NEVER run `pkill`, `open`, or launch/reinstall the app. Verify ONLY with `cd /Users/jschwefel/repositories/medit && swift build` and `swift test` (and at most `xcodebuild ... build CODE_SIGNING_ALLOWED=NO`, which does not launch). Use plain `git commit` (NO `-c` identity override). Work from `/Users/jschwefel/repositories/medit` on branch `feature/sidebar-1.4`. **NEVER create any `superpowers/` path** — a pre-commit hook blocks it; design docs are in `docs/specs/` and `docs/plans/`.

Spec: `docs/specs/2026-06-16-sidebar-file-browser-1.4-design.md`.

---

## File Structure

New pure-logic units (tested over temp dirs):
- `Sources/MeditKit/FileTreeNode.swift` — lazy file-tree node + configurable sort/filter.
- `Sources/MeditKit/FileSystemOperations.swift` — create/rename/move/trash + conflict logic.
- `Sources/MeditKit/FileTreeDataSource.swift` — NSOutlineView data source (multi-root).

New AppKit units:
- `Sources/MeditKit/SidebarViewController.swift` — outline view, roots, context menu, drag.
- `Sources/MeditKit/DirectoryWatcher.swift` — per-root FS monitor.

Modified:
- `EditorWindowController.swift` — host the split view; sidebar toggles + validation; Open Folder.
- `MainMenu.swift` — View → Show Sidebar / Show Hidden Files / Reveal Active File; File → Open Folder.
- `Preferences.swift` (+ 8 sidebar keys), `PreferencesWindowController.swift` (Sidebar section).

---

## Task 1: FileTreeNode (lazy tree, configurable sort + hidden filter)

**Files:**
- Create: `Sources/MeditKit/FileTreeNode.swift`, `Tests/MeditKitTests/FileTreeNodeTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MeditKitTests/FileTreeNodeTests.swift`:

```swift
import XCTest
@testable import MeditKit

final class FileTreeNodeTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("medit-ftn-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Layout: Bravo/ (dir), alpha.txt, Charlie.txt, .hidden, zebra/ (dir)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Bravo"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("zebra"), withIntermediateDirectories: true)
        try Data("a".utf8).write(to: root.appendingPathComponent("alpha.txt"))
        try Data("c".utf8).write(to: root.appendingPathComponent("Charlie.txt"))
        try Data("h".utf8).write(to: root.appendingPathComponent(".hidden"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func names(_ nodes: [FileTreeNode]) -> [String] { nodes.map { $0.url.lastPathComponent } }

    func testIsDirectory() {
        let node = FileTreeNode(url: root.appendingPathComponent("Bravo"))
        XCTAssertTrue(node.isDirectory)
        let file = FileTreeNode(url: root.appendingPathComponent("alpha.txt"))
        XCTAssertFalse(file.isDirectory)
    }

    func testFoldersFirstAscending() {
        let node = FileTreeNode(url: root)
        let children = node.children(foldersFirst: true, ascending: true, showHidden: false)
        // dirs (Bravo, zebra) first alpha-sorted, then files (alpha.txt, Charlie.txt) alpha-sorted
        XCTAssertEqual(names(children), ["Bravo", "zebra", "alpha.txt", "Charlie.txt"])
    }

    func testMixedAscendingWhenFoldersFirstOff() {
        let node = FileTreeNode(url: root)
        let children = node.children(foldersFirst: false, ascending: true, showHidden: false)
        // single case-insensitive list: alpha.txt, Bravo, Charlie.txt, zebra
        XCTAssertEqual(names(children), ["alpha.txt", "Bravo", "Charlie.txt", "zebra"])
    }

    func testDescending() {
        let node = FileTreeNode(url: root)
        let children = node.children(foldersFirst: true, ascending: false, showHidden: false)
        XCTAssertEqual(names(children), ["zebra", "Bravo", "Charlie.txt", "alpha.txt"])
    }

    func testHiddenExcludedByDefault() {
        let node = FileTreeNode(url: root)
        let children = node.children(foldersFirst: true, ascending: true, showHidden: false)
        XCTAssertFalse(names(children).contains(".hidden"))
    }

    func testHiddenShownWhenRequested() {
        let node = FileTreeNode(url: root)
        let children = node.children(foldersFirst: true, ascending: true, showHidden: true)
        XCTAssertTrue(names(children).contains(".hidden"))
    }

    func testCaseInsensitiveSort() {
        // alpha.txt (lowercase) should sort before Charlie.txt (uppercase) case-insensitively
        let node = FileTreeNode(url: root)
        let files = node.children(foldersFirst: true, ascending: true, showHidden: false)
            .filter { !$0.isDirectory }
        XCTAssertEqual(names(files), ["alpha.txt", "Charlie.txt"])
    }

    func testChildrenCachedUntilInvalidated() {
        let node = FileTreeNode(url: root)
        _ = node.children(foldersFirst: true, ascending: true, showHidden: false)
        // Add a new file; without invalidation the cached result shouldn't include it.
        try? Data("n".utf8).write(to: root.appendingPathComponent("new.txt"))
        let cached = node.children(foldersFirst: true, ascending: true, showHidden: false)
        XCTAssertFalse(names(cached).contains("new.txt"))
        node.invalidateChildren()
        let fresh = node.children(foldersFirst: true, ascending: true, showHidden: false)
        XCTAssertTrue(names(fresh).contains("new.txt"))
    }

    func testFileNodeHasNoChildren() {
        let file = FileTreeNode(url: root.appendingPathComponent("alpha.txt"))
        XCTAssertTrue(file.children(foldersFirst: true, ascending: true, showHidden: false).isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter FileTreeNodeTests 2>&1 | grep -E "error:|cannot find"`
Expected: `cannot find 'FileTreeNode' in scope`.

- [ ] **Step 3: Implement FileTreeNode**

Create `Sources/MeditKit/FileTreeNode.swift`:

```swift
import Foundation

/// A node in the sidebar's file tree. Wraps a URL, knows whether it's a
/// directory, and lazily reads + caches its children. Sorting and hidden-file
/// filtering are parameters so the view layer can re-apply preferences. Pure
/// value logic over the filesystem; tested over temp directories.
public final class FileTreeNode {

    public let url: URL
    public let isDirectory: Bool

    private var cachedChildren: [FileTreeNode]?

    public init(url: URL) {
        self.url = url
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        self.isDirectory = values?.isDirectory ?? false
    }

    /// Drop the cached children so the next `children(...)` re-reads from disk.
    public func invalidateChildren() {
        cachedChildren = nil
    }

    /// Sorted, filtered child nodes. Non-directories return []. Children are read
    /// from disk once and cached until `invalidateChildren()`.
    public func children(foldersFirst: Bool, ascending: Bool, showHidden: Bool) -> [FileTreeNode] {
        guard isDirectory else { return [] }
        let nodes: [FileTreeNode]
        if let cached = cachedChildren {
            nodes = cached
        } else {
            let read = readChildren()
            cachedChildren = read
            nodes = read
        }
        let filtered = showHidden ? nodes : nodes.filter { !$0.url.lastPathComponent.hasPrefix(".") }
        return FileTreeNode.sort(filtered, foldersFirst: foldersFirst, ascending: ascending)
    }

    private func readChildren() -> [FileTreeNode] {
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(at: url,
                                                    includingPropertiesForKeys: [.isDirectoryKey],
                                                    options: [])) ?? []
        return contents.map { FileTreeNode(url: $0) }
    }

    /// Sort: optionally folders before files; within a group, case-insensitive
    /// name order, ascending or descending.
    static func sort(_ nodes: [FileTreeNode], foldersFirst: Bool, ascending: Bool) -> [FileTreeNode] {
        func nameLess(_ a: FileTreeNode, _ b: FileTreeNode) -> Bool {
            let r = a.url.lastPathComponent.localizedCaseInsensitiveCompare(b.url.lastPathComponent)
            return ascending ? (r == .orderedAscending) : (r == .orderedDescending)
        }
        if foldersFirst {
            return nodes.sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory && !b.isDirectory }
                return nameLess(a, b)
            }
        }
        return nodes.sorted(by: nameLess)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter FileTreeNodeTests 2>&1 | grep -E "Executed|failed"`
Expected: `Executed 9 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/MeditKit/FileTreeNode.swift Tests/MeditKitTests/FileTreeNodeTests.swift
git commit -m "Add FileTreeNode: lazy file tree with configurable sort + hidden filter"
```

---

## Task 2: FileSystemOperations (create/rename/move/trash + conflicts)

**Files:**
- Create: `Sources/MeditKit/FileSystemOperations.swift`, `Tests/MeditKitTests/FileSystemOperationsTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MeditKitTests/FileSystemOperationsTests.swift`:

```swift
import XCTest
@testable import MeditKit

final class FileSystemOperationsTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("medit-fso-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testNewFileCreatesUntitled() throws {
        let url = try FileSystemOperations.newFile(in: dir)
        XCTAssertEqual(url.lastPathComponent, "untitled")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testNewFileAutoNamesOnCollision() throws {
        let first = try FileSystemOperations.newFile(in: dir)
        let second = try FileSystemOperations.newFile(in: dir)
        XCTAssertEqual(first.lastPathComponent, "untitled")
        XCTAssertEqual(second.lastPathComponent, "untitled 2")
    }

    func testNewFolderCreates() throws {
        let url = try FileSystemOperations.newFolder(in: dir)
        XCTAssertEqual(url.lastPathComponent, "untitled folder")
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func testRenameMovesItem() throws {
        let file = try FileSystemOperations.newFile(in: dir)
        let renamed = try FileSystemOperations.rename(file, to: "renamed.txt")
        XCTAssertEqual(renamed.lastPathComponent, "renamed.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
    }

    func testRenameRejectsEmptyName() throws {
        let file = try FileSystemOperations.newFile(in: dir)
        XCTAssertThrowsError(try FileSystemOperations.rename(file, to: "")) { error in
            XCTAssertEqual(error as? FileSystemOperations.OpError, .invalidName)
        }
    }

    func testRenameRejectsSlash() throws {
        let file = try FileSystemOperations.newFile(in: dir)
        XCTAssertThrowsError(try FileSystemOperations.rename(file, to: "a/b")) { error in
            XCTAssertEqual(error as? FileSystemOperations.OpError, .invalidName)
        }
    }

    func testRenameRejectsCollision() throws {
        let a = try FileSystemOperations.newFile(in: dir) // untitled
        _ = try FileSystemOperations.rename(a, to: "keep.txt")
        let b = try FileSystemOperations.newFile(in: dir) // untitled
        XCTAssertThrowsError(try FileSystemOperations.rename(b, to: "keep.txt")) { error in
            XCTAssertEqual(error as? FileSystemOperations.OpError, .nameExists)
        }
    }

    func testMoveIntoFolder() throws {
        let file = try FileSystemOperations.rename(try FileSystemOperations.newFile(in: dir), to: "m.txt")
        let folder = try FileSystemOperations.newFolder(in: dir)
        let moved = try FileSystemOperations.move(file, into: folder)
        XCTAssertEqual(moved.deletingLastPathComponent().lastPathComponent, folder.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))
    }

    func testMoveRejectsIntoOwnDescendant() throws {
        let parent = try FileSystemOperations.rename(try FileSystemOperations.newFolder(in: dir), to: "parent")
        let child = try FileSystemOperations.newFolder(in: parent) // parent/untitled folder
        XCTAssertThrowsError(try FileSystemOperations.move(parent, into: child)) { error in
            XCTAssertEqual(error as? FileSystemOperations.OpError, .intoDescendant)
        }
    }

    func testMoveRejectsCollision() throws {
        let folder = try FileSystemOperations.rename(try FileSystemOperations.newFolder(in: dir), to: "folder")
        // folder/dup.txt exists; a sibling dup.txt tries to move in
        let inside = try FileSystemOperations.rename(try FileSystemOperations.newFile(in: folder), to: "dup.txt")
        _ = inside
        let outside = try FileSystemOperations.rename(try FileSystemOperations.newFile(in: dir), to: "dup.txt")
        XCTAssertThrowsError(try FileSystemOperations.move(outside, into: folder)) { error in
            XCTAssertEqual(error as? FileSystemOperations.OpError, .nameExists)
        }
    }

    func testTrashRemovesFromDisk() throws {
        let file = try FileSystemOperations.newFile(in: dir)
        try FileSystemOperations.moveToTrash(file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter FileSystemOperationsTests 2>&1 | grep -E "error:|cannot find"`
Expected: `cannot find 'FileSystemOperations' in scope`.

- [ ] **Step 3: Implement FileSystemOperations**

Create `Sources/MeditKit/FileSystemOperations.swift`:

```swift
import Foundation

/// File mutations for the sidebar (create/rename/move/trash) with conflict
/// detection. UI-free so the rules are tested headlessly over temp directories.
public enum FileSystemOperations {

    public enum OpError: Error, Equatable {
        case invalidName     // empty or contains "/"
        case nameExists      // a target with that name already exists
        case intoDescendant  // tried to move a folder into its own subtree
    }

    /// Create an empty file named "untitled" (auto-incrementing on collision).
    @discardableResult
    public static func newFile(in directory: URL) throws -> URL {
        let url = uniqueURL(in: directory, base: "untitled", isDirectory: false)
        try Data().write(to: url)
        return url
    }

    /// Create a folder named "untitled folder" (auto-incrementing on collision).
    @discardableResult
    public static func newFolder(in directory: URL) throws -> URL {
        let url = uniqueURL(in: directory, base: "untitled folder", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    /// Rename `item` to `newName` within the same directory.
    @discardableResult
    public static func rename(_ item: URL, to newName: String) throws -> URL {
        guard !newName.isEmpty, !newName.contains("/") else { throw OpError.invalidName }
        let target = item.deletingLastPathComponent().appendingPathComponent(newName)
        if FileManager.default.fileExists(atPath: target.path) { throw OpError.nameExists }
        try FileManager.default.moveItem(at: item, to: target)
        return target
    }

    /// Move `item` into `folder`.
    @discardableResult
    public static func move(_ item: URL, into folder: URL) throws -> URL {
        // Reject moving a folder into itself or a descendant.
        let itemPath = item.standardizedFileURL.path
        let folderPath = folder.standardizedFileURL.path
        if folderPath == itemPath || folderPath.hasPrefix(itemPath + "/") {
            throw OpError.intoDescendant
        }
        let target = folder.appendingPathComponent(item.lastPathComponent)
        if FileManager.default.fileExists(atPath: target.path) { throw OpError.nameExists }
        try FileManager.default.moveItem(at: item, to: target)
        return target
    }

    /// Move `item` to the Trash (recoverable; never a hard delete).
    public static func moveToTrash(_ item: URL) throws {
        try FileManager.default.trashItem(at: item, resultingItemURL: nil)
    }

    /// A non-colliding URL: "base", then "base 2", "base 3", … (files keep no
    /// extension here since callers pass a bare base name).
    private static func uniqueURL(in directory: URL, base: String, isDirectory: Bool) -> URL {
        var candidate = directory.appendingPathComponent(base)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(n)")
            n += 1
        }
        return candidate
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter FileSystemOperationsTests 2>&1 | grep -E "Executed|failed"`
Expected: `Executed 11 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/MeditKit/FileSystemOperations.swift Tests/MeditKitTests/FileSystemOperationsTests.swift
git commit -m "Add FileSystemOperations: create/rename/move/trash with conflict checks"
```

---

## Task 3: FileTreeDataSource (NSOutlineView data source, multi-root)

**Files:**
- Create: `Sources/MeditKit/FileTreeDataSource.swift`, `Tests/MeditKitTests/FileTreeDataSourceTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MeditKitTests/FileTreeDataSourceTests.swift`:

```swift
import XCTest
import AppKit
@testable import MeditKit

final class FileTreeDataSourceTests: XCTestCase {

    private var rootA: URL!
    private var rootB: URL!

    override func setUpWithError() throws {
        let tmp = FileManager.default.temporaryDirectory
        rootA = tmp.appendingPathComponent("medit-ds-A-\(UUID().uuidString)")
        rootB = tmp.appendingPathComponent("medit-ds-B-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootA.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: rootA.appendingPathComponent("file.txt"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootA)
        try? FileManager.default.removeItem(at: rootB)
    }

    private func makeDataSource() -> FileTreeDataSource {
        let ds = FileTreeDataSource()
        ds.roots = [FileTreeNode(url: rootA), FileTreeNode(url: rootB)]
        return ds
    }

    func testRootLevelCountIsNumberOfRoots() {
        let ds = makeDataSource()
        let outline = NSOutlineView()
        XCTAssertEqual(ds.outlineView(outline, numberOfChildrenOfItem: nil), 2)
    }

    func testRootLevelItemsAreRoots() {
        let ds = makeDataSource()
        let outline = NSOutlineView()
        let first = ds.outlineView(outline, child: 0, ofItem: nil) as? FileTreeNode
        XCTAssertEqual(first?.url.lastPathComponent, rootA.lastPathComponent)
    }

    func testDirectoryIsExpandable() {
        let ds = makeDataSource()
        let outline = NSOutlineView()
        let rootNode = ds.outlineView(outline, child: 0, ofItem: nil) as! FileTreeNode
        XCTAssertTrue(ds.outlineView(outline, isItemExpandable: rootNode))
    }

    func testFileIsNotExpandable() {
        let ds = makeDataSource()
        let outline = NSOutlineView()
        let rootNode = ds.outlineView(outline, child: 0, ofItem: nil) as! FileTreeNode
        // rootA children: "sub" (dir), "file.txt"
        let count = ds.outlineView(outline, numberOfChildrenOfItem: rootNode)
        XCTAssertEqual(count, 2)
        var foundFile = false
        for i in 0..<count {
            let child = ds.outlineView(outline, child: i, ofItem: rootNode) as! FileTreeNode
            if child.url.lastPathComponent == "file.txt" {
                foundFile = true
                XCTAssertFalse(ds.outlineView(outline, isItemExpandable: child))
            }
        }
        XCTAssertTrue(foundFile)
    }

    func testChildrenRespectSortPreferences() {
        let ds = makeDataSource()
        ds.foldersFirst = true; ds.ascending = true; ds.showHidden = false
        let outline = NSOutlineView()
        let rootNode = ds.outlineView(outline, child: 0, ofItem: nil) as! FileTreeNode
        let first = ds.outlineView(outline, child: 0, ofItem: rootNode) as! FileTreeNode
        XCTAssertEqual(first.url.lastPathComponent, "sub", "folder should sort first")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter FileTreeDataSourceTests 2>&1 | grep -E "error:|cannot find"`
Expected: `cannot find 'FileTreeDataSource' in scope`.

- [ ] **Step 3: Implement FileTreeDataSource**

Create `Sources/MeditKit/FileTreeDataSource.swift`:

```swift
import AppKit

/// NSOutlineView data source + delegate for the sidebar's multi-root file tree.
/// `item == nil` represents the invisible root whose children are the root
/// folders; a `FileTreeNode` directory's children are its lazy contents. Sorting
/// and hidden-file preferences are applied through the node.
public final class FileTreeDataSource: NSObject, NSOutlineViewDataSource {

    public var roots: [FileTreeNode] = []
    public var foldersFirst = true
    public var ascending = true
    public var showHidden = false

    private func childList(of node: FileTreeNode) -> [FileTreeNode] {
        node.children(foldersFirst: foldersFirst, ascending: ascending, showHidden: showHidden)
    }

    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? FileTreeNode else { return roots.count }
        return childList(of: node).count
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? FileTreeNode else { return roots[index] }
        return childList(of: node)[index]
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any?) -> Bool {
        (item as? FileTreeNode)?.isDirectory ?? false
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter FileTreeDataSourceTests 2>&1 | grep -E "Executed|failed"`
Expected: `Executed 5 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/MeditKit/FileTreeDataSource.swift Tests/MeditKitTests/FileTreeDataSourceTests.swift
git commit -m "Add FileTreeDataSource: NSOutlineView data source (multi-root level)"
```

---

## Task 4: Window restructuring — NSSplitViewController + showSidebar toggle

**Files:**
- Create: `Sources/MeditKit/SidebarViewController.swift` (minimal stub this task)
- Modify: `Sources/MeditKit/EditorWindowController.swift`, `Sources/MeditKit/Preferences.swift`, `Sources/MeditKit/MainMenu.swift`, `Tests/MeditKitTests/PreferencesTests.swift`, `Tests/MeditKitTests/EditorSmokeTests.swift`

This is the riskiest task: the window's content view controller changes from the
editor directly to a split view. The render-regression smoke test must stay green.

- [ ] **Step 1: Add the sidebar preferences (all 8)**

In `Sources/MeditKit/Preferences.swift`, add to the `Key` enum:

```swift
        static let showSidebar = "showSidebar"
        static let showHiddenFiles = "showHiddenFiles"
        static let syncSidebarWithActiveTab = "syncSidebarWithActiveTab"
        static let sidebarSortFoldersFirst = "sidebarSortFoldersFirst"
        static let sidebarSortAscending = "sidebarSortAscending"
        static let sidebarOpenOnSingleClick = "sidebarOpenOnSingleClick"
        static let sidebarOnRight = "sidebarOnRight"
        static let confirmBeforeDelete = "confirmBeforeDelete"
```

Add to `registerDefaults()`:

```swift
            Key.showSidebar: false,
            Key.showHiddenFiles: false,
            Key.syncSidebarWithActiveTab: true,
            Key.sidebarSortFoldersFirst: true,
            Key.sidebarSortAscending: true,
            Key.sidebarOpenOnSingleClick: false,
            Key.sidebarOnRight: false,
            Key.confirmBeforeDelete: true,
```

Add 8 properties (same shape as `showLineNumbers`):

```swift
    public var showSidebar: Bool {
        get { defaults.bool(forKey: Key.showSidebar) }
        set { defaults.set(newValue, forKey: Key.showSidebar); didChange() }
    }
    public var showHiddenFiles: Bool {
        get { defaults.bool(forKey: Key.showHiddenFiles) }
        set { defaults.set(newValue, forKey: Key.showHiddenFiles); didChange() }
    }
    public var syncSidebarWithActiveTab: Bool {
        get { defaults.bool(forKey: Key.syncSidebarWithActiveTab) }
        set { defaults.set(newValue, forKey: Key.syncSidebarWithActiveTab); didChange() }
    }
    public var sidebarSortFoldersFirst: Bool {
        get { defaults.bool(forKey: Key.sidebarSortFoldersFirst) }
        set { defaults.set(newValue, forKey: Key.sidebarSortFoldersFirst); didChange() }
    }
    public var sidebarSortAscending: Bool {
        get { defaults.bool(forKey: Key.sidebarSortAscending) }
        set { defaults.set(newValue, forKey: Key.sidebarSortAscending); didChange() }
    }
    public var sidebarOpenOnSingleClick: Bool {
        get { defaults.bool(forKey: Key.sidebarOpenOnSingleClick) }
        set { defaults.set(newValue, forKey: Key.sidebarOpenOnSingleClick); didChange() }
    }
    public var sidebarOnRight: Bool {
        get { defaults.bool(forKey: Key.sidebarOnRight) }
        set { defaults.set(newValue, forKey: Key.sidebarOnRight); didChange() }
    }
    public var confirmBeforeDelete: Bool {
        get { defaults.bool(forKey: Key.confirmBeforeDelete) }
        set { defaults.set(newValue, forKey: Key.confirmBeforeDelete); didChange() }
    }
```

In `Tests/MeditKitTests/PreferencesTests.swift`, add:

```swift
    func testSidebarPrefsDefaults() {
        XCTAssertFalse(prefs.showSidebar)
        XCTAssertFalse(prefs.showHiddenFiles)
        XCTAssertTrue(prefs.syncSidebarWithActiveTab)
        XCTAssertTrue(prefs.sidebarSortFoldersFirst)
        XCTAssertTrue(prefs.sidebarSortAscending)
        XCTAssertFalse(prefs.sidebarOpenOnSingleClick)
        XCTAssertFalse(prefs.sidebarOnRight)
        XCTAssertTrue(prefs.confirmBeforeDelete)
    }

    func testShowSidebarPersists() {
        prefs.showSidebar = true
        XCTAssertTrue(Preferences(defaults: defaults).showSidebar)
    }
```

- [ ] **Step 2: Create a minimal SidebarViewController stub**

Create `Sources/MeditKit/SidebarViewController.swift`:

```swift
import AppKit

/// The file-browser sidebar. This task is a minimal collapsible stub; the outline
/// view and file logic land in later tasks. Holds a reference to its window
/// controller so it can open files / read the active document later.
public final class SidebarViewController: NSViewController {

    private let prefs: Preferences
    weak var windowController: EditorWindowController?

    public init(preferences: Preferences = .shared) {
        self.prefs = preferences
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func loadView() {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        // Minimum sensible sidebar width.
        v.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        self.view = v
    }

    /// Build/teardown the file tree + watchers. Stub for now (Task 5/6 fill in).
    public func activate() {}
    public func deactivate() {}
}
```

- [ ] **Step 3: Host the split view in EditorWindowController**

In `Sources/MeditKit/EditorWindowController.swift`, the init currently does
`window.contentViewController = editor` (around line 42). Replace that with a split
view controller. Find:

```swift
        let editor = EditorViewController(document: document, preferences: preferences)
        self.editor = editor
        editor.newTabActionTarget = self
        window.contentViewController = editor
```

Replace with:

```swift
        let editor = EditorViewController(document: document, preferences: preferences)
        self.editor = editor
        editor.newTabActionTarget = self

        let sidebar = SidebarViewController(preferences: preferences)
        self.sidebar = sidebar

        let split = NSSplitViewController()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.canCollapse = true
        sidebarItem.minimumThickness = 180
        let editorItem = NSSplitViewItem(viewController: editor)
        // Sidebar on the left by default; sidebarOnRight swaps the order.
        if preferences.sidebarOnRight {
            split.addSplitViewItem(editorItem)
            split.addSplitViewItem(sidebarItem)
        } else {
            split.addSplitViewItem(sidebarItem)
            split.addSplitViewItem(editorItem)
        }
        split.splitView.autosaveName = "medit.sidebar.split"
        self.splitViewController = split
        self.sidebarItem = sidebarItem
        sidebar.windowController = self
        window.contentViewController = split
        // Apply initial visibility (default collapsed/off).
        sidebarItem.isCollapsed = !preferences.showSidebar
```

Add stored properties near the other ones (e.g. after `private var editor: EditorViewController!`):

```swift
    private var sidebar: SidebarViewController!
    private var splitViewController: NSSplitViewController!
    private var sidebarItem: NSSplitViewItem!
```

- [ ] **Step 4: Add the Show Sidebar toggle + action + validation**

In `Sources/MeditKit/EditorWindowController.swift`, add (near `toggleStatusBar`):

```swift
    @IBAction public func toggleSidebar(_ sender: Any?) {
        prefs.showSidebar.toggle()
        applySidebarVisibility()
    }

    private func applySidebarVisibility() {
        let show = prefs.showSidebar
        sidebarItem?.isCollapsed = !show
        if show { sidebar?.activate() } else { sidebar?.deactivate() }
    }
```

In `validateMenuItem(_:)`, add a case:

```swift
        case #selector(toggleSidebar(_:)):
            menuItem.state = prefs.showSidebar ? .on : .off
```

- [ ] **Step 5: Add the View → Show Sidebar menu item (⌘⌃0)**

In `Sources/MeditKit/MainMenu.swift`, in `viewMenuItem()`, add near the top of the
View menu (before Show Line Numbers is fine):

```swift
        let sidebar = NSMenuItem(title: "Show Sidebar",
                                 action: #selector(EditorWindowController.toggleSidebar(_:)), keyEquivalent: "0")
        sidebar.keyEquivalentModifierMask = [.command, .control]
        menu.addItem(sidebar)
        menu.addItem(.separator())
```

- [ ] **Step 6: Add the render-regression smoke test**

In `Tests/MeditKitTests/EditorSmokeTests.swift`, add:

```swift
    func testEditorStillRendersWithSplitViewHostingSidebar() {
        let controller = makeWindowController(text: "line one\nline two\nline three")
        guard let window = controller.window else { return XCTFail("no window") }
        window.setFrame(NSRect(x: 0, y: 0, width: 1000, height: 700), display: true)
        controller.showWindow(nil)
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        // The window's contentViewController is now a split view; the editor must
        // still be present and rendering.
        XCTAssertTrue(window.contentViewController is NSSplitViewController)
        if let tv = controller.focusedTextView {
            XCTAssertGreaterThan(tv.frame.width, 100, "editor collapsed under the split view")
            XCTAssertEqual(tv.string, "line one\nline two\nline three")
        } else { XCTFail("no text view") }
    }
```

- [ ] **Step 7: Build, test, commit**

Run: `swift build 2>&1 | grep -E "error:|Build complete"` → `Build complete!`
Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests, with"` → all pass (editor render test green).

```bash
git add Sources/MeditKit/SidebarViewController.swift Sources/MeditKit/EditorWindowController.swift Sources/MeditKit/Preferences.swift Sources/MeditKit/MainMenu.swift Tests/MeditKitTests/PreferencesTests.swift Tests/MeditKitTests/EditorSmokeTests.swift
git commit -m "Host editor in NSSplitViewController with collapsible sidebar (default off)"
```

---

## Task 5: SidebarViewController outline view (render tree + open files)

**Files:**
- Modify: `Sources/MeditKit/SidebarViewController.swift`, `Sources/MeditKit/EditorWindowController.swift`, `Tests/MeditKitTests/EditorSmokeTests.swift`

- [ ] **Step 1: Implement the outline view + roots in SidebarViewController**

Replace the body of `Sources/MeditKit/SidebarViewController.swift` with the full
outline implementation (keeping the init/prefs/windowController members):

```swift
import AppKit

public final class SidebarViewController: NSViewController {

    private let prefs: Preferences
    weak var windowController: EditorWindowController?

    private var scrollView: NSScrollView!
    private(set) var outlineView: NSOutlineView!
    private let dataSource = FileTreeDataSource()
    private var active = false

    public init(preferences: Preferences = .shared) {
        self.prefs = preferences
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func loadView() {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        let outline = NSOutlineView()
        outline.headerView = nil
        outline.rowSizeStyle = .default
        outline.focusRingType = .none
        outline.indentationPerLevel = 14
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.dataSource = dataSource
        outline.delegate = self
        outline.target = self
        outline.action = #selector(outlineSingleClick)
        outline.doubleAction = #selector(outlineDoubleClick)

        scroll.documentView = outline
        self.scrollView = scroll
        self.outlineView = outline

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        self.view = container
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        if prefs.showSidebar { activate() }
    }

    // MARK: Activation (zero-overhead when off)

    public func activate() {
        guard !active else { return }
        active = true
        applyPrefsToDataSource()
        if dataSource.roots.isEmpty, let dir = defaultRootDirectory() {
            dataSource.roots = [FileTreeNode(url: dir)]
        }
        outlineView.reloadData()
    }

    public func deactivate() {
        guard active else { return }
        active = false
        dataSource.roots = []
        outlineView.reloadData()
    }

    /// Parent folder of the active document's file (nil for untitled).
    private func defaultRootDirectory() -> URL? {
        windowController?.currentDocumentFileURL?.deletingLastPathComponent()
    }

    private func applyPrefsToDataSource() {
        dataSource.foldersFirst = prefs.sidebarSortFoldersFirst
        dataSource.ascending = prefs.sidebarSortAscending
        dataSource.showHidden = prefs.showHiddenFiles
    }

    /// Re-read prefs and reload (called when sidebar prefs change).
    public func refreshFromPreferences() {
        guard active else { return }
        applyPrefsToDataSource()
        for root in dataSource.roots { root.invalidateChildren() }
        outlineView.reloadData()
    }

    // MARK: Open

    @objc private func outlineSingleClick() {
        guard prefs.sidebarOpenOnSingleClick else { return }
        openSelected()
    }

    @objc private func outlineDoubleClick() {
        guard !prefs.sidebarOpenOnSingleClick else { return }
        // Double-click a folder toggles expansion; a file opens.
        if let node = outlineView.item(atRow: outlineView.clickedRow) as? FileTreeNode, node.isDirectory {
            if outlineView.isItemExpanded(node) { outlineView.collapseItem(node) }
            else { outlineView.expandItem(node) }
            return
        }
        openSelected()
    }

    private func openSelected() {
        let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileTreeNode, !node.isDirectory else { return }
        NSDocumentController.shared.openDocument(withContentsOf: node.url, display: true) { _, _, _ in }
    }
}

extension SidebarViewController: NSOutlineViewDelegate {
    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileTreeNode else { return nil }
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = (outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? Self.makeCell(id: id)
        cell.textField?.stringValue = node.url.lastPathComponent
        cell.imageView?.image = NSWorkspace.shared.icon(forFile: node.url.path)
        // Emphasize root rows.
        let isRoot = dataSource.roots.contains { $0 === node }
        cell.textField?.font = isRoot ? .boldSystemFont(ofSize: 12) : .systemFont(ofSize: 12)
        return cell
    }

    private static func makeCell(id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        let image = NSImageView()
        image.translatesAutoresizingMaskIntoConstraints = false
        let field = NSTextField(labelWithString: "")
        field.translatesAutoresizingMaskIntoConstraints = false
        field.lineBreakMode = .byTruncatingMiddle
        cell.addSubview(image); cell.addSubview(field)
        cell.imageView = image; cell.textField = field
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 16),
            image.heightAnchor.constraint(equalToConstant: 16),
            field.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        cell.identifier = id
        return cell
    }
}
```

- [ ] **Step 2: Expose the active document's file URL on EditorWindowController**

In `Sources/MeditKit/EditorWindowController.swift`, add:

```swift
    /// The active document's file URL (nil for untitled). Used by the sidebar's
    /// default root.
    var currentDocumentFileURL: URL? { textDocument.fileURL }
```

- [ ] **Step 3: Build, test, commit**

Run: `swift build 2>&1 | grep -E "error:|Build complete"` → `Build complete!`
Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests, with"` → all pass.

```bash
git add Sources/MeditKit/SidebarViewController.swift Sources/MeditKit/EditorWindowController.swift
git commit -m "Sidebar outline view: render roots tree, single/double-click open"
```

- [ ] **Step 4: Add a sidebar smoke test (build over a temp dir)**

In `Tests/MeditKitTests/EditorSmokeTests.swift`, add:

```swift
    func testSidebarActivateBuildsTreeAndDeactivateClears() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("medit-sb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try Data("x".utf8).write(to: tmp.appendingPathComponent("a.txt"))

        let sb = SidebarViewController(preferences: Preferences(defaults: UserDefaults(suiteName: "medit.sb.\(UUID().uuidString)")!))
        sb.loadViewIfNeeded()
        // Seed a root directly and activate.
        sb.setRootForTesting(tmp)
        sb.activate()
        XCTAssertGreaterThan(sb.outlineView.numberOfRows, 0, "tree should have rows after activate")
        sb.deactivate()
        XCTAssertEqual(sb.outlineView.numberOfRows, 0, "deactivate should clear the tree (zero overhead)")
    }
```

Add the test hook to `SidebarViewController`:

```swift
    func setRootForTesting(_ url: URL) {
        dataSource.roots = [FileTreeNode(url: url)]
        applyPrefsToDataSource()
    }
```

Run: `swift test --filter EditorSmokeTests/testSidebarActivateBuildsTreeAndDeactivateClears 2>&1 | grep -E "passed|failed"` → passed.

```bash
git add Sources/MeditKit/SidebarViewController.swift Tests/MeditKitTests/EditorSmokeTests.swift
git commit -m "Test sidebar activate builds tree, deactivate clears it"
```

---

## Task 6: DirectoryWatcher + external refresh + sync-with-active-tab + teardown

**Files:**
- Create: `Sources/MeditKit/DirectoryWatcher.swift`
- Modify: `Sources/MeditKit/SidebarViewController.swift`, `Sources/MeditKit/EditorWindowController.swift`, `Tests/MeditKitTests/EditorSmokeTests.swift`

- [ ] **Step 1: Implement DirectoryWatcher**

Create `Sources/MeditKit/DirectoryWatcher.swift`:

```swift
import Foundation

/// Watches a directory for filesystem changes (writes/renames/deletes within it)
/// using a DispatchSource, and fires `onChange` on the main queue. One per root.
/// The raw FS callback is verified manually; consumers test their own refresh
/// logic.
public final class DirectoryWatcher {

    private let url: URL
    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private let onChange: () -> Void

    public init?(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return nil }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main)
        src.setEventHandler { [weak self] in self?.onChange() }
        src.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 { close(fd) }
            self?.fileDescriptor = -1
        }
        source = src
        src.resume()
    }

    public func stop() {
        source?.cancel()
        source = nil
    }

    deinit { stop() }
}
```

- [ ] **Step 2: Wire watchers into the sidebar (start on activate, stop on deactivate)**

In `Sources/MeditKit/SidebarViewController.swift`, add a watchers store:

```swift
    private var watchers: [DirectoryWatcher] = []
```

In `activate()`, after `outlineView.reloadData()`, start watchers for each root:

```swift
        startWatchers()
```

In `deactivate()`, before clearing roots, stop watchers:

```swift
        stopWatchers()
```

Add the methods:

```swift
    private func startWatchers() {
        stopWatchers()
        for root in dataSource.roots {
            if let w = DirectoryWatcher(url: root.url, onChange: { [weak self] in
                self?.refreshTree()
            }) {
                watchers.append(w)
            }
        }
    }

    private func stopWatchers() {
        watchers.forEach { $0.stop() }
        watchers.removeAll()
    }

    /// Invalidate cached children and reload, preserving expansion where possible.
    public func refreshTree() {
        guard active else { return }
        let expanded = expandedURLs()
        for root in dataSource.roots { invalidateRecursively(root) }
        outlineView.reloadData()
        reexpand(expanded)
    }

    private func invalidateRecursively(_ node: FileTreeNode) {
        node.invalidateChildren()
    }

    private func expandedURLs() -> Set<String> {
        var set = Set<String>()
        for row in 0..<outlineView.numberOfRows {
            if let node = outlineView.item(atRow: row) as? FileTreeNode, outlineView.isItemExpanded(node) {
                set.insert(node.url.path)
            }
        }
        return set
    }

    private func reexpand(_ paths: Set<String>) {
        var row = 0
        while row < outlineView.numberOfRows {
            if let node = outlineView.item(atRow: row) as? FileTreeNode,
               node.isDirectory, paths.contains(node.url.path) {
                outlineView.expandItem(node)
            }
            row += 1
        }
    }
```

- [ ] **Step 3: Sync-with-active-tab — reveal the active file**

In `Sources/MeditKit/SidebarViewController.swift`, add:

```swift
    /// Expand to and select the active document's file in the tree, if it's under
    /// a root and the preference is on.
    public func revealActiveFile() {
        guard active, prefs.syncSidebarWithActiveTab,
              let url = windowController?.currentDocumentFileURL else { return }
        // Find which root contains it.
        guard let root = dataSource.roots.first(where: { url.path.hasPrefix($0.url.path + "/") }) else { return }
        // Walk components, expanding each directory along the way.
        let relative = url.path.dropFirst(root.url.path.count + 1)
        var current = root
        outlineView.expandItem(current)
        var prefix = root.url
        for comp in relative.split(separator: "/").dropLast() {
            prefix.appendPathComponent(String(comp))
            if let next = dataSource.outlineChild(of: current, named: String(comp)) {
                outlineView.expandItem(next)
                current = next
            }
        }
        if let fileNode = dataSource.outlineChild(of: current, named: url.lastPathComponent) {
            let row = outlineView.row(forItem: fileNode)
            if row >= 0 {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outlineView.scrollRowToVisible(row)
            }
        }
    }
```

Add a helper to `FileTreeDataSource`:

```swift
    /// Find a child node of `node` by file name (using current sort/filter).
    func outlineChild(of node: FileTreeNode, named name: String) -> FileTreeNode? {
        childList(of: node).first { $0.url.lastPathComponent == name }
    }
```

(Change `childList` from `private` to `internal` so the data source can expose it.)

Call `revealActiveFile()` when the window becomes the active tab — in
`EditorWindowController`, in `windowDidBecomeKey` (which already exists), add:

```swift
        sidebar?.revealActiveFile()
```

- [ ] **Step 4: Add a teardown smoke test**

In `Tests/MeditKitTests/EditorSmokeTests.swift`, add:

```swift
    func testSidebarDeactivateStopsWatchers() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("medit-sbw-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let sb = SidebarViewController(preferences: Preferences(defaults: UserDefaults(suiteName: "medit.sbw.\(UUID().uuidString)")!))
        sb.loadViewIfNeeded()
        sb.setRootForTesting(tmp)
        sb.activate()
        XCTAssertGreaterThan(sb.watcherCountForTesting, 0, "active sidebar should watch its roots")
        sb.deactivate()
        XCTAssertEqual(sb.watcherCountForTesting, 0, "deactivate must stop all watchers (zero overhead)")
    }
```

Add the hook to `SidebarViewController`:

```swift
    var watcherCountForTesting: Int { watchers.count }
```

- [ ] **Step 5: Build, test, commit**

Run: `swift build 2>&1 | grep -E "error:|Build complete"` → `Build complete!`
Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests, with"` → all pass.

```bash
git add Sources/MeditKit/DirectoryWatcher.swift Sources/MeditKit/SidebarViewController.swift Sources/MeditKit/FileTreeDataSource.swift Sources/MeditKit/EditorWindowController.swift Tests/MeditKitTests/EditorSmokeTests.swift
git commit -m "Add DirectoryWatcher, external refresh, reveal-active-file, teardown"
```

---

## Task 7: File operations context menu

**Files:**
- Modify: `Sources/MeditKit/SidebarViewController.swift`

- [ ] **Step 1: Add a context menu to the outline view**

In `Sources/MeditKit/SidebarViewController.swift`, in `loadView()` after the outline
is configured, add:

```swift
        let menu = NSMenu()
        menu.delegate = self
        outline.menu = menu
```

Make the controller an `NSMenuDelegate` and build the menu based on the clicked
row. Add:

```swift
extension SidebarViewController: NSMenuDelegate {
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = outlineView.clickedRow
        let node = (row >= 0) ? outlineView.item(atRow: row) as? FileTreeNode : nil

        func item(_ title: String, _ sel: Selector) -> NSMenuItem {
            let mi = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            mi.target = self
            return mi
        }
        // Target directory for new items: the clicked folder, or the clicked
        // file's parent, or the first root.
        menu.addItem(item("New File", #selector(ctxNewFile)))
        menu.addItem(item("New Folder", #selector(ctxNewFolder)))
        if node != nil {
            menu.addItem(.separator())
            menu.addItem(item("Rename…", #selector(ctxRename)))
            menu.addItem(item("Move to Trash", #selector(ctxDelete)))
            menu.addItem(.separator())
            menu.addItem(item("Reveal in Finder", #selector(ctxReveal)))
        }
    }
}
```

- [ ] **Step 2: Implement the context actions**

Add to `SidebarViewController`:

```swift
    private func targetDirectory() -> URL? {
        let row = outlineView.clickedRow
        if row >= 0, let node = outlineView.item(atRow: row) as? FileTreeNode {
            return node.isDirectory ? node.url : node.url.deletingLastPathComponent()
        }
        return dataSource.roots.first?.url
    }

    @objc private func ctxNewFile() {
        guard let dir = targetDirectory() else { return }
        do { _ = try FileSystemOperations.newFile(in: dir); refreshTree() }
        catch { NSApp.presentError(error) }
    }

    @objc private func ctxNewFolder() {
        guard let dir = targetDirectory() else { return }
        do { _ = try FileSystemOperations.newFolder(in: dir); refreshTree() }
        catch { NSApp.presentError(error) }
    }

    @objc private func ctxRename() {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileTreeNode else { return }
        let alert = NSAlert()
        alert.messageText = "Rename"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = node.url.lastPathComponent
        alert.accessoryView = field
        if alert.runModal() == .alertFirstButtonReturn {
            do { _ = try FileSystemOperations.rename(node.url, to: field.stringValue); refreshTree() }
            catch { NSApp.presentError(error) }
        }
    }

    @objc private func ctxDelete() {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileTreeNode else { return }
        if prefs.confirmBeforeDelete {
            let alert = NSAlert()
            alert.messageText = "Move “\(node.url.lastPathComponent)” to the Trash?"
            alert.addButton(withTitle: "Move to Trash")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        do { try FileSystemOperations.moveToTrash(node.url); refreshTree() }
        catch { NSApp.presentError(error) }
    }

    @objc private func ctxReveal() {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileTreeNode else { return }
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }
```

- [ ] **Step 3: Build, test, commit**

Run: `swift build 2>&1 | grep -E "error:|Build complete"` → `Build complete!`
Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests, with"` → all pass (no new tests; FileSystemOperations is already covered by Task 2; this is UI wiring).

```bash
git add Sources/MeditKit/SidebarViewController.swift
git commit -m "Add sidebar context menu: New File/Folder, Rename, Trash, Reveal"
```

---

## Task 8: Drag-to-move + Open Folder / Remove Folder (multi-root) + persistence

**Files:**
- Modify: `Sources/MeditKit/SidebarViewController.swift`, `Sources/MeditKit/EditorWindowController.swift`, `Sources/MeditKit/MainMenu.swift`, `Sources/MeditKit/Preferences.swift`, `Tests/MeditKitTests/PreferencesTests.swift`

- [ ] **Step 1: Register drag types + implement drag data-source methods**

In `Sources/MeditKit/SidebarViewController.swift`, in `loadView()` after the outline
setup:

```swift
        outline.registerForDraggedTypes([.fileURL])
```

Add the drag methods (on `FileTreeDataSource` is cleaner, but since acceptDrop must
trigger a tree refresh on the controller, implement them on `SidebarViewController`
as the outline's dataSource is `FileTreeDataSource` — so instead set the outline's
dragging via the delegate path). Implement these on `FileTreeDataSource`:

```swift
    // MARK: Drag & drop (internal moves)

    public func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        (item as? FileTreeNode)?.url as NSURL?
    }

    public func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo,
                            proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        // Only allow dropping onto a directory node (not between rows).
        guard let target = item as? FileTreeNode, target.isDirectory, index == NSOutlineViewDropOnItemIndex else {
            return []
        }
        return .move
    }

    public var onDropMove: ((_ sources: [URL], _ destination: URL) -> Void)?

    public func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo,
                            item: Any?, childIndex index: Int) -> Bool {
        guard let target = item as? FileTreeNode, target.isDirectory else { return false }
        var sources: [URL] = []
        info.enumerateDraggingItems(options: [], for: outlineView, classes: [NSURL.self], searchOptions: [:]) { drag, _, _ in
            if let url = drag.item as? URL { sources.append(url) }
        }
        guard !sources.isEmpty else { return false }
        onDropMove?(sources, target.url)
        return true
    }
```

In `SidebarViewController.loadView()`, after creating `dataSource`, wire the move:

```swift
        dataSource.onDropMove = { [weak self] sources, dest in
            guard let self else { return }
            for src in sources {
                do { _ = try FileSystemOperations.move(src, into: dest) }
                catch { NSApp.presentError(error) }
            }
            self.refreshTree()
        }
```

- [ ] **Step 2: Add the rootPaths preference (persistence) + Open/Remove Folder**

In `Sources/MeditKit/Preferences.swift`, add to `Key`:

```swift
        static let sidebarRootPaths = "sidebarRootPaths"
```

Add to `registerDefaults()`:

```swift
            Key.sidebarRootPaths: [String](),
```

Add the property (array of paths):

```swift
    public var sidebarRootPaths: [String] {
        get { defaults.stringArray(forKey: Key.sidebarRootPaths) ?? [] }
        set { defaults.set(newValue, forKey: Key.sidebarRootPaths); didChange() }
    }
```

In `Tests/MeditKitTests/PreferencesTests.swift`:

```swift
    func testSidebarRootPathsPersist() {
        prefs.sidebarRootPaths = ["/tmp/a", "/tmp/b"]
        XCTAssertEqual(Preferences(defaults: defaults).sidebarRootPaths, ["/tmp/a", "/tmp/b"])
    }
```

- [ ] **Step 3: Sidebar root management + restore from prefs**

In `Sources/MeditKit/SidebarViewController.swift`, change `activate()` so it
restores persisted roots (falling back to the active file's dir):

Replace the root-seeding block in `activate()`:

```swift
        if dataSource.roots.isEmpty, let dir = defaultRootDirectory() {
            dataSource.roots = [FileTreeNode(url: dir)]
        }
```

with:

```swift
        if dataSource.roots.isEmpty {
            let saved = prefs.sidebarRootPaths.map { URL(fileURLWithPath: $0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            if !saved.isEmpty {
                dataSource.roots = saved.map { FileTreeNode(url: $0) }
            } else if let dir = defaultRootDirectory() {
                dataSource.roots = [FileTreeNode(url: dir)]
            }
        }
```

Add root add/remove:

```swift
    public func addRoot(_ url: URL) {
        guard !dataSource.roots.contains(where: { $0.url.path == url.path }) else { return }
        dataSource.roots.append(FileTreeNode(url: url))
        persistRoots()
        if active { startWatchers(); outlineView.reloadData() }
    }

    public func removeRoot(_ node: FileTreeNode) {
        dataSource.roots.removeAll { $0 === node }
        persistRoots()
        if active { startWatchers(); outlineView.reloadData() }
    }

    private func persistRoots() {
        prefs.sidebarRootPaths = dataSource.roots.map { $0.url.path }
    }
```

Add "Remove Folder from Sidebar" to the context menu for root rows — in
`menuNeedsUpdate`, after the Reveal item, add:

```swift
        if let node, dataSource.roots.contains(where: { $0 === node }) {
            menu.addItem(.separator())
            menu.addItem(item("Remove Folder from Sidebar", #selector(ctxRemoveRoot)))
        }
```

And the action:

```swift
    @objc private func ctxRemoveRoot() {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileTreeNode else { return }
        removeRoot(node)
    }
```

- [ ] **Step 4: File → Open Folder…**

In `Sources/MeditKit/EditorWindowController.swift`, add:

```swift
    @IBAction public func openFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !prefs.showSidebar { prefs.showSidebar = true; applySidebarVisibility() }
        sidebar?.activate()
        sidebar?.addRoot(url)
    }
```

In `Sources/MeditKit/MainMenu.swift`, in `fileMenuItem()` after "Open…":

```swift
        let openFolder = NSMenuItem(title: "Open Folder…",
                                    action: #selector(EditorWindowController.openFolder(_:)), keyEquivalent: "o")
        openFolder.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(openFolder)
```

- [ ] **Step 5: Build, test, commit**

Run: `swift build 2>&1 | grep -E "error:|Build complete"` → `Build complete!`
Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests, with"` → all pass.

```bash
git add Sources/MeditKit/SidebarViewController.swift Sources/MeditKit/FileTreeDataSource.swift Sources/MeditKit/EditorWindowController.swift Sources/MeditKit/MainMenu.swift Sources/MeditKit/Preferences.swift Tests/MeditKitTests/PreferencesTests.swift
git commit -m "Add drag-to-move, Open Folder / Remove Folder, root persistence"
```

---

## Task 9: Settings "Sidebar" section + View toggles

**Files:**
- Modify: `Sources/MeditKit/PreferencesWindowController.swift`, `Sources/MeditKit/MainMenu.swift`, `Sources/MeditKit/EditorWindowController.swift`

- [ ] **Step 1: Add the View-menu toggles (Show Hidden Files, Reveal Active File)**

In `Sources/MeditKit/MainMenu.swift`, in `viewMenuItem()` after the Show Invisibles
item:

```swift
        let hiddenFiles = NSMenuItem(title: "Show Hidden Files",
                                     action: #selector(EditorWindowController.toggleHiddenFiles(_:)), keyEquivalent: "")
        menu.addItem(hiddenFiles)
        let revealActive = NSMenuItem(title: "Reveal Active File in Sidebar",
                                      action: #selector(EditorWindowController.toggleRevealActiveFile(_:)), keyEquivalent: "")
        menu.addItem(revealActive)
```

In `Sources/MeditKit/EditorWindowController.swift`, add the actions + validation:

```swift
    @IBAction public func toggleHiddenFiles(_ sender: Any?) {
        prefs.showHiddenFiles.toggle()
        sidebar?.refreshFromPreferences()
    }

    @IBAction public func toggleRevealActiveFile(_ sender: Any?) {
        prefs.syncSidebarWithActiveTab.toggle()
        if prefs.syncSidebarWithActiveTab { sidebar?.revealActiveFile() }
    }
```

In `validateMenuItem(_:)`, add:

```swift
        case #selector(toggleHiddenFiles(_:)):
            menuItem.state = prefs.showHiddenFiles ? .on : .off
        case #selector(toggleRevealActiveFile(_:)):
            menuItem.state = prefs.syncSidebarWithActiveTab ? .on : .off
```

- [ ] **Step 2: Add the Settings "Sidebar" checkboxes**

In `Sources/MeditKit/PreferencesWindowController.swift` (read the current file to
match the pattern; it already uses a scroll view from 1.3, so adding rows is safe).
Add properties:

```swift
    private var sortFoldersFirstCheck: NSButton!
    private var sortAscendingCheck: NSButton!
    private var openOnSingleClickCheck: NSButton!
    private var sidebarOnRightCheck: NSButton!
    private var confirmDeleteCheck: NSButton!
```

In `buildUI()`, create the five checkboxes (alongside the others):

```swift
        sortFoldersFirstCheck = NSButton(checkboxWithTitle: "Sidebar: sort folders first",
                                         target: self, action: #selector(sidebarCheckChanged))
        sortAscendingCheck = NSButton(checkboxWithTitle: "Sidebar: sort A→Z (off = Z→A)",
                                      target: self, action: #selector(sidebarCheckChanged))
        openOnSingleClickCheck = NSButton(checkboxWithTitle: "Sidebar: open on single click",
                                          target: self, action: #selector(sidebarCheckChanged))
        sidebarOnRightCheck = NSButton(checkboxWithTitle: "Sidebar on the right",
                                       target: self, action: #selector(sidebarCheckChanged))
        confirmDeleteCheck = NSButton(checkboxWithTitle: "Sidebar: confirm before deleting",
                                      target: self, action: #selector(sidebarCheckChanged))
        [sortFoldersFirstCheck, sortAscendingCheck, openOnSingleClickCheck,
         sidebarOnRightCheck, confirmDeleteCheck].forEach { $0?.translatesAutoresizingMaskIntoConstraints = false }
```

Add them to the `content.addSubview(...)` list, and chain them in the constraints
below the external-change popup row (anchor each 10pt below the previous,
leading-aligned to `lineNumbersCheck`). The scroll view already handles overflow.

In `syncFromPrefs()`:

```swift
        sortFoldersFirstCheck.state = prefs.sidebarSortFoldersFirst ? .on : .off
        sortAscendingCheck.state = prefs.sidebarSortAscending ? .on : .off
        openOnSingleClickCheck.state = prefs.sidebarOpenOnSingleClick ? .on : .off
        sidebarOnRightCheck.state = prefs.sidebarOnRight ? .on : .off
        confirmDeleteCheck.state = prefs.confirmBeforeDelete ? .on : .off
```

Add the action:

```swift
    @objc private func sidebarCheckChanged(_ sender: NSButton) {
        prefs.sidebarSortFoldersFirst = sortFoldersFirstCheck.state == .on
        prefs.sidebarSortAscending = sortAscendingCheck.state == .on
        prefs.sidebarOpenOnSingleClick = openOnSingleClickCheck.state == .on
        prefs.sidebarOnRight = sidebarOnRightCheck.state == .on
        prefs.confirmBeforeDelete = confirmDeleteCheck.state == .on
    }
```

- [ ] **Step 3: Make the sidebar observe pref changes (sort + side live)**

In `Sources/MeditKit/SidebarViewController.swift`, observe the change notification
in `viewDidLoad`:

```swift
        NotificationCenter.default.addObserver(self, selector: #selector(prefsChanged),
                                               name: Preferences.didChangeNotification, object: nil)
```

Add:

```swift
    @objc private func prefsChanged() {
        guard active else { return }
        refreshFromPreferences()
    }

    deinit { NotificationCenter.default.removeObserver(self) }
```

For `sidebarOnRight` (which reorders split items), handle it in
`EditorWindowController` by observing the pref and re-ordering — add in the existing
`preferencesChanged`-style path or a dedicated observer. Simplest: in
`EditorWindowController.init` after creating the split, store the current side; add
a small observer:

```swift
    @objc private func applySidebarSideIfChanged() {
        guard let split = splitViewController, let sidebarItem = sidebarItem else { return }
        let wantRight = prefs.sidebarOnRight
        let isRight = split.splitViewItems.last === sidebarItem
        if wantRight != isRight {
            split.removeSplitViewItem(sidebarItem)
            if wantRight { split.addSplitViewItem(sidebarItem) }
            else { split.insertSplitViewItem(sidebarItem, at: 0) }
        }
    }
```

Register it in `init` (after `window.contentViewController = split`):

```swift
        NotificationCenter.default.addObserver(self, selector: #selector(applySidebarSideIfChanged),
                                               name: Preferences.didChangeNotification, object: nil)
```

- [ ] **Step 4: Build, test, commit**

Run: `swift build 2>&1 | grep -E "error:|Build complete"` → `Build complete!`
Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests, with"` → all pass.

```bash
git add Sources/MeditKit/PreferencesWindowController.swift Sources/MeditKit/MainMenu.swift Sources/MeditKit/EditorWindowController.swift Sources/MeditKit/SidebarViewController.swift
git commit -m "Add Settings Sidebar section + Show Hidden/Reveal Active View toggles"
```

---

## Task 10: Version bump to 1.4.0 + README + tag

**Files:**
- Modify: `App/Info.plist`, `App/medit.xcodeproj/project.pbxproj`, `README.md`

- [ ] **Step 1: Bump version strings**

In `App/Info.plist`, change `CFBundleShortVersionString` from `1.3.0` to `1.4.0`.
In `App/medit.xcodeproj/project.pbxproj`, change BOTH `MARKETING_VERSION = 1.3.0;`
to `1.4.0`.

- [ ] **Step 2: Update README**

In `README.md`, add to the **Features** list:

```markdown
- **Sidebar file browser** (optional, off by default — ⌘⌃0) — a multi-root file
  tree: open folders, navigate, and manage files (New File/Folder, Rename, Move to
  Trash, Reveal in Finder, drag-to-move). Double-click to open a file in a tab.
  Lots of toggles (folders-first sort, sort direction, single-click open, sidebar
  side, confirm-before-delete, show hidden files, reveal active file). Zero
  overhead when hidden.
```

Add to the keyboard-shortcuts table:

```markdown
| ⌘⌃0 | Toggle sidebar |
| ⇧⌘O | Open Folder… |
```

- [ ] **Step 3: Build, full test, app build (no launch)**

Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests, with"` → all pass.
Run: `cd App && xcodebuild -project medit.xcodeproj -scheme medit -configuration Debug -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"` → `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add App/Info.plist App/medit.xcodeproj/project.pbxproj README.md
git commit -m "Bump version to 1.4.0; document the sidebar"
```

- [ ] **Step 5: Tag (GATED — only after the user confirms)**

> Do NOT tag/merge/reinstall until the user approves (a live instance may be
> running). When approved:

```bash
git tag -a v1.4.0 -m "medit 1.4.0 — optional multi-root sidebar file browser."
git describe --tags
```

---

## Self-Review

**Spec coverage:**
- Optional, default-OFF, zero-overhead (teardown) → Task 4 (split + toggle) + Task 6
  (watcher teardown test). ✓
- Multi-root tree → Task 1 (node) + Task 3 (data source root level) + Task 8 (add/
  remove roots). ✓
- FileSystemOperations create/rename/move/trash + conflicts → Task 2. ✓
- Configurable sort (folders-first, ascending) + hidden filter → Task 1 + Task 9
  toggles. ✓
- Single/double-click open (toggle single) → Task 5. ✓
- DirectoryWatcher external refresh → Task 6. ✓
- Reveal-active-file (sync toggle) → Task 6. ✓
- Context menu (New/Rename/Trash w/ confirm/Reveal) → Task 7. ✓
- Drag-to-move (reject descendant/collision) → Task 8 + Task 2 logic. ✓
- Open Folder / Remove Folder + persistence → Task 8. ✓
- Sidebar-on-right → Task 4 (init) + Task 9 (live swap). ✓
- All 8 toggles + rootPaths persistence → Tasks 4/8/9. ✓
- Render regression → Task 4 smoke test + retained EditorSmokeTests. ✓
- Version 1.4.0 + README + tag → Task 10. ✓

**Placeholder scan:** No TBD/TODO. The "read the file first to match the pattern"
notes (PreferencesWindowController layout) are concrete integration guidance.

**Type consistency:** `FileTreeNode.children(foldersFirst:ascending:showHidden:)` +
`.invalidateChildren()` + `.sort(...)`; `FileSystemOperations.newFile/newFolder/
rename/move/moveToTrash` + `OpError`; `FileTreeDataSource.roots/foldersFirst/
ascending/showHidden` + outline methods + `outlineChild(of:named:)` + `onDropMove`;
`SidebarViewController.activate()/deactivate()/refreshTree()/refreshFromPreferences()
/revealActiveFile()/addRoot/removeRoot` + test hooks; `EditorWindowController`
`toggleSidebar/openFolder/toggleHiddenFiles/toggleRevealActiveFile`,
`currentDocumentFileURL`, `applySidebarVisibility`. Preference names match across
Preferences, the window controller, the settings UI, and tests.
