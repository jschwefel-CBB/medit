import Foundation

/// Maps a 1-based line number to the UTF-16 character offset of that line's
/// start. Pure value logic, fully tested. Returns nil for out-of-range lines.
public enum TextLocator {

    /// Character offset of the start of `line` (1-based), or nil if the line is
    /// out of range. A document always has at least line 1 (offset 0). A file
    /// ending in a newline has an extra empty final line.
    public static func characterIndex(forLine line: Int, in text: String) -> Int? {
        guard line >= 1 else { return nil }
        if line == 1 { return 0 }

        let ns = text as NSString
        let length = ns.length
        var currentLine = 1
        var index = 0

        while index <= length {
            let lineRange = ns.lineRange(for: NSRange(location: index, length: 0))
            let next = NSMaxRange(lineRange)
            if next == index {
                // No progress (only happens at end with empty trailing line).
                break
            }
            currentLine += 1
            if currentLine == line {
                return next
            }
            index = next
        }
        return nil
    }
}
