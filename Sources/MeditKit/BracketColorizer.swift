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

    /// Memoized depth scan: the source it was computed from (an owned copy) and
    /// its hits. Compared against the live text on every refresh, so no explicit
    /// invalidation is needed — same pattern as the preview's renderBody cache.
    private var scannedSource: NSString?
    private var scannedHits: [BracketHit] = []

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

    /// Serial home of the depth scan, off the main thread. The scan is pure
    /// (text in, hits out) but cost ~67 ms on a 470 KB file — a main-thread
    /// hitch at open and after every edit debounce when it ran inline.
    private static let scanQueue = DispatchQueue(label: "com.jschwefel.medit.brackets", qos: .userInitiated)

    /// Monotonic pass counter, main-thread only; drops superseded background scans.
    private var scanGeneration = 0

    /// Source of the scan currently on the background queue, main-thread only.
    /// Coalesces duplicates: the several refresh() calls at open all miss the
    /// cache (the first scan hasn't landed yet) and each dispatched its own
    /// identical scan — 3 × ~80 ms of wasted background CPU for one result.
    private var inFlightSource: NSString?

    /// Repaint. With a fresh memoized scan (appearance flip, redundant open-time
    /// calls) the repaint is synchronous; otherwise the text is snapshotted and
    /// scanned on the background queue, and colors land on main a beat later —
    /// the same pattern as the syntax highlighter.
    public func refresh() {
        guard let textView, let lm = layoutManager else { return }
        let text = textView.string

        if let cachedSource = scannedSource, cachedSource.isEqual(to: text) {
            applyDepthColors(scannedHits, lm: lm, textLength: (text as NSString).length)
            updateCaretEmphasis()
            return
        }

        // The same text is already being scanned — its result will apply; a
        // second identical scan would only burn background CPU.
        if let inFlight = inFlightSource, inFlight.isEqual(to: text) { return }

        scanGeneration &+= 1
        let gen = scanGeneration
        // Snapshot by explicit copy — the bridged string can share the text
        // view's mutable backing store, and the scan reads it off-main.
        let ns = text as NSString
        let code = ns.substring(with: NSRange(location: 0, length: ns.length))
        inFlightSource = code as NSString
        BracketColorizer.scanQueue.async { [weak self] in
            let hits = PerfLog.measure("bracket.scan", "chars=\(ns.length)") {
                BracketDepthScanner.scan(code)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                // This scan is no longer in flight, whatever happens to its
                // result below — clear BEFORE the guards or a dropped result
                // would block rescans of this text forever.
                if self.inFlightSource?.isEqual(to: code) == true { self.inFlightSource = nil }
                guard gen == self.scanGeneration else { return }   // superseded
                guard let tv = self.textView, let lm = self.layoutManager else { return }
                // Text changed while scanning → drop; the debounced refresh that
                // edit scheduled will rescan the current text.
                guard (code as NSString).isEqual(to: tv.string) else { return }
                self.scannedSource = code as NSString
                self.scannedHits = hits
                self.applyDepthColors(hits, lm: lm, textLength: (tv.string as NSString).length)
                self.updateCaretEmphasis()
            }
        }
    }

    /// Remove-and-repaint the depth colors. Main thread only. Stale colors stay
    /// up until their replacement is ready (no uncolored flash mid-scan).
    private func applyDepthColors(_ hits: [BracketHit], lm: NSLayoutManager, textLength: Int) {
        lm.removeTemporaryAttribute(.foregroundColor,
                                    forCharacterRange: NSRange(location: 0, length: textLength))
        guard !hits.isEmpty else { return }
        PerfLog.measure("bracket.applyTemp", "hits=\(hits.count)") {
            for hit in hits {
                // The scanner emits only ()[]{} — single ASCII characters — so
                // the UTF-16 length is always 1.
                let r = NSRange(location: hit.utf16Offset, length: 1)
                guard NSMaxRange(r) <= textLength else { continue }
                let color = hit.unmatched ? EditorColors.bracketUnmatchedColor
                                          : EditorColors.bracketColor(forDepth: hit.depth)
                lm.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: r)
            }
        }
    }

    // MARK: Caret emphasis

    public func updateCaretEmphasis() {
        PerfLog.measure("bracket.caretEmphasis") {
            clearEmphasis()
            guard emphasizeEnclosingPair, let textView, let lm = layoutManager else { return }
            let text = textView.string
            // Computed from the memoized scan — walking only the (sparse) bracket
            // hits instead of the document's characters. The previous text-walk
            // cost ~60–135 ms per CARET MOVE on a 470 KB file whenever the caret
            // had no enclosing pair (the common case: between functions), because
            // the left scan lazily walked the whole document backwards.
            //
            // The scan is only trusted when it matches the live text: during the
            // edit-debounce window it's stale, and stale offsets would paint
            // emphasis on the wrong characters. Emphasis vanishes for ≤150 ms
            // until the scheduled refresh rescans (which re-asserts it) — the
            // isEqual is a memcmp, ~0.1 ms, vs the text walks it replaces.
            guard let source = scannedSource, source.isEqual(to: text) else { return }
            let caret = textView.selectedRange().location
            guard let pair = Self.enclosingPair(inHits: scannedHits, caretUTF16: caret) else { return }

            for hit in [pair.open, pair.close] {
                let r = NSRange(location: hit.utf16Offset, length: 1)
                applyEmphasis(to: r, lm: lm)
                emphasisRanges.append(r)
            }
        }
    }

    /// The innermost pair enclosing a UTF-16 caret, computed from the hit list
    /// alone. This is `BracketMatcher.enclosingPair`'s exact algorithm, walking
    /// only bracket characters: the matcher's scans skip every non-bracket
    /// character, and `hits` is exactly the ordered bracket characters — so the
    /// two are equivalent by construction (pinned by an equivalence test).
    static func enclosingPair(inHits hits: [BracketHit], caretUTF16: Int)
        -> (open: BracketHit, close: BracketHit)? {
        // First hit at/after the caret. Hits strictly before it feed the left
        // scan; the right scan starts here (a bracket AT the caret belongs to
        // the right scan, matching the matcher's index arithmetic).
        var lo = 0, hi = hits.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if hits[mid].utf16Offset < caretUTF16 { lo = mid + 1 } else { hi = mid }
        }

        // Left: the first opener not cancelled by a closer we've stepped over
        // (any family cancels, so this finds the innermost).
        var pendingClose = 0
        var openHit: BracketHit?
        var i = lo - 1
        while i >= 0 {
            let h = hits[i]
            if h.isOpen {
                if pendingClose == 0 { openHit = h; break }
                pendingClose -= 1
            } else {
                pendingClose += 1
            }
            i -= 1
        }
        guard let open = openHit else { return nil }

        // Right: the matching closer of the same family, honoring nesting.
        let wantClose: Character = open.kind == "(" ? ")" : (open.kind == "[" ? "]" : "}")
        var depth = 0
        var j = lo
        while j < hits.count {
            let h = hits[j]
            if h.kind == open.kind {
                depth += 1
            } else if h.kind == wantClose {
                if depth == 0 { return (open, h) }
                depth -= 1
            }
            j += 1
        }
        return nil
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
        // Invalidate any in-flight background scan, or its main-thread apply
        // would repaint the colors this clear just removed.
        scanGeneration &+= 1
        guard let textView, let lm = layoutManager else { return }
        let full = NSRange(location: 0, length: (textView.string as NSString).length)
        lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
        lm.removeTemporaryAttribute(.font, forCharacterRange: full)
        lm.removeTemporaryAttribute(.underlineStyle, forCharacterRange: full)
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
        emphasisRanges.removeAll()
    }
}
