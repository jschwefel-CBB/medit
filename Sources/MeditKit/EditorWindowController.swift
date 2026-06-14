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
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
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
        window.contentViewController = editor
        shouldCascadeWindows = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Document bridge

    /// Live editor text, read by the document when saving.
    var currentEditorText: String? { editor?.currentText }

    /// The editor's text view, used by cross-tab search to focus a match.
    var focusedTextView: NSTextView? { editor?.textView }

    /// Called by the document after it reloads from disk (revert).
    func documentTextDidReload() {
        editor?.reloadFromDocument()
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
