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

    func testRecursiveInvalidationClearsDeepCache() {
        // Build root/sub and cache both levels, holding the SAME node references
        // the sidebar keeps across refreshes.
        let sub = root.appendingPathComponent("sub", isDirectory: true)
        try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let node = FileTreeNode(url: root)
        guard let subNode = node.children(foldersFirst: true, ascending: true, showHidden: false)
            .first(where: { $0.url.lastPathComponent == "sub" }) else { return XCTFail("no sub") }
        // Cache sub's (currently empty) children.
        XCTAssertTrue(subNode.children(foldersFirst: true, ascending: true, showHidden: false).isEmpty)

        // Create a folder inside sub on disk.
        try? FileManager.default.createDirectory(at: sub.appendingPathComponent("deep"), withIntermediateDirectories: false)

        // The retained subNode still serves its stale (empty) cache...
        XCTAssertTrue(subNode.children(foldersFirst: true, ascending: true, showHidden: false).isEmpty,
                      "stale cache should not yet show the new folder")

        // ...until a recursive invalidation from the root clears the whole subtree.
        node.invalidateChildrenRecursively()
        let deep = subNode.children(foldersFirst: true, ascending: true, showHidden: false)
            .map { $0.url.lastPathComponent }
        XCTAssertTrue(deep.contains("deep"),
                      "recursive invalidation should clear the deep cache so the new folder appears")
    }
}
