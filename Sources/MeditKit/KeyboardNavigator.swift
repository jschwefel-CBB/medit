import Foundation

/// Computes the resulting selection for PC-style Home/End navigation. Pure value
/// logic over `NSRange`s (UTF-16), so it maps directly onto NSTextView and is
/// fully unit-tested without AppKit. The current visual/logical line is supplied
/// by an injected provider so wrapped-line behavior lives in the view layer.
public enum KeyboardNavigator {

    public enum NavCommand {
        case lineStart   // Home
        case lineEnd     // End
        case docStart    // Ctrl+Home
        case docEnd      // Ctrl+End
    }

    /// Returns the new selection.
    /// - `current`: current selection (caret when length 0).
    /// - `extend`: true when Shift is held — keep the anchor, move the active end
    ///   to the target. The anchor is the end of `current` farther from the
    ///   target's direction; for a caret it's `current.location`.
    /// - `lineRangeProvider`: the range (incl. trailing newline) of the line
    ///   containing a given location.
    public static func newSelection(in text: String,
                                    current: NSRange,
                                    command: NavCommand,
                                    extend: Bool,
                                    lineRangeProvider: (NSRange) -> NSRange) -> NSRange {
        let ns = text as NSString
        let length = ns.length

        let target = targetLocation(command: command, current: current, ns: ns,
                                    length: length, lineRangeProvider: lineRangeProvider)

        if !extend {
            return NSRange(location: target, length: 0)
        }

        let anchor = anchorLocation(current: current)
        let lower = min(anchor, target)
        let upper = max(anchor, target)
        return NSRange(location: lower, length: upper - lower)
    }

    private static func targetLocation(command: NavCommand, current: NSRange,
                                       ns: NSString, length: Int,
                                       lineRangeProvider: (NSRange) -> NSRange) -> Int {
        switch command {
        case .docStart:
            return 0
        case .docEnd:
            return length
        case .lineStart:
            let line = lineRangeProvider(NSRange(location: caretForLineQuery(command, current), length: 0))
            return line.location
        case .lineEnd:
            let line = lineRangeProvider(NSRange(location: caretForLineQuery(command, current), length: 0))
            var end = NSMaxRange(line)
            if end > line.location {
                let lastCharRange = NSRange(location: end - 1, length: 1)
                if end <= length, ns.substring(with: lastCharRange) == "\n" {
                    end -= 1
                }
            }
            return end
        }
    }

    /// Which caret position to use when asking for the current line. For Home we
    /// use the selection's min; for End its max — so a multi-line selection
    /// resolves against the expected edge.
    private static func caretForLineQuery(_ command: NavCommand, _ current: NSRange) -> Int {
        switch command {
        case .lineStart: return current.location
        case .lineEnd: return NSMaxRange(current)
        default: return current.location
        }
    }

    /// The fixed anchor when extending. With only an `NSRange` to work from we
    /// treat `current.location` as the anchor and `NSMaxRange(current)` as the
    /// active (moving) end. So Shift+Home/Shift+End pin `location` and move the
    /// active end to the target; for a caret the two coincide.
    private static func anchorLocation(current: NSRange) -> Int {
        return current.location
    }
}
