import AppKit
import WebKit

/// The editing surface for one document: an `NSTextView` inside a scroll view,
/// with a line-number ruler and a syntax-highlighting controller. One of these
/// lives in each window (and thus each tab).
public final class EditorViewController: NSViewController {

    private weak var document: TextDocument?

    private var scrollView: NSScrollView!
    private(set) var textView: NSTextView!
    private var ruler: LineNumberRulerView?
    private var highlighter: SyntaxHighlightingController?
    private var bracketColorizer: BracketColorizer?
    private var appearanceObservation: NSKeyValueObservation?
    private var isWrapping = false

    // Markdown formatting toolbar (top of the editor, Markdown docs only).
    private var markdownStyleBar: MarkdownStyleBar?
    private var styleBarHeightConstraint: NSLayoutConstraint?

    // Markdown preview (per-tab; not a global pref). The preview pane is built
    // lazily and swapped in for the editor scroll view by `showPreview`.
    private var isShowingPreview = false
    /// The Markdown preview is a WKWebView rendering HTML+CSS — like every other
    /// Markdown editor — so tables/wrapping/scrolling/selection/copy are browser
    /// native instead of hand-built in TextKit.
    private var previewWebView: WKWebView?
    private var previewRefreshWorkItem: DispatchWorkItem?

    /// The window controller that handles "New Tab" from our context menu.
    weak var newTabActionTarget: AnyObject?

    // Reload banner (external-change notice), above the find bar.
    private var reloadBanner: ReloadBanner?
    private var reloadBannerHeightConstraint: NSLayoutConstraint?

    // Find & Replace.
    private var findReplaceBar: FindReplaceBar?
    private var barHeightConstraint: NSLayoutConstraint?

    // Status bar.
    private var statusBar: StatusBarView?
    private var statusBarHeightConstraint: NSLayoutConstraint?

    // Go to Line.
    private var goToLineSheet: GoToLineSheet?

    // Show Invisibles.
    private weak var invisiblesLayoutManager: InvisiblesLayoutManager?

    private let prefs: Preferences

    public init(document: TextDocument, preferences: Preferences = .shared) {
        self.document = document
        self.prefs = preferences
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: View construction

    public override func loadView() {
        // We build the scroll view + text view + TextKit stack manually rather
        // than via NSTextView.scrollableTextView(), because the factory can't
        // produce our EditorTextView subclass. This assembly deliberately
        // mirrors the factory's wiring (container width-tracks the view, layout
        // manager + text storage attached) — an earlier ad-hoc assembly that
        // got this wrong rendered correct geometry/colors yet showed no text, so
        // keep the container/layoutManager/storage setup below intact.
        let frame = NSRect(x: 0, y: 0, width: 800, height: 560)
        let scrollView = NSScrollView(frame: frame)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        self.scrollView = scrollView

        // Build EditorTextView with the same TextKit wiring the factory uses.
        let contentSize = scrollView.contentSize
        let textContainer = NSTextContainer(containerSize: NSSize(width: contentSize.width,
                                                                  height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        let layoutManager = InvisiblesLayoutManager()
        layoutManager.showInvisibles = prefs.showInvisibles
        layoutManager.addTextContainer(textContainer)
        self.invisiblesLayoutManager = layoutManager
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let textView = EditorTextView(frame: NSRect(origin: .zero, size: contentSize),
                                      textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.pcStyleNavigationKeys = prefs.pcStyleNavigationKeys
        textView.autoIndentEnabled = prefs.autoIndent
        textView.indentBetweenBracketsEnabled = prefs.indentBetweenBrackets
        textView.autoCloseBracketsEnabled = prefs.autoCloseBrackets
        textView.indentTabWidth = prefs.tabWidth
        textView.indentUseSpaces = prefs.insertSpacesForTab
        scrollView.documentView = textView
        textView.isRichText = false                 // plain-text editor
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = prefs.smartQuotes
        textView.isAutomaticDashSubstitutionEnabled = prefs.smartDashes
        textView.isAutomaticTextReplacementEnabled = prefs.automaticTextReplacement
        textView.isAutomaticSpellingCorrectionEnabled = prefs.automaticSpellingCorrection
        textView.smartInsertDeleteEnabled = prefs.smartInsertDelete
        textView.isContinuousSpellCheckingEnabled = prefs.continuousSpellChecking
        // We provide our own Find & Replace bar (with regex), so disable Apple's
        // native find bar (its UI can't do regex).
        textView.usesFindBar = false
        let pad = CGFloat(prefs.editorPadding)
        textView.textContainerInset = NSSize(width: pad, height: pad)
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = EditorColors.foreground
        textView.insertionPointColor = EditorColors.foreground
        textView.delegate = self
        textView.setAccessibilityIdentifier("editorTextView")
        self.textView = textView

        // Container holding the (hidden) find/replace bar above the editor.
        let container = NSView(frame: frame)
        container.autoresizingMask = [.width, .height]

        // Reload banner sits ABOVE the find bar (order: reload banner / find bar
        // / scroll view / status bar). Like the find bar, it collapses to zero
        // height while hidden so it reserves NO space above the editor.
        let banner = ReloadBanner()
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.isHidden = true
        banner.onReload = { [weak self] in
            self?.document?.revertToSavedSafely()
            self?.hideReloadBanner()
        }
        banner.onDismiss = { [weak self] in self?.hideReloadBanner() }
        self.reloadBanner = banner

        let bar = FindReplaceBar()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.delegate = self
        bar.isHidden = true
        self.findReplaceBar = bar

        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // Markdown formatting toolbar at the very top (above the reload banner);
        // collapses to zero height when hidden, like the find bar.
        let styleBar = MarkdownStyleBar()
        styleBar.translatesAutoresizingMaskIntoConstraints = false
        styleBar.isHidden = true
        styleBar.delegate = self
        self.markdownStyleBar = styleBar
        container.addSubview(styleBar)

        container.addSubview(banner)
        container.addSubview(bar)
        container.addSubview(scrollView)

        let styleBarHeight = styleBar.heightAnchor.constraint(equalToConstant: 0)
        styleBarHeight.isActive = true
        styleBarHeightConstraint = styleBarHeight

        // Collapse the banner to zero height while hidden (starts hidden).
        let bannerHeight = banner.heightAnchor.constraint(equalToConstant: 0)
        bannerHeight.isActive = true
        reloadBannerHeightConstraint = bannerHeight

        // Collapse the bar to zero height while hidden so it reserves NO space
        // above the editor. Activated by default (bar starts hidden).
        let heightConstraint = bar.heightAnchor.constraint(equalToConstant: 0)
        heightConstraint.isActive = true
        barHeightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            styleBar.topAnchor.constraint(equalTo: container.topAnchor),
            styleBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            styleBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            banner.topAnchor.constraint(equalTo: styleBar.bottomAnchor),
            banner.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            bar.topAnchor.constraint(equalTo: banner.bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: bar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        // Status bar pinned to the bottom; the scroll view's bottom now meets the
        // status bar's top (instead of the container bottom).
        let statusBar = StatusBarView()
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        statusBar.onLanguagePick = { [weak self] pick in
            switch pick {
            case "auto": self?.setLanguageOverride(nil)
            case "plaintext": self?.setLanguageOverride("plaintext")
            default: self?.setLanguageOverride(pick)
            }
        }
        statusBar.onReinterpret = { [weak self] enc in
            self?.document?.reinterpret(as: enc)
            self?.rehighlightAndRefresh()
        }
        statusBar.onConvert = { [weak self] enc in
            self?.document?.convert(to: enc)
            self?.updateStatusBar()
        }
        statusBar.onLineEndingPick = { [weak self] ending in
            self?.document?.setLineEnding(ending)
            self?.updateStatusBar()
        }
        statusBar.onWrapToggle = { [weak self] in
            guard let self else { return }
            self.prefs.wrapLines.toggle()
            self.applyWrapMode(self.prefs.wrapLines)
            self.updateStatusBar()
        }
        statusBar.onModeToggle = { [weak self] in
            guard let self, let editor = self.textView as? EditorTextView else { return }
            editor.toggleOverwriteMode()
            self.updateStatusBar()
        }
        self.statusBar = statusBar
        container.addSubview(statusBar)

        let sbHeight = statusBar.heightAnchor.constraint(equalToConstant: 22)
        sbHeight.isActive = true
        statusBarHeightConstraint = sbHeight

        NSLayoutConstraint.activate([
            scrollView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
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
        configureBracketColorizer()
        (textView as? EditorTextView)?.onOverwriteModeChange = { [weak self] _ in self?.updateStatusBar() }
        (textView as? EditorTextView)?.onColumnModeChange = { [weak self] active in self?.statusBar?.setColumnMode(active) }
        // Dragged files open (in tabs, preserving order) instead of pasting paths.
        (textView as? EditorTextView)?.onOpenFiles = { [weak self] urls in
            guard let wc = self?.newTabActionTarget as? EditorWindowController else { return }
            wc.openFiles(at: urls)
        }
        applyStatusBarVisibility(prefs.showStatusBar)
        updateStatusBar()
        observePreferences()
        observeResize()
        installScrollFractionHooksIfRequested()
        // Auto-open the preview for Markdown documents when the user opted in.
        // The `--no-auto-preview` launch flag (GUI-test hook) suppresses this so a
        // test that drives the editor of a .md file starts from a deterministic
        // preview-off state regardless of the user's autoShowPreviewForMarkdown default.
        if prefs.autoShowPreviewForMarkdown,
           document?.highlightLanguage == "markdown",
           !LaunchReset.isAutoPreviewSuppressed(in: CommandLine.arguments) {
            showPreview(true)
        }
        applyStyleBarVisibility()
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        // Install the scroll-fraction test labels now the view is in a window — a
        // label added in viewDidLoad (no window) isn't reliably registered in the
        // AX tree. Idempotent; only does anything under --expose-scroll-fraction.
        installScrollFractionHooksIfRequested()
        // Apply a focus request made before this view had a window (auto-preview
        // runs in viewDidLoad, where makeFirstResponder cannot work). Re-assert DOM
        // focus too: the web view's didFinish may have run before the window
        // existed, and AppKit first-responder alone leaves the content unfocused.
        if let pending = pendingFirstResponder {
            pendingFirstResponder = nil
            view.window?.makeFirstResponder(pending)
        }
        // macOS UI state restoration can restore the caret/selection to a spot
        // below the fold (e.g. the end of a long file) AFTER viewDidLoad, without
        // scrolling it into view — so the editor opened showing the top while the
        // caret sat 100+ lines down. Reveal the current selection once the view is
        // on screen and has real geometry. Guarded so it only fires for the first
        // appearance (re-appearing a tab shouldn't yank the user's scroll position).
        guard !hasRevealedInitialSelection else { return }
        hasRevealedInitialSelection = true
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    /// One-shot guard so the initial caret-reveal in `viewDidAppear` runs only on
    /// the first appearance, not every time a tab is re-shown.
    private var hasRevealedInitialSelection = false

    private func observeResize() {
        // Reflow wrapped text live as the scroll view / clip view changes size.
        scrollView.postsFrameChangedNotifications = true
        scrollView.contentView.postsFrameChangedNotifications = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(scrollViewContentDidResize(_:)),
                       name: NSView.frameDidChangeNotification, object: scrollView)
        nc.addObserver(self, selector: #selector(scrollViewContentDidResize(_:)),
                       name: NSView.frameDidChangeNotification, object: scrollView.contentView)
        nc.addObserver(self, selector: #selector(scrollViewContentDidResize(_:)),
                       name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
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
        applyIndentLanguagePolicy()
        configureRuler(visible: prefs.showLineNumbers)
        bracketColorizer?.refresh()
        ruler?.needsDisplay = true
        if isShowingPreview { renderPreview() }
        applyStyleBarVisibility()
    }

    /// The live text currently in the editor (for saves).
    var currentText: String { textView.string }

    // MARK: Markdown style bar

    private var isMarkdownDocument: Bool { document?.highlightLanguage == "markdown" }

    /// Whether the current language treats `{`/`:` at end of line as block
    /// openers that add an indent level on Return. True for real code languages;
    /// false for plain text (nil / "plaintext") and Markdown, where they are prose.
    private var languageUsesBlockOpeners: Bool {
        switch document?.highlightLanguage {
        case nil, .some("plaintext"), .some("markdown"): return false
        default: return true
        }
    }

    /// Show the formatting toolbar for Markdown documents when the pref is on.
    func applyStyleBarVisibility() {
        let show = isMarkdownDocument && prefs.showMarkdownToolbar
        markdownStyleBar?.isHidden = !show
        styleBarHeightConstraint?.constant = show ? 30 : 0
    }

    /// Apply a style-bar action to the editor's current selection, as a single
    /// undoable edit, then re-highlight.
    private func applyStyleAction(_ action: MarkdownStyleBar.Action) {
        let tv = textView!
        let full = tv.string
        let sel = tv.selectedRange()
        let edit: MarkdownEditing.Edit
        switch action {
        case .bold: edit = MarkdownEditing.toggleInline(full, sel, marker: "**")
        case .italic: edit = MarkdownEditing.toggleInline(full, sel, marker: "*")
        case .strikethrough: edit = MarkdownEditing.toggleInline(full, sel, marker: "~~")
        case .code: edit = MarkdownEditing.toggleInline(full, sel, marker: "`")
        case .link: edit = MarkdownEditing.insertLink(full, sel)
        case .heading: edit = MarkdownEditing.toggleLinePrefix(full, sel, prefix: .heading(2))
        case .bullet: edit = MarkdownEditing.toggleLinePrefix(full, sel, prefix: .bullet)
        case .ordered: edit = MarkdownEditing.toggleLinePrefix(full, sel, prefix: .ordered)
        case .quote: edit = MarkdownEditing.toggleLinePrefix(full, sel, prefix: .quote)
        case .codeBlock: edit = MarkdownEditing.toggleCodeBlock(full, sel)
        }
        let fullRange = NSRange(location: 0, length: (full as NSString).length)
        if tv.shouldChangeText(in: fullRange, replacementString: edit.text) {
            tv.textStorage?.replaceCharacters(in: fullRange, with: edit.text)
            tv.didChangeText()
        }
        tv.setSelectedRange(edit.selectedRange)
        document?.updateText(tv.string)
        highlighter?.scheduleHighlight()
        bracketColorizer?.scheduleRefresh()
        updateStatusBar()
        schedulePreviewRefresh()
    }

    /// Test hook: invoke a style-bar action.
    public func applyStyleActionForTesting(_ action: MarkdownStyleBar.Action) { applyStyleAction(action) }
    public var styleBarVisibleForTesting: Bool { markdownStyleBar?.isHidden == false }

    // MARK: Text transforms (sort lines / change case)

    /// Replace the whole document with `newText`, reselecting `newSelection`, as a
    /// single undoable edit, then refresh highlighting/status.
    private func applyWholeTextEdit(_ newText: String, select newSelection: NSRange) {
        let tv = textView!
        let fullRange = NSRange(location: 0, length: (tv.string as NSString).length)
        guard tv.shouldChangeText(in: fullRange, replacementString: newText) else { return }
        tv.textStorage?.replaceCharacters(in: fullRange, with: newText)
        tv.didChangeText()
        let len = (tv.string as NSString).length
        tv.setSelectedRange(NSRange(location: min(newSelection.location, len),
                                    length: min(newSelection.length, len - min(newSelection.location, len))))
        document?.updateText(tv.string)
        highlighter?.scheduleHighlight()
        bracketColorizer?.scheduleRefresh()
        updateStatusBar()
        schedulePreviewRefresh()
    }

    public func sortSelectedLines(ascending: Bool) {
        let e = TextTransforms.sortLines(textView.string, range: textView.selectedRange(),
                                         ascending: ascending, caseInsensitive: false)
        applyWholeTextEdit(e.text, select: e.selectedRange)
    }

    public func changeCaseOfSelection(to mode: TextTransforms.Case) {
        let e = TextTransforms.changeCase(textView.string, range: textView.selectedRange(), to: mode)
        applyWholeTextEdit(e.text, select: e.selectedRange)
    }

    /// Test hooks.
    public func sortSelectedLinesForTesting(ascending: Bool) { sortSelectedLines(ascending: ascending) }
    public func changeCaseForTesting(_ mode: TextTransforms.Case) { changeCaseOfSelection(to: mode) }

    // MARK: Markdown preview

    /// Whether the rendered Markdown preview is currently shown (per-tab state).
    public var isPreviewVisible: Bool { isShowingPreview }

    // MARK: Preview Select All / Copy
    //
    // These drive the web view directly instead of relying on the responder chain.
    //
    // Routing `selectAll:`/`copy:` through the chain does not work for this view:
    // `WKWebView` sits at position 0, claims both selectors, and handles them
    // against internal state that is not the page's DOM selection — Select All
    // then copies only the first element (or nothing after a click), while the
    // same commands sent straight to the web view copy the whole document. See
    // WebKit bug 143482 for the underlying first-responder forwarding problem.
    //
    // App-initiated `evaluateJavaScript` is unaffected by
    // `allowsContentJavaScript = false` (that only blocks scripts *in* the page),
    // so this path is both reliable and safe.

    /// Select the entire rendered preview. No-op when the preview isn't showing.
    public func selectAllInPreview() {
        guard isShowingPreview, let wv = previewWebView else { return }
        // Build the range explicitly rather than using `execCommand('selectAll')`:
        // execCommand acts on the *focused* element, and the preview's web content
        // never takes DOM focus (it is a passive, read-only view), so it selected
        // only the first block. Selecting the body's contents directly needs no
        // focus and always covers the whole document.
        wv.evaluateJavaScript("""
        (function () {
          var sel = window.getSelection();
          if (!sel || !document.body) { return false; }
          var range = document.createRange();
          range.selectNodeContents(document.body);
          sel.removeAllRanges();
          sel.addRange(range);
          return true;
        })();
        """)
    }

    /// Copy the preview's current selection to the general pasteboard.
    ///
    /// Nothing selected means nothing copied — the pasteboard is left untouched,
    /// as in any editor. No-op when the preview isn't showing. `completion` reports
    /// whether anything was written.
    public func copyPreviewSelection(completion: ((Bool) -> Void)? = nil) {
        guard isShowingPreview, let wv = previewWebView else { completion?(false); return }
        wv.evaluateJavaScript("window.getSelection().toString()") { result, _ in
            let text = (result as? String) ?? ""
            guard !text.isEmpty else { completion?(false); return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            completion?(true)
        }
    }

    // MARK: Preview scrolling
    //
    // The rendered preview is a WKWebView, so all scrolling is done in JS. When the
    // preview covers the editor, Find/Go-to-Line/Jump must move the PREVIEW to the
    // match — moving the hidden editor's NSTextView (as the code originally did) has
    // no visible effect. Position is expressed as a fraction 0…1 of the scrollable
    // range so it maps cleanly between the editor and the preview across a toggle.

    /// Scroll the preview to `fraction` (0 = top, 1 = bottom). No-op when hidden.
    public func scrollPreview(toFraction fraction: Double) {
        guard isShowingPreview, let wv = previewWebView else { return }
        let clamped = max(0, min(1, fraction))
        wv.evaluateJavaScript("""
        (function () {
          var max = document.documentElement.scrollHeight - window.innerHeight;
          window.scrollTo(0, Math.max(0, max) * \(clamped));
          return true;
        })();
        """) { [weak self] _, _ in self?.updatePreviewScrollFractionLabel() }
    }

    /// Scroll the preview so the content at source `line` (1-based) is in view,
    /// mapping line position proportionally onto the rendered document. Exact
    /// line→element anchoring isn't available (the renderer emits no source map),
    /// so this is proportional — good enough to bring a Find/Go-to-Line target on
    /// screen. No-op when the preview isn't showing.
    public func scrollPreviewToSourceLine(_ line: Int) {
        let total = max(1, currentText.reduce(into: 1) { n, c in if c == "\n" { n += 1 } })
        scrollPreview(toFraction: Double(line - 1) / Double(max(1, total - 1)))
    }

    /// Scroll the preview to the source `range`'s start line. Used by Find so a
    /// match below the fold brings the preview to it. No-op when hidden.
    public func scrollPreviewToSourceRange(_ range: NSRange) {
        let prefix = (currentText as NSString).substring(to: min(range.location, (currentText as NSString).length))
        let line = prefix.reduce(into: 1) { n, c in if c == "\n" { n += 1 } }
        scrollPreviewToSourceLine(line)
    }

    /// Read the preview's current scroll fraction (0…1) asynchronously. Used to
    /// carry position back to the editor on toggle-off, and by the test hook.
    public func readPreviewScrollFraction(_ completion: @escaping (Double) -> Void) {
        guard isShowingPreview, let wv = previewWebView else { completion(0); return }
        wv.evaluateJavaScript("""
        (function () {
          var max = document.documentElement.scrollHeight - window.innerHeight;
          return max > 0 ? (window.pageYOffset / max) : 0;
        })();
        """) { result, _ in completion((result as? Double) ?? 0) }
    }

    /// The editor's current vertical scroll fraction (0 = top, 1 = bottom).
    var editorScrollFraction: Double {
        guard let clip = textView.enclosingScrollView?.contentView else { return 0 }
        let docHeight = textView.bounds.height
        let visible = clip.bounds.height
        let maxScroll = max(0, docHeight - visible)
        guard maxScroll > 0 else { return 0 }
        return max(0, min(1, Double(clip.bounds.origin.y / maxScroll)))
    }

    /// Scroll the editor to `fraction` (0…1). Used to carry the preview's position
    /// back on toggle-off.
    func scrollEditor(toFraction fraction: Double) {
        guard let scroll = textView.enclosingScrollView else { return }
        let clamped = max(0, min(1, fraction))
        let docHeight = textView.bounds.height
        let visible = scroll.contentView.bounds.height
        let y = max(0, docHeight - visible) * CGFloat(clamped)
        textView.scroll(NSPoint(x: 0, y: y))
    }

    /// Show or hide the read-only Markdown preview, swapping it for the editor.
    ///
    /// Scroll position is preserved across the swap (proportional by fraction), so
    /// toggling editor↔preview lands you at the same relative place instead of
    /// jumping to the top. The two views are never visible at once; "sync" here
    /// means the outgoing view's fraction is applied to the incoming one.
    public func showPreview(_ show: Bool) {
        if show { buildPreviewIfNeeded() }

        if show {
            // Capture where the editor was before hiding it, to apply to the preview.
            let editorFraction = editorScrollFraction
            isShowingPreview = show
            previewWebView?.isHidden = !show
            scrollView.isHidden = show
            renderPreview()
            // Apply after render so the scrollable height is up to date. A short
            // async hop lets WebKit lay out the freshly-set body first.
            let target = editorFraction
            DispatchQueue.main.async { [weak self] in self?.scrollPreview(toFraction: target) }
            // Give the web view first responder so navigation keys
            // (Home/End/PageUp/PageDown, arrows) scroll the preview, and so ⌘C
            // copies the preview's selection rather than going to whatever else
            // holds focus.
            if let wv = previewWebView { focusWhenInWindow(wv) }
        } else {
            // Read the preview's fraction BEFORE swapping (the web view must still be
            // live to answer). The read is async; the swap and focus happen
            // synchronously so `isPreviewVisible`, menu state, and the toggle's
            // direction check all see the new value immediately — only the editor
            // scroll is applied when the async read returns.
            readPreviewScrollFraction { [weak self] fraction in
                self?.scrollEditor(toFraction: fraction)
            }
            isShowingPreview = false
            previewWebView?.isHidden = true
            scrollView.isHidden = false
            pendingFirstResponder = nil
            view.window?.makeFirstResponder(textView)
        }
    }

    /// A focus request made before the view had a window, applied on `viewDidAppear`.
    private weak var pendingFirstResponder: NSResponder?

    /// Focus `responder` now, or as soon as the view is in a window.
    ///
    /// Auto-preview calls `showPreview(true)` from `viewDidLoad`, where
    /// `view.window` is still nil — so `view.window?.makeFirstResponder(_:)`
    /// silently did nothing. The preview rendered but never took focus, which is
    /// why Select All and ⌘C in an auto-opened preview did nothing at all: the
    /// keystrokes went to whatever else held first responder (a toolbar button).
    /// Toggling the preview off and on "fixed" it only because by then a window
    /// existed. Never drop the request on the floor.
    private func focusWhenInWindow(_ responder: NSResponder) {
        if let window = view.window {
            window.makeFirstResponder(responder)
        } else {
            pendingFirstResponder = responder
        }
    }

    /// Whether the preview shell (the full HTML document with CSS) has been loaded.
    /// After the first load, edits update only the <body> via JS so the scroll
    /// position is kept and the CSS isn't re-parsed. Reset when the theme flips
    /// (the CSS palette depends on dark/light) to force a fresh shell.
    private var previewShellLoadedDark: Bool?

    private func buildPreviewIfNeeded() {
        guard previewWebView == nil else { return }
        let config = WKWebViewConfiguration()
        // Block PAGE/content JavaScript (security): scripts in the rendered document
        // never run. App-initiated evaluateJavaScript (used to update the body in
        // place) still works — it is not "content JS".
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        // PreviewWebView, not a bare WKWebView: while the preview is showing it
        // covers the editor, whose text view is hidden and therefore receives no
        // drag events. Without its own file-drop handling, dropping a file onto a
        // rendered .md silently did nothing.
        let wv = PreviewWebView(frame: .zero, configuration: config)
        wv.translatesAutoresizingMaskIntoConstraints = false
        wv.navigationDelegate = self
        wv.setAccessibilityIdentifier("markdownPreviewWebView")
        // The same handler the editor's text view uses, so a drop behaves
        // identically whether it lands on the editor or the rendered preview.
        wv.onOpenFiles = { [weak self] urls in
            guard let wc = self?.newTabActionTarget as? EditorWindowController else { return }
            wc.openFiles(at: urls)
        }
        wv.isHidden = true
        view.addSubview(wv)
        // Occupy the exact band the editor scroll view occupies.
        NSLayoutConstraint.activate([
            wv.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            wv.topAnchor.constraint(equalTo: scrollView.topAnchor),
            wv.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
        ])
        previewWebView = wv
    }

    private func renderPreview() {
        guard let wv = previewWebView else { return }
        let dark = view.effectiveAppearance.isDark
        // Match the web view's appearance to the actual mode so native controls (GFM
        // task-list checkboxes, scrollbars) render correctly. The original "header
        // dimmed to grey" bug came from CSS `color-scheme: dark`, which the template
        // no longer sets — so a mode-matched appearance keeps the steel header AND
        // gives correctly-themed controls (pinning to aqua broke dark checkboxes).
        wv.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

        let body = MarkdownHTMLRenderer.renderBody(currentText)
        // First load (or after a theme flip) needs the full shell + CSS. Subsequent
        // edits replace only the body via JS, preserving scroll position and avoiding
        // a full page reparse/flash.
        if previewShellLoadedDark != dark {
            wv.loadHTMLString(PreviewHTMLTemplate.htmlDocument(body: body, isDark: dark),
                              baseURL: nil)
            previewShellLoadedDark = dark
            lastRenderedBody = body
        } else if body != lastRenderedBody {
            // Only touch the DOM when the content actually changed. Assigning
            // `innerHTML` destroys the user's selection, and `renderPreview()` is
            // called for reasons that have nothing to do with the text — notably the
            // `effectiveAppearance` observer, which fires when the window changes
            // key/main state. Re-rendering identical HTML there silently wiped a
            // selection between Select All and Copy, so ⌘C copied a stale fragment.
            let json = String(data: (try? JSONSerialization.data(withJSONObject: [body])) ?? Data(),
                              encoding: .utf8) ?? "[\"\"]"
            // json is a 1-element array literal; index [0] yields a safely-escaped
            // JS string of the body HTML.
            wv.evaluateJavaScript("document.body.innerHTML = \(json)[0];")
            lastRenderedBody = body
        }
    }

    /// The body HTML currently in the DOM, so an unchanged re-render can skip the
    /// `innerHTML` write (which would destroy any selection).
    private var lastRenderedBody: String?

    /// Debounced re-render while preview is visible and auto-refresh is on.
    private func schedulePreviewRefresh() {
        guard isShowingPreview, prefs.autoRefreshPreview else { return }
        previewRefreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.renderPreview() }
        previewRefreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

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
        isWrapping = wrap
        if wrap {
            // Width-tracking: the container follows the text view's width, so do
            // NOT pin a fixed containerSize.width (a stale snapshot is exactly
            // what stopped live reflow on resize). We also update it explicitly
            // on each resize via scrollViewContentDidResize().
            container.widthTracksTextView = true
            textView.isHorizontallyResizable = false
            textView.maxSize = NSSize(width: infinite, height: infinite)
            textView.autoresizingMask = [.width]
            scrollView.hasHorizontalScroller = false
            syncWrapWidth()
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

    /// Set the wrapping text container's width to the scroll view's current
    /// content width and force a re-layout, so wrapped text re-flows immediately.
    private func syncWrapWidth() {
        guard isWrapping, let container = textView.textContainer,
              let layoutManager = textView.layoutManager else { return }
        let width = scrollView.contentSize.width
        if container.size.width != width {
            container.size = NSSize(width: width, height: container.size.height)
        }
        // Invalidate layout for the full range so the new width takes effect live.
        let full = NSRange(location: 0, length: (textView.string as NSString).length)
        layoutManager.invalidateLayout(forCharacterRange: full, actualCharacterRange: nil)
    }

    /// Called when the scroll view / clip view resizes; reflows wrapped text.
    @objc private func scrollViewContentDidResize(_ note: Notification) {
        syncWrapWidth()
        ruler?.needsDisplay = true
        updateEditorScrollFractionLabel()
    }

    // MARK: Scroll-fraction AX test hooks
    //
    // Created only under `--expose-scroll-fraction`. AutoPilot's AX layer cannot read
    // a WKWebView's rendered scroll position (or the editor's, reliably), so these
    // hidden labels surface the fractions as AX values a plan can assert. Never
    // created in a normal launch, so they add no production surface.

    private var scrollFractionExposed: Bool {
        LaunchReset.isScrollFractionExposed(in: CommandLine.arguments)
    }
    private var editorScrollFractionLabel: NSTextField?
    private var previewScrollFractionLabel: NSTextField?

    private func makeFractionLabel(_ identifier: String) -> NSTextField {
        let label = NSTextField(labelWithString: "0.000")
        label.setAccessibilityIdentifier(identifier)
        // Must stay in the AX tree for AutoPilot to read it: a hidden view is pruned
        // from accessibility entirely. So keep it un-hidden but visually imperceptible
        // — a 1×1 point in the corner, and explicitly marked an AX element so its
        // string value is exposed. Only ever created under --expose-scroll-fraction.
        label.isHidden = false
        label.isBezeled = false
        label.drawsBackground = false
        label.textColor = .clear
        label.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
        label.setAccessibilityElement(true)
        label.setAccessibilityRole(.staticText)
        view.addSubview(label)
        return label
    }

    /// Create the labels if the flag is set. Idempotent.
    func installScrollFractionHooksIfRequested() {
        guard scrollFractionExposed else { return }
        if editorScrollFractionLabel == nil {
            editorScrollFractionLabel = makeFractionLabel("editorScrollFractionLabel")
        }
        if previewScrollFractionLabel == nil {
            previewScrollFractionLabel = makeFractionLabel("previewScrollFractionLabel")
        }
        updateEditorScrollFractionLabel()
    }

    private func updateEditorScrollFractionLabel() {
        guard let label = editorScrollFractionLabel else { return }
        label.stringValue = String(format: "%.3f", editorScrollFraction)
    }

    /// Push the preview's current fraction into its AX label. Async (JS read).
    func updatePreviewScrollFractionLabel() {
        guard let label = previewScrollFractionLabel else { return }
        readPreviewScrollFraction { fraction in
            label.stringValue = String(format: "%.3f", fraction)
        }
    }

    // MARK: Ruler

    public func configureRuler(visible: Bool) {
        // Only show the gutter when line numbers are enabled AND there is text:
        // an empty document otherwise shows a wide, contentless gutter (most
        // glaring with the sidebar open and nothing loaded).
        let effective = visible && !textView.string.isEmpty
        if effective {
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
            // Re-resolve the depth palette for the new appearance.
            self.bracketColorizer?.refresh()
            if self.isShowingPreview { self.renderPreview() }
        }
    }

    /// Create or tear down the rainbow-bracket overlay based on preferences.
    private func configureBracketColorizer() {
        if prefs.rainbowBrackets {
            let colorizer = bracketColorizer ?? BracketColorizer(textView: textView)
            colorizer.emphasizeEnclosingPair = prefs.emphasizeEnclosingPair
            colorizer.emphasisStyle = prefs.enclosingPairEmphasisStyle
            bracketColorizer = colorizer
            colorizer.refresh()
        } else {
            bracketColorizer?.clear()
            bracketColorizer = nil
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
        if let editorTextView = textView as? EditorTextView {
            editorTextView.pcStyleNavigationKeys = prefs.pcStyleNavigationKeys
            if !prefs.pcStyleNavigationKeys { editorTextView.resetOverwriteMode() }
            editorTextView.autoIndentEnabled = prefs.autoIndent
            editorTextView.indentBetweenBracketsEnabled = prefs.indentBetweenBrackets
            editorTextView.autoCloseBracketsEnabled = prefs.autoCloseBrackets
            editorTextView.indentTabWidth = prefs.tabWidth
            editorTextView.indentUseSpaces = prefs.insertSpacesForTab
            editorTextView.indentAfterOpenersEnabled = languageUsesBlockOpeners
        }
        // Smart behaviors + editor padding (live).
        textView.isAutomaticQuoteSubstitutionEnabled = prefs.smartQuotes
        textView.isAutomaticDashSubstitutionEnabled = prefs.smartDashes
        textView.isAutomaticTextReplacementEnabled = prefs.automaticTextReplacement
        textView.isAutomaticSpellingCorrectionEnabled = prefs.automaticSpellingCorrection
        textView.smartInsertDeleteEnabled = prefs.smartInsertDelete
        textView.isContinuousSpellCheckingEnabled = prefs.continuousSpellChecking
        let pad = CGFloat(prefs.editorPadding)
        textView.textContainerInset = NSSize(width: pad, height: pad)
        textView.needsDisplay = true
        applyStatusBarVisibility(prefs.showStatusBar)
        applyShowInvisibles(prefs.showInvisibles)
        configureBracketColorizer()
        if isShowingPreview {
            renderPreview()   // the web view re-renders with current theme/padding (CSS)
        }
        applyStyleBarVisibility()
    }

    deinit { NotificationCenter.default.removeObserver(self) }
    // MARK: Find & Replace

    /// ⌘F — show the bar in find mode.
    @objc public func showFindBar(_ sender: Any?) { presentFindBar(showingReplace: false) }

    /// ⌥⌘F — show the bar in find+replace mode.
    @objc public func showFindReplaceBar(_ sender: Any?) { presentFindBar(showingReplace: true) }

    /// ⌘L / ⌃G — prompt for a line number and jump to it.
    @objc public func goToLine(_ sender: Any?) {
        guard let window = view.window else { return }
        let sheet = GoToLineSheet()
        goToLineSheet = sheet
        sheet.present(on: window) { [weak self] line in
            guard let self, let offset = TextLocator.characterIndex(forLine: line, in: self.textView.string) else {
                return false
            }
            let range = NSRange(location: offset, length: 0)
            self.textView.setSelectedRange(range)
            if self.isShowingPreview {
                // Editor is hidden behind the preview — scroll the preview to the line.
                self.scrollPreviewToSourceLine(line)
            } else {
                self.textView.scrollRangeToVisible(range)
                self.textView.showFindIndicator(for: range)
                self.view.window?.makeFirstResponder(self.textView)
            }
            return true
        }
    }

    // MARK: Status bar

    private func updateStatusBar() {
        guard let statusBar else { return }
        let sel = textView.selectedRange()
        let pos = TextPosition.lineColumn(forOffset: sel.location, in: textView.string)
        let overrideOrDetected = document?.highlightLanguage
        let language: String
        switch overrideOrDetected {
        case .none: language = "Plain Text"
        case .some("plaintext"): language = "Plain Text"
        case .some(let id): language = LanguageCatalog.displayName(for: id)
        }
        let encoding = TextEncodingDetector.displayName(for: document?.fileEncoding ?? .utf8)
        let overwrite = (textView as? EditorTextView)?.isOverwriteMode ?? false
        statusBar.update(line: pos.line, column: pos.column, language: language, encoding: encoding,
                         lineEnding: document?.lineEnding ?? .lf, overwrite: overwrite, wrap: prefs.wrapLines)
        statusBar.setColumnMode((textView as? EditorTextView)?.isColumnEditing ?? false)
        // Live document statistics (word/line/char count), gated on the pref.
        if prefs.showDocumentStats {
            let counts = TextStatistics.counts(for: textView.string, selection: sel)
            statusBar.setStats(TextStatistics.label(for: counts))
        } else {
            statusBar.setStats("")
        }
    }

    /// Test hooks for document statistics.
    public func refreshStatusBarForTesting() { updateStatusBar() }
    public var statusBarStatsForTesting: String { statusBar?.statsTextForTesting ?? "" }
    public var columnModeIndicatorVisibleForTesting: Bool { statusBar?.columnModeActiveForTesting ?? false }

    /// Apply a manual language override (nil = auto-detect), re-highlight, and
    /// refresh the status bar.
    func setLanguageOverride(_ id: String?) {
        document?.languageOverride = id
        highlighter?.setLanguage(document?.highlightLanguage)
        applyIndentLanguagePolicy()
        updateStatusBar()
        applyStyleBarVisibility()
    }

    /// Push the language-dependent indent policy (openers on/off) onto the text
    /// view. Called whenever the effective language changes, so a mid-session
    /// language switch takes effect without reopening the document.
    private func applyIndentLanguagePolicy() {
        (textView as? EditorTextView)?.indentAfterOpenersEnabled = languageUsesBlockOpeners
    }

    func setLanguageOverrideForTesting(_ id: String?) { setLanguageOverride(id) }

    /// After a Reinterpret (or any op that replaces the buffer from the model),
    /// push the model text into the view, re-highlight, and refresh chrome.
    private func rehighlightAndRefresh() {
        if let storage = textView.textStorage {
            textView.string = document?.text ?? textView.string
            _ = storage
        }
        highlighter?.highlightNow()
        updateStatusBar()
        ruler?.needsDisplay = true
    }

    public func applyStatusBarVisibility(_ visible: Bool) {
        statusBar?.isHidden = !visible
        statusBarHeightConstraint?.constant = visible ? 22 : 0
    }

    public func applyShowInvisibles(_ show: Bool) {
        invisiblesLayoutManager?.showInvisibles = show
        textView.needsDisplay = true
    }

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

    // MARK: Reload banner

    /// Show the external-change banner with `message`, expanding it to its
    /// intrinsic height (collapse constraint deactivated).
    func showReloadBanner(message: String) {
        guard let banner = reloadBanner else { return }
        banner.show(message: message)
        reloadBannerHeightConstraint?.isActive = false
        view.layoutSubtreeIfNeeded()
    }

    /// Hide the external-change banner, collapsing it back to zero height.
    func hideReloadBanner() {
        guard let banner = reloadBanner else { return }
        banner.hide()
        reloadBannerHeightConstraint?.constant = 0
        reloadBannerHeightConstraint?.isActive = true
        view.layoutSubtreeIfNeeded()
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
        if isShowingPreview {
            // The editor is hidden behind the preview; scrolling it does nothing the
            // user can see. Move the PREVIEW to the match instead. (Selection is still
            // set on the editor so toggling back lands there.)
            scrollPreviewToSourceRange(target)
        } else {
            textView.scrollRangeToVisible(target)
            textView.showFindIndicator(for: target)
        }
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
    /// Test hook: simulate a resize-driven reflow and report the wrap container width.
    func syncWrapWidthForTesting() { syncWrapWidth() }
    var wrapContainerWidthForTesting: CGFloat { textView.textContainer?.size.width ?? -1 }
    /// Test hook: whether the scroll view's line-number ruler is visible.
    var rulersVisibleForTesting: Bool { scrollView.rulersVisible }
    /// Test hook: the current showLineNumbers preference.
    var showLineNumbersForTesting: Bool { prefs.showLineNumbers }
    /// Test hook: the current wrapLines preference.
    var wrapLinesForTesting: Bool { prefs.wrapLines }
    /// Test hook: invoke the status bar's wrap toggle as if clicked.
    func simulateStatusBarWrapClickForTesting() { statusBar?.simulateWrapClickForTesting() }
    func simulateStatusBarModeClickForTesting() { statusBar?.simulateModeClickForTesting() }
    /// Test hook: force a synchronous bracket-overlay repaint.
    func refreshBracketColorizerForTesting() { bracketColorizer?.refresh() }
    /// Test hook: re-run the preference-changed handler.
    func applyPreferencesForTesting() { preferencesChanged() }
    var isPreviewVisibleForTesting: Bool { isShowingPreview }
    func togglePreviewForTesting() { showPreview(!isShowingPreview) }
    var previewWebViewForTesting: WKWebView? { previewWebView }
    func refreshPreviewForTesting() { renderPreview() }

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

// MARK: - MarkdownStyleBarDelegate

extension EditorViewController: WKNavigationDelegate {
    /// Schemes a clicked link in the preview is allowed to open in the default app.
    /// Document content is untrusted, so a link must NOT be able to launch arbitrary
    /// `file:`, `data:`, or custom-scheme handlers — only web/mail links are opened.
    private static let allowedLinkSchemes: Set<String> = ["http", "https", "mailto"]

    /// After each full shell load, (re)install the navigation-key scroll handler.
    /// Content JS is disabled, so the keys Home/End/PageUp/PageDown won't scroll the
    /// preview on their own — this app-injected handler restores that behavior.
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(PreviewHTMLTemplate.scrollKeyHandlerJS)
    }

    /// Allow only the in-app HTML load; open clicked web/mail links in the default
    /// browser, and ignore links of any other scheme.
    public func webView(_ webView: WKWebView,
                        decidePolicyFor navigationAction: WKNavigationAction,
                        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated {
            // Never navigate the preview itself; open safe schemes externally, drop
            // everything else (file:/data:/custom: from untrusted document content).
            if let url = navigationAction.request.url,
               let scheme = url.scheme?.lowercased(),
               Self.allowedLinkSchemes.contains(scheme) {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

extension EditorViewController: MarkdownStyleBarDelegate {
    public func styleBar(_ bar: MarkdownStyleBar, didInvoke action: MarkdownStyleBar.Action) {
        applyStyleAction(action)
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
        bracketColorizer?.scheduleRefresh()
        // Empty↔non-empty transitions flip the gutter (hidden when empty).
        configureRuler(visible: prefs.showLineNumbers)
        ruler?.needsDisplay = true
        updateStatusBar()
        schedulePreviewRefresh()
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
        updateStatusBar()
        bracketColorizer?.updateCaretEmphasis()
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
