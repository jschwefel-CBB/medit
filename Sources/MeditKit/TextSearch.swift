import Foundation

/// A search specification: a term, whether it's a regular expression, and
/// case sensitivity. Shared by the per-document find bar and the
/// find-in-all-tabs feature.
public struct SearchQuery: Equatable {
    public var term: String
    public var isRegex: Bool
    public var caseSensitive: Bool

    public init(term: String, isRegex: Bool, caseSensitive: Bool) {
        self.term = term
        self.isRegex = isRegex
        self.caseSensitive = caseSensitive
    }
}

/// Stateless search/replace over `String`, returning `NSRange`s (UTF-16) so
/// results map directly onto `NSTextView`/`NSTextStorage`. Pure logic — fully
/// unit-tested without any AppKit.
public enum TextSearch {

    /// Build an `NSRegularExpression` for the query, treating literal queries
    /// as escaped patterns. Returns `nil` if a regex query fails to compile.
    private static func makeRegex(_ query: SearchQuery) -> NSRegularExpression? {
        guard !query.term.isEmpty else { return nil }
        let pattern = query.isRegex ? query.term : NSRegularExpression.escapedPattern(for: query.term)
        var options: NSRegularExpression.Options = []
        if !query.caseSensitive { options.insert(.caseInsensitive) }
        return try? NSRegularExpression(pattern: pattern, options: options)
    }

    /// Returns a human-readable error message if the query's regex is invalid,
    /// or `nil` if the query is usable (literal queries are always valid).
    public static func validate(_ query: SearchQuery) -> String? {
        guard query.isRegex, !query.term.isEmpty else { return nil }
        do {
            _ = try NSRegularExpression(pattern: query.term, options: [])
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// All match ranges of `query` within `text`.
    public static func matches(of query: SearchQuery, in text: String) -> [NSRange] {
        guard let regex = makeRegex(query) else { return [] }
        let full = NSRange(location: 0, length: (text as NSString).length)
        return regex.matches(in: text, options: [], range: full).map { $0.range }
    }

    /// Replace every match with `template`. For regex queries, `template`
    /// supports `$1`-style capture references; for literal queries it is used
    /// verbatim (any `$` is escaped first). Returns the new string and the
    /// number of replacements made.
    public static func replacingAll(of query: SearchQuery, in text: String, with template: String) -> (result: String, count: Int) {
        guard let regex = makeRegex(query) else { return (text, 0) }
        let ns = NSMutableString(string: text)
        let full = NSRange(location: 0, length: ns.length)
        let safeTemplate = query.isRegex ? template : NSRegularExpression.escapedTemplate(for: template)
        let count = regex.replaceMatches(in: ns, options: [], range: full, withTemplate: safeTemplate)
        return (ns as String, count)
    }

    /// 1-based line number containing the given UTF-16 offset within `text`.
    public static func lineNumber(for utf16Offset: Int, in text: String) -> Int {
        let ns = text as NSString
        let clamped = min(max(0, utf16Offset), ns.length)
        var line = 1
        var index = 0
        while index < clamped {
            let range = ns.lineRange(for: NSRange(location: index, length: 0))
            if NSMaxRange(range) <= clamped {
                line += 1
                index = NSMaxRange(range)
                if range.length == 0 { break } // guard against non-advancing range
            } else {
                break
            }
        }
        return line
    }
}
