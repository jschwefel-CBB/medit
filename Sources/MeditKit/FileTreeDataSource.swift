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

    func childList(of node: FileTreeNode) -> [FileTreeNode] {
        node.children(foldersFirst: foldersFirst, ascending: ascending, showHidden: showHidden)
    }

    /// Find a child node of `node` by file name (using current sort/filter).
    func outlineChild(of node: FileTreeNode, named name: String) -> FileTreeNode? {
        childList(of: node).first { $0.url.lastPathComponent == name }
    }

    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? FileTreeNode else { return roots.count }
        return childList(of: node).count
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? FileTreeNode else { return roots[index] }
        return childList(of: node)[index]
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FileTreeNode)?.isDirectory ?? false
    }
}
