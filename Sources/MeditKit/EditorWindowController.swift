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
        window.setFrameAutosaveName("medit.editor.window")

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
        shouldCascadeWindows = true

        NotificationCenter.default.addObserver(self, selector: #selector(applySidebarSideIfChanged),
                                               name: Preferences.didChangeNotification, object: nil)
    }

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

    @IBAction public func toggleSidebar(_ sender: Any?) {
        prefs.showSidebar.toggle()
        applySidebarVisibility()
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

    @IBAction public func toggleInvisibles(_ sender: Any?) {
        prefs.showInvisibles.toggle()
        editor?.applyShowInvisibles(prefs.showInvisibles)
    }

    /// Keep the View-menu check marks in sync with current state.
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleSidebar(_:)):
            menuItem.state = prefs.showSidebar ? .on : .off
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
        case #selector(toggleInvisibles(_:)):
            menuItem.state = prefs.showInvisibles ? .on : .off
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
