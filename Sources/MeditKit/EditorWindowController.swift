import AppKit

/// Window controller for one document. Hosts an `EditorViewController`, opts the
/// window into macOS native tabbing (so multiple open documents stack as tabs in
/// one window), and routes View-menu actions (toggle line numbers / wrap) and
/// the Find-in-All-Tabs command.
public final class EditorWindowController: NSWindowController, NSWindowDelegate {

    private let textDocument: TextDocument
    private let prefs: Preferences
    private var editor: EditorViewController!

    public init(document: TextDocument, preferences: Preferences = .shared) {
        self.textDocument = document
        self.prefs = preferences

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.tabbingMode = .preferred         // stack documents as native tabs
        window.tabbingIdentifier = "medit.editor"
        window.setFrameAutosaveName("medit.editor.window")
        window.minSize = NSSize(width: 360, height: 240)

        super.init(window: window)

        window.delegate = self
        let editor = EditorViewController(document: document, preferences: preferences)
        self.editor = editor
        editor.newTabActionTarget = self
        window.contentViewController = editor
        shouldCascadeWindows = true
    }

    public override func windowDidLoad() {
        super.windowDidLoad()
        NSWindow.allowsAutomaticWindowTabbing = true
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

    /// The editor's text view, used by cross-tab search to focus a match.
    var focusedTextView: NSTextView? { editor?.textView }

    /// Test hook: force the editor view (and thus viewDidLoad) to load.
    func loadViewIfNeededForTesting() { editor?.loadViewIfNeeded() }

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

    @IBAction public func toggleLineNumbers(_ sender: Any?) {
        prefs.showLineNumbers.toggle()
        // Preference change notification refreshes all editors; ensure ours too.
        editor?.configureRuler(visible: prefs.showLineNumbers)
    }

    @IBAction public func toggleWordWrap(_ sender: Any?) {
        prefs.wrapLines.toggle()
        editor?.applyWrapMode(prefs.wrapLines)
    }

    /// Keep the View-menu check marks in sync with current state.
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleLineNumbers(_:)):
            menuItem.state = prefs.showLineNumbers ? .on : .off
        case #selector(toggleWordWrap(_:)):
            menuItem.state = prefs.wrapLines ? .on : .off
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
