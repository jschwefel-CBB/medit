import AppKit

/// Window controller for one document. Hosts an `EditorViewController`, opts the
/// window into macOS native tabbing (so multiple open documents stack as tabs in
/// one window), and routes View-menu actions (toggle line numbers / wrap) and
/// the Find-in-All-Tabs command.
public final class EditorWindowController: NSWindowController, NSWindowDelegate {

    private let textDocument: TextDocument
    private let prefs: Preferences
    private var editor: EditorViewController!
    private var sidebar: SidebarViewController!
    private var splitViewController: NSSplitViewController!
    private var sidebarItem: NSSplitViewItem!

    /// Default size for a window with no remembered frame.
    static let defaultWindowSize = NSSize(width: 1100, height: 750)
    /// Hard floor — a window is never restored or resized smaller than this, so
    /// it can't come back tiny from a stale autosaved frame.
    static let minWindowSize = NSSize(width: 800, height: 560)

    public init(document: TextDocument, preferences: Preferences = .shared) {
        self.textDocument = document
        self.prefs = preferences

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: EditorWindowController.defaultWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.tabbingMode = .preferred         // stack documents as native tabs
        window.tabbingIdentifier = "medit.editor"
        // A real floor so a window can never be saved/restored absurdly small
        // (the old 360x240 floor is what let it come back tiny).
        window.minSize = EditorWindowController.minWindowSize
        // We manage the window frame ourselves (persisted to the windowFrame
        // pref and restored in restoreWindowFrame). Opt OUT of AppKit's automatic
        // window-state restoration so it can't fight our explicit positioning —
        // that tug-of-war was making windows land in the wrong place / lower-left.
        window.isRestorable = false

        super.init(window: window)

        window.delegate = self
        let editor = EditorViewController(document: document, preferences: preferences)
        self.editor = editor
        editor.newTabActionTarget = self

        let sidebar = SidebarViewController(preferences: preferences)
        self.sidebar = sidebar

        let split = NSSplitViewController()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.canCollapse = true
        sidebarItem.minimumThickness = 180
        let editorItem = NSSplitViewItem(viewController: editor)
        // Sidebar on the left by default; sidebarOnRight swaps the order.
        if preferences.sidebarOnRight {
            split.addSplitViewItem(editorItem)
            split.addSplitViewItem(sidebarItem)
        } else {
            split.addSplitViewItem(sidebarItem)
            split.addSplitViewItem(editorItem)
        }
        split.splitView.autosaveName = "medit.sidebar.split"
        self.splitViewController = split
        self.sidebarItem = sidebarItem
        sidebar.windowController = self
        window.contentViewController = split
        // Apply initial visibility (default collapsed/off).
        sidebarItem.isCollapsed = !preferences.showSidebar
        // Don't let AppKit cascade windows to a new spot — that's what made
        // windows march toward the lower-left on open. We position explicitly
        // from the saved frame (or center a brand-new window) in restoreWindowFrame().
        shouldCascadeWindows = false
        restoreWindowFrame()

        NotificationCenter.default.addObserver(self, selector: #selector(applySidebarSideIfChanged),
                                               name: Preferences.didChangeNotification, object: nil)
    }

    // MARK: Window frame persistence (reopen at last size/position)

    /// Set true once the saved frame has been applied, so the construction-time
    /// flurry of resize/move notifications (which carry transient setup frames)
    /// can't overwrite the persisted value before we've even restored it.
    private var frameTrackingEnabled = false

    /// Restore the last-saved window frame, or center a default-sized window the
    /// first time. Clamped to the visible screen so a frame saved on a now-absent
    /// external display can't strand the window offscreen.
    private func restoreWindowFrame() {
        guard let window else { return }
        let saved = prefs.windowFrame
        if !saved.isEmpty {
            let frame = NSRectFromString(saved)
            if frame.width >= EditorWindowController.minWindowSize.width,
               frame.height >= EditorWindowController.minWindowSize.height {
                window.setFrame(clampToScreen(frame), display: false)
                enableFrameTrackingAfterSetup()
                return
            }
        }
        // No saved frame: center the (already default-sized) window. The window
        // was created at defaultWindowSize, so just position it — no resize, which
        // keeps us from disturbing content/scroll-view width baselines.
        window.center()
        enableFrameTrackingAfterSetup()
    }

    /// Begin honoring move/resize notifications only after the construction-time
    /// layout settles, so transient setup frames never get persisted.
    private func enableFrameTrackingAfterSetup() {
        DispatchQueue.main.async { [weak self] in self?.frameTrackingEnabled = true }
    }

    /// Keep a frame within the visible area of some screen (handles a display
    /// that was unplugged since the frame was saved).
    private func clampToScreen(_ frame: NSRect) -> NSRect {
        let screens = NSScreen.screens
        // If the frame already intersects a screen meaningfully, keep it.
        if screens.contains(where: { $0.visibleFrame.intersects(frame) }) { return frame }
        guard let main = NSScreen.main?.visibleFrame else { return frame }
        var f = frame
        f.size.width = Swift.min(f.size.width, main.width)
        f.size.height = Swift.min(f.size.height, main.height)
        f.origin.x = main.midX - f.size.width / 2
        f.origin.y = main.midY - f.size.height / 2
        return f
    }

    /// Persist the current window frame so the next launch reopens here. Skips
    /// degenerate frames (zero-size, or smaller than the floor) so a transient
    /// mid-setup frame can't poison the saved value.
    private func saveWindowFrame() {
        guard frameTrackingEnabled, let window else { return }
        let f = window.frame
        guard f.width >= EditorWindowController.minWindowSize.width,
              f.height >= EditorWindowController.minWindowSize.height else { return }
        prefs.windowFrame = NSStringFromRect(f)
    }

    public func windowDidResize(_ notification: Notification) { saveWindowFrame() }
    public func windowDidMove(_ notification: Notification) { saveWindowFrame() }

    /// Test hook: persist the current frame as a move/resize would.
    func simulateWindowMoveForTesting() { frameTrackingEnabled = true; saveWindowFrame() }

    @objc private func applySidebarSideIfChanged() {
        guard let split = splitViewController, let sidebarItem = sidebarItem else { return }
        let wantRight = prefs.sidebarOnRight
        let isRight = split.splitViewItems.last === sidebarItem
        if wantRight != isRight {
            split.removeSplitViewItem(sidebarItem)
            if wantRight { split.addSplitViewItem(sidebarItem) }
            else { split.insertSplitViewItem(sidebarItem, at: 0) }
        }
    }

    public override func windowDidLoad() {
        super.windowDidLoad()
        NSWindow.allowsAutomaticWindowTabbing = true
        enforceMinimumSize()
        // If the sidebar pref persisted ON from a prior session, the pane is
        // already visible — but it must also be activated (restore roots / prompt
        // for a folder), which the toggle path would otherwise be the only thing
        // to do. Without this, a persisted-on sidebar shows up empty and silent.
        if prefs.showSidebar { sidebar?.activate() }
    }

    /// If a restored/autosaved frame came back smaller than the floor (e.g. an
    /// old tiny session), grow it back to at least the minimum, keeping the
    /// top-left corner anchored. Honors "remember my size" for any size at or
    /// above the floor.
    private func enforceMinimumSize() {
        guard let window else { return }
        let min = EditorWindowController.minWindowSize
        let frame = window.frame
        if frame.width < min.width || frame.height < min.height {
            let newWidth = max(frame.width, min.width)
            let newHeight = max(frame.height, min.height)
            // Anchor top-left: keep maxY (top) fixed as height grows.
            let newOrigin = NSPoint(x: frame.origin.x, y: frame.maxY - newHeight)
            window.setFrame(NSRect(origin: newOrigin, size: NSSize(width: newWidth, height: newHeight)),
                            display: true)
        }
    }

    /// Order the window on screen, then force the tab bar visible. Empirically,
    /// `toggleTabBar(_:)` reliably shows the bar for a lone `.preferred` window
    /// only when called AFTER the window is on screen — and delegate callbacks
    /// like windowDidBecomeKey don't always fire (e.g. accessory/background
    /// launches), so we do it here in the show flow rather than depending on
    /// them. `isTabBarVisible` is get-only, so toggle is the only lever.
    public override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        ensureTabBarVisible()
    }

    /// When focus lands on this window — including after a sibling tab closes,
    /// which collapses a 2-tab group down to this lone tab and hides the bar —
    /// re-assert tab-bar visibility.
    public func windowDidBecomeKey(_ notification: Notification) {
        ensureTabBarVisible()
        sidebar?.revealActiveFile()
    }

    public func windowDidBecomeMain(_ notification: Notification) {
        ensureTabBarVisible()
    }

    /// Show the tab bar for a lone tab so the native "+" (and tabs) are always
    /// present — gedit-style. Idempotent: only toggles when the group exists and
    /// the bar is hidden. Runs on the next runloop pass to ensure the window has
    /// finished ordering on screen / the closing tab has fully detached.
    func ensureTabBarVisible() {
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window, let group = window.tabGroup else { return }
            if !group.isTabBarVisible {
                window.toggleTabBar(nil)
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Document bridge

    /// Live editor text, read by the document when saving.
    var currentEditorText: String? { editor?.currentText }

    /// The active document's file URL (nil for untitled). Used by the sidebar's
    /// default root.
    var currentDocumentFileURL: URL? { textDocument.fileURL }

    /// The editor's text view, used by cross-tab search to focus a match.
    var focusedTextView: NSTextView? { editor?.textView }

    /// The editor view controller, for external-change banner display.
    var editorForExternalChange: EditorViewController? { editor }

    /// Test hook: force the editor view (and thus viewDidLoad) to load.
    func loadViewIfNeededForTesting() { editor?.loadViewIfNeeded() }

    /// Test hook: the editor view controller.
    var editorForTesting: EditorViewController? { editor }

    /// Test hook: the underlying document.
    var documentForTesting: TextDocument? { textDocument }

    /// Called by the document after it reloads from disk (revert).
    func documentTextDidReload() {
        editor?.reloadFromDocument()
    }

    // MARK: New tab

    /// Standard AppKit hook (⌘T / tab-bar "+"): open a new untitled document and
    /// add its window as a tab adjacent to this one.
    @IBAction public override func newWindowForTab(_ sender: Any?) {
        openNewTab()
    }

    /// Also reachable from our context menus.
    @IBAction public func newTabFromMenu(_ sender: Any?) {
        openNewTab()
    }

    /// Open `url` as a tab in THIS window (so the sidebar stays put), or focus the
    /// tab if the file is already open. Called by the sidebar.
    public func openFile(at url: URL) {
        openFiles(at: [url])
    }

    /// Open one or more files as tabs in THIS window, preserving the given order.
    /// Opens sequentially (openDocument is async, so a plain loop would race and
    /// tab them in nondeterministic / reverse order) and chains each new tab
    /// after the previously inserted one so left-to-right order matches `urls`.
    public func openFiles(at urls: [URL]) {
        guard window != nil else { return }
        var remaining = urls
        openNext(&remaining, after: nil)
    }

    private func openNext(_ urls: inout [URL], after previous: NSWindow?) {
        guard let window else { return }
        guard !urls.isEmpty else { return }
        let url = urls.removeFirst()
        var rest = urls

        // Already open? Focus it, then continue with the rest (anchored after it).
        if let existing = NSDocumentController.shared.document(for: url),
           let w = existing.windowControllers.first?.window {
            w.makeKeyAndOrderFront(nil)
            openNext(&rest, after: w)
            return
        }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: false) { [weak self] doc, _, error in
            if let error { NSApp.presentError(error) }
            var anchor = previous
            if let doc {
                if doc.windowControllers.isEmpty { doc.makeWindowControllers() }
                if let newWindow = doc.windowControllers.first?.window {
                    // Place after the previously inserted tab (or the original
                    // window for the first file) so drop order is preserved.
                    let target = previous ?? window
                    target.addTabbedWindow(newWindow, ordered: .above)
                    newWindow.makeKeyAndOrderFront(nil)
                    anchor = newWindow
                }
            }
            var restCopy = rest
            self?.openNext(&restCopy, after: anchor)
        }
    }

    private func openNewTab() {
        guard let window else { return }
        do {
            let controller = NSDocumentController.shared
            let newDoc = try controller.openUntitledDocumentAndDisplay(false)
            guard let newWindow = newDoc.windowControllers.first?.window else {
                newDoc.makeWindowControllers()
                if let w = newDoc.windowControllers.first?.window {
                    window.addTabbedWindow(w, ordered: .above)
                    w.makeKeyAndOrderFront(nil)
                }
                return
            }
            window.addTabbedWindow(newWindow, ordered: .above)
            newWindow.makeKeyAndOrderFront(nil)
        } catch {
            NSApp.presentError(error)
        }
    }

    // MARK: View menu actions

    // NOTE: named `toggleSidebarVisible`, NOT `toggleSidebar` — AppKit's
    // NSSplitViewController defines a built-in `toggleSidebar(_:)` that sits
    // deeper in the responder chain (it's the window's contentViewController) and
    // would intercept the menu action, collapsing the pane WITHOUT updating our
    // pref or calling activate(). The distinct name routes the action to us.
    @IBAction public func toggleSidebarVisible(_ sender: Any?) {
        prefs.showSidebar.toggle()
        applySidebarVisibility()
    }

    /// Flip the sidebar between the Folders tree and the Recent Files list,
    /// showing the sidebar first if it's hidden.
    @IBAction public func toggleSidebarPane(_ sender: Any?) {
        if !prefs.showSidebar { prefs.showSidebar = true; applySidebarVisibility() }
        sidebar?.togglePane()
    }

    private func applySidebarVisibility() {
        let show = prefs.showSidebar
        sidebarItem?.isCollapsed = !show
        if show { sidebar?.activate() } else { sidebar?.deactivate() }
    }

    @IBAction public func openFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openFolder(at: url)
    }

    /// Open a folder as a sidebar root programmatically (no panel). Shared by the
    /// menu handler and the `--open-folder` launch hook used by the test driver.
    public func openFolder(at url: URL) {
        if !prefs.showSidebar { prefs.showSidebar = true; applySidebarVisibility() }
        sidebar?.activate()
        sidebar?.addRoot(url)
    }

    @IBAction public func toggleHiddenFiles(_ sender: Any?) {
        prefs.showHiddenFiles.toggle()
        sidebar?.refreshFromPreferences()
    }

    @IBAction public func toggleRevealActiveFile(_ sender: Any?) {
        prefs.syncSidebarWithActiveTab.toggle()
        if prefs.syncSidebarWithActiveTab { sidebar?.revealActiveFile() }
    }

    @IBAction public func toggleLineNumbers(_ sender: Any?) {
        prefs.showLineNumbers.toggle()
        // Preference change notification refreshes all editors; ensure ours too.
        editor?.configureRuler(visible: prefs.showLineNumbers)
    }

    @IBAction public func toggleWordWrap(_ sender: Any?) {
        prefs.wrapLines.toggle()
        editor?.applyWrapMode(prefs.wrapLines)
    }

    @IBAction public func toggleStatusBar(_ sender: Any?) {
        prefs.showStatusBar.toggle()
        editor?.applyStatusBarVisibility(prefs.showStatusBar)
    }

    @IBAction public func toggleDocumentStats(_ sender: Any?) {
        // Toggling the pref posts the change notification, which the editor
        // observes and refreshes the status bar (showing/hiding the count).
        prefs.showDocumentStats.toggle()
    }

    @IBAction public func toggleInvisibles(_ sender: Any?) {
        prefs.showInvisibles.toggle()
        editor?.applyShowInvisibles(prefs.showInvisibles)
    }

    @IBAction public func toggleMarkdownPreview(_ sender: Any?) {
        guard let editor else { return }
        editor.showPreview(!editor.isPreviewVisible)
    }

    @IBAction public func toggleAutoShowMarkdownPreview(_ sender: Any?) {
        prefs.autoShowPreviewForMarkdown.toggle()
    }

    @IBAction public func toggleMarkdownToolbar(_ sender: Any?) {
        prefs.showMarkdownToolbar.toggle()
        editor?.applyStyleBarVisibility()
    }

    // Distinct name (NOT a generic `toggleBrackets`) to avoid any AppKit selector
    // collision — the lesson from the toggleSidebar/NSSplitViewController clash.
    @IBAction public func toggleRainbowBrackets(_ sender: Any?) {
        prefs.rainbowBrackets.toggle()
        // The pref-change notification reconfigures the colorizer in each editor.
    }

    /// Keep the View-menu check marks in sync with current state.
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleSidebarVisible(_:)):
            menuItem.state = prefs.showSidebar ? .on : .off
        case #selector(toggleSidebarPane(_:)):
            // Checked when the Recent pane is showing.
            menuItem.state = (prefs.sidebarPane == "recent") ? .on : .off
        case #selector(toggleHiddenFiles(_:)):
            menuItem.state = prefs.showHiddenFiles ? .on : .off
        case #selector(toggleRevealActiveFile(_:)):
            menuItem.state = prefs.syncSidebarWithActiveTab ? .on : .off
        case #selector(toggleLineNumbers(_:)):
            menuItem.state = prefs.showLineNumbers ? .on : .off
        case #selector(toggleWordWrap(_:)):
            menuItem.state = prefs.wrapLines ? .on : .off
        case #selector(toggleStatusBar(_:)):
            menuItem.state = prefs.showStatusBar ? .on : .off
        case #selector(toggleDocumentStats(_:)):
            menuItem.state = prefs.showDocumentStats ? .on : .off
        case #selector(toggleInvisibles(_:)):
            menuItem.state = prefs.showInvisibles ? .on : .off
        case #selector(toggleRainbowBrackets(_:)):
            menuItem.state = prefs.rainbowBrackets ? .on : .off
        case #selector(toggleMarkdownPreview(_:)):
            menuItem.state = (editor?.isPreviewVisible == true) ? .on : .off
            // Only meaningful for Markdown documents.
            return textDocument.highlightLanguage == "markdown"
        case #selector(toggleAutoShowMarkdownPreview(_:)):
            menuItem.state = prefs.autoShowPreviewForMarkdown ? .on : .off
        case #selector(toggleMarkdownToolbar(_:)):
            menuItem.state = prefs.showMarkdownToolbar ? .on : .off
            return textDocument.highlightLanguage == "markdown"
        default:
            break
        }
        return true
    }

    // MARK: Find in all tabs

    @IBAction public func findInAllTabs(_ sender: Any?) {
        FindInTabsCoordinator.shared.present(relativeTo: window)
    }
}
