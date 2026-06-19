import Foundation

/// Pure rectangular (column/block) selection model: given text and a block region
/// expressed as line/column bounds, compute per-line ranges and the result of
/// deleting or inserting into the block. Used for column editing — typing or
/// deleting across multiple rows at once (e.g. scraping aligned terminal output).
/// No AppKit.
public enum ColumnSelection {

    public struct Edit: Equatable {
        public var text: String
        /// Caret column after the edit (for the model; the view maps it to offsets).
        public var caretColumn: Int
    }

    /// The lines of `text` as substrings (without their trailing newline).
    private static func lines(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
    }

    /// The NSRange on each line from `startLine`…`endLine` covering columns
    /// `startColumn`..<`endColumn`, clamped to each line's length (short lines get
    /// an empty range at their end). Ranges are in whole-document coordinates.
    public static func perLineRanges(in text: String, startLine: Int, endLine: Int,
                                     startColumn: Int, endColumn: Int) -> [NSRange] {
        let allLines = lines(text)
        let lo = min(startColumn, endColumn)
        let hi = max(startColumn, endColumn)
        var result: [NSRange] = []
        var offset = 0
        for (i, line) in allLines.enumerated() {
            let lineLen = (line as NSString).length
            if i >= startLine && i <= endLine {
                let s = min(lo, lineLen)
                let e = min(hi, lineLen)
                result.append(NSRange(location: offset + s, length: e - s))
            }
            offset += lineLen + 1   // +1 for the newline
        }
        return result
    }

    /// Delete the block (every per-line range), bottom-up so offsets stay valid.
    public static func deleteBlock(in text: String, startLine: Int, endLine: Int,
                                   startColumn: Int, endColumn: Int) -> Edit {
        let ranges = perLineRanges(in: text, startLine: startLine, endLine: endLine,
                                   startColumn: startColumn, endColumn: endColumn)
        let ns = NSMutableString(string: text)
        for r in ranges.reversed() where r.length > 0 {
            ns.deleteCharacters(in: r)
        }
        return Edit(text: ns as String, caretColumn: min(startColumn, endColumn))
    }

    /// Insert `string` at the block's left column on every line, bottom-up. Short
    /// lines are space-padded so the insertion lands at the requested column.
    public static func insertIntoBlock(_ string: String, in text: String,
                                       startLine: Int, endLine: Int,
                                       startColumn: Int, endColumn: Int) -> Edit {
        let col = min(startColumn, endColumn)
        var allLines = lines(text)
        for i in stride(from: min(endLine, allLines.count - 1), through: startLine, by: -1) {
            guard i >= 0, i < allLines.count else { continue }
            var line = allLines[i]
            let lineLen = (line as NSString).length
            if lineLen < col {
                line += String(repeating: " ", count: col - lineLen)
            }
            let ns = NSMutableString(string: line)
            ns.insert(string, at: min(col, ns.length))
            allLines[i] = ns as String
        }
        return Edit(text: allLines.joined(separator: "\n"),
                    caretColumn: col + (string as NSString).length)
    }

    /// Replace the block on every row with `string`: delete the rectangle, then
    /// insert `string` at the (now-collapsed) left column on each affected row.
    public static func replaceBlock(_ string: String, in text: String,
                                    startLine: Int, endLine: Int,
                                    startColumn: Int, endColumn: Int) -> Edit {
        let deleted = deleteBlock(in: text, startLine: startLine, endLine: endLine,
                                  startColumn: startColumn, endColumn: endColumn)
        let col = min(startColumn, endColumn)
        return insertIntoBlock(string, in: deleted.text,
                               startLine: startLine, endLine: endLine,
                               startColumn: col, endColumn: col)
    }

    /// Paste `clipboardLines` as a block: line *i* goes to row `startLine + i`,
    /// inserted at `column` (short rows space-padded). Lines that would fall past
    /// the last existing row are dropped (no new lines created in this cut).
    public static func pasteBlock(_ clipboardLines: [String], in text: String,
                                  startLine: Int, column: Int) -> Edit {
        var allLines = lines(text)
        // Apply bottom-up so insertions don't disturb earlier line offsets (line
        // indexing is by array position, so order doesn't matter, but keep it tidy).
        for (i, piece) in clipboardLines.enumerated() {
            let row = startLine + i
            guard row >= 0, row < allLines.count else { continue }   // stop at last line
            var line = allLines[row]
            let lineLen = (line as NSString).length
            if lineLen < column { line += String(repeating: " ", count: column - lineLen) }
            let ns = NSMutableString(string: line)
            ns.insert(piece, at: min(column, ns.length))
            allLines[row] = ns as String
        }
        return Edit(text: allLines.joined(separator: "\n"), caretColumn: column)
    }

    /// The block's text, rows joined by newlines (for copy).
    public static func copyBlock(in text: String, startLine: Int, endLine: Int,
                                 startColumn: Int, endColumn: Int) -> String {
        let ranges = perLineRanges(in: text, startLine: startLine, endLine: endLine,
                                   startColumn: startColumn, endColumn: endColumn)
        let ns = text as NSString
        return ranges.map { ns.substring(with: $0) }.joined(separator: "\n")
    }
}
