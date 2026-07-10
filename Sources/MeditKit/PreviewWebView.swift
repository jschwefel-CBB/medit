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
