import AppKit
import WebKit

/// The Markdown preview's web view.
///
/// Exists to restore file drag-and-drop. While the preview is showing it covers
/// the editor (`scrollView.isHidden = true`), and a hidden view receives no drag
/// events — so dropping a file onto a rendered `.md` document landed on the web
/// view, which has no file-drop handling of its own and silently ignored it.
/// Since auto-preview became the default, that is the *normal* state for every
/// Markdown document, so file drops appeared to be broken outright.
///
/// Only **file** drags are intercepted. Everything else (text drags, links)
/// falls through to WebKit's own handling untouched.
final class PreviewWebView: WKWebView {

    /// Called with the dropped file URLs. Wired to the same handler the editor's
    /// text view uses, so a drop behaves identically in either view.
    var onOpenFiles: (([URL]) -> Void)?

    /// Both types are required: a single-file Finder drag advertises `.fileURL`,
    /// while a *multi*-file drag advertises only the legacy filenames type. Omit
    /// either and that shape of drop never even reaches `draggingEntered`.
    private static let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    private static let fileDragTypes: [NSPasteboard.PasteboardType] = [.fileURL, filenamesType]

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        registerForDraggedTypes(PreviewWebView.fileDragTypes)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static let tabKeyCode: UInt16 = 48   // kVK_Tab

    /// What a key chord should do to the tab selection. Pure and unit-testable —
    /// the *decision* is separated from the *effect* (`selectNextTab`), which only
    /// works on-screen and is verified end-to-end by the AP plan.
    enum TabSwitchIntent { case next, previous, none }

    /// ⌃⇥ → next, ⌃⇧⇥ → previous, but only when there is another tab to move to.
    /// Anything else (⌘⇥, plain ⇥, single tab) is `none`, so the chord falls
    /// through to WebKit / the responder chain untouched.
    static func tabSwitchIntent(keyCode: UInt16, flags: NSEvent.ModifierFlags,
                                tabCount: Int) -> TabSwitchIntent {
        guard keyCode == tabKeyCode, tabCount > 1 else { return .none }
        let f = flags.intersection(.deviceIndependentFlagsMask)
        if f == .control { return .next }
        if f == [.control, .shift] { return .previous }
        return .none
    }

    /// Which zoom command a ⌘ chord maps to (pure, unit-testable). ⌘+/⌘= zoom in,
    /// ⌘-/⌘_ zoom out, ⌘0 actual size; anything else is `nil`. Shift is allowed
    /// (⌘+ is physically ⌘⇧=), but Control/Option are not.
    static func zoomSelector(flags: NSEvent.ModifierFlags, characters: String?) -> Selector? {
        let f = flags.intersection(.deviceIndependentFlagsMask)
        guard f.contains(.command), !f.contains(.control), !f.contains(.option),
              let chars = characters else { return nil }
        switch chars {
        case "+", "=": return Selector(("zoomIn:"))
        case "-", "_": return Selector(("zoomOut:"))
        case "0":      return Selector(("actualSize:"))
        default:       return nil
        }
    }

    /// Intercept two chords WebKit would otherwise mishandle while the preview is
    /// first responder. (Only reached when the preview is visible — a hidden view
    /// is skipped during key-equivalent dispatch — so editor-mode behavior is
    /// untouched.)
    ///
    /// 1. **⌃⇥ / ⌃⇧⇥ (switch tab).** WebKit's own `performKeyEquivalent` swallows
    ///    the FIRST Ctrl+Tab (it returns handled without switching), so the menu's
    ///    Show Next/Previous Tab item didn't fire until a second press — the "twice
    ///    on the rendered page, once in text" bug. Drive the window's native tab
    ///    switch directly instead, on the first press.
    /// 2. **⌘+ / ⌘= / ⌘- / ⌘0 (text size).** Routed to the controller so WebKit
    ///    can't eat the zoom chords; matches the editor's behavior.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        switch PreviewWebView.tabSwitchIntent(keyCode: event.keyCode, flags: event.modifierFlags,
                                              tabCount: window?.tabGroup?.windows.count ?? 0) {
        case .next:     window?.selectNextTab(nil); return true
        case .previous: window?.selectPreviousTab(nil); return true
        case .none:     break
        }

        if let sel = PreviewWebView.zoomSelector(flags: event.modifierFlags,
                                                 characters: event.charactersIgnoringModifiers) {
            NSApp.sendAction(sel, to: nil, from: self)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    /// ⌥+scroll changes the text size (routed to the controller); everything else
    /// scrolls the page normally.
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.option), event.scrollingDeltaY != 0 {
            NSApp.sendAction(Selector(("zoomScrollFromEvent:")), to: nil, from: event)
            return
        }
        super.scrollWheel(with: event)
    }

    /// File URLs on `pasteboard`, reading both the modern and legacy flavors.
    private func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL] ?? [])
            .filter(\.isFileURL)
        if !urls.isEmpty { return urls }
        guard let names = pasteboard.propertyList(forType: PreviewWebView.filenamesType) as? [String] else {
            return []
        }
        return names.map { URL(fileURLWithPath: $0) }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !fileURLs(on: sender.draggingPasteboard).isEmpty { return .copy }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !fileURLs(on: sender.draggingPasteboard).isEmpty { return .copy }
        return super.draggingUpdated(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if !fileURLs(on: sender.draggingPasteboard).isEmpty { return true }
        return super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(on: sender.draggingPasteboard)
        guard !urls.isEmpty else { return super.performDragOperation(sender) }
        onOpenFiles?(urls)
        return true
    }

    /// Test hook: simulate dropping file URLs onto the preview.
    func performFileDropForTesting(_ urls: [URL]) { onOpenFiles?(urls) }
}
