import AppKit

/// The file-browser sidebar: an NSOutlineView over a multi-root file tree. Owns
/// the roots and (in later tasks) file watchers, the context menu, and drag-drop.
/// Opens files into tabs via NSDocumentController. Builds its tree only when
/// active (the sidebar is shown), so it imposes zero overhead when hidden.
public final class SidebarViewController: NSViewController {

    private let prefs: Preferences
    weak var windowController: EditorWindowController?

    private var scrollView: NSScrollView!
    private(set) var outlineView: NSOutlineView!
    private var recentFilesView: RecentFilesView!
    private var paneSwitcher: NSSegmentedControl!
    private let dataSource = FileTreeDataSource()
    private var active = false
    private var watchers: [DirectoryWatcher] = []
    /// Root URLs we're currently holding security-scoped access to (sandbox).
    private var accessedRootURLs: Set<URL> = []

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
        outline.setAccessibilityIdentifier("sidebarOutline")

        let menu = NSMenu()
        menu.delegate = self
        outline.menu = menu
        outline.registerForDraggedTypes([.fileURL])

        dataSource.onDropMove = { [weak self] sources, dest in
            guard let self else { return }
            for src in sources {
                do { _ = try FileSystemOperations.move(src, into: dest) }
                catch { NSApp.presentError(error) }
            }
            self.refreshTree()
        }

        scroll.documentView = outline
        self.scrollView = scroll
        self.outlineView = outline

        // Recent Files list (alternate sidebar pane).
        let recent = RecentFilesView(preferences: prefs)
        recent.delegate = self
        self.recentFilesView = recent

        // Pane switcher: Folders | Recent.
        let switcher = NSSegmentedControl(labels: ["Folders", "Recent"],
                                          trackingMode: .selectOne,
                                          target: self, action: #selector(paneSwitcherChanged))
        switcher.translatesAutoresizingMaskIntoConstraints = false
        switcher.segmentStyle = .automatic
        switcher.setAccessibilityIdentifier("sidebarPaneSwitcher")
        self.paneSwitcher = switcher

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        container.addSubview(switcher)
        container.addSubview(scroll)
        container.addSubview(recent)
        NSLayoutConstraint.activate([
            switcher.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            switcher.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            switcher.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),

            scroll.topAnchor.constraint(equalTo: switcher.bottomAnchor, constant: 6),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            recent.topAnchor.constraint(equalTo: scroll.topAnchor),
            recent.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            recent.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            recent.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        self.view = container
        applyPane(prefs.sidebarPane == "recent" ? .recent : .folders)
    }

    // MARK: Pane switching (Folders | Recent)

    public enum Pane: String { case folders, recent }
    private(set) var pane: Pane = .folders

    @objc private func paneSwitcherChanged() {
        let idx = paneSwitcher?.selectedSegment ?? 0
        setPane(idx == 1 ? .recent : .folders)
    }

    /// Switch the sidebar between the folder tree and the recent-files list.
    public func setPane(_ pane: Pane) {
        guard pane != self.pane else { return }
        applyPane(pane)
        prefs.sidebarPane = pane.rawValue
    }

    private func applyPane(_ pane: Pane) {
        self.pane = pane
        paneSwitcher?.selectedSegment = (pane == .recent) ? 1 : 0
        scrollView?.isHidden = (pane == .recent)
        recentFilesView?.isHidden = (pane != .recent)
        if pane == .recent { recentFilesView?.reload() }
    }

    public func togglePane() { setPane(pane == .folders ? .recent : .folders) }
    public var currentPaneForTesting: Pane { pane }
    public var folderPaneHiddenForTesting: Bool { scrollView?.isHidden ?? false }

    public override func viewDidLoad() {
        super.viewDidLoad()
        if prefs.showSidebar { activate() }
        NotificationCenter.default.addObserver(self, selector: #selector(prefsChanged),
                                               name: Preferences.didChangeNotification, object: nil)
    }

    @objc private func prefsChanged() {
        guard active else { return }
        refreshFromPreferences()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopAllRootAccess()
    }

    // MARK: Activation (zero-overhead when off)

    public func activate() {
        guard !active else { return }
        active = true
        applyPrefsToDataSource()
        if dataSource.roots.isEmpty {
            restoreRootsFromBookmarks()
        }
        outlineView.reloadData()
        startWatchers()
        // App sandbox: with no granted folders, the tree is necessarily empty —
        // prompt the user to choose one (the open panel IS the grant). Deferred so
        // it doesn't block the toggle / launch.
        if dataSource.roots.isEmpty {
            DispatchQueue.main.async { [weak self] in self?.promptForRootIfEmpty() }
        }
    }

    /// Resolve saved security-scoped bookmarks into accessible roots.
    private func restoreRootsFromBookmarks() {
        var restored: [FileTreeNode] = []
        var keptBookmarks: [Data] = []
        for data in prefs.sidebarRootBookmarks {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data,
                                     options: [.withSecurityScope],
                                     relativeTo: nil,
                                     bookmarkDataIsStale: &stale) else { continue }
            guard url.startAccessingSecurityScopedResource() else { continue }
            accessedRootURLs.insert(url)
            restored.append(FileTreeNode(url: url))
            // Refresh a stale bookmark so it keeps resolving next launch.
            if stale, let fresh = try? url.bookmarkData(options: [.withSecurityScope]) {
                keptBookmarks.append(fresh)
            } else {
                keptBookmarks.append(data)
            }
        }
        dataSource.roots = restored
        if keptBookmarks != prefs.sidebarRootBookmarks {
            prefs.sidebarRootBookmarks = keptBookmarks
        }
    }

    /// Show an open panel to choose a folder when the sidebar is empty.
    private func promptForRootIfEmpty() {
        guard active, dataSource.roots.isEmpty, let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        panel.message = "Choose a folder to show in the sidebar."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.addRoot(url)
        }
    }

    // MARK: Root management (multi-root)

    public func addRoot(_ url: URL) {
        // Normalize so the same folder added via two code paths (e.g. AppKit's
        // openFiles plus the --open-folder hook, which may differ only by a
        // trailing slash) is deduped to a single root.
        let target = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard !dataSource.roots.contains(where: {
            $0.url.standardizedFileURL.resolvingSymlinksInPath().path == target
        }) else { return }
        // The open panel granted access; hold it and bookmark it for next launch.
        if url.startAccessingSecurityScopedResource() {
            accessedRootURLs.insert(url)
        }
        dataSource.roots.append(FileTreeNode(url: url))
        persistRoots()
        if active { startWatchers(); outlineView.reloadData() }
    }

    public func removeRoot(_ node: FileTreeNode) {
        if accessedRootURLs.contains(node.url) {
            node.url.stopAccessingSecurityScopedResource()
            accessedRootURLs.remove(node.url)
        }
        dataSource.roots.removeAll { $0 === node }
        persistRoots()
        if active { startWatchers(); outlineView.reloadData() }
    }

    /// Store a security-scoped bookmark per root so they reopen with access.
    private func persistRoots() {
        prefs.sidebarRootBookmarks = dataSource.roots.compactMap {
            try? $0.url.bookmarkData(options: [.withSecurityScope])
        }
    }

    private func stopAllRootAccess() {
        for url in accessedRootURLs { url.stopAccessingSecurityScopedResource() }
        accessedRootURLs.removeAll()
    }

    public func deactivate() {
        guard active else { return }
        active = false
        stopWatchers()
        stopAllRootAccess()
        dataSource.roots = []
        outlineView.reloadData()
    }

    // MARK: Watching + refresh

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
        // Invalidate the WHOLE tree, not just roots — a file/folder created or
        // moved inside any subdirectory must be picked up, not only top-level ones.
        for root in dataSource.roots { root.invalidateChildrenRecursively() }
        outlineView.reloadData()
        reexpand(expanded)
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

    /// Expand to and select the active document's file in the tree, if it's under
    /// a root and the preference is on.
    public func revealActiveFile() {
        guard active, prefs.syncSidebarWithActiveTab,
              let url = windowController?.currentDocumentFileURL else { return }
        guard let root = dataSource.roots.first(where: { url.path.hasPrefix($0.url.path + "/") }) else { return }
        let relative = url.path.dropFirst(root.url.path.count + 1)
        var current = root
        outlineView.expandItem(current)
        for comp in relative.split(separator: "/").dropLast() {
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
        // Open in a tab in this window (keeps the sidebar in place) rather than
        // spawning a separate window via NSDocumentController.openDocument.
        windowController?.openFile(at: node.url)
    }

    // MARK: Test hooks

    func setRootForTesting(_ url: URL) {
        dataSource.roots = [FileTreeNode(url: url)]
        applyPrefsToDataSource()
    }

    var watcherCountForTesting: Int { watchers.count }
}

extension SidebarViewController: RecentFilesViewDelegate {
    public func recentFiles(_ view: RecentFilesView, didActivate url: URL) {
        windowController?.openFile(at: url)
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

// MARK: - Context menu

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
        guard let node else {
            // Empty space (no item clicked): the only file action is opening a
            // folder to add as a root.
            menu.addItem(item("Open Folder…", #selector(ctxOpenFolder)))
            return
        }

        // "Open" for a clicked FILE (folders open/collapse via the disclosure
        // triangle, so an Open item only makes sense for files).
        if !node.isDirectory {
            menu.addItem(item("Open", #selector(ctxOpen)))
            menu.addItem(.separator())
        }
        // New items are created inside the clicked folder (or the clicked file's
        // parent), per targetDirectory().
        menu.addItem(item("New File", #selector(ctxNewFile)))
        menu.addItem(item("New Folder", #selector(ctxNewFolder)))
        menu.addItem(.separator())
        menu.addItem(item("Rename…", #selector(ctxRename)))
        menu.addItem(item("Move to Trash", #selector(ctxDelete)))
        menu.addItem(.separator())
        menu.addItem(item("Reveal in Finder", #selector(ctxReveal)))
        if dataSource.roots.contains(where: { $0 === node }) {
            menu.addItem(.separator())
            menu.addItem(item("Remove Folder from Sidebar", #selector(ctxRemoveRoot)))
        }
    }
}

extension SidebarViewController {

    /// Target directory for new items: INSIDE the clicked folder, or the clicked
    /// file's parent folder. Returns nil when nothing is clicked (the empty-space
    /// context menu offers only "Open Folder…", so New File/Folder never run
    /// without a clicked item).
    private func targetDirectory() -> URL? {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileTreeNode else { return nil }
        return node.isDirectory ? node.url : node.url.deletingLastPathComponent()
    }

    @objc fileprivate func ctxNewFile() {
        guard let dir = targetDirectory() else { return }
        do {
            let url = try FileSystemOperations.newFile(in: dir)
            refreshTree()
            selectByPath(url)
            beginRename(url)   // drop straight into naming the new file
        }
        catch { NSApp.presentError(error) }
    }

    @objc fileprivate func ctxNewFolder() {
        guard let dir = targetDirectory() else { return }
        do {
            let url = try FileSystemOperations.newFolder(in: dir)
            refreshTree()
            selectByPath(url)
            beginRename(url)   // drop straight into naming the new folder
        }
        catch { NSApp.presentError(error) }
    }

    /// Select the row whose node matches `url` by PATH (identity-independent, so
    /// it works after reloadData churns node instances). Expands the clicked
    /// folder if needed to bring the new child into view, but does not force-
    /// expand unrelated collapsed parents.
    private func selectByPath(_ url: URL) {
        // Ensure the parent directory is expanded so the new child has a row.
        let parent = url.deletingLastPathComponent()
        for row in 0..<outlineView.numberOfRows {
            if let node = outlineView.item(atRow: row) as? FileTreeNode,
               node.isDirectory, node.url.path == parent.path {
                outlineView.expandItem(node)
                break
            }
        }
        for row in 0..<outlineView.numberOfRows {
            if let node = outlineView.item(atRow: row) as? FileTreeNode, node.url.path == url.path {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outlineView.scrollRowToVisible(row)
                return
            }
        }
    }

    @objc fileprivate func ctxRename() {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileTreeNode else { return }
        beginRename(node.url)
    }

    /// Present the rename dialog for the item at `url`, pre-filled with its name
    /// (text selected so the user can type a replacement immediately). On success
    /// the tree refreshes and the renamed item is reselected.
    func beginRename(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = "Rename"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = url.lastPathComponent
        alert.accessoryView = field
        // Focus the field and select all so typing replaces the placeholder name.
        alert.window.initialFirstResponder = field
        field.selectText(nil)
        if alert.runModal() == .alertFirstButtonReturn {
            do {
                let renamed = try FileSystemOperations.rename(url, to: field.stringValue)
                refreshTree()
                selectByPath(renamed)
            }
            catch { NSApp.presentError(error) }
        }
    }

    @objc fileprivate func ctxDelete() {
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

    @objc fileprivate func ctxOpen() {
        openSelected()
    }

    @objc fileprivate func ctxOpenFolder() {
        windowController?.openFolder(nil)
    }

    @objc fileprivate func ctxReveal() {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileTreeNode else { return }
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    @objc fileprivate func ctxRemoveRoot() {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileTreeNode else { return }
        removeRoot(node)
    }
}
