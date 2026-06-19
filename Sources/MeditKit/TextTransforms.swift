import Foundation

/// Pure text transforms for the Edit menu: sort lines and change case. Each takes
/// the full text + a selection and returns the edited text plus the range to
/// reselect. No AppKit.
public enum TextTransforms {

    public struct Edit: Equatable {
        public var text: String
        public var selectedRange: NSRange
    }

    public enum Case { case upper, lower, title }

    // MARK: Sort lines

    /// Sort the full lines overlapping `range` (or all lines if the range spans the
    /// whole document). Preserves a trailing newline; reselects the sorted block.
    public static func sortLines(_ text: String, range: NSRange, ascending: Bool, caseInsensitive: Bool) -> Edit {
        let ns = text as NSString
        let lineRange = ns.lineRange(for: range)
        var block = ns.substring(with: lineRange)
        let hadTrailingNewline = block.hasSuffix("\n")
        if hadTrailingNewline { block.removeLast() }

        var lines = block.components(separatedBy: "\n")
        lines.sort { a, b in
            let lhs = caseInsensitive ? a.lowercased() : a
            let rhs = caseInsensitive ? b.lowercased() : b
            return ascending ? (lhs.localizedStandardCompare(rhs) == .orderedAscending)
                             : (lhs.localizedStandardCompare(rhs) == .orderedDescending)
        }
        var newBlock = lines.joined(separator: "\n")
        if hadTrailingNewline { newBlock += "\n" }
        let newText = ns.replacingCharacters(in: lineRange, with: newBlock)
        return Edit(text: newText, selectedRange: NSRange(location: lineRange.location, length: (newBlock as NSString).length))
    }

    // MARK: Change case

    /// Change the case of the selection. An empty selection operates on the word
    /// surrounding the caret (matching AppKit's Transformations behavior).
    public static func changeCase(_ text: String, range: NSRange, to mode: Case) -> Edit {
        let ns = text as NSString
        let target = range.length > 0 ? range : wordRange(in: ns, at: range.location)
        guard target.length > 0 else { return Edit(text: text, selectedRange: range) }

        let sub = ns.substring(with: target)
        let transformed: String
        switch mode {
        case .upper: transformed = sub.uppercased()
        case .lower: transformed = sub.lowercased()
        case .title: transformed = sub.capitalized
        }
        let newText = ns.replacingCharacters(in: target, with: transformed)
        return Edit(text: newText, selectedRange: NSRange(location: target.location, length: (transformed as NSString).length))
    }

    /// The range of the word (run of letters/digits) containing `loc`.
    private static func wordRange(in ns: NSString, at loc: Int) -> NSRange {
        let wordChars = CharacterSet.alphanumerics
        func isWord(_ i: Int) -> Bool {
            guard i >= 0, i < ns.length else { return false }
            let c = ns.substring(with: NSRange(location: i, length: 1))
            return c.unicodeScalars.allSatisfy { wordChars.contains($0) }
        }
        var start = loc
        while start > 0, isWord(start - 1) { start -= 1 }
        var end = loc
        while end < ns.length, isWord(end) { end += 1 }
        return NSRange(location: start, length: end - start)
    }
}
