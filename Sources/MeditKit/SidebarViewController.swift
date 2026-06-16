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

    // MARK: Test hooks

    func setRootForTesting(_ url: URL) {
        dataSource.roots = [FileTreeNode(url: url)]
        applyPrefsToDataSource()
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
