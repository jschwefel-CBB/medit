import AppKit
import Markdown

/// Renders Markdown (CommonMark + GFM) into a styled `NSAttributedString` for the
/// read-only preview. Pure value type: parse with swift-markdown, walk the AST,
/// emit attributes. No web view. The caller supplies a `Theme` (proportional body
/// font, monospace for code) so the preview reads like a modern document.
public struct MarkdownRenderer {
    public struct Theme {
        public var baseFont: NSFont        // proportional body font
        public var monoFont: NSFont        // code font
        public var foreground: NSColor
        public var secondary: NSColor
        public var codeBackground: NSColor
        public var headingColor: NSColor
        public var quoteBarColor: NSColor
        public var tableBorderColor: NSColor
        public var linkColor: NSColor
        public var isDark: Bool
        public init(baseFont: NSFont, monoFont: NSFont, foreground: NSColor,
                    secondary: NSColor, codeBackground: NSColor, headingColor: NSColor,
                    quoteBarColor: NSColor, tableBorderColor: NSColor,
                    linkColor: NSColor, isDark: Bool) {
            self.baseFont = baseFont; self.monoFont = monoFont
            self.foreground = foreground; self.secondary = secondary
            self.codeBackground = codeBackground; self.headingColor = headingColor
            self.quoteBarColor = quoteBarColor; self.tableBorderColor = tableBorderColor
            self.linkColor = linkColor; self.isDark = isDark
        }
    }

    private let theme: Theme
    public init(theme: Theme) { self.theme = theme }

    public func render(_ markdown: String) -> NSAttributedString {
        let document = Document(parsing: markdown)
        var builder = AttributedStringBuilder(theme: theme)
        return builder.build(document)
    }
}

/// Walks the markdown AST accumulating an NSAttributedString. Inline styling is
/// tracked with a small style stack; block styling is applied per block.
private struct AttributedStringBuilder: MarkupVisitor {
    typealias Result = Void
    let theme: MarkdownRenderer.Theme
    private let out = NSMutableAttributedString()

    // Inline style state, pushed/popped as we descend.
    private var bold = false, italic = false, strike = false, code = false
    private var link: URL?
    private var listDepth = 0

    init(theme: MarkdownRenderer.Theme) { self.theme = theme }

    mutating func build(_ doc: Document) -> NSAttributedString {
        visit(doc)
        // Trim a trailing run of blank lines for a tidy bottom.
        while out.string.hasSuffix("\n") {
            out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1))
        }
        return out
    }

    // MARK: Fonts / paragraph styles

    private func font(bold: Bool, italic: Bool, mono: Bool, size: CGFloat? = nil) -> NSFont {
        let base = mono ? theme.monoFont : theme.baseFont
        let pt = size ?? base.pointSize
        var f = NSFont(descriptor: base.fontDescriptor, size: pt) ?? base
        var traits: NSFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        if !traits.isEmpty {
            let d = f.fontDescriptor.withSymbolicTraits(traits)
            f = NSFont(descriptor: d, size: pt) ?? f
        }
        return f
    }

    /// A body paragraph style with comfortable reading line-height + spacing.
    private func bodyParagraph(headIndent: CGFloat = 0, firstLineIndent: CGFloat = 0,
                               spacingAfter: CGFloat = 10, spacingBefore: CGFloat = 0) -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = 1.35
        p.paragraphSpacing = spacingAfter
        p.paragraphSpacingBefore = spacingBefore
        p.headIndent = headIndent
        p.firstLineHeadIndent = firstLineIndent
        return p
    }

    private func emit(_ text: String) {
        var a: [NSAttributedString.Key: Any] = [
            .font: font(bold: bold, italic: italic, mono: code),
            .foregroundColor: link != nil ? theme.linkColor : theme.foreground,
        ]
        if strike { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if code {
            a[.backgroundColor] = theme.codeBackground
            a[.foregroundColor] = theme.secondary
        }
        if let link {
            a[.link] = link
            a[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        out.append(NSAttributedString(string: text, attributes: a))
    }

    private func applyParagraph(_ style: NSParagraphStyle, from start: Int) {
        guard out.length > start else { return }
        out.addAttribute(.paragraphStyle, value: style,
                         range: NSRange(location: start, length: out.length - start))
    }

    // MARK: Inline

    mutating func defaultVisit(_ markup: Markup) {
        for child in markup.children { visit(child) }
    }
    mutating func visitText(_ text: Text) { emit(text.string) }
    mutating func visitSoftBreak(_ softBreak: SoftBreak) { emit(" ") }
    mutating func visitLineBreak(_ lineBreak: LineBreak) { emit("\n") }
    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        let was = code; code = true; emit(" " + inlineCode.code + " "); code = was
    }
    mutating func visitEmphasis(_ emphasis: Emphasis) {
        let was = italic; italic = true; defaultVisit(emphasis); italic = was
    }
    mutating func visitStrong(_ strong: Strong) {
        let was = bold; bold = true; defaultVisit(strong); bold = was
    }
    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        let was = strike; strike = true; defaultVisit(strikethrough); strike = was
    }
    mutating func visitLink(_ l: Link) {
        let was = link
        link = l.destination.flatMap { URL(string: $0) }
        defaultVisit(l)
        link = was
    }

    // MARK: Blocks

    mutating func visitParagraph(_ paragraph: Paragraph) {
        let start = out.length
        defaultVisit(paragraph)
        if listDepth > 0 {
            applyParagraph(bodyParagraph(headIndent: 24, firstLineIndent: 0, spacingAfter: 4), from: start)
            out.append(NSAttributedString(string: "\n"))
        } else {
            applyParagraph(bodyParagraph(), from: start)
            out.append(NSAttributedString(string: "\n"))
        }
    }

    mutating func visitHeading(_ heading: Heading) {
        let scale: CGFloat = [1: 1.9, 2: 1.55, 3: 1.3, 4: 1.15, 5: 1.05, 6: 0.95][heading.level] ?? 1.0
        let size = theme.baseFont.pointSize * scale
        let weight: NSFont.Weight = heading.level <= 2 ? .bold : .semibold
        let headFont = NSFont.systemFont(ofSize: size, weight: weight)
        let para = bodyParagraph(spacingAfter: size * 0.35, spacingBefore: size * 0.6)
        para.lineHeightMultiple = 1.1
        let start = out.length
        defaultVisit(heading)
        if out.length > start {
            let range = NSRange(location: start, length: out.length - start)
            out.addAttributes([.font: headFont, .foregroundColor: theme.headingColor,
                               .paragraphStyle: para], range: range)
        }
        out.append(NSAttributedString(string: "\n"))
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let para = bodyParagraph(headIndent: 12, firstLineIndent: 12, spacingAfter: 12, spacingBefore: 4)
        para.lineHeightMultiple = 1.2
        // Trim the single trailing newline cmark includes so the panel isn't padded oddly.
        var body = codeBlock.code
        if body.hasSuffix("\n") { body.removeLast() }
        out.append(NSAttributedString(string: body, attributes: [
            .font: theme.monoFont, .foregroundColor: theme.foreground,
            .backgroundColor: theme.codeBackground, .paragraphStyle: para]))
        out.append(NSAttributedString(string: "\n\n"))
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        let para = bodyParagraph(headIndent: 18, firstLineIndent: 18, spacingAfter: 10)
        let start = out.length
        // Leading colored bar via a styled vertical bar glyph.
        out.append(NSAttributedString(string: "▎ ", attributes: [
            .foregroundColor: theme.quoteBarColor, .font: theme.baseFont]))
        let savedItalic = italic
        defaultVisit(blockQuote)
        italic = savedItalic
        // Recolor the quote body secondary, keep the bar color.
        if out.length > start {
            out.addAttribute(.paragraphStyle, value: para,
                             range: NSRange(location: start, length: out.length - start))
        }
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        renderList(Array(unorderedList.listItems), ordered: false)
    }
    mutating func visitOrderedList(_ orderedList: OrderedList) {
        renderList(Array(orderedList.listItems), ordered: true)
    }

    private mutating func renderList(_ items: [ListItem], ordered: Bool) {
        listDepth += 1
        var n = 1
        for item in items {
            let marker: String
            var markerColor = theme.secondary
            if let checkbox = item.checkbox {            // GFM task list
                marker = (checkbox == .checked ? "☑  " : "☐  ")
                markerColor = checkbox == .checked ? theme.headingColor : theme.secondary
            } else if ordered {
                marker = "\(n).  "; n += 1
            } else {
                marker = "•  "
            }
            let para = bodyParagraph(headIndent: 24, firstLineIndent: 8, spacingAfter: 4)
            let start = out.length
            out.append(NSAttributedString(string: marker,
                attributes: [.font: theme.baseFont, .foregroundColor: markerColor]))
            for child in item.children { visit(child) }
            applyParagraph(para, from: start)
        }
        listDepth -= 1
        out.append(NSAttributedString(string: "\n"))
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        let para = NSMutableParagraphStyle()
        para.paragraphSpacing = 12; para.paragraphSpacingBefore = 8
        // A full-width hairline rule.
        out.append(NSAttributedString(string: String(repeating: "\u{2500}", count: 48) + "\n",
            attributes: [.foregroundColor: theme.tableBorderColor,
                         .font: theme.baseFont, .paragraphStyle: para]))
    }

    // MARK: Tables

    mutating func visitTable(_ table: Table) {
        let para = bodyParagraph(spacingAfter: 12, spacingBefore: 4)
        para.lineHeightMultiple = 1.25
        let start = out.length
        renderTableRow(table.head, bold: true)
        // Separator under the header.
        let cols = max(1, Array(table.head.children).count)
        let sep: String = Array(repeating: "──────", count: cols).joined(separator: "┼")
        out.append(NSAttributedString(string: sep + "\n",
            attributes: [.foregroundColor: theme.tableBorderColor, .font: theme.monoFont]))
        for row in table.body.rows { renderTableRow(row, bold: false) }
        applyParagraph(para, from: start)
        out.append(NSAttributedString(string: "\n"))
    }

    private mutating func renderTableRow(_ row: Markup, bold: Bool) {
        let wasBold = self.bold
        self.bold = bold
        var first = true
        for cell in row.children {
            if !first {
                out.append(NSAttributedString(string: "  │  ",
                    attributes: [.foregroundColor: theme.tableBorderColor, .font: theme.monoFont]))
            }
            for child in cell.children { visit(child) }
            first = false
        }
        self.bold = wasBold
        out.append(NSAttributedString(string: "\n"))
    }
}
