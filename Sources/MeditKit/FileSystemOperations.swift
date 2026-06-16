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
