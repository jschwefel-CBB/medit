import AppKit
import Highlighter

/// Drives syntax highlighting for one editor's `NSTextStorage` using
/// HighlighterSwift (highlight.js). Re-highlights on edits with a short debounce
/// so typing stays responsive, and re-themes when appearance or font changes.
///
/// HighlighterSwift returns an `NSAttributedString` carrying both colors and the
/// configured font, so we replace the storage's attributes with its output. When
/// highlighting is disabled or the language is unknown, we fall back to a plain
/// monospaced styling so the text still renders with the chosen font.
public final class SyntaxHighlightingController {

    private let textStorage: NSTextStorage
    private let highlighter: Highlighter?

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

    public init?(textStorage: NSTextStorage,
                 language: String?,
                 fontName: String,
                 fontSize: CGFloat,
                 themeName: String) {
        guard let hl = Highlighter() else { return nil }
        self.textStorage = textStorage
        self.highlighter = hl
        self.language = language
        self.fontName = fontName
        self.fontSize = fontSize
        self.themeName = themeName
        _ = hl.setTheme(themeName, withFont: fontName, ofSize: fontSize)
    }

    // MARK: Configuration

    /// Apply a new theme (typically on light/dark switch) and re-highlight.
    public func setTheme(_ name: String) {
        guard name != themeName else { return }
        themeName = name
        highlighter?.setTheme(name, withFont: fontName, ofSize: fontSize)
        highlightNow()
    }

    /// Update font and re-theme so highlighted output uses it.
    public func setFont(name: String, size: CGFloat) {
        guard name != fontName || size != fontSize else { return }
        fontName = name
        fontSize = size
        highlighter?.setTheme(themeName, withFont: fontName, ofSize: fontSize)
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

    /// Re-highlight the entire document immediately.
    public func highlightNow() {
        guard !isApplying else { return }
        let code = textStorage.string
        let fullRange = NSRange(location: 0, length: (code as NSString).length)

        let styled: NSAttributedString
        if isEnabled, let language, let highlighter,
           let result = PerfLog.measure("highlight.tokenize", "lang=\(language) chars=\(fullRange.length)",
                                        { highlighter.highlight(code, as: language) }) {
            styled = result
        } else {
            styled = plainAttributedString(code)
        }

        PerfLog.measure("highlight.applyAttrs", "chars=\(fullRange.length)") {
        isApplying = true
        textStorage.beginEditing()
        // Reset to a known-visible base (font + system text color) rather than
        // wiping to nil — a nil wipe removes the foreground, so any range the
        // styled string doesn't cover would render with no color (invisible on a
        // dark background). The styled attributes below then override per range.
        let baseFont = NSFont(name: fontName, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textStorage.setAttributes([.font: baseFont, .foregroundColor: EditorColors.foreground],
                                  range: fullRange)
        // Copy attributes from the styled string onto our storage.
        styled.enumerateAttributes(in: NSRange(location: 0, length: styled.length), options: []) { attrs, range, _ in
            // Guard against any range drift if the string lengths differ.
            if NSMaxRange(range) <= fullRange.length {
                textStorage.setAttributes(attrs, range: range)
            }
        }
        textStorage.endEditing()
        isApplying = false
        }   // PerfLog.measure("highlight.applyAttrs")
    }

    private func plainAttributedString(_ code: String) -> NSAttributedString {
        let font = NSFont(name: fontName, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        return NSAttributedString(string: code, attributes: [
            .font: font,
            .foregroundColor: EditorColors.foreground
        ])
    }
}
