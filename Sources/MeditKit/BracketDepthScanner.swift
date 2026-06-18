import Foundation

/// One bracket found in the text, with its nesting depth. Pure value type —
/// no AppKit. `depth` is 0 for the outermost pair; the colorizer cycles it %6.
public struct BracketHit: Equatable {
    public let offset: Int        // character offset into the String
    public let kind: Character    // one of ( ) [ ] { }
    public let isOpen: Bool
    public let depth: Int
    public let unmatched: Bool    // stray closer or family mismatch

    public init(offset: Int, kind: Character, isOpen: Bool, depth: Int, unmatched: Bool) {
        self.offset = offset; self.kind = kind; self.isOpen = isOpen
        self.depth = depth; self.unmatched = unmatched
    }
}

/// Classifies every ()[]{} in `text` with a shared nesting depth (one stack
/// across all three families). Tolerant of mismatches so coloring stays stable
/// while the user is mid-typing: a stray/family-mismatched closer is flagged
/// `unmatched` (depth 0) and does not pop; unclosed openers keep their depth.
public enum BracketDepthScanner {

    private static let openers: [Character: Character] = [")": "(", "]": "[", "}": "{"]
    private static let openSet: Set<Character> = ["(", "[", "{"]
    private static let closeSet: Set<Character> = [")", "]", "}"]

    public static func scan(_ text: String) -> [BracketHit] {
        var hits: [BracketHit] = []
        var stack: [(kind: Character, depth: Int)] = []
        var offset = 0
        for ch in text {
            if openSet.contains(ch) {
                let depth = stack.count
                stack.append((ch, depth))
                hits.append(BracketHit(offset: offset, kind: ch, isOpen: true, depth: depth, unmatched: false))
            } else if closeSet.contains(ch) {
                if let top = stack.last, top.kind == openers[ch] {
                    stack.removeLast()
                    hits.append(BracketHit(offset: offset, kind: ch, isOpen: false, depth: top.depth, unmatched: false))
                } else {
                    // Empty stack or different family on top: unmatched, don't pop.
                    hits.append(BracketHit(offset: offset, kind: ch, isOpen: false, depth: 0, unmatched: true))
                }
            }
            offset += 1
        }
        return hits
    }
}
