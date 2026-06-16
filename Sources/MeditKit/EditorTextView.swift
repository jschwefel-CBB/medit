import AppKit

/// NSTextView subclass adding PC-standard Home/End/Insert handling and an
/// overwrite ("type-over") mode with a block caret. Behavior is gated by
/// `pcStyleNavigationKeys`; when off, keys fall through to AppKit defaults.
public final class EditorTextView: NSTextView {

    /// Gates the PC-style key handling. Set by the editor from Preferences.
    public var pcStyleNavigationKeys: Bool = true

    /// Keep indentation (and add a level after an opener) on Return.
    public var autoIndentEnabled: Bool = true
    /// When Return is pressed with the caret between an opener and its matching
    /// closer (`{|}`), split the pair across three lines with the caret indented.
    public var indentBetweenBracketsEnabled: Bool = true
    /// Auto-insert closing brackets and skip over them; brackets only (no quotes).
    public var autoCloseBracketsEnabled: Bool = true

    /// Tab width and spaces-vs-tab for auto-indent (set by the editor from prefs).
    public var indentTabWidth: Int = 4
    public var indentUseSpaces: Bool = true

    /// Called whenever overwrite mode changes (so the status bar can update).
    public var onOverwriteModeChange: ((Bool) -> Void)?

    /// Per-window overwrite ("type-over") mode. Not persisted; resets each launch.
    public private(set) var isOverwriteMode: Bool = false {
        didSet { needsDisplay = true; onOverwriteModeChange?(isOverwriteMode) }
    }

    private var homeChar: unichar { unichar(NSHomeFunctionKey) }
    private var endChar: unichar { unichar(NSEndFunctionKey) }

    /// Hardware keyCode of the Insert key. On a PC keyboard under macOS this is
    /// the same physical key as Help (keyCode 114), and it reports the
    /// `NSHelpFunctionKey` unichar — NOT `NSInsertFunctionKey`. Matching on the
    /// keyCode is the reliable signal across keyboards.
    private static let insertKeyCode: UInt16 = 114

    public override func keyDown(with event: NSEvent) {
        // Ctrl+G -> Go to Line (routes up the responder chain to the controller).
        if event.modifierFlags.contains(.control),
           event.charactersIgnoringModifiers?.lowercased() == "g" {
            NSApp.sendAction(Selector(("goToLine:")), to: nil, from: self)
            return
        }

        guard pcStyleNavigationKeys else { super.keyDown(with: event); return }

        let mods = event.modifierFlags
        let shift = mods.contains(.shift)
        let control = mods.contains(.control)

        // Insert: detect by hardware keyCode (Insert == Help == 114 on Mac) so it
        // works regardless of whether the unichar is NSInsertFunctionKey or
        // NSHelpFunctionKey.
        if event.keyCode == EditorTextView.insertKeyCode {
            if shift { paste(nil) }
            else if control { copy(nil) }
            else { isOverwriteMode.toggle() }
            return
        }

        // Home / End: detect by the function-key unichar.
        if let chars = event.charactersIgnoringModifiers, chars.utf16.count == 1,
           let first = chars.utf16.first {
            switch first {
            case homeChar:
                applyNav(control ? .docStart : .lineStart, extend: shift)
                return
            case endChar:
                applyNav(control ? .docEnd : .lineEnd, extend: shift)
                return
            default:
                break
            }
        }

        super.keyDown(with: event)
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

    public override func insertNewline(_ sender: Any?) {
        guard autoIndentEnabled else { super.insertNewline(sender); return }
        let ns = string as NSString
        let caret = selectedRange().location
        let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
        // The text of the current line up to (not past) its newline.
        var lineText = ns.substring(with: lineRange)
        if lineText.hasSuffix("\n") { lineText.removeLast() }
        let leadingIndent = String(lineText.prefix { $0 == " " || $0 == "\t" })

        // Split a bracket pair when the caret sits between an opener and its
        // matching closer (e.g. `{|}`): opener line / indented blank / closer line.
        if indentBetweenBracketsEnabled, selectedRange().length == 0,
           caret > 0, caret < ns.length {
            let before = Character(ns.substring(with: NSRange(location: caret - 1, length: 1)))
            let after = Character(ns.substring(with: NSRange(location: caret, length: 1)))
            if Indenter.shouldSplitPair(before: before, after: after) {
                let split = Indenter.splitPairInsertion(currentIndent: leadingIndent,
                                                        tabWidth: indentTabWidth, useSpaces: indentUseSpaces)
                let sel = selectedRange()
                if shouldChangeText(in: sel, replacementString: split.text) {
                    replaceCharacters(in: sel, with: split.text)
                    didChangeText()
                    // Place the caret on the indented middle line.
                    setSelectedRange(NSRange(location: sel.location + split.caretOffset, length: 0))
                }
                return
            }
        }

        let indent = Indenter.indent(forNewLineAfter: lineText, tabWidth: indentTabWidth, useSpaces: indentUseSpaces)
        let insertion = "\n" + indent
        let sel = selectedRange()
        if shouldChangeText(in: sel, replacementString: insertion) {
            replaceCharacters(in: sel, with: insertion)
            didChangeText()
        }
    }

    public override func insertText(_ string: Any, replacementRange: NSRange) {
        if autoCloseBracketsEnabled, let typed = (string as? String) ?? (string as? NSAttributedString)?.string,
           typed.count == 1, let ch = typed.first {
            let openers: [Character: Character] = ["(": ")", "[": "]", "{": "}"]
            let closersSet: Set<Character> = [")", "]", "}"]
            let sel = selectedRange()
            let ns = self.string as NSString

            // Skip over an existing closer.
            if closersSet.contains(ch), sel.length == 0, sel.location < ns.length,
               ns.substring(with: NSRange(location: sel.location, length: 1)) == String(ch) {
                setSelectedRange(NSRange(location: sel.location + 1, length: 0))
                return
            }
            // Auto-close an opener; wrap a selection if present.
            if let close = openers[ch] {
                if sel.length > 0 {
                    let selected = ns.substring(with: sel)
                    let replacement = String(ch) + selected + String(close)
                    if shouldChangeText(in: sel, replacementString: replacement) {
                        replaceCharacters(in: sel, with: replacement)
                        didChangeText()
                        setSelectedRange(NSRange(location: sel.location + 1, length: (selected as NSString).length))
                    }
                    return
                } else {
                    let pair = String(ch) + String(close)
                    if shouldChangeText(in: sel, replacementString: pair) {
                        replaceCharacters(in: sel, with: pair)
                        didChangeText()
                        setSelectedRange(NSRange(location: sel.location + 1, length: 0))
                    }
                    return
                }
            }
        }
        // Existing overwrite-mode handling.
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

    /// Bracket-match highlighting is intentionally disabled. The previous
    /// implementation used `showFindIndicator(for:)`, whose animated yellow bubble
    /// re-flashed on every keystroke inside a bracket pair — visually jarring. A
    /// proper static, depth-colored ("rainbow brackets") highlight is planned as a
    /// separate feature; until then, no bracket highlight is drawn.
    /// `BracketMatcher` (the pure matching logic) is retained for that feature.
    public func highlightMatchingBracket() {
        // no-op (see doc comment)
    }

    /// Resetting overwrite mode (used when the preference is toggled off).
    public func resetOverwriteMode() { isOverwriteMode = false }

    /// Test hook: flip overwrite mode.
    func toggleOverwriteForTesting() { isOverwriteMode.toggle() }
}
