import Foundation

/// Pure document-statistics math for the status bar: characters, words, and lines
/// for a document, plus the selection counts. No AppKit.
public enum TextStatistics {

    public struct Counts: Equatable {
        public var characters: Int
        public var words: Int
        public var lines: Int
        public var selectedCharacters: Int
        public var selectedWords: Int
    }

    /// Count words in `s` — runs of non-whitespace separated by whitespace/newlines.
    private static func wordCount(_ s: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in s.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                inWord = false
            } else if !inWord {
                inWord = true
                count += 1
            }
        }
        return count
    }

    /// Line count: number of newlines + 1 when there's any text; 0 for empty.
    private static func lineCount(_ s: String) -> Int {
        if s.isEmpty { return 0 }
        let newlines = s.unicodeScalars.lazy.filter { CharacterSet.newlines.contains($0) }.count
        return newlines + 1
    }

    public static func counts(for text: String, selection: NSRange) -> Counts {
        let ns = text as NSString
        let chars = ns.length
        let words = wordCount(text)
        let lines = lineCount(text)

        var selChars = 0
        var selWords = 0
        if selection.length > 0, selection.location >= 0,
           selection.location + selection.length <= ns.length {
            let selected = ns.substring(with: selection)
            selChars = (selected as NSString).length
            selWords = wordCount(selected)
        }
        return Counts(characters: chars, words: words, lines: lines,
                      selectedCharacters: selChars, selectedWords: selWords)
    }

    /// A compact status-bar label, e.g. "120 words · 14 lines · 842 chars", or with
    /// a selection "23 of 120 words · 156 of 842 chars".
    public static func label(for counts: Counts) -> String {
        func plural(_ n: Int, _ unit: String) -> String { "\(n) \(unit)\(n == 1 ? "" : "s")" }
        if counts.selectedCharacters > 0 {
            return "\(counts.selectedWords) of \(plural(counts.words, "word")) · "
                 + "\(counts.selectedCharacters) of \(counts.characters) chars"
        }
        return "\(plural(counts.words, "word")) · \(plural(counts.lines, "line")) · \(counts.characters) chars"
    }
}
