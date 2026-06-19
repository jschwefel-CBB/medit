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

    /// Called when files are DRAGGED onto the editor. The editor opens them
    /// (in tabs) instead of letting NSTextView paste their paths as text.
    /// Copy/paste of a path still inserts text — only drags are intercepted.
    public var onOpenFiles: (([URL]) -> Void)?

    /// Per-window overwrite ("type-over") mode. Not persisted; resets each launch.
    public private(set) var isOverwriteMode: Bool = false {
        didSet { needsDisplay = true; onOverwriteModeChange?(isOverwriteMode) }
    }

    // MARK: Column / block editing state

    /// A rectangular selection. Line/column are 0-based (column = character index
    /// within the line), matching the pure `ColumnSelection` model. NSTextView
    /// can't represent multi-row zero-width carets, so we own this state.
    struct ColumnBlock: Equatable {
        var anchorLine: Int, anchorColumn: Int
        var caretLine: Int, caretColumn: Int
        var topLine: Int { min(anchorLine, caretLine) }
        var bottomLine: Int { max(anchorLine, caretLine) }
        var leftColumn: Int { min(anchorColumn, caretColumn) }
        var rightColumn: Int { max(anchorColumn, caretColumn) }
        var isZeroWidth: Bool { leftColumn == rightColumn }
    }

    /// Non-nil while column mode is active.
    private(set) var columnBlock: ColumnBlock? {
        didSet { needsDisplay = true }
    }
    /// Sticky column mode toggled from the menu (⌥⌘B): subsequent clicks start
    /// blocks without needing the Option key.
    public private(set) var stickyColumnMode = false

    /// Whether column editing is currently driving the view.
    var isColumnEditing: Bool { columnBlock != nil }

    private var homeChar: unichar { unichar(NSHomeFunctionKey) }
    private var endChar: unichar { unichar(NSEndFunctionKey) }

    /// Hardware keyCode of the Insert key. On a PC keyboard under macOS this is
    /// the same physical key as Help (keyCode 114), and it reports the
    /// `NSHelpFunctionKey` unichar — NOT `NSInsertFunctionKey`. Matching on the
    /// keyCode is the reliable signal across keyboards.
    private static let insertKeyCode: UInt16 = 114

    public override func keyDown(with event: NSEvent) {
        // Column-edit mode handles Escape (exit) and arrows (move/extend the block)
        // before anything else.
        if columnBlock != nil {
            if let chars = event.charactersIgnoringModifiers, chars.utf16.count == 1,
               let first = chars.utf16.first {
                if first == 0x1B {   // Escape
                    exitColumnMode()
                    return
                }
                if [NSUpArrowFunctionKey, NSDownArrowFunctionKey,
                    NSLeftArrowFunctionKey, NSRightArrowFunctionKey].contains(Int(first)) {
                    if columnArrow(first, shift: event.modifierFlags.contains(.shift)) { return }
                }
            }
        }

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
        // Column / block editing: type into every row of the active block.
        if columnBlock != nil, let typed = (string as? String) ?? (string as? NSAttributedString)?.string {
            if columnInsert(typed) { return }
        }
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

    public override func deleteBackward(_ sender: Any?) {
        if columnBlock != nil { columnDeleteBackward(); return }
        super.deleteBackward(sender)
    }

    public override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        // Suppress the normal caret while a column block is active (we draw our own
        // multi-row carets in drawColumnBlock).
        if columnBlock != nil { return }
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

    // MARK: Column / block editing

    /// 0-based (line, column) for a character offset.
    private func lineColumn(forOffset offset: Int) -> (line: Int, column: Int) {
        let ns = string as NSString
        let clamped = max(0, min(offset, ns.length))
        var line = 0
        var idx = 0
        while idx < clamped {
            let r = ns.lineRange(for: NSRange(location: idx, length: 0))
            let next = NSMaxRange(r)
            if next <= idx { break }
            if next <= clamped { line += 1; idx = next } else { break }
        }
        let lineStart = ns.lineRange(for: NSRange(location: clamped, length: 0)).location
        return (line, clamped - lineStart)
    }

    /// Character offset for a 0-based (line, column). Column is clamped to the
    /// line's content length (not past the newline).
    private func offset(forLine line: Int, column: Int) -> Int {
        let ns = string as NSString
        var idx = 0
        var current = 0
        while current < line {
            let r = ns.lineRange(for: NSRange(location: idx, length: 0))
            let next = NSMaxRange(r)
            if next <= idx { return ns.length }   // past last line
            idx = next; current += 1
        }
        // idx is the start of `line`. Its content length excludes the terminator.
        var lineEnd = 0, contentsEnd = 0
        ns.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: idx, length: 0))
        let contentLen = contentsEnd - idx
        return idx + min(column, contentLen)
    }

    /// The number of lines in the document (0-based last line = count-1).
    private var lineCount: Int {
        let ns = string as NSString
        if ns.length == 0 { return 1 }
        var n = 1, idx = 0
        while idx < ns.length {
            let r = ns.lineRange(for: NSRange(location: idx, length: 0))
            let next = NSMaxRange(r)
            if next <= idx { break }
            if next < ns.length { n += 1 }
            idx = next
        }
        return n
    }

    private var charAdvance: CGFloat {
        let w = (font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)).maximumAdvancement.width
        return w > 1 ? w : 8
    }

    /// Map a point (view coords) to a 0-based (line, column), allowing columns
    /// beyond a short line's text (extrapolated by character advance) so a
    /// rectangle can be dragged wider than the text.
    private func lineColumn(at point: NSPoint) -> (line: Int, column: Int) {
        guard let lm = layoutManager, let tc = textContainer else { return (0, 0) }
        let inset = textContainerInset
        let p = NSPoint(x: point.x - inset.width, y: point.y - inset.height)
        let glyph = lm.glyphIndex(for: p, in: tc)
        let charIndex = lm.characterIndexForGlyph(at: glyph)
        let (line, _) = lineColumn(forOffset: charIndex)
        // Compute column from x relative to the line's start x.
        let ns = string as NSString
        let lineStartOffset = offset(forLine: line, column: 0)
        let startPoint = self.point(forLine: line, column: 0)
        let col = max(0, Int(((point.x - startPoint.x) / charAdvance).rounded()))
        _ = ns; _ = lineStartOffset
        return (line, col)
    }

    /// The point (view coords) at the top-left of a 0-based (line, column),
    /// extrapolating past a short line's end by character advance.
    private func point(forLine line: Int, column: Int) -> NSPoint {
        guard let lm = layoutManager else { return .zero }
        let inset = textContainerInset
        let ns = string as NSString
        let lineStart = offset(forLine: line, column: 0)
        var lineEnd = 0, contentsEnd = 0
        ns.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: lineStart, length: 0))
        let contentLen = contentsEnd - lineStart
        let withinCol = min(column, contentLen)
        // Rect of the glyph at the within-content column.
        let probeOffset = lineStart + withinCol
        let glyphRange = lm.glyphRange(forCharacterRange: NSRange(location: min(probeOffset, max(0, ns.length)), length: 0), actualCharacterRange: nil)
        var frag = lm.lineFragmentRect(forGlyphAt: min(glyphRange.location, max(0, lm.numberOfGlyphs - 1)), effectiveRange: nil)
        // x within the fragment for the within-content column.
        let loc = lm.location(forGlyphAt: min(glyphRange.location, max(0, lm.numberOfGlyphs - 1)))
        var x = frag.minX + loc.x
        if column > contentLen { x += CGFloat(column - contentLen) * charAdvance }
        frag.origin.y += inset.height
        return NSPoint(x: x + inset.width, y: frag.minY)
    }

    /// The rect for a row from leftColumn..rightColumn (view coords).
    private func rowRect(line: Int, left: Int, right: Int) -> NSRect {
        let p0 = point(forLine: line, column: left)
        let p1 = point(forLine: line, column: right)
        let h = (layoutManager?.defaultLineHeight(for: font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))) ?? 16
        let w = max(right > left ? (p1.x - p0.x) : 1.5, 1.5)
        return NSRect(x: p0.x, y: p0.y, width: w, height: h)
    }

    /// Re-sync NSTextView's own selection to the block's per-line ranges (for
    /// non-zero-width blocks) or a single caret (zero-width) so AppKit stays
    /// coherent. The block remains the source of truth.
    private func syncSelectionToBlock() {
        guard let b = columnBlock else { return }
        if b.isZeroWidth {
            super.setSelectedRange(NSRange(location: offset(forLine: b.caretLine, column: b.caretColumn), length: 0))
        } else {
            let ranges = ColumnSelection.perLineRanges(in: string, startLine: b.topLine, endLine: b.bottomLine,
                                                       startColumn: b.leftColumn, endColumn: b.rightColumn)
            setSelectedRanges(ranges.map { NSValue(range: $0) }, affinity: .downstream, stillSelecting: false)
        }
    }

    /// Exit column mode, leaving a single normal caret at the current corner.
    func exitColumnMode() {
        guard let b = columnBlock else { return }
        let off = offset(forLine: b.caretLine, column: b.caretColumn)
        columnBlock = nil
        stickyColumnMode = false
        super.setSelectedRange(NSRange(location: off, length: 0))
    }

    /// Toggle sticky column mode (from the menu). Seeds a zero-width block at the
    /// current caret when turning on.
    public func toggleColumnMode() {
        if columnBlock != nil { exitColumnMode(); return }
        stickyColumnMode = true
        let (line, col) = lineColumn(forOffset: selectedRange().location)
        columnBlock = ColumnBlock(anchorLine: line, anchorColumn: col, caretLine: line, caretColumn: col)
        syncSelectionToBlock()
    }

    // Mouse: Option-drag (or sticky mode) drives a rectangular block.

    public override func mouseDown(with event: NSEvent) {
        let wantsColumn = event.modifierFlags.contains(.option) || stickyColumnMode
        guard wantsColumn else {
            if columnBlock != nil { exitColumnMode() }
            super.mouseDown(with: event)
            return
        }
        let p = convert(event.locationInWindow, from: nil)
        let (line, col) = lineColumn(at: p)
        columnBlock = ColumnBlock(anchorLine: line, anchorColumn: col, caretLine: line, caretColumn: col)
        syncSelectionToBlock()
    }

    public override func mouseDragged(with event: NSEvent) {
        guard columnBlock != nil else { super.mouseDragged(with: event); return }
        let p = convert(event.locationInWindow, from: nil)
        let (line, col) = lineColumn(at: p)
        columnBlock?.caretLine = max(0, min(line, lineCount - 1))
        columnBlock?.caretColumn = max(0, col)
        syncSelectionToBlock()
    }

    public override func mouseUp(with event: NSEvent) {
        guard columnBlock != nil else { super.mouseUp(with: event); return }
        // Keep the block so the user can type into it.
    }

    /// Apply a column edit (insert/replace/delete/paste) as one undoable
    /// whole-text replacement, then update the block to the post-edit caret.
    private func applyColumnText(_ newText: String, caretLine: Int, caretColumn: Int) {
        let full = NSRange(location: 0, length: (string as NSString).length)
        guard shouldChangeText(in: full, replacementString: newText) else { return }
        replaceCharacters(in: full, with: newText)
        didChangeText()
        let line = max(0, min(caretLine, lineCount - 1))
        columnBlock = ColumnBlock(anchorLine: line, anchorColumn: caretColumn,
                                  caretLine: line, caretColumn: caretColumn)
        syncSelectionToBlock()
    }

    /// Handle a typed string in column mode (zero-width → insert on each row;
    /// width → replace the block on each row). Returns true if handled.
    private func columnInsert(_ text: String) -> Bool {
        guard let b = columnBlock else { return false }
        let e: ColumnSelection.Edit
        if b.isZeroWidth {
            e = ColumnSelection.insertIntoBlock(text, in: string, startLine: b.topLine, endLine: b.bottomLine,
                                                startColumn: b.leftColumn, endColumn: b.leftColumn)
        } else {
            e = ColumnSelection.replaceBlock(text, in: string, startLine: b.topLine, endLine: b.bottomLine,
                                             startColumn: b.leftColumn, endColumn: b.rightColumn)
        }
        // Caret collapses just after the inserted text, anchored on every row.
        applyColumnText(e.text, caretLine: b.caretLine, caretColumn: e.caretColumn)
        // Anchor the block across all rows at the new zero-width column.
        columnBlock = ColumnBlock(anchorLine: b.topLine, anchorColumn: e.caretColumn,
                                  caretLine: b.bottomLine, caretColumn: e.caretColumn)
        syncSelectionToBlock()
        return true
    }

    private func columnDeleteBackward() {
        guard let b = columnBlock else { return }
        if b.isZeroWidth {
            guard b.leftColumn > 0 else { return }
            let e = ColumnSelection.deleteBlock(in: string, startLine: b.topLine, endLine: b.bottomLine,
                                                startColumn: b.leftColumn - 1, endColumn: b.leftColumn)
            applyColumnText(e.text, caretLine: b.caretLine, caretColumn: b.leftColumn - 1)
            columnBlock = ColumnBlock(anchorLine: b.topLine, anchorColumn: b.leftColumn - 1,
                                      caretLine: b.bottomLine, caretColumn: b.leftColumn - 1)
        } else {
            let e = ColumnSelection.deleteBlock(in: string, startLine: b.topLine, endLine: b.bottomLine,
                                                startColumn: b.leftColumn, endColumn: b.rightColumn)
            applyColumnText(e.text, caretLine: b.caretLine, caretColumn: b.leftColumn)
            columnBlock = ColumnBlock(anchorLine: b.topLine, anchorColumn: b.leftColumn,
                                      caretLine: b.bottomLine, caretColumn: b.leftColumn)
        }
        syncSelectionToBlock()
    }

    /// Move/extend the block corner with arrow keys. Returns true if handled.
    private func columnArrow(_ key: unichar, shift: Bool) -> Bool {
        guard var b = columnBlock else { return false }
        switch Int(key) {
        case NSUpArrowFunctionKey:    b.caretLine = max(0, b.caretLine - 1)
        case NSDownArrowFunctionKey:  b.caretLine = min(lineCount - 1, b.caretLine + 1)
        case NSLeftArrowFunctionKey:  b.caretColumn = max(0, b.caretColumn - 1)
        case NSRightArrowFunctionKey: b.caretColumn += 1
        default: return false
        }
        if !shift { b.anchorLine = b.caretLine; b.anchorColumn = b.caretColumn }
        columnBlock = b
        syncSelectionToBlock()
        return true
    }

    // Clipboard.

    /// Copy the block (rows joined by newlines). Returns true if a block was copied.
    @discardableResult
    private func columnCopy() -> Bool {
        guard let b = columnBlock, !b.isZeroWidth else { return false }
        let text = ColumnSelection.copyBlock(in: string, startLine: b.topLine, endLine: b.bottomLine,
                                             startColumn: b.leftColumn, endColumn: b.rightColumn)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        return true
    }

    public override func copy(_ sender: Any?) {
        if columnCopy() { return }
        super.copy(sender)
    }

    public override func cut(_ sender: Any?) {
        if let b = columnBlock, !b.isZeroWidth, columnCopy() {
            columnDeleteBackward()   // width block → deletes the block
            return
        }
        super.cut(sender)
    }

    public override func paste(_ sender: Any?) {
        guard let b = columnBlock,
              let clip = NSPasteboard.general.string(forType: .string) else {
            super.paste(sender); return
        }
        let pieces = clip.components(separatedBy: "\n")
        // Paste as a block at the block's top-left; if the block has width, replace
        // it first (delete), then paste at the left column.
        var working = string
        let top = b.topLine
        let col = b.leftColumn
        if !b.isZeroWidth {
            let del = ColumnSelection.deleteBlock(in: working, startLine: b.topLine, endLine: b.bottomLine,
                                                  startColumn: b.leftColumn, endColumn: b.rightColumn)
            working = del.text
        }
        let e = ColumnSelection.pasteBlock(pieces, in: working, startLine: top, column: col)
        applyColumnText(e.text, caretLine: top + max(0, pieces.count - 1), caretColumn: col)
        _ = top
    }

    /// Draw the rectangular selection / multi-row carets.
    private func drawColumnBlock() {
        guard let b = columnBlock else { return }
        let color = NSColor.selectedTextBackgroundColor
        for line in b.topLine...b.bottomLine {
            let rect = rowRect(line: line, left: b.leftColumn, right: b.rightColumn)
            if b.isZeroWidth {
                NSColor.textColor.withAlphaComponent(0.85).setFill()
                NSRect(x: rect.minX, y: rect.minY, width: 1.5, height: rect.height).fill()
            } else {
                color.withAlphaComponent(0.45).setFill()
                rect.fill()
            }
        }
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if columnBlock != nil { drawColumnBlock() }
    }

    // Test hooks (drive column editing without a rendered view / mouse).
    func beginColumnBlockForTesting(anchorLine: Int, anchorColumn: Int, caretLine: Int, caretColumn: Int) {
        columnBlock = ColumnBlock(anchorLine: anchorLine, anchorColumn: anchorColumn,
                                  caretLine: caretLine, caretColumn: caretColumn)
    }
    var columnBlockForTesting: ColumnBlock? { columnBlock }
    func columnTypeForTesting(_ s: String) { _ = columnInsert(s) }
    func columnDeleteForTesting() { columnDeleteBackward() }
    func columnCopyForTesting() -> Bool { columnCopy() }
    func columnPasteForTesting() { paste(nil) }

    // MARK: Drag & drop — open dragged files, don't paste their paths

    /// Register the drag types dropped FILES advertise so the OS routes file
    /// drags to our overrides. A plain-text NSTextView (isRichText = false) does
    /// not accept file drops by default. Crucially we register BOTH `.fileURL`
    /// (single-file drags) AND the classic `NSFilenamesPboardType` — a multi-file
    /// Finder drag advertises the filenames type, and a view registered only for
    /// `.fileURL` never even receives `draggingEntered` for a multi-file drag.
    /// We append to (not replace) the superclass's text drag types.
    private static let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    private func registerFileDragTypes() {
        var types = registeredDraggedTypes
        for t in [NSPasteboard.PasteboardType.fileURL, EditorTextView.filenamesType] where !types.contains(t) {
            types.append(t)
        }
        registerForDraggedTypes(types)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { registerFileDragTypes() }
    }

    /// File URLs on a dragging pasteboard (empty for a plain-text drag). Reads
    /// both the modern URL representation and the legacy filenames array so both
    /// single- and multi-file drags resolve.
    private static func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        var urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL] ?? [])
            .filter { $0.isFileURL }
        if urls.isEmpty,
           let names = pasteboard.propertyList(forType: filenamesType) as? [String] {
            urls = names.map { URL(fileURLWithPath: $0) }
        }
        return urls
    }

    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !EditorTextView.fileURLs(on: sender.draggingPasteboard).isEmpty { return .copy }
        return super.draggingEntered(sender)
    }

    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !EditorTextView.fileURLs(on: sender.draggingPasteboard).isEmpty { return .copy }
        return super.draggingUpdated(sender)
    }

    public override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if !EditorTextView.fileURLs(on: sender.draggingPasteboard).isEmpty { return true }
        return super.prepareForDragOperation(sender)
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        // A dragged file OPENS (in a tab) rather than pasting its path as text.
        // Copy/paste still inserts text — only drags are intercepted here.
        let urls = EditorTextView.fileURLs(on: sender.draggingPasteboard)
        if !urls.isEmpty {
            onOpenFiles?(urls)
            return true
        }
        return super.performDragOperation(sender)
    }

    /// Test hook: simulate dropping file URLs onto the editor.
    func performFileDropForTesting(_ urls: [URL]) { onOpenFiles?(urls) }
}
