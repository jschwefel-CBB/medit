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
}
