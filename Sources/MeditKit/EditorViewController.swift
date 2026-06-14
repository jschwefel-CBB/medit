import AppKit

/// The editing surface for one document: an `NSTextView` inside a scroll view,
/// with a line-number ruler and a syntax-highlighting controller. One of these
/// lives in each window (and thus each tab).
public final class EditorViewController: NSViewController {

    private weak var document: TextDocument?

    private var scrollView: NSScrollView!
    private(set) var textView: NSTextView!
    private var ruler: LineNumberRulerView?
    private var highlighter: SyntaxHighlightingController?
    private var appearanceObservation: NSKeyValueObservation?

    /// The window controller that handles "New Tab" from our context menu.
    weak var newTabActionTarget: AnyObject?

    // Find & Replace.
    private var findReplaceBar: FindReplaceBar?
    private var barHeightConstraint: NSLayoutConstraint?

    private let prefs: Preferences

    public init(document: TextDocument, preferences: Preferences = .shared) {
        self.document = document
        self.prefs = preferences
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: View construction

    public override func loadView() {
        // Use Apple's factory for the scroll-view + text-view + text-system
        // wiring. A hand-rolled NSTextView(frame:) assembly rendered nothing
        // (correct geometry and white-on-dark colors, yet invisible) — the
        // factory sets up the TextKit stack and clip view correctly.
        let frame = NSRect(x: 0, y: 0, width: 800, height: 560)
        let scrollView = NSTextView.scrollableTextView()
        scrollView.frame = frame
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        self.scrollView = scrollView

        guard let textView = scrollView.documentView as? NSTextView else {
            fatalError("scrollableTextView did not provide an NSTextView")
        }
        textView.isRichText = false                 // plain-text editor
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        // We provide our own Find & Replace bar (with regex), so disable Apple's
        // native find bar (its UI can't do regex).
        textView.usesFindBar = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = EditorColors.foreground
        textView.insertionPointColor = EditorColors.foreground
        textView.delegate = self
        self.textView = textView

        // Container holding the (hidden) find/replace bar above the editor.
        let container = NSView(frame: frame)
        container.autoresizingMask = [.width, .height]

        let bar = FindReplaceBar()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.delegate = self
        bar.isHidden = true
        self.findReplaceBar = bar

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bar)
        container.addSubview(scrollView)

        // Collapse the bar to zero height while hidden so it reserves NO space
        // above the editor. Activated by default (bar starts hidden).
        let heightConstraint = bar.heightAnchor.constraint(equalToConstant: 0)
        heightConstraint.isActive = true
        barHeightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: container.topAnchor),
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: bar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        self.view = container
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        configureFont()
        loadDocumentText()
        applyWrapMode(prefs.wrapLines)
        configureRuler(visible: prefs.showLineNumbers)
        configureHighlighter()
        observePreferences()
    }

    // MARK: Document text

    private func loadDocumentText() {
        let text = document?.text ?? ""
        textView.string = text
    }

    /// Push fresh text from the model into the view (after a revert/reload).
    func reloadFromDocument() {
        loadDocumentText()
        highlighter?.setLanguage(document?.highlightLanguage)
        ruler?.needsDisplay = true
    }

    /// The live text currently in the editor (for saves).
    var currentText: String { textView.string }

    // MARK: Font

    private func configureFont() {
        let font = NSFont(name: prefs.fontName, size: prefs.fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: prefs.fontSize, weight: .regular)
        textView.font = font
        // Tab width in terms of spaces of the current font.
        applyTabWidth(font: font)
    }

    private func applyTabWidth(font: NSFont) {
        let style = NSMutableParagraphStyle()
        let charWidth = (" " as NSString).size(withAttributes: [.font: font]).width
        let width = charWidth * CGFloat(prefs.tabWidth)
        style.tabStops = []
        style.defaultTabInterval = width
        textView.defaultParagraphStyle = style
        textView.typingAttributes[.paragraphStyle] = style
        textView.typingAttributes[.font] = font
        // Always carry a foreground so the caret and freshly typed/pasted text
        // are visible even before the highlighter runs.
        textView.typingAttributes[.foregroundColor] = EditorColors.foreground
    }

    // MARK: Wrap

    public func applyWrapMode(_ wrap: Bool) {
        guard let container = textView.textContainer else { return }
        let infinite = CGFloat.greatestFiniteMagnitude
        if wrap {
            container.widthTracksTextView = true
            container.containerSize = NSSize(width: scrollView.contentSize.width,
                                             height: infinite)
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            scrollView.hasHorizontalScroller = false
        } else {
            container.widthTracksTextView = false
            container.containerSize = NSSize(width: infinite, height: infinite)
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = [.width, .height]
            scrollView.hasHorizontalScroller = true
        }
        textView.didChangeText()
        ruler?.needsDisplay = true
    }

    // MARK: Ruler

    public func configureRuler(visible: Bool) {
        if visible {
            if ruler == nil {
                let r = LineNumberRulerView(textView: textView, scrollView: scrollView)
                scrollView.verticalRulerView = r
                ruler = r
            }
            scrollView.hasVerticalRuler = true
            scrollView.rulersVisible = true
        } else {
            scrollView.rulersVisible = false
            scrollView.hasVerticalRuler = false
        }
    }

    // MARK: Highlighting

    private func configureHighlighter() {
        guard let storage = textView.textStorage else { return }
        let isDark = view.effectiveAppearance.isDark
        let theme = prefs.highlightThemeName(forDarkMode: isDark)
        highlighter = SyntaxHighlightingController(
            textStorage: storage,
            language: document?.highlightLanguage,
            fontName: prefs.fontName,
            fontSize: prefs.fontSize,
            themeName: theme
        )
        highlighter?.highlightNow()

        // Re-theme highlighting when the effective appearance flips (system
        // dark/light change). NSViewController has no appearance hook, so we
        // observe the view's effectiveAppearance directly.
        appearanceObservation = view.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            guard let self else { return }
            let isDark = self.view.effectiveAppearance.isDark
            self.highlighter?.setTheme(self.prefs.highlightThemeName(forDarkMode: isDark))
        }
    }

    // MARK: Preferences observation

    private func observePreferences() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(preferencesChanged),
            name: Preferences.didChangeNotification, object: nil)
    }

    @objc private func preferencesChanged() {
        configureFont()
        applyWrapMode(prefs.wrapLines)
        configureRuler(visible: prefs.showLineNumbers)
        ruler?.updateFont(matching: textView.font)
        let isDark = view.effectiveAppearance.isDark
        highlighter?.setFont(name: prefs.fontName, size: prefs.fontSize)
        highlighter?.setTheme(prefs.highlightThemeName(forDarkMode: isDark))
    }

    deinit { NotificationCenter.default.removeObserver(self) }
    // MARK: Find & Replace

    /// ⌘F — show the bar in find mode.
    @objc public func showFindBar(_ sender: Any?) { presentFindBar(showingReplace: false) }

    /// ⌥⌘F — show the bar in find+replace mode.
    @objc public func showFindReplaceBar(_ sender: Any?) { presentFindBar(showingReplace: true) }

    /// ⌘G / ⇧⌘G — next/previous match using the bar's current query. If the bar
    /// isn't shown yet, show it first.
    @objc public func findNextMatch(_ sender: Any?) {
        guard let bar = findReplaceBar else { return }
        if bar.isHidden { presentFindBar(showingReplace: false); return }
        selectMatch(bar.query, forward: true)
    }

    @objc public func findPreviousMatch(_ sender: Any?) {
        guard let bar = findReplaceBar else { return }
        if bar.isHidden { presentFindBar(showingReplace: false); return }
        selectMatch(bar.query, forward: false)
    }

    private func presentFindBar(showingReplace: Bool) {
        guard let bar = findReplaceBar else { return }
        // Seed the find field with the current selection, if any.
        let selected = (textView.string as NSString).substring(with: textView.selectedRange())
        bar.isHidden = false
        // Let the bar's intrinsic height drive its size (collapse off).
        barHeightConstraint?.isActive = false
        bar.present(showingReplace: showingReplace, in: view.window)
        if !selected.isEmpty && !selected.contains("\n") {
            bar.setFindTerm(selected)
        }
        view.layoutSubtreeIfNeeded()
        updateMatchStatus(for: bar.query)
    }

    private func hideFindBar() {
        guard let bar = findReplaceBar else { return }
        bar.isHidden = true
        // Collapse to zero so it reserves no space above the editor.
        barHeightConstraint?.constant = 0
        barHeightConstraint?.isActive = true
        view.layoutSubtreeIfNeeded()
        view.window?.makeFirstResponder(textView)
    }

    /// Select and reveal the match at/after the current selection (or before it
    /// for `forward == false`). Returns whether a match was found.
    @discardableResult
    private func selectMatch(_ query: SearchQuery, forward: Bool) -> Bool {
        let text = textView.string
        let matches = TextSearch.matches(of: query, in: text)
        guard !matches.isEmpty else {
            NSSound.beep()
            updateMatchStatus(for: query)
            return false
        }
        let selection = textView.selectedRange()
        let target: NSRange
        if forward {
            target = matches.first(where: { $0.location >= NSMaxRange(selection) }) ?? matches[0]
        } else {
            target = matches.last(where: { NSMaxRange($0) <= selection.location }) ?? matches[matches.count - 1]
        }
        textView.setSelectedRange(target)
        textView.scrollRangeToVisible(target)
        textView.showFindIndicator(for: target)
        updateMatchStatus(for: query)
        return true
    }

    private func replaceCurrent(_ query: SearchQuery, with replacement: String) {
        let selection = textView.selectedRange()
        guard selection.length > 0 else { selectMatch(query, forward: true); return }
        let selectedText = (textView.string as NSString).substring(with: selection)
        // Confirm the current selection actually matches the query before replacing.
        let matchesSelection = TextSearch.matches(of: query, in: selectedText).contains { $0 == NSRange(location: 0, length: (selectedText as NSString).length) }
        guard matchesSelection else { selectMatch(query, forward: true); return }

        // Compute the replacement (regex template expansion via the engine).
        let (replaced, _) = TextSearch.replacingAll(of: query, in: selectedText, with: replacement)
        if textView.shouldChangeText(in: selection, replacementString: replaced) {
            textView.replaceCharacters(in: selection, with: replaced)
            textView.didChangeText()
        }
        // Move to the next match.
        selectMatch(query, forward: true)
    }

    private func replaceAllMatches(_ query: SearchQuery, with replacement: String) {
        let text = textView.string
        let (result, count) = TextSearch.replacingAll(of: query, in: text, with: replacement)
        guard count > 0 else { NSSound.beep(); findReplaceBar?.setStatus("Not found"); return }
        let whole = NSRange(location: 0, length: (text as NSString).length)
        if textView.shouldChangeText(in: whole, replacementString: result) {
            textView.replaceCharacters(in: whole, with: result)
            textView.didChangeText()
        }
        findReplaceBar?.setStatus("Replaced \(count)")
    }

    // Test hooks.
    func runFindForTesting(_ query: SearchQuery, forward: Bool) { selectMatch(query, forward: forward) }
    func runReplaceAllForTesting(_ query: SearchQuery, with replacement: String) { replaceAllMatches(query, with: replacement) }
    var findBarHeightForTesting: CGFloat { findReplaceBar?.frame.height ?? -1 }
    func closeFindBarForTesting() { hideFindBar() }

    private func updateMatchStatus(for query: SearchQuery) {
        guard let bar = findReplaceBar else { return }
        if let error = TextSearch.validate(query) {
            bar.setStatus("Bad regex")
            _ = error
            return
        }
        guard !query.term.isEmpty else { bar.setStatus(""); return }
        let count = TextSearch.matches(of: query, in: textView.string).count
        bar.setStatus(count == 0 ? "Not found" : "\(count) match\(count == 1 ? "" : "es")")
    }
}

// MARK: - FindReplaceBarDelegate

extension EditorViewController: FindReplaceBarDelegate {
    func findBar(_ bar: FindReplaceBar, query: SearchQuery, didRequest action: FindReplaceBar.Action) {
        switch action {
        case .findNext: selectMatch(query, forward: true)
        case .findPrevious: selectMatch(query, forward: false)
        case .replace: replaceCurrent(query, with: bar.replacementText)
        case .replaceAll: replaceAllMatches(query, with: bar.replacementText)
        case .liveUpdate: updateMatchStatus(for: query)
        }
    }

    func findBarDidClose(_ bar: FindReplaceBar) {
        hideFindBar()
    }
}

// MARK: - NSTextViewDelegate

extension EditorViewController: NSTextViewDelegate {
    public func textDidChange(_ notification: Notification) {
        document?.updateText(textView.string)
        highlighter?.scheduleHighlight()
        ruler?.needsDisplay = true
    }

    /// Inject "New Tab" at the top of the editor's right-click menu.
    public func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        let item = NSMenuItem(title: "New Tab",
                              action: #selector(EditorWindowController.newTabFromMenu(_:)),
                              keyEquivalent: "")
        // Route to the window controller regardless of first-responder quirks.
        item.target = newTabActionTarget
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }
}

// MARK: - Appearance helper

extension NSAppearance {
    /// True when the effective appearance is one of the dark variants.
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
