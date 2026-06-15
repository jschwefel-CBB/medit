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
