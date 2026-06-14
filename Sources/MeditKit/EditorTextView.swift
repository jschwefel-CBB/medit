import AppKit

/// NSTextView subclass adding PC-standard Home/End/Insert handling and an
/// overwrite ("type-over") mode with a block caret. Behavior is gated by
/// `pcStyleNavigationKeys`; when off, keys fall through to AppKit defaults.
public final class EditorTextView: NSTextView {

    /// Gates the PC-style key handling. Set by the editor from Preferences.
    public var pcStyleNavigationKeys: Bool = true

    /// Per-window overwrite ("type-over") mode. Not persisted; resets each launch.
    public private(set) var isOverwriteMode: Bool = false {
        didSet { needsDisplay = true }
    }

    private var homeChar: unichar { unichar(NSHomeFunctionKey) }
    private var endChar: unichar { unichar(NSEndFunctionKey) }
    private var insertChar: unichar { unichar(NSInsertFunctionKey) }

    public override func keyDown(with event: NSEvent) {
        guard pcStyleNavigationKeys,
              let chars = event.charactersIgnoringModifiers, chars.utf16.count == 1,
              let first = chars.utf16.first else {
            super.keyDown(with: event); return
        }
        let mods = event.modifierFlags
        let shift = mods.contains(.shift)
        let control = mods.contains(.control)
        switch first {
        case homeChar:
            applyNav(control ? .docStart : .lineStart, extend: shift)
        case endChar:
            applyNav(control ? .docEnd : .lineEnd, extend: shift)
        case insertChar:
            if shift { paste(nil) }
            else if control { copy(nil) }
            else { isOverwriteMode.toggle() }
        default:
            super.keyDown(with: event)
        }
    }

    private func applyNav(_ command: KeyboardNavigator.NavCommand, extend: Bool) {
        let result = KeyboardNavigator.newSelection(
            in: string,
            current: selectedRange(),
            command: command,
            extend: extend,
            lineRangeProvider: { [weak self] range in
                self?.lineRange(for: range) ?? range
            })
        setSelectedRange(result)
        scrollRangeToVisible(result)
    }

    private func lineRange(for range: NSRange) -> NSRange {
        let ns = string as NSString
        if let lm = layoutManager, let tc = textContainer,
           tc.widthTracksTextView, ns.length > 0 {
            let loc = min(range.location, ns.length - (range.location == ns.length ? 1 : 0))
            let glyphIndex = lm.glyphIndexForCharacter(at: max(0, min(loc, ns.length - 1)))
            var effective = NSRange()
            _ = lm.lineFragmentRect(forGlyphAt: max(0, min(glyphIndex, lm.numberOfGlyphs - 1)),
                                    effectiveRange: &effective)
            return lm.characterRange(forGlyphRange: effective, actualGlyphRange: nil)
        }
        return ns.lineRange(for: range)
    }

    public override func insertText(_ string: Any, replacementRange: NSRange) {
        guard isOverwriteMode else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }
        let sel = selectedRange()
        let ns = self.string as NSString
        if sel.length == 0, sel.location < ns.length {
            let nextChar = ns.substring(with: NSRange(location: sel.location, length: 1))
            if nextChar != "\n" {
                super.insertText(string, replacementRange: NSRange(location: sel.location, length: 1))
                return
            }
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    public override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        guard isOverwriteMode else {
            super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
            return
        }
        guard flag else { super.drawInsertionPoint(in: rect, color: color, turnedOn: flag); return }
        let charWidth = (font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
            .maximumAdvancement.width
        let width = charWidth > 1 ? charWidth : rect.height * 0.55
        let blockRect = NSRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
        color.withAlphaComponent(0.45).setFill()
        blockRect.fill()
    }

    /// Resetting overwrite mode (used when the preference is toggled off).
    public func resetOverwriteMode() { isOverwriteMode = false }

    /// Test hook: flip overwrite mode.
    func toggleOverwriteForTesting() { isOverwriteMode.toggle() }
}
