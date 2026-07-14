import Foundation

/// Finds the matching bracket for a caret adjacent to one of ( ) [ ] { }. Pure
/// value logic, fully tested. Brackets only — never quotes.
public enum BracketMatcher {

    private static let openers: [Character: Character] = ["(": ")", "[": "]", "{": "}"]
    private static let closers: [Character: Character] = [")": "(", "]": "[", "}": "{"]

    /// Given `offset` (a caret position), if the character immediately before OR
    /// after the caret is a bracket, return the partner's character offset, or
    /// nil if there's no balanced match. Prefers the character before the caret
    /// (matches typical editor behavior when the caret sits after a typed bracket).
    public static func matchingOffset(in text: String, at offset: Int) -> Int? {
        let chars = Array(text)
        let n = chars.count

        // Character before the caret.
        if offset - 1 >= 0, offset - 1 < n {
            if let partner = match(chars, at: offset - 1) { return partner }
        }
        // Character at the caret.
        if offset >= 0, offset < n {
            if let partner = match(chars, at: offset) { return partner }
        }
        return nil
    }

    /// The innermost bracket pair that strictly encloses `caret` (a position
    /// between characters). Returns the opener's and closer's single-Character
    /// ranges — directly convertible to NSRange via `NSRange(_:in:)` — or nil if
    /// the caret is not inside any balanced pair. Shared across families.
    ///
    /// Walks the string lazily from the caret in both directions, so the cost
    /// scales with the distance to the enclosing pair, not the document size.
    /// The old character-offset version materialized `Array(text)` — an O(n)
    /// allocation of grapheme Characters on EVERY caret move, the bulk of a
    /// ~135 ms per-keystroke stall on a 470 KB file.
    public static func enclosingPair(in text: String, at caret: String.Index)
        -> (open: Range<String.Index>, close: Range<String.Index>)? {
        guard caret >= text.startIndex, caret <= text.endIndex else { return nil }

        // Scan left: the first opener not cancelled by a closer we've stepped over
        // is the enclosing opener (any family cancels, so this finds the innermost).
        var pendingClose = 0
        var openIdx: String.Index?
        var openKind: Character = "("
        var i = caret
        scanLeft: while i > text.startIndex {
            i = text.index(before: i)
            switch text[i] {
            case ")", "]", "}":
                pendingClose += 1
            case "(", "[", "{":
                if pendingClose == 0 { openIdx = i; openKind = text[i]; break scanLeft }
                pendingClose -= 1
            default:
                break
            }
        }
        guard let open = openIdx else { return nil }

        // Scan right for the matching closer of openKind, honoring nesting.
        let wantClose: Character = openers[openKind] ?? ")"
        var depth = 0
        var j = caret
        while j < text.endIndex {
            let c = text[j]
            if c == openKind {
                depth += 1
            } else if c == wantClose {
                if depth == 0 {
                    return (open..<text.index(after: open), j..<text.index(after: j))
                }
                depth -= 1
            }
            j = text.index(after: j)
        }
        return nil
    }

    private static func match(_ chars: [Character], at index: Int) -> Int? {
        let c = chars[index]
        if let close = openers[c] {
            var depth = 0
            var i = index
            while i < chars.count {
                if chars[i] == c { depth += 1 }
                else if chars[i] == close {
                    depth -= 1
                    if depth == 0 { return i }
                }
                i += 1
            }
            return nil
        } else if let open = closers[c] {
            var depth = 0
            var i = index
            while i >= 0 {
                if chars[i] == c { depth += 1 }
                else if chars[i] == open {
                    depth -= 1
                    if depth == 0 { return i }
                }
                i -= 1
            }
            return nil
        }
        return nil
    }
}
