import Foundation

/// One bracket found in the text, with its nesting depth. Pure value type —
/// no AppKit. `depth` is 0 for the outermost pair; the colorizer cycles it %6.
public struct BracketHit: Equatable {
    public let offset: Int        // character offset into the String
    public let utf16Offset: Int   // the same position in UTF-16 units (NSRange space)
    public let kind: Character    // one of ( ) [ ] { }
    public let isOpen: Bool
    public let depth: Int
    public let unmatched: Bool    // stray closer or family mismatch

    public init(offset: Int, utf16Offset: Int, kind: Character, isOpen: Bool, depth: Int, unmatched: Bool) {
        self.offset = offset; self.utf16Offset = utf16Offset; self.kind = kind
        self.isOpen = isOpen; self.depth = depth; self.unmatched = unmatched
    }
}

/// Classifies every ()[]{} in `text` with a shared nesting depth (one stack
/// across all three families). Tolerant of mismatches so coloring stays stable
/// while the user is mid-typing: a stray/family-mismatched closer is flagged
/// `unmatched` (depth 0) and does not pop; unclosed openers keep their depth.
///
/// Hits carry both a character offset (the public contract, grapheme-correct)
/// and a UTF-16 offset computed in the same pass, so consumers that need
/// NSRanges (the colorizer) don't have to build an O(n) conversion map — that
/// map cost ~94 ms per refresh on a 470 KB file, on the main thread.
public enum BracketDepthScanner {

    public static func scan(_ text: String) -> [BracketHit] {
        var hits: [BracketHit] = []
        var stack: [(kind: Character, depth: Int)] = []
        var offset = 0
        var utf16Offset = 0
        for ch in text {
            // Direct comparisons, not Set<Character>/Dictionary lookups: Character
            // hashing does canonical work per element, and this loop runs once per
            // character of the document (~75 ms of the old scan on 470 KB).
            switch ch {
            case "(", "[", "{":
                let depth = stack.count
                stack.append((ch, depth))
                hits.append(BracketHit(offset: offset, utf16Offset: utf16Offset,
                                       kind: ch, isOpen: true, depth: depth, unmatched: false))
            case ")", "]", "}":
                let opener: Character = ch == ")" ? "(" : (ch == "]" ? "[" : "{")
                if let top = stack.last, top.kind == opener {
                    stack.removeLast()
                    hits.append(BracketHit(offset: offset, utf16Offset: utf16Offset,
                                           kind: ch, isOpen: false, depth: top.depth, unmatched: false))
                } else {
                    // Empty stack or different family on top: unmatched, don't pop.
                    hits.append(BracketHit(offset: offset, utf16Offset: utf16Offset,
                                           kind: ch, isOpen: false, depth: 0, unmatched: true))
                }
            default:
                break
            }
            offset += 1
            // ASCII fast path; otherwise sum the scalar widths (no String alloc —
            // the old conversion map built a String per character).
            utf16Offset += ch.isASCII ? 1 : ch.unicodeScalars.reduce(0) { $0 + UTF16.width($1) }
        }
        return hits
    }
}
