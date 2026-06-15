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

    /// Encoding to use when saving. Defaults to UTF-8 for new documents;
    /// set to the detected encoding when an existing file is read.
    public var fileEncoding: String.Encoding = .utf8

    /// Whether to write a BOM on save (true when the read file had one, for
    /// UTF-8; UTF-16/32 always emit a BOM via Foundation regardless).
    public var writesBOM: Bool = false

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

    // MARK: Reading

    public override func read(from data: Data, ofType typeName: String) throws {
        guard let decoded = TextEncodingDetector.decode(data) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadInapplicableStringEncodingError)
        }
        self.text = decoded.string
        self.fileEncoding = decoded.encoding
        self.writesBOM = decoded.hadBOM
        // If the window already exists (revert), refresh its editor.
        editorWindowController?.documentTextDidReload()
    }

    // MARK: Writing

    public override func data(ofType typeName: String) throws -> Data {
        // Pull the freshest text from the editor if it's loaded, so an
        // in-progress edit is captured even before the model sync fires.
        if let live = editorWindowController?.currentEditorText {
            self.text = live
        }
        if Preferences.shared.stripTrailingWhitespaceOnSave {
            self.text = TextHygiene.cleaned(self.text, stripTrailing: true, ensureFinalNewline: true)
        }
        return TextEncodingDetector.encode(text, as: fileEncoding, includeBOM: writesBOM)
    }

    // MARK: Editor <-> model sync

    /// Called by the editor when its text changes. Marks the document edited so
    /// the close/save machinery and the dirty dot behave correctly.
    public func updateText(_ newText: String) {
        guard newText != text else { return }
        text = newText
        updateChangeCount(.changeDone)
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
    /// detected language. (languageOverride is added in Task 3.)
    public var highlightLanguage: String? {
        detectedLanguage
    }

    /// The most current text: the live editor contents if a window is open,
    /// otherwise the model. Used by cross-tab search.
    var currentEditorTextOrModel: String {
        editorWindowController?.currentEditorText ?? text
    }

    /// Test hook: seed the model text without a file read.
    func setTextForTesting(_ value: String) { text = value }
}
