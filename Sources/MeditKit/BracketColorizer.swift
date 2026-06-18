import AppKit

/// Paints rainbow-depth bracket colors and caret-pair emphasis as layout-manager
/// TEMPORARY attributes — an overlay that layers over the syntax highlighter's
/// text-storage colors and is never clobbered by it. The owner drives
/// `scheduleRefresh()` on text change and `updateCaretEmphasis()` on selection
/// change; `clear()` removes everything on toggle-off / teardown.
public final class BracketColorizer {

    private weak var textView: NSTextView?
    public var emphasizeEnclosingPair = true
    public var emphasisStyle: EnclosingPairEmphasisStyle = .bold

    /// Ranges (UTF-16) currently carrying caret emphasis, so we can clear them.
    private var emphasisRanges: [NSRange] = []
    private var refreshScheduled = false

    public init(textView: NSTextView) {
        self.textView = textView
    }

    private var layoutManager: NSLayoutManager? { textView?.layoutManager }

    // MARK: Depth coloring

    /// Recompute and repaint depth colors (debounced ~0.15s, like the highlighter).
    public func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.refreshScheduled = false
            self?.refresh()
        }
    }

    /// Immediate repaint (initial apply / appearance flip).
    public func refresh() {
        guard let textView, let lm = layoutManager else { return }
        let text = textView.string
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)

        let hits = BracketDepthScanner.scan(text)
        if !hits.isEmpty {
            // Character offset -> UTF-16 location map (one O(n) pass).
            let scalars = Array(text)
            var utf16Loc = [Int](repeating: 0, count: scalars.count + 1)
            var loc = 0
            for (i, ch) in scalars.enumerated() {
                utf16Loc[i] = loc
                loc += String(ch).utf16.count
            }
            utf16Loc[scalars.count] = loc

            for hit in hits where hit.offset < scalars.count {
                let start = utf16Loc[hit.offset]
                let len = String(scalars[hit.offset]).utf16.count
                let r = NSRange(location: start, length: len)
                guard NSMaxRange(r) <= ns.length else { continue }
                let color = hit.unmatched ? EditorColors.bracketUnmatchedColor
                                          : EditorColors.bracketColor(forDepth: hit.depth)
                lm.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: r)
            }
        }
        // Depth repaint dropped the emphasis overlay's interplay; re-assert it.
        updateCaretEmphasis()
    }

    // MARK: Caret emphasis

    public func updateCaretEmphasis() {
        clearEmphasis()
        guard emphasizeEnclosingPair, let textView, let lm = layoutManager else { return }
        let text = textView.string
        let ns = text as NSString
        let sel = textView.selectedRange()
        // UTF-16 caret location -> character offset.
        let caretUTF16 = min(sel.location, ns.length)
        let charOffset = ns.substring(to: caretUTF16).count
        guard let pair = BracketMatcher.enclosingPair(in: text, at: charOffset) else { return }

        for charIdx in [pair.open, pair.close] {
            guard let r = utf16Range(forCharIndex: charIdx, in: text, ns: ns),
                  NSMaxRange(r) <= ns.length else { continue }
            applyEmphasis(to: r, lm: lm)
            emphasisRanges.append(r)
        }
    }

    /// UTF-16 NSRange for the single character at `charIndex` (character offset).
    private func utf16Range(forCharIndex charIndex: Int, in text: String, ns: NSString) -> NSRange? {
        guard charIndex >= 0 else { return nil }
        let scalars = Array(text)
        guard charIndex < scalars.count else { return nil }
        var loc = 0
        for k in 0..<charIndex { loc += String(scalars[k]).utf16.count }
        let len = String(scalars[charIndex]).utf16.count
        return NSRange(location: loc, length: len)
    }

    private func applyEmphasis(to r: NSRange, lm: NSLayoutManager) {
        switch emphasisStyle {
        case .bold:
            if let base = textView?.font {
                let bold = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
                lm.addTemporaryAttribute(.font, value: bold, forCharacterRange: r)
            }
        case .underline:
            lm.addTemporaryAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, forCharacterRange: r)
        case .background:
            if let fg = lm.temporaryAttribute(.foregroundColor, atCharacterIndex: r.location,
                                              effectiveRange: nil) as? NSColor {
                lm.addTemporaryAttribute(.backgroundColor, value: fg.withAlphaComponent(0.18), forCharacterRange: r)
            }
        }
    }

    private func clearEmphasis() {
        guard let lm = layoutManager else { emphasisRanges.removeAll(); return }
        for r in emphasisRanges {
            lm.removeTemporaryAttribute(.font, forCharacterRange: r)
            lm.removeTemporaryAttribute(.underlineStyle, forCharacterRange: r)
            lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: r)
        }
        emphasisRanges.removeAll()
    }

    // MARK: Teardown

    /// Remove every temporary attribute this colorizer applies (toggle-off).
    public func clear() {
        guard let textView, let lm = layoutManager else { return }
        let full = NSRange(location: 0, length: (textView.string as NSString).length)
        lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
        lm.removeTemporaryAttribute(.font, forCharacterRange: full)
        lm.removeTemporaryAttribute(.underlineStyle, forCharacterRange: full)
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
        emphasisRanges.removeAll()
    }
}
