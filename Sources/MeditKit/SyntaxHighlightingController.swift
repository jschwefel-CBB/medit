import AppKit
import Highlighter

/// The one process-wide highlight.js engine, shared by every editor tab.
///
/// `Highlighter()` evaluates all of highlight.min.js into a fresh JSContext —
/// measured at 30–73 ms — so constructing one per tab made every new tab pay that
/// cost (~75–80% of total tab creation). One engine serves all tabs; per-tab state
/// (storage, language) stays in `SyntaxHighlightingController`.
///
/// A JSContext is not thread-safe: ALL engine access — theme changes and
/// tokenizing — is confined to `queue`, a single serial background queue. That
/// also keeps tokenizing off the main thread (measured 478–1613 ms for large
/// documents when it ran there, freezing the window at open and on every edit).
private enum HighlightEngine {

    /// Serial owner of `engine`. Everything that touches the JSContext runs here.
    static let queue = DispatchQueue(label: "com.jschwefel.medit.highlight", qos: .userInitiated)

    /// Created lazily on first tokenize (on `queue`, so even the first document
    /// doesn't pay engine construction on the main thread). Nil if highlight.js
    /// failed to load — callers fall back to plain styling.
    private static let engine: Highlighter? = PerfLog.measure("highlight.engineInit") { Highlighter() }

    struct ThemeSpec: Equatable {
        let name: String
        let fontName: String
        let fontSize: CGFloat
    }

    /// Theme currently applied to the engine. Queue-confined. All tabs share the
    /// global theme/font prefs, so in practice this changes only on a real
    /// theme/font/appearance switch, not per tokenize.
    private static var appliedTheme: ThemeSpec?

    /// Tokenize `code` with the engine carrying `theme`. Must be called on `queue`.
    static func tokenize(_ code: String, language: String, theme: ThemeSpec) -> NSAttributedString? {
        guard let engine else { return nil }
        if appliedTheme != theme {
            _ = engine.setTheme(theme.name, withFont: theme.fontName, ofSize: theme.fontSize)
            appliedTheme = theme
        }
        return engine.highlight(code, as: language)
    }
}

/// Drives syntax highlighting for one editor's `NSTextStorage` using
/// HighlighterSwift (highlight.js). Re-highlights on edits with a short debounce
/// so typing stays responsive, and re-themes when appearance or font changes.
///
/// Tokenizing runs on the shared background engine queue and the result is applied
/// back on the main thread, so opening or editing a large document no longer
/// blocks the UI — the text appears immediately and colors arrive a beat later.
/// The plain fallback (no language / highlighting off) is cheap and stays fully
/// synchronous, so unhighlighted documents behave exactly as before.
public final class SyntaxHighlightingController {

    private let textStorage: NSTextStorage

    /// highlight.js language id (e.g. "swift"); nil disables language highlighting.
    public var language: String?
    /// Master on/off (also off when `language` is nil).
    public var isEnabled: Bool = true

    private var fontName: String
    private var fontSize: CGFloat
    private var themeName: String

    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 0.15
    private var isApplying = false

    /// Monotonic pass counter, main-thread only. An in-flight tokenize result is
    /// applied only if no newer pass started while it was on the queue.
    private var generation = 0

    public init(textStorage: NSTextStorage,
                language: String?,
                fontName: String,
                fontSize: CGFloat,
                themeName: String) {
        self.textStorage = textStorage
        self.language = language
        self.fontName = fontName
        self.fontSize = fontSize
        self.themeName = themeName
        // No engine work here: the shared engine is built lazily on its own queue,
        // so creating a tab (this controller) is no longer an expensive operation.
    }

    // MARK: Configuration

    /// Apply a new theme (typically on light/dark switch) and re-highlight.
    public func setTheme(_ name: String) {
        guard name != themeName else { return }
        themeName = name
        highlightNow()
    }

    /// Update font and re-theme so highlighted output uses it.
    public func setFont(name: String, size: CGFloat) {
        guard name != fontName || size != fontSize else { return }
        fontName = name
        fontSize = size
        highlightNow()
    }

    public func setLanguage(_ language: String?) {
        self.language = language
        highlightNow()
    }

    // MARK: Highlighting

    /// Schedule a debounced re-highlight. Call from the text-storage delegate
    /// on every edit.
    public func scheduleHighlight() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            self?.highlightNow()
        }
    }

    /// Re-highlight the entire document. With a language set, tokenizing happens
    /// on the shared engine queue and attributes are applied back on main; the
    /// plain fallback applies synchronously.
    public func highlightNow() {
        guard !isApplying else { return }
        generation &+= 1
        let gen = generation
        // A pending debounced pass would only duplicate the one starting now.
        debounceTimer?.invalidate()

        guard isEnabled, let language else {
            applyPlain()
            return
        }

        // Snapshot by explicit copy: the storage's backing store is mutable and the
        // bridged `string` may share it — the copy is what makes reading the text
        // on another thread safe while the user keeps typing.
        let ns = textStorage.string as NSString
        let code = ns.substring(with: NSRange(location: 0, length: ns.length))
        let theme = HighlightEngine.ThemeSpec(name: themeName, fontName: fontName, fontSize: fontSize)

        HighlightEngine.queue.async { [weak self] in
            let styled = PerfLog.measure("highlight.tokenize", "lang=\(language) chars=\(ns.length)") {
                HighlightEngine.tokenize(code, language: language, theme: theme)
            }
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }   // superseded by a newer pass
                guard let styled else { self.applyPlain(); return }      // engine unavailable / unknown language
                // The text may have changed after the snapshot without bumping the
                // generation (edits only *schedule* a pass, debounced). Applying
                // attribute runs computed from old text onto new text misaligns
                // colors, so drop the stale result — the pending debounced pass
                // re-highlights the current text. Compare against the SNAPSHOT, not
                // `styled.string`: the engine's output length can legitimately
                // drift from its input (see the range guard in apply).
                guard (code as NSString).isEqual(to: self.textStorage.string) else { return }
                self.apply(styled)
            }
        }
    }

    /// Copy the styled attributes onto the storage. Main thread only.
    private func apply(_ styled: NSAttributedString) {
        PerfLog.measure("highlight.applyAttrs", "chars=\(textStorage.length)") {
            isApplying = true
            textStorage.beginEditing()
            let fullRange = NSRange(location: 0, length: textStorage.length)
            // Reset to a known-visible base (font + system text color) rather than
            // wiping to nil — a nil wipe removes the foreground, so any range the
            // styled string doesn't cover would render with no color (invisible on
            // a dark background). The styled attributes below then override per range.
            textStorage.setAttributes([.font: baseFont(), .foregroundColor: EditorColors.foreground],
                                      range: fullRange)
            styled.enumerateAttributes(in: NSRange(location: 0, length: styled.length), options: []) { attrs, range, _ in
                // Guard against any range drift if the string lengths differ.
                if NSMaxRange(range) <= fullRange.length {
                    textStorage.setAttributes(attrs, range: range)
                }
            }
            textStorage.endEditing()
            isApplying = false
        }
    }

    /// Plain monospaced styling for documents without highlighting. Cheap (one
    /// attribute set over the whole range), so it runs synchronously.
    private func applyPlain() {
        PerfLog.measure("highlight.applyPlain", "chars=\(textStorage.length)") {
            isApplying = true
            textStorage.beginEditing()
            textStorage.setAttributes([.font: baseFont(), .foregroundColor: EditorColors.foreground],
                                      range: NSRange(location: 0, length: textStorage.length))
            textStorage.endEditing()
            isApplying = false
        }
    }

    private func baseFont() -> NSFont {
        NSFont(name: fontName, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }
}
