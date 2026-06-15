import Foundation

/// Save-time text hygiene: strip trailing whitespace per line and/or ensure the
/// file ends with exactly one newline. Pure value logic, fully tested. Preserves
/// the existing line-ending style (LF or CRLF) when stripping.
public enum TextHygiene {

    public static func cleaned(_ text: String, stripTrailing: Bool, ensureFinalNewline: Bool) -> String {
        var result = text

        if stripTrailing {
            // Split on \n, strip trailing spaces/tabs and a stray \r is preserved
            // by only trimming space/tab (not \r) then re-adding it.
            let lines = result.components(separatedBy: "\n")
            let stripped = lines.map { line -> String in
                // Preserve a trailing \r (CRLF); trim spaces/tabs before it.
                if line.hasSuffix("\r") {
                    let body = String(line.dropLast())
                    return trimTrailingSpacesTabs(body) + "\r"
                }
                return trimTrailingSpacesTabs(line)
            }
            result = stripped.joined(separator: "\n")
        }

        if ensureFinalNewline {
            // Determine the dominant line ending.
            let ending = result.contains("\r\n") ? "\r\n" : "\n"
            // Trim all trailing newlines, then add exactly one.
            while result.hasSuffix("\n") || result.hasSuffix("\r") {
                result.removeLast()
            }
            if !result.isEmpty {
                result += ending
            }
        }

        return result
    }

    private static func trimTrailingSpacesTabs(_ s: String) -> String {
        var out = s
        while let last = out.last, last == " " || last == "\t" {
            out.removeLast()
        }
        return out
    }
}
