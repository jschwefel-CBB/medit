import AppKit

/// Actions the find/replace bar asks its editor to perform. The editor owns the
/// text view and the actual search/replace (via `TextSearch`); the bar is just
/// the UI.
protocol FindReplaceBarDelegate: AnyObject {
    func findBar(_ bar: FindReplaceBar, query: SearchQuery, didRequest action: FindReplaceBar.Action)
    func findBarDidClose(_ bar: FindReplaceBar)
}

/// A custom in-editor Find & Replace bar. Replaces Apple's native find bar so we
/// can offer regex (which NSTextFinder's UI does not expose). Two rows: a find
/// row (always shown) and a replace row (shown in replace mode).
public final class FindReplaceBar: NSView {

    enum Action {
        case findNext
        case findPrevious
        case replace
        case replaceAll
        case liveUpdate   // query changed; update match count / highlight
    }

    weak var delegate: FindReplaceBarDelegate?

    private let findField = NSSearchField()
    private let replaceField = NSTextField()
    private let regexToggle = NSButton(checkboxWithTitle: "Regex", target: nil, action: nil)
    private let caseToggle = NSButton(checkboxWithTitle: "Match Case", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let replaceRow = NSStackView()

    private(set) var showsReplace = false

    public override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: showsReplace ? 72 : 38)
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Public API

    /// The current search specification from the fields/toggles.
    var query: SearchQuery {
        SearchQuery(term: findField.stringValue,
                    isRegex: regexToggle.state == .on,
                    caseSensitive: caseToggle.state == .on)
    }

    var replacementText: String { replaceField.stringValue }

    func present(showingReplace: Bool, in window: NSWindow?) {
        setReplaceVisible(showingReplace)
        window?.makeFirstResponder(findField)
        findField.selectText(nil)
    }

    func setStatus(_ text: String) { statusLabel.stringValue = text }

    func setFindTerm(_ term: String) { findField.stringValue = term }

    func setReplaceVisible(_ visible: Bool) {
        guard visible != showsReplace else { return }
        showsReplace = visible
        replaceRow.isHidden = !visible
        invalidateIntrinsicContentSize()
    }

    // MARK: Build UI

    private func build() {
        wantsLayer = true
        // A subtle bar background distinct from the editor.
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        findField.placeholderString = "Find"
        findField.target = self
        findField.action = #selector(findFieldChanged)
        findField.sendsWholeSearchString = false
        findField.sendsSearchStringImmediately = true

        regexToggle.target = self
        regexToggle.action = #selector(toggleChanged)
        caseToggle.target = self
        caseToggle.action = #selector(toggleChanged)

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.alignment = .right
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Accessibility identifiers for autopilot GUI tests. The regex/case
        // toggles are cell-based NSButtons, so use the cell-aware setter (an
        // identifier set only on the control is not vended to the AX tree).
        findField.setAccessibilityIdentifier("findField")
        replaceField.setAccessibilityIdentifier("replaceField")
        statusLabel.setAccessibilityIdentifier("findStatusLabel")
        regexToggle.setTestAXIdentifier("findRegexToggle")
        caseToggle.setTestAXIdentifier("findCaseToggle")

        let prevButton = makeButton(symbol: "chevron.left", fallback: "<", action: #selector(findPrev))
        let nextButton = makeButton(symbol: "chevron.right", fallback: ">", action: #selector(findNext))
        let doneButton = NSButton(title: "Done", target: self, action: #selector(close))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\u{1b}" // Esc

        let findRow = NSStackView(views: [findField, prevButton, nextButton,
                                          regexToggle, caseToggle, statusLabel, doneButton])
        findRow.orientation = .horizontal
        findRow.spacing = 6
        findRow.alignment = .centerY
        findRow.translatesAutoresizingMaskIntoConstraints = false
        findField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        findField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true

        replaceField.placeholderString = "Replace"
        replaceField.target = self
        replaceField.action = #selector(replaceOne)
        let replaceButton = NSButton(title: "Replace", target: self, action: #selector(replaceOne))
        replaceButton.bezelStyle = .rounded
        let replaceAllButton = NSButton(title: "All", target: self, action: #selector(replaceAll))
        replaceAllButton.bezelStyle = .rounded

        replaceRow.orientation = .horizontal
        replaceRow.spacing = 6
        replaceRow.alignment = .centerY
        replaceRow.translatesAutoresizingMaskIntoConstraints = false
        replaceRow.addArrangedSubview(replaceField)
        replaceRow.addArrangedSubview(replaceButton)
        replaceRow.addArrangedSubview(replaceAllButton)
        replaceField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        replaceField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        replaceRow.isHidden = true

        let column = NSStackView(views: [findRow, replaceRow])
        column.orientation = .vertical
        column.spacing = 6
        column.alignment = .leading
        column.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Bottom hairline separator.
        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sep)
        NSLayoutConstraint.activate([
            sep.leadingAnchor.constraint(equalTo: leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: trailingAnchor),
            sep.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func makeButton(symbol: String, fallback: String, action: Selector) -> NSButton {
        let button: NSButton
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            button = NSButton(image: image, target: self, action: action)
        } else {
            button = NSButton(title: fallback, target: self, action: action)
        }
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        return button
    }

    // MARK: Actions

    @objc private func findFieldChanged() { delegate?.findBar(self, query: query, didRequest: .liveUpdate) }
    @objc private func toggleChanged() { delegate?.findBar(self, query: query, didRequest: .liveUpdate) }
    @objc private func findNext() { delegate?.findBar(self, query: query, didRequest: .findNext) }
    @objc private func findPrev() { delegate?.findBar(self, query: query, didRequest: .findPrevious) }
    @objc private func replaceOne() { delegate?.findBar(self, query: query, didRequest: .replace) }
    @objc private func replaceAll() { delegate?.findBar(self, query: query, didRequest: .replaceAll) }
    @objc private func close() { delegate?.findBarDidClose(self) }
}
