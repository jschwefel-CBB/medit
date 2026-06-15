import Foundation

/// Detect and normalize a string's line endings. Pure value logic, fully tested.
public enum LineEnding: String {
    case lf   // "\n"
    case crlf // "\r\n"

    public var string: String { self == .crlf ? "\r\n" : "\n" }
}

public enum LineEndings {

    /// Dominant line ending of `text`. Defaults to `.lf` when there are no breaks.
    public static func detect(_ text: String) -> LineEnding {
        let ns = text as NSString
        var crlf = 0
        var lf = 0
        var i = 0
        while i < ns.length {
            let c = ns.character(at: i)
            if c == 13 { // \r
                if i + 1 < ns.length, ns.character(at: i + 1) == 10 { crlf += 1; i += 2; continue }
            } else if c == 10 { // \n
                lf += 1
            }
            i += 1
        }
        if crlf == 0 && lf == 0 { return .lf }
        return crlf > lf ? .crlf : .lf
    }

    /// Normalize all line endings in `text` to `target`.
    public static func normalize(_ text: String, to target: LineEnding) -> String {
        // First collapse everything to LF, then expand if needed.
        let lfOnly = text.replacingOccurrences(of: "\r\n", with: "\n")
                         .replacingOccurrences(of: "\r", with: "\n")
        if target == .lf { return lfOnly }
        return lfOnly.replacingOccurrences(of: "\n", with: "\r\n")
    }
}
