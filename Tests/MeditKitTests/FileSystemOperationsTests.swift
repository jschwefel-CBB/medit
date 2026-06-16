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
