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
        guard let node = item as? FileTreeNode, node.isDirectory else { return false }
        // An empty directory (after hidden-file filtering) is not expandable — no
        // disclosure triangle for a folder with nothing to show.
        return !childList(of: node).isEmpty
    }

    // MARK: Drag & drop

    /// Called for internal moves (a file dragged from one folder to another within the sidebar).
    public var onDropMove: ((_ sources: [URL], _ destination: URL) -> Void)?

    /// Called when external files are dropped onto the sidebar (open them as tabs).
    public var onOpenFiles: ((_ urls: [URL]) -> Void)?

    public func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        (item as? FileTreeNode)?.url as NSURL?
    }

    public func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo,
                            proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        // External drag (from Finder/outside the app) — accept anywhere as an open.
        if info.draggingSource == nil {
            return .copy
        }
        // Internal move: only onto a directory node.
        guard let target = item as? FileTreeNode, target.isDirectory, index == NSOutlineViewDropOnItemIndex else {
            return []
        }
        return .move
    }

    public func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo,
                            item: Any?, childIndex index: Int) -> Bool {
        // External drag — open the files as tabs.
        if info.draggingSource == nil {
            var urls: [URL] = []
            let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
            if let read = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL] {
                urls = read.filter { $0.isFileURL }
            }
            if urls.isEmpty,
               let names = info.draggingPasteboard.propertyList(
                   forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
                urls = names.map { URL(fileURLWithPath: $0) }
            }
            guard !urls.isEmpty else { return false }
            onOpenFiles?(urls)
            return true
        }
        // Internal move.
        guard let target = item as? FileTreeNode, target.isDirectory else { return false }
        var sources: [URL] = []
        info.enumerateDraggingItems(options: [], for: outlineView, classes: [NSURL.self], searchOptions: [:]) { drag, _, _ in
            if let url = drag.item as? URL { sources.append(url) }
        }
        guard !sources.isEmpty else { return false }
        onDropMove?(sources, target.url)
        return true
    }
}
