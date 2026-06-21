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

    mutating func defaultVisit(_ markup: Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }

    // MARK: Inline

    mutating func visitText(_ text: Text) -> String { htmlEscape(text.string) }
    // Raw HTML embedded in the Markdown is ESCAPED, not passed through — the preview
    // must never render arbitrary markup/script from document content.
    mutating func visitInlineHTML(_ h: InlineHTML) -> String { htmlEscape(h.rawHTML) }
    mutating func visitHTMLBlock(_ h: HTMLBlock) -> String { "<p>\(htmlEscape(h.rawHTML))</p>\n" }
    mutating func visitSoftBreak(_ s: SoftBreak) -> String { " " }
    mutating func visitLineBreak(_ l: LineBreak) -> String { "<br>" }
    mutating func visitInlineCode(_ c: InlineCode) -> String { "<code>\(htmlEscape(c.code))</code>" }
    mutating func visitEmphasis(_ e: Emphasis) -> String { "<em>\(defaultVisit(e))</em>" }
    mutating func visitStrong(_ s: Strong) -> String { "<strong>\(defaultVisit(s))</strong>" }
    mutating func visitStrikethrough(_ s: Strikethrough) -> String { "<del>\(defaultVisit(s))</del>" }

    mutating func visitLink(_ l: Link) -> String {
        let href = htmlEscape(l.destination ?? "")
        return "<a href=\"\(href)\">\(defaultVisit(l))</a>"
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
