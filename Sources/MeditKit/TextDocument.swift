import AppKit

/// A plain-text document. Reads bytes through `TextEncodingDetector`, remembers
/// the detected encoding and BOM so saves round-trip faithfully, and hands its
/// text to an `EditorWindowController` for display.
///
/// medit is a document-based app: `NSDocumentController` creates one
/// `TextDocument` per file and this class owns the model (the string + encoding
/// metadata). The view layer reads `text` and writes back via `updateText(_:)`.
public final class TextDocument: NSDocument {

    /// The full text of the document. Mutations from the editor flow back
    /// through `updateText(_:)` (which also flags the document dirty).
    public private(set) var text: String = ""

    /// A pristine, untitled document: never saved (no file), currently empty, and
    /// never edited. Such a lone tab can be replaced when a file is opened.
    public var isPristineUntitled: Bool {
        fileURL == nil && text.isEmpty && !isDocumentEdited
    }

    /// Encoding to use when saving. Defaults to UTF-8 for new documents;
    /// set to the detected encoding when an existing file is read.
    public var fileEncoding: String.Encoding = .utf8

    /// Whether to write a BOM on save (true when the read file had one, for
    /// UTF-8; UTF-16/32 always emit a BOM via Foundation regardless).
    public var writesBOM: Bool = false

    /// Manual language override (nil = auto-detect). Session-only; not persisted.
    public var languageOverride: String?

    /// Line ending used on save (detected on read; default LF).
    public var lineEnding: LineEnding = .lf
    /// The original file bytes from the last read, for Reinterpret.
    public private(set) var originalData: Data?

    /// The file's modification date when we last read or wrote it. Used to ignore
    /// spurious file-presenter callbacks (including our own I/O) and only react to
    /// a genuine on-disk change.
    private var lastKnownModificationDate: Date?

    /// Set by the window controller so the document can push fresh text into
    /// the editor after a revert/reload.
    weak var editorWindowController: EditorWindowController?

    public override init() {
        super.init()
    }

    // MARK: NSDocument plumbing

    public override class var autosavesInPlace: Bool { true }

    public override func makeWindowControllers() {
        let controller = EditorWindowController(document: self)
        addWindowController(controller)
        self.editorWindowController = controller
    }

    // MARK: Printing

    /// Print the rendered Markdown preview for Markdown documents; otherwise fall
    /// back to AppKit's default (plain text) printing. Uses the live editor text
    /// so unsaved edits print too.
    public override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        let info = NSPrintInfo(dictionary: printSettings)
        let text = currentEditorTextOrModel
        if highlightLanguage == "markdown" {
            let op = MarkdownPrinter.operation(forMarkdown: text, info: info)
            op.jobTitle = fileURL?.lastPathComponent ?? "Markdown"
            return op
        }
        // Plain-text fallback (NSDocument's base printOperation is unimplemented).
        return MarkdownPrinter.plainTextOperation(
            text, info: info,
            jobTitle: fileURL?.lastPathComponent ?? "Document",
            lineNumbers: Preferences.shared.printLineNumbers)
    }

    // MARK: Reading

    public override func read(from data: Data, ofType typeName: String) throws {
        guard let decoded = PerfLog.measure("file.decode", "bytes=\(data.count)",
                                            { TextEncodingDetector.decode(data) }) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadInapplicableStringEncodingError)
        }
        self.text = decoded.string
        self.fileEncoding = decoded.encoding
        self.writesBOM = decoded.hadBOM
        self.originalData = data
        self.lineEnding = PerfLog.measure("file.detectLineEndings", "chars=\(decoded.string.count)",
                                          { LineEndings.detect(decoded.string) })
        captureModificationDate()
        // If the window already exists (revert), refresh its editor.
        editorWindowController?.documentTextDidReload()
    }

    /// Record the current on-disk modification date of the file (if any).
    private func captureModificationDate() {
        lastKnownModificationDate = currentFileModificationDate()
    }

    /// AppKit sets the document's URL on open, save-as, and move. Whenever a real
    /// file URL is established, add it to the Recent Files list. This one hook
    /// covers open-from-anywhere (Finder, File ▸ Open, sidebar, drag) and save-as.
    public override var fileURL: URL? {
        didSet {
            if let url = fileURL, url.isFileURL, url != oldValue {
                RecentFilesStore.shared.record(url)
            }
        }
    }

    private func currentFileModificationDate() -> Date? {
        guard let url = fileURL else { return nil }
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    // MARK: Writing

    public override func data(ofType typeName: String) throws -> Data {
        // Pull the freshest text from the editor if it's loaded, so an
        // in-progress edit is captured even before the model sync fires.
        if let live = editorWindowController?.currentEditorText {
            self.text = live
        }
        // Build the on-disk bytes from a LOCAL copy so a save never mutates the
        // in-memory text (which would disturb the caret/selection in the editor).
        var outText = self.text
        if Preferences.shared.stripTrailingWhitespaceOnSave {
            outText = TextHygiene.cleaned(outText, stripTrailing: true, ensureFinalNewline: true)
        }
        outText = LineEndings.normalize(outText, to: lineEnding)
        return TextEncodingDetector.encode(outText, as: fileEncoding, includeBOM: writesBOM)
    }

    // MARK: Editor <-> model sync

    /// Called by the editor when its text changes. Marks the document edited so
    /// the close/save machinery and the dirty dot behave correctly.
    public func updateText(_ newText: String) {
        guard newText != text else { return }
        text = newText
        updateChangeCount(.changeDone)
    }

    // MARK: Encoding / line-ending operations

    /// Re-decode the original file bytes as `encoding` (fixes a wrong auto-detect).
    /// No-op if there are no original bytes or decode fails.
    public func reinterpret(as encoding: String.Encoding) {
        guard let data = originalData,
              let decoded = String(bytes: data, encoding: encoding) else { return }
        self.text = decoded
        self.fileEncoding = encoding
        self.lineEnding = LineEndings.detect(decoded)
        editorWindowController?.documentTextDidReload()
        updateChangeCount(.changeDone)
    }

    /// Keep the current text; write it in `encoding` on the next save.
    public func convert(to encoding: String.Encoding) {
        guard encoding != fileEncoding else { return }
        self.fileEncoding = encoding
        updateChangeCount(.changeDone)
    }

    /// Set the save line ending and normalize the in-memory text to match.
    public func setLineEnding(_ ending: LineEnding) {
        guard ending != lineEnding else { return }
        self.lineEnding = ending
        let normalized = LineEndings.normalize(text, to: ending)
        if normalized != text {
            self.text = normalized
            editorWindowController?.documentTextDidReload()
            updateChangeCount(.changeDone)
        }
    }

    // MARK: External-change detection (NSFilePresenter)

    /// Reload from disk, refreshing the editor. Safe to call from the banner.
    public func revertToSavedSafely() {
        guard let url = fileURL, let type = fileType else { return }
        try? revert(toContentsOf: url, ofType: type)
        // revert() calls read(from:) which re-captures the modification date.
    }

    public override func presentedItemDidChange() {
        // Called on a background queue; marshal to main.
        DispatchQueue.main.async { [weak self] in
            self?.handleExternalChange(deleted: false)
        }
    }

    public override func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.handleExternalChange(deleted: true)
            completionHandler(nil)
        }
    }

    private func handleExternalChange(deleted: Bool) {
        guard let url = fileURL else { return }

        if deleted {
            // Only treat as deleted if the file truly no longer exists (rename/
            // atomic-save can fire this spuriously).
            if FileManager.default.fileExists(atPath: url.path) { return }
            updateChangeCount(.changeDone)
            editorWindowController?.editorForExternalChange?.showReloadBanner(message: "The file has been moved or deleted.")
            return
        }

        // Ignore callbacks that aren't a genuine on-disk change. This kills the
        // false positive on open/save (our own I/O) and spurious presenter pings:
        // the file must (a) have a newer modification date than the one we
        // recorded, AND (b) actually contain different bytes than we loaded.
        guard isGenuineExternalChange(url: url) else { return }

        let policy = Preferences.shared.externalChangePolicy
        switch ExternalChangeResolver.action(policy: policy, isDirty: isDocumentEdited) {
        case .reloadSilently:
            revertToSavedSafely()
        case .banner:
            editorWindowController?.editorForExternalChange?.showReloadBanner(message: "This file has changed on disk.")
        case .prompt:
            presentReloadPrompt()
        }
    }

    /// True only when the file on disk actually contains different bytes than
    /// what we last loaded. The byte comparison is the authoritative signal (it
    /// kills the false positive on open/save and any spurious presenter ping);
    /// the modification date is only a cheap pre-check to skip the read when the
    /// file demonstrably hasn't been touched since we recorded it.
    ///
    /// Note: filesystem mtime can have 1-second resolution, so we do NOT treat
    /// "same second" as "unchanged" — only a strictly-older disk date short-
    /// circuits. Otherwise we fall through to the content comparison.
    private func isGenuineExternalChange(url: URL) -> Bool {
        let diskDate = currentFileModificationDate()
        // Skip the read only if the disk date is strictly OLDER than what we
        // recorded (can't be a newer change). Equal or newer -> verify content.
        if let known = lastKnownModificationDate, let disk = diskDate, disk < known {
            return false
        }
        guard let diskData = try? Data(contentsOf: url) else { return false }
        guard let original = originalData else {
            // No baseline bytes (shouldn't happen for a loaded file) — be safe.
            lastKnownModificationDate = diskDate
            return false
        }
        if diskData == original {
            // Same content (our own save, a touch, a no-op ping). Record the date
            // and the (unchanged) bytes so we don't keep re-reading.
            lastKnownModificationDate = diskDate
            return false
        }
        // Genuine change: adopt the new bytes as the baseline so the same change
        // isn't reported twice, and update the date.
        originalData = diskData
        lastKnownModificationDate = diskDate
        return true
    }

    private func presentReloadPrompt() {
        let alert = NSAlert()
        alert.messageText = "This file has changed on disk."
        alert.informativeText = "Reload it and discard your unsaved changes, or keep your version?"
        alert.addButton(withTitle: "Reload")
        alert.addButton(withTitle: "Keep My Version")
        if alert.runModal() == .alertFirstButtonReturn {
            revertToSavedSafely()
        }
    }

    /// Auto-detected language: file extension first, then a shebang on the first
    /// line. nil when neither matches.
    public var detectedLanguage: String? {
        if let url = fileURL, let byExt = LanguageMap.language(forURL: url) {
            return byExt
        }
        let firstLine = text.prefix(while: { $0 != "\n" })
        return ShebangDetector.language(forFirstLine: String(firstLine))
    }

    /// The language used for highlighting: a manual override wins, else the
    /// detected language.
    public var highlightLanguage: String? {
        languageOverride ?? detectedLanguage
    }

    /// The most current text: the live editor contents if a window is open,
    /// otherwise the model. Used by cross-tab search.
    var currentEditorTextOrModel: String {
        editorWindowController?.currentEditorText ?? text
    }

    /// Test hook: seed the model text without a file read.
    func setTextForTesting(_ value: String) { text = value }

    /// Test hooks for the external-change guard.
    func isGenuineExternalChangeForTesting(url: URL) -> Bool { isGenuineExternalChange(url: url) }
    func captureModificationDateForTesting() { captureModificationDate() }
    func setOriginalDataForTesting(_ data: Data) { originalData = data }
}
