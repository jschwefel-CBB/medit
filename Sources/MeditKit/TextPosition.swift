import Foundation

/// Converts a UTF-16 character offset into a 1-based (line, column). Pure value
/// logic, fully tested. Used by the status bar.
public enum TextPosition {

    public static func lineColumn(forOffset offset: Int, in text: String) -> (line: Int, column: Int) {
        let ns = text as NSString
        let clamped = max(0, min(offset, ns.length))
        // Line = 1 + number of newlines before `clamped`.
        // Column = 1 + distance from the start of the current line.
        let lineStart = ns.lineRange(for: NSRange(location: clamped, length: 0)).location
        // Line = 1 + number of line terminators strictly before `clamped`. Walk
        // line ranges from the document start; a line increment happens only when
        // we cross an actual terminator (contentsEnd < lineEnd). Reaching the end
        // of the buffer with no trailing newline is NOT a new line. (Counting line
        // *substrings* would over-count the trailing partial line.)
        var line = 1
        var index = 0
        while index < clamped {
            var lineEnd = 0
            var contentsEnd = 0
            ns.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd,
                            for: NSRange(location: index, length: 0))
            if lineEnd <= index { break }              // no progress (defensive)
            // Only count a line break if the terminator lies before `clamped`.
            guard contentsEnd < lineEnd, lineEnd <= clamped else { break }
            line += 1
            index = lineEnd
        }
        let column = clamped - lineStart + 1
        return (line, column)
    }
}
