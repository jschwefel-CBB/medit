import AppKit
import Markdown

/// Renders Markdown (CommonMark + GFM) into a styled `NSAttributedString` for the
/// read-only preview. Pure value type: parse with swift-markdown, walk the AST,
/// emit attributes. No web view. The caller supplies a `Theme` built from the
/// editor's font/colors/appearance so the preview matches the editor.
public struct MarkdownRenderer {
    public struct Theme {
        public var baseFont: NSFont
        public var foreground: NSColor
        public var secondary: NSColor
        public var codeBackground: NSColor
        public var linkColor: NSColor
        public var isDark: Bool
        public init(baseFont: NSFont, foreground: NSColor, secondary: NSColor,
                    codeBackground: NSColor, linkColor: NSColor, isDark: Bool) {
            self.baseFont = baseFont; self.foreground = foreground
            self.secondary = secondary; self.codeBackground = codeBackground
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

    init(theme: MarkdownRenderer.Theme) { self.theme = theme }

    mutating func build(_ doc: Document) -> NSAttributedString {
        visit(doc)
        return out
    }

    // MARK: Fonts / emit

    private func font(bold: Bool, italic: Bool, mono: Bool, size: CGFloat? = nil) -> NSFont {
        let pt = size ?? theme.baseFont.pointSize
        var f = mono ? NSFont.monospacedSystemFont(ofSize: pt, weight: .regular)
                     : NSFont(descriptor: theme.baseFont.fontDescriptor, size: pt) ?? theme.baseFont
        var traits: NSFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        if !traits.isEmpty {
            let d = f.fontDescriptor.withSymbolicTraits(traits)
            f = NSFont(descriptor: d, size: pt) ?? f
        }
        return f
    }

    private func emit(_ text: String) {
        var a: [NSAttributedString.Key: Any] = [
            .font: font(bold: bold, italic: italic, mono: code),
            .foregroundColor: link != nil ? theme.linkColor : theme.foreground,
        ]
        if strike { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if code { a[.backgroundColor] = theme.codeBackground }
        if let link { a[.link] = link }
        out.append(NSAttributedString(string: text, attributes: a))
    }

    // MARK: MarkupVisitor — inline

    mutating func defaultVisit(_ markup: Markup) {
        for child in markup.children { visit(child) }
    }
    mutating func visitText(_ text: Text) { emit(text.string) }
    mutating func visitSoftBreak(_ softBreak: SoftBreak) { emit(" ") }
    mutating func visitLineBreak(_ lineBreak: LineBreak) { emit("\n") }
    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        let was = code; code = true; emit(inlineCode.code); code = was
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

    // MARK: MarkupVisitor — blocks

    /// When > 0 we're inside a list item; paragraphs then use a single newline
    /// (tight) and skip the double block-gap.
    private var listDepth = 0

    mutating func visitParagraph(_ paragraph: Paragraph) {
        defaultVisit(paragraph)
        out.append(NSAttributedString(string: listDepth > 0 ? "\n" : "\n\n"))
    }

    mutating func visitHeading(_ heading: Heading) {
        let scale: CGFloat = [1: 2.0, 2: 1.6, 3: 1.3, 4: 1.15, 5: 1.05, 6: 1.0][heading.level] ?? 1.0
        let size = theme.baseFont.pointSize * scale
        let headFont = font(bold: true, italic: false, mono: false, size: size)
        let para = NSMutableParagraphStyle()
        para.paragraphSpacingBefore = size * 0.4
        para.paragraphSpacing = size * 0.2
        let start = out.length
        defaultVisit(heading)
        if out.length > start {
            let range = NSRange(location: start, length: out.length - start)
            out.addAttributes([.font: headFont, .paragraphStyle: para], range: range)
        }
        out.append(NSAttributedString(string: "\n\n"))
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let para = NSMutableParagraphStyle()
        para.firstLineHeadIndent = 8; para.headIndent = 8
        let mono = NSFont.monospacedSystemFont(ofSize: theme.baseFont.pointSize, weight: .regular)
        // CodeBlock.code includes a trailing newline; keep it as the block body.
        out.append(NSAttributedString(string: codeBlock.code, attributes: [
            .font: mono, .foregroundColor: theme.foreground,
            .backgroundColor: theme.codeBackground, .paragraphStyle: para]))
        out.append(NSAttributedString(string: "\n"))
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        let para = NSMutableParagraphStyle()
        para.firstLineHeadIndent = 16; para.headIndent = 16
        let start = out.length
        defaultVisit(blockQuote)
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
        let para = NSMutableParagraphStyle()
        para.headIndent = 24; para.firstLineHeadIndent = 8
        listDepth += 1
        var n = 1
        for item in items {
            let marker: String
            if let checkbox = item.checkbox {            // GFM task list
                marker = (checkbox == .checked ? "☑ " : "☐ ")
            } else if ordered {
                marker = "\(n). "; n += 1
            } else {
                marker = "•  "
            }
            let start = out.length
            out.append(NSAttributedString(string: marker,
                attributes: [.font: theme.baseFont, .foregroundColor: theme.foreground]))
            for child in item.children { visit(child) }
            if out.length > start {
                out.addAttribute(.paragraphStyle, value: para,
                                 range: NSRange(location: start, length: out.length - start))
            }
        }
        listDepth -= 1
        out.append(NSAttributedString(string: "\n"))
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        // A full-width rule rendered as a struck-through run of spaces.
        out.append(NSAttributedString(string: "\u{00A0}\n", attributes: [
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .strikethroughColor: theme.secondary,
            .foregroundColor: theme.secondary,
            .font: theme.baseFont]))
        out.append(NSAttributedString(string: "\n"))
    }

    mutating func visitTable(_ table: Table) {
        renderTableRow(table.head, bold: true)
        for row in table.body.rows { renderTableRow(row, bold: false) }
        out.append(NSAttributedString(string: "\n"))
    }

    private mutating func renderTableRow(_ row: Markup, bold: Bool) {
        let wasBold = self.bold
        self.bold = bold
        var first = true
        for cell in row.children {
            if !first { out.append(NSAttributedString(string: "\t",
                attributes: [.font: theme.baseFont, .foregroundColor: theme.foreground])) }
            for child in cell.children { visit(child) }
            first = false
        }
        self.bold = wasBold
        out.append(NSAttributedString(string: "\n"))
    }
}
