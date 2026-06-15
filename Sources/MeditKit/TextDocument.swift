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

    /// Manual language override (nil = auto-detect). Session-only; not persisted.
    public var languageOverride: String?

    /// Line ending used on save (detected on read; default LF).
    public var lineEnding: LineEnding = .lf
    /// The original file bytes from the last read, for Reinterpret.
    public private(set) var originalData: Data?

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
        self.originalData = data
        self.lineEnding = LineEndings.detect(self.text)
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
}
