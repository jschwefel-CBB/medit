import Foundation

/// Pure Markdown source transforms used by the style bar. Each takes the full
/// text and the current selection (NSRange, UTF-16 — matching NSTextView) and
/// returns the edited text plus where the selection should land. No AppKit, so
/// every transform is exhaustively unit-testable.
public enum MarkdownEditing {

    public struct Edit: Equatable {
        public var text: String
        public var selectedRange: NSRange
        public init(text: String, selectedRange: NSRange) {
            self.text = text; self.selectedRange = selectedRange
        }
    }

    public enum LinePrefix: Equatable {
        case heading(Int)   // # … ###### (level 1–6)
        case bullet         // "- "
        case ordered        // "1. ", "2. " …
        case quote          // "> "

        /// The literal prefix for a single line (ordered uses the running index).
        func marker(index: Int) -> String {
            switch self {
            case .heading(let l): return String(repeating: "#", count: max(1, min(6, l))) + " "
            case .bullet: return "- "
            case .ordered: return "\(index). "
            case .quote: return "> "
            }
        }
        /// Regex-free test for whether a line already carries this prefix.
        func matches(_ line: String) -> Bool {
            switch self {
            case .heading(let l):
                let hashes = String(repeating: "#", count: max(1, min(6, l)))
                return line.hasPrefix(hashes + " ")
            case .bullet: return line.hasPrefix("- ")
            case .quote: return line.hasPrefix("> ")
            case .ordered:
                // "<digits>. " at the start.
                var seenDigit = false
                var i = line.startIndex
                while i < line.endIndex, line[i].isNumber { seenDigit = true; i = line.index(after: i) }
                guard seenDigit, i < line.endIndex, line[i] == "." else { return false }
                let j = line.index(after: i)
                return j < line.endIndex && line[j] == " "
            }
        }
        /// Strip this prefix from a line known to match.
        func strip(_ line: String) -> String {
            switch self {
            case .heading(let l):
                let p = String(repeating: "#", count: max(1, min(6, l))) + " "
                return String(line.dropFirst(p.count))
            case .bullet: return String(line.dropFirst(2))
            case .quote: return String(line.dropFirst(2))
            case .ordered:
                if let dot = line.firstIndex(of: ".") {
                    let after = line.index(after: dot)
                    if after < line.endIndex && line[after] == " " {
                        return String(line[line.index(after: after)...])
                    }
                }
                return line
            }
        }
    }

    // MARK: Inline

    public static func toggleInline(_ text: String, _ range: NSRange, marker: String) -> Edit {
        let ns = text as NSString
        let m = marker as NSString
        let mLen = m.length

        // Empty selection → insert "<marker><marker>" with caret between.
        if range.length == 0 {
            let inserted = ns.replacingCharacters(in: range, with: marker + marker)
            return Edit(text: inserted, selectedRange: NSRange(location: range.location + mLen, length: 0))
        }

        let selected = ns.substring(with: range)

        // Already wrapped *inside* the selection? e.g. selection == "**bold**".
        if selected.hasPrefix(marker), selected.hasSuffix(marker), selected.count >= 2 * marker.count {
            let inner = (selected as NSString).substring(with: NSRange(location: mLen, length: (selected as NSString).length - 2 * mLen))
            let newText = ns.replacingCharacters(in: range, with: inner)
            return Edit(text: newText, selectedRange: NSRange(location: range.location, length: (inner as NSString).length))
        }

        // Already wrapped *just outside* the selection? markers flank it.
        let beforeStart = range.location - mLen
        let afterEnd = range.location + range.length
        if beforeStart >= 0, afterEnd + mLen <= ns.length,
           ns.substring(with: NSRange(location: beforeStart, length: mLen)) == marker,
           ns.substring(with: NSRange(location: afterEnd, length: mLen)) == marker {
            // Remove the flanking markers.
            let outer = NSRange(location: beforeStart, length: range.length + 2 * mLen)
            let newText = ns.replacingCharacters(in: outer, with: selected)
            return Edit(text: newText, selectedRange: NSRange(location: beforeStart, length: range.length))
        }

        // Otherwise wrap.
        let wrapped = marker + selected + marker
        let newText = ns.replacingCharacters(in: range, with: wrapped)
        return Edit(text: newText, selectedRange: NSRange(location: range.location + mLen, length: range.length))
    }

    // MARK: Link

    public static func insertLink(_ text: String, _ range: NSRange) -> Edit {
        let ns = text as NSString
        let label = ns.substring(with: range)
        let replacement = "[\(label)]()"
        let newText = ns.replacingCharacters(in: range, with: replacement)
        // Caret inside the empty () — after "[label](".
        let caret = range.location + ("[\(label)](" as NSString).length
        return Edit(text: newText, selectedRange: NSRange(location: caret, length: 0))
    }

    // MARK: Line prefixes

    public static func toggleLinePrefix(_ text: String, _ range: NSRange, prefix: LinePrefix) -> Edit {
        let ns = text as NSString
        // Expand the range to whole lines.
        let lineRange = ns.lineRange(for: range)
        let block = ns.substring(with: lineRange)
        // Split, preserving a trailing newline if present.
        let hadTrailingNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if hadTrailingNewline { lines.removeLast() }   // last component is "" from the trailing \n

        let nonEmpty = lines.filter { !$0.isEmpty }
        let allPrefixed = !nonEmpty.isEmpty && nonEmpty.allSatisfy { prefix.matches($0) }

        var out: [String] = []
        var idx = 1
        for line in lines {
            if line.isEmpty { out.append(line); continue }
            if allPrefixed {
                out.append(prefix.strip(line))
            } else {
                out.append(prefix.marker(index: idx) + line)
            }
            idx += 1
        }
        var newBlock = out.joined(separator: "\n")
        if hadTrailingNewline { newBlock += "\n" }
        let newText = ns.replacingCharacters(in: lineRange, with: newBlock)
        // Select the edited block.
        return Edit(text: newText, selectedRange: NSRange(location: lineRange.location, length: (newBlock as NSString).length))
    }

    // MARK: Code block

    public static func toggleCodeBlock(_ text: String, _ range: NSRange) -> Edit {
        let ns = text as NSString
        let lineRange = ns.lineRange(for: range)
        var block = ns.substring(with: lineRange)
        let hadTrailingNewline = block.hasSuffix("\n")
        if hadTrailingNewline { block.removeLast() }

        let lines = block.components(separatedBy: "\n")
        // Already fenced? first line "```" and last line "```".
        if lines.count >= 2, lines.first == "```", lines.last == "```" {
            let inner = lines.dropFirst().dropLast().joined(separator: "\n")
            var newBlock = inner
            if hadTrailingNewline { newBlock += "\n" }
            let newText = ns.replacingCharacters(in: lineRange, with: newBlock)
            return Edit(text: newText, selectedRange: NSRange(location: lineRange.location, length: (newBlock as NSString).length))
        }

        var newBlock = "```\n" + block + "\n```"
        if hadTrailingNewline { newBlock += "\n" }
        let newText = ns.replacingCharacters(in: lineRange, with: newBlock)
        return Edit(text: newText, selectedRange: NSRange(location: lineRange.location, length: (newBlock as NSString).length))
    }
}
