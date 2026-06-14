import AppKit

/// One search hit somewhere in an open document.
struct TabSearchHit {
    let document: TextDocument
    let range: NSRange
    let lineNumber: Int
    let preview: String
    let fileLabel: String
}

/// Presents a panel that searches across all open documents (a capability gedit
/// lacks) using the tested `TextSearch` engine. Per-document find/replace is the
/// native `NSTextView` find bar; this is strictly the cross-tab search.
///
/// Singleton because there is one shared panel for the whole app.
public final class FindInTabsCoordinator: NSObject {

    public static let shared = FindInTabsCoordinator()

    private var panel: NSPanel?
    private var searchField: NSSearchField!
    private var regexToggle: NSButton!
    private var caseToggle: NSButton!
    private var resultsLabel: NSTextField!
    private var tableView: NSTableView!

    private var hits: [TabSearchHit] = []

    private override init() { super.init() }

    // MARK: Presentation

    public func present(relativeTo window: NSWindow?) {
        if panel == nil { buildPanel() }
        panel?.makeKeyAndOrderFront(nil)
        panel?.center()
        searchField.becomeFirstResponder()
        runSearch()
    }

    private func buildPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered, defer: false)
        panel.title = "Find in All Tabs"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false

        let content = NSView(frame: panel.contentLayoutRect)
        content.autoresizingMask = [.width, .height]

        searchField = NSSearchField()
        searchField.placeholderString = "Find across open documents"
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false

        regexToggle = NSButton(checkboxWithTitle: "Regex", target: self, action: #selector(searchChanged))
        regexToggle.translatesAutoresizingMaskIntoConstraints = false
        caseToggle = NSButton(checkboxWithTitle: "Match Case", target: self, action: #selector(searchChanged))
        caseToggle.translatesAutoresizingMaskIntoConstraints = false

        resultsLabel = NSTextField(labelWithString: "")
        resultsLabel.textColor = .secondaryLabelColor
        resultsLabel.font = .systemFont(ofSize: 11)
        resultsLabel.translatesAutoresizingMaskIntoConstraints = false

        tableView = NSTableView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("hit"))
        col.title = "Matches"
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.rowHeight = 34
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelectedHit)
        tableView.action = #selector(openSelectedHit)

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(searchField)
        content.addSubview(regexToggle)
        content.addSubview(caseToggle)
        content.addSubview(resultsLabel)
        content.addSubview(scroll)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            regexToggle.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            regexToggle.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            caseToggle.centerYAnchor.constraint(equalTo: regexToggle.centerYAnchor),
            caseToggle.leadingAnchor.constraint(equalTo: regexToggle.trailingAnchor, constant: 16),
            resultsLabel.centerYAnchor.constraint(equalTo: regexToggle.centerYAnchor),
            resultsLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            scroll.topAnchor.constraint(equalTo: regexToggle.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])

        panel.contentView = content
        self.panel = panel
    }

    // MARK: Search

    @objc private func searchChanged() { runSearch() }

    private func runSearch() {
        let term = searchField.stringValue
        let query = SearchQuery(term: term,
                                isRegex: regexToggle.state == .on,
                                caseSensitive: caseToggle.state == .on)

        hits.removeAll()

        if let errorMessage = TextSearch.validate(query) {
            resultsLabel.stringValue = "Invalid regex: \(errorMessage)"
            tableView.reloadData()
            return
        }

        guard !term.isEmpty else {
            resultsLabel.stringValue = ""
            tableView.reloadData()
            return
        }

        let documents = NSDocumentController.shared.documents.compactMap { $0 as? TextDocument }
        for document in documents {
            let text = document.currentEditorTextOrModel
            let ns = text as NSString
            let label = document.displayName ?? (document.fileURL?.lastPathComponent ?? "Untitled")
            for range in TextSearch.matches(of: query, in: text) {
                let line = TextSearch.lineNumber(for: range.location, in: text)
                let preview = lineSnippet(in: ns, around: range)
                hits.append(TabSearchHit(document: document, range: range,
                                         lineNumber: line, preview: preview, fileLabel: label))
            }
        }

        let fileCount = Set(hits.map { ObjectIdentifier($0.document) }).count
        resultsLabel.stringValue = hits.isEmpty
            ? "No matches"
            : "\(hits.count) match\(hits.count == 1 ? "" : "es") in \(fileCount) file\(fileCount == 1 ? "" : "s")"
        tableView.reloadData()
    }

    /// The text of the line containing `range`, trimmed for display.
    private func lineSnippet(in text: NSString, around range: NSRange) -> String {
        let lineRange = text.lineRange(for: range)
        var snippet = text.substring(with: lineRange)
        snippet = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        if snippet.count > 120 { snippet = String(snippet.prefix(120)) + "…" }
        return snippet
    }

    // MARK: Navigation

    @objc private func openSelectedHit() {
        let row = tableView.selectedRow
        guard row >= 0, row < hits.count else { return }
        let hit = hits[row]
        hit.document.showWindows()
        guard let windowController = hit.document.windowControllers.first as? EditorWindowController,
              let textView = windowController.focusedTextView else { return }
        let safeRange = NSRange(location: min(hit.range.location, (textView.string as NSString).length),
                                length: min(hit.range.length, max(0, (textView.string as NSString).length - hit.range.location)))
        textView.setSelectedRange(safeRange)
        textView.scrollRangeToVisible(safeRange)
        textView.showFindIndicator(for: safeRange)
    }
}

// MARK: - Table data/delegate

extension FindInTabsCoordinator: NSTableViewDataSource, NSTableViewDelegate {
    public func numberOfRows(in tableView: NSTableView) -> Int { hits.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let hit = hits[row]
        let id = NSUserInterfaceItemIdentifier("HitCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? makeCell(id: id)

        let title = "\(hit.fileLabel):\(hit.lineNumber)"
        let attributed = NSMutableAttributedString(
            string: title + "  ",
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
                         .foregroundColor: NSColor.secondaryLabelColor])
        attributed.append(NSAttributedString(
            string: hit.preview,
            attributes: [.font: NSFont.systemFont(ofSize: 12),
                         .foregroundColor: NSColor.labelColor]))
        cell.textField?.attributedStringValue = attributed
        return cell
    }

    private func makeCell(id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        cell.textField = field
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        cell.identifier = id
        return cell
    }
}
