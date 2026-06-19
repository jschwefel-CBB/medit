import AppKit

public protocol RecentFilesViewDelegate: AnyObject {
    func recentFiles(_ view: RecentFilesView, didActivate url: URL)
}

/// The sidebar's Recent Files list: a flat table of recently opened files (icon +
/// name + containing-folder subtitle), backed by `RecentFilesStore`. Click to
/// open; right-click to reveal / remove / clear. Shown in place of the folder
/// outline when the sidebar's Recent pane is selected.
public final class RecentFilesView: NSView {

    public weak var delegate: RecentFilesViewDelegate?

    private let store: RecentFilesStore
    private let prefs: Preferences
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private var urls: [URL] = []

    public init(store: RecentFilesStore = .shared, preferences: Preferences = .shared) {
        self.store = store
        self.prefs = preferences
        super.init(frame: .zero)
        build()
        reload()
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged),
                                               name: RecentFilesStore.didChangeNotification, object: nil)
    }
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("recent"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowSizeStyle = .default
        tableView.usesAutomaticRowHeights = true
        tableView.backgroundColor = .clear
        tableView.style = .sourceList
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.doubleAction = #selector(rowDoubleClicked)
        tableView.setAccessibilityIdentifier("recentFilesTable")

        let menu = NSMenu()
        menu.delegate = self
        tableView.menu = menu

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = tableView
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @objc private func storeChanged() { reload() }

    public func reload() {
        urls = store.urls
        tableView.reloadData()
    }

    private func url(at row: Int) -> URL? {
        (row >= 0 && row < urls.count) ? urls[row] : nil
    }

    @objc private func rowClicked() {
        guard prefs.sidebarOpenOnSingleClick else { return }
        activate(row: tableView.clickedRow)
    }
    @objc private func rowDoubleClicked() {
        if !prefs.sidebarOpenOnSingleClick { activate(row: tableView.clickedRow) }
    }
    private func activate(row: Int) {
        guard let url = url(at: row) else { return }
        delegate?.recentFiles(self, didActivate: url)
    }

    /// Test hook: activate the file at `row`.
    public func activateRowForTesting(_ row: Int) { activate(row: row) }
    public var rowCountForTesting: Int { urls.count }
}

// MARK: - Table data source / delegate

extension RecentFilesView: NSTableViewDataSource, NSTableViewDelegate {
    public func numberOfRows(in tableView: NSTableView) -> Int { urls.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let url = url(at: row) else { return nil }
        let id = NSUserInterfaceItemIdentifier("recentCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? RecentCellView) ?? RecentCellView(id: id)
        let exists = FileManager.default.fileExists(atPath: url.path)
        cell.configure(name: url.lastPathComponent,
                       subtitle: url.deletingLastPathComponent().path,
                       icon: NSWorkspace.shared.icon(forFile: url.path),
                       dimmed: !exists)
        cell.toolTip = url.path
        return cell
    }
}

// MARK: - Context menu

extension RecentFilesView: NSMenuDelegate {
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = tableView.clickedRow
        if row >= 0, url(at: row) != nil {
            menu.addItem(withTitle: "Open", action: #selector(ctxOpen), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Reveal in Finder", action: #selector(ctxReveal), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Remove from Recent", action: #selector(ctxRemove), keyEquivalent: "").target = self
        }
        if !urls.isEmpty {
            menu.addItem(withTitle: "Clear Recent Files", action: #selector(ctxClear), keyEquivalent: "").target = self
        }
    }
    @objc private func ctxOpen() { activate(row: tableView.clickedRow) }
    @objc private func ctxReveal() {
        guard let url = url(at: tableView.clickedRow) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    @objc private func ctxRemove() {
        guard let url = url(at: tableView.clickedRow) else { return }
        store.remove(url)
    }
    @objc private func ctxClear() { store.clear() }
}

// MARK: - Cell

private final class RecentCellView: NSTableCellView {
    private let icon = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")

    init(id: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        identifier = id
        icon.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 12)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.font = .systemFont(ofSize: 10)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(icon); addSubview(nameLabel); addSubview(pathLabel)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            nameLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            pathLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            pathLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            pathLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 1),
            pathLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(name: String, subtitle: String, icon iconImage: NSImage, dimmed: Bool) {
        nameLabel.stringValue = name
        pathLabel.stringValue = subtitle
        icon.image = iconImage
        let alpha: CGFloat = dimmed ? 0.5 : 1.0
        nameLabel.alphaValue = alpha; pathLabel.alphaValue = alpha; icon.alphaValue = alpha
    }
}
