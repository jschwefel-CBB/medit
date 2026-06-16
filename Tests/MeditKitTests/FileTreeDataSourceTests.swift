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
