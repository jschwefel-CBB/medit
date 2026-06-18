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

    /// The innermost bracket pair that strictly encloses `offset` (a caret
    /// position between characters). Returns the opener/closer character offsets,
    /// or nil if the caret is not inside any balanced pair. Shared across families.
    public static func enclosingPair(in text: String, at offset: Int) -> (open: Int, close: Int)? {
        let chars = Array(text)
        guard offset >= 0, offset <= chars.count else { return nil }

        let openSet: Set<Character> = ["(", "[", "{"]
        let closeSet: Set<Character> = [")", "]", "}"]

        // Scan left: the first opener not cancelled by a closer we've stepped over
        // is the enclosing opener (any family cancels, so this finds the innermost).
        var pendingClose = 0
        var openIndex = -1
        var openKind: Character = "("
        var i = offset - 1
        while i >= 0 {
            let c = chars[i]
            if closeSet.contains(c) {
                pendingClose += 1
            } else if openSet.contains(c) {
                if pendingClose == 0 { openIndex = i; openKind = c; break }
                pendingClose -= 1
            }
            i -= 1
        }
        guard openIndex >= 0 else { return nil }

        // Scan right for the matching closer of openKind, honoring nesting.
        let wantClose: Character = openers[openKind] ?? ")"
        var depth = 0
        var j = offset
        while j < chars.count {
            let c = chars[j]
            if c == openKind {
                depth += 1
            } else if c == wantClose {
                if depth == 0 { return (openIndex, j) }
                depth -= 1
            }
            j += 1
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
