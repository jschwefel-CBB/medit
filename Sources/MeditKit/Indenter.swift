import Foundation

/// Computes the indentation for a new line created by pressing Return after a
/// given line. Pure value logic, fully tested.
public enum Indenter {

    /// Leading whitespace of `line`, plus one extra indent level when the line's
    /// last non-whitespace character is an opener (`{` or `:`).
    public static func indent(forNewLineAfter line: String, tabWidth: Int, useSpaces: Bool) -> String {
        // Leading whitespace (spaces/tabs) of the line.
        let leading = line.prefix { $0 == " " || $0 == "\t" }
        var result = String(leading)

        // Last non-whitespace character.
        if let lastNonWS = line.reversed().first(where: { $0 != " " && $0 != "\t" }),
           lastNonWS == "{" || lastNonWS == ":" {
            result += useSpaces ? String(repeating: " ", count: max(1, tabWidth)) : "\t"
        }
        return result
    }

    /// One indentation level as a string (a tab, or `tabWidth` spaces).
    public static func oneLevel(tabWidth: Int, useSpaces: Bool) -> String {
        useSpaces ? String(repeating: " ", count: max(1, tabWidth)) : "\t"
    }

    /// True when pressing Return should "split" a bracket pair onto three lines
    /// (opener line / indented blank line / closer line) — i.e. the caret sits
    /// immediately between an opener and its matching closer, e.g. `{|}`.
    public static func shouldSplitPair(before: Character, after: Character) -> Bool {
        switch (before, after) {
        case ("{", "}"), ("(", ")"), ("[", "]"): return true
        default: return false
        }
    }

    /// The two-line insertion for a split pair: a newline + (current indent + one
    /// level) for the caret line, then a newline + current indent for the closer.
    /// Returns (textToInsert, caretOffsetFromInsertionStart).
    public static func splitPairInsertion(currentIndent: String, tabWidth: Int, useSpaces: Bool) -> (text: String, caretOffset: Int) {
        let level = oneLevel(tabWidth: tabWidth, useSpaces: useSpaces)
        let caretLine = "\n" + currentIndent + level
        let closerLine = "\n" + currentIndent
        return (caretLine + closerLine, caretLine.count)
    }
}
