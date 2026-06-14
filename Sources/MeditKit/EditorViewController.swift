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

    private let prefs: Preferences

    public init(document: TextDocument, preferences: Preferences = .shared) {
        self.document = document
        self.prefs = preferences
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: View construction

    public override func loadView() {
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isRichText = false                 // plain-text editor
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.usesFindBar = true                 // native Cmd-F find bar
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.delegate = self
        self.textView = textView

        scrollView.documentView = textView
        self.view = scrollView
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
