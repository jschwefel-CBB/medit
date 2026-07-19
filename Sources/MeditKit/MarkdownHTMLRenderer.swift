import Foundation
import Markdown

/// Renders Markdown (CommonMark + GFM) to an HTML body string for the WKWebView
/// preview. A `MarkupVisitor` walks the swift-markdown AST and emits HTML; the web
/// view + CSS (see `PreviewHTMLTemplate`) then handle layout, wrapping, scrolling,
/// selection and copy — the things browsers do natively and TextKit does not.
///
/// All document **text** is HTML-escaped so file content can't inject markup/script.
public enum MarkdownHTMLRenderer {
    public static func renderBody(_ markdown: String) -> String {
        let document = Document(parsing: markdown)
        var visitor = HTMLVisitor()
        return visitor.visit(document)
    }
}

/// Escape text for safe inclusion in HTML element content / attribute values.
func htmlEscape(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.count)
    for ch in s {
        switch ch {
        case "&": out += "&amp;"
        case "<": out += "&lt;"
        case ">": out += "&gt;"
        case "\"": out += "&quot;"
        case "'": out += "&#39;"
        default: out.append(ch)
        }
    }
    return out
}

private struct HTMLVisitor: MarkupVisitor {
    typealias Result = String

    /// Nonzero while visiting the children of a `Link`. Bare-URL autolinking in
    /// `visitText` is suppressed there so an autolink can never be nested inside
    /// an existing anchor (`<a>` inside `<a>` is invalid and would double-style).
    private var linkDepth = 0

    /// Apple's own URL/email recognizer — the same data detection Mail and Notes
    /// use — reused as one shared instance (it is immutable and thread-safe after
    /// creation, and `renderBody` may run off the main thread). `.link` matches
    /// http/https/ftp, bare `www.` hosts, and email addresses; it deliberately
    /// does NOT match arbitrary schemes such as `javascript:`, so autolinking
    /// cannot introduce a script URL.
    private static let linkDetector: NSDataDetector? =
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    // SECURITY INVARIANT: every visitor returns already-HTML-safe output. Leaf text
    // nodes go through `htmlEscape`; raw-HTML nodes are escaped; element nodes wrap
    // already-safe child output. So assembled strings (e.g. image alt, table cells,
    // the final body) are safe to interpolate without a second escape. When adding a
    // new visitor, escape any text it introduces — that is what keeps document
    // content from injecting markup/script into the preview.
    mutating func defaultVisit(_ markup: Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }

    // MARK: Inline

    // A bare URL typed as plain prose ("see https://example.com") is, per
    // CommonMark, just text — swift-markdown does not attach the GFM autolink
    // extension — so it arrives here as a Text node and would otherwise render in
    // body colour, indistinguishable from surrounding prose. Autolink it so EVERY
    // URL in the preview is a highlighted link, matching `[label](url)` and
    // `<url>` (which already parse to Link nodes).
    mutating func visitText(_ text: Text) -> String { autolinked(text.string) }
    // Raw HTML embedded in the Markdown is ESCAPED, not passed through — the preview
    // must never render arbitrary markup/script from document content.
    mutating func visitInlineHTML(_ h: InlineHTML) -> String { htmlEscape(h.rawHTML) }
    // A raw-HTML block is shown verbatim (escaped) in a <pre> so its line structure
    // is preserved, rather than collapsed into one run-on <p>.
    mutating func visitHTMLBlock(_ h: HTMLBlock) -> String {
        var raw = h.rawHTML
        if raw.hasSuffix("\n") { raw.removeLast() }
        return "<pre class=\"raw-html\">\(htmlEscape(raw))</pre>\n"
    }
    mutating func visitSoftBreak(_ s: SoftBreak) -> String { " " }
    mutating func visitLineBreak(_ l: LineBreak) -> String { "<br>" }
    mutating func visitInlineCode(_ c: InlineCode) -> String { "<code>\(htmlEscape(c.code))</code>" }
    mutating func visitEmphasis(_ e: Emphasis) -> String { "<em>\(defaultVisit(e))</em>" }
    mutating func visitStrong(_ s: Strong) -> String { "<strong>\(defaultVisit(s))</strong>" }
    mutating func visitStrikethrough(_ s: Strikethrough) -> String { "<del>\(defaultVisit(s))</del>" }

    mutating func visitLink(_ l: Link) -> String {
        let href = htmlEscape(l.destination ?? "")
        // Suppress bare-URL autolinking while rendering this link's own children,
        // so a URL used as link text is not wrapped in a second, nested anchor.
        linkDepth += 1
        defer { linkDepth -= 1 }
        return "<a href=\"\(href)\">\(defaultVisit(l))</a>"
    }

    /// HTML-escape `text`, additionally wrapping any URL or email address it
    /// contains in an `<a>`. Every emitted fragment — the surrounding prose, the
    /// visible URL text, and the `href` value — is HTML-escaped, so the security
    /// invariant (document content can never inject markup or script) still holds.
    /// Inside an existing link (`linkDepth > 0`) or when nothing is detected, this
    /// is exactly the old behaviour: escape and return.
    private func autolinked(_ text: String) -> String {
        guard linkDepth == 0,
              let detector = HTMLVisitor.linkDetector,
              !text.isEmpty else { return htmlEscape(text) }

        let ns = text as NSString
        let matches = detector.matches(in: text, options: [],
                                       range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return htmlEscape(text) }

        var out = ""
        var cursor = 0
        for match in matches {
            let r = match.range
            if r.location > cursor {
                out += htmlEscape(ns.substring(with: NSRange(location: cursor,
                                                             length: r.location - cursor)))
            }
            let shown = ns.substring(with: r)
            // NSDataDetector normalizes the destination (e.g. "www.x.com" →
            // "http://www.x.com", "a@b.com" → "mailto:a@b.com"); the visible text
            // stays exactly as the author typed it. Fall back to the shown text.
            let href = match.url?.absoluteString ?? shown
            out += "<a href=\"\(htmlEscape(href))\">\(htmlEscape(shown))</a>"
            cursor = r.location + r.length
        }
        if cursor < ns.length {
            out += htmlEscape(ns.substring(with: NSRange(location: cursor,
                                                         length: ns.length - cursor)))
        }
        return out
    }

    mutating func visitImage(_ image: Image) -> String {
        // v1: do not load remote images (network/sandbox); show alt text.
        let alt = image.children.map { visit($0) }.joined()
        return alt.isEmpty ? "" : "<span class=\"img-alt\">\(alt)</span>"
    }

    // MARK: Blocks

    mutating func visitParagraph(_ p: Paragraph) -> String { "<p>\(defaultVisit(p))</p>\n" }

    mutating func visitHeading(_ h: Heading) -> String {
        let level = min(max(h.level, 1), 6)
        return "<h\(level)>\(defaultVisit(h))</h\(level)>\n"
    }

    mutating func visitCodeBlock(_ c: CodeBlock) -> String {
        let lang = c.language.map { " class=\"language-\(htmlEscape($0))\"" } ?? ""
        // Strip a single trailing newline swift-markdown includes.
        var code = c.code
        if code.hasSuffix("\n") { code.removeLast() }
        return "<pre><code\(lang)>\(htmlEscape(code))</code></pre>\n"
    }

    mutating func visitBlockQuote(_ q: BlockQuote) -> String {
        "<blockquote>\(defaultVisit(q))</blockquote>\n"
    }

    mutating func visitUnorderedList(_ list: UnorderedList) -> String {
        "<ul>\n\(defaultVisit(list))</ul>\n"
    }

    mutating func visitOrderedList(_ list: OrderedList) -> String {
        "<ol>\n\(defaultVisit(list))</ol>\n"
    }

    mutating func visitListItem(_ item: ListItem) -> String {
        if let checkbox = item.checkbox {
            let checked = (checkbox == .checked) ? " checked" : ""
            return "<li class=\"task\"><input type=\"checkbox\" disabled\(checked)> \(defaultVisit(item))</li>\n"
        }
        return "<li>\(defaultVisit(item))</li>\n"
    }

    mutating func visitThematicBreak(_ t: ThematicBreak) -> String { "<hr>\n" }

    // MARK: Tables (GFM)

    mutating func visitTable(_ table: Table) -> String {
        var html = "<div class=\"table-wrap\"><table>\n<thead>\n<tr>"
        for cell in table.head.children {
            html += "<th>\(cell.children.map { visit($0) }.joined())</th>"
        }
        html += "</tr>\n</thead>\n<tbody>\n"
        for row in table.body.rows {
            html += "<tr>"
            for cell in row.children {
                html += "<td>\(cell.children.map { visit($0) }.joined())</td>"
            }
            html += "</tr>\n"
        }
        html += "</tbody>\n</table></div>\n"
        return html
    }
}
