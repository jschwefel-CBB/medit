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
