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
    public init(theme: Theme) {
        self.theme = theme
    }

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
    let out = NSMutableAttributedString()

    // Inline style state, pushed/popped as we descend.
    var bold = false
    private var italic = false, strike = false, code = false
    private var link: URL?
    private var listDepth = 0

    init(theme: MarkdownRenderer.Theme) {
        self.theme = theme
    }

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
            // Marker only — the layout manager draws a tight rounded box behind the
            // glyphs (symmetric padding), instead of a line-height background fill.
            // This renderer is print-only (white paper), so keep inline-code text the
            // theme foreground (dark) for legibility rather than light steel.
            a[MarkdownBlockAttribute.inlineCode] = true
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
        // Thin hair-spaces give a snug background box instead of the loose padding a
        // full space produced.
        let was = code; code = true; emit("\u{2009}" + inlineCode.code + "\u{2009}"); code = was
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
        if heading.level <= 2 { para.paragraphSpacing = size * 0.55 }  // room for the rule
        let start = out.length
        defaultVisit(heading)
        if out.length > start {
            let range = NSRange(location: start, length: out.length - start)
            var attrs: [NSAttributedString.Key: Any] = [
                .font: headFont, .foregroundColor: theme.headingColor, .paragraphStyle: para,
                MarkdownBlockAttribute.headingLevel: heading.level]
            // h1/h2 get an underline rule drawn by the layout manager.
            if heading.level <= 2 {
                attrs[MarkdownBlockAttribute.blockKind] = MarkdownBlockAttribute.Kind.headingRule.rawValue
            }
            out.addAttributes(attrs, range: range)
        }
        out.append(NSAttributedString(string: "\n"))
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let para = bodyParagraph(headIndent: 16, firstLineIndent: 16, spacingAfter: 14, spacingBefore: 6)
        para.lineHeightMultiple = 1.25
        para.tailIndent = -16
        // Trim the single trailing newline cmark includes so the panel isn't padded oddly.
        var body = codeBlock.code
        if body.hasSuffix("\n") { body.removeLast() }
        let start = out.length
        out.append(NSAttributedString(string: body, attributes: [
            .font: theme.monoFont, .foregroundColor: theme.foreground,
            .paragraphStyle: para,
            MarkdownBlockAttribute.blockKind: MarkdownBlockAttribute.Kind.codeBlock.rawValue]))
        _ = start
        out.append(NSAttributedString(string: "\n\n"))
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        let para = bodyParagraph(headIndent: 18, firstLineIndent: 18, spacingAfter: 10)
        let start = out.length
        let savedItalic = italic
        defaultVisit(blockQuote)
        italic = savedItalic
        if out.length > start {
            let range = NSRange(location: start, length: out.length - start)
            out.addAttribute(.paragraphStyle, value: para, range: range)
            // The layout manager draws the left bar; recolor body secondary.
            out.addAttribute(MarkdownBlockAttribute.blockKind,
                             value: MarkdownBlockAttribute.Kind.blockQuote.rawValue, range: range)
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
        para.paragraphSpacing = 14; para.paragraphSpacingBefore = 10
        // A blank line carrying the thematic-break attribute; the layout manager
        // draws a full-width hairline through it (no box-drawing glyphs).
        out.append(NSAttributedString(string: "\u{00A0}\n", attributes: [
            .foregroundColor: NSColor.clear, .font: theme.baseFont, .paragraphStyle: para,
            MarkdownBlockAttribute.blockKind: MarkdownBlockAttribute.Kind.thematicBreak.rawValue]))
    }

    // MARK: Tables

    /// Tables render to a drawn image (a true bordered grid with header shading and
    /// padded cells), wrapped in a text attachment — far cleaner than tab/box-glyph
    /// approximations. Cell content is rendered with the same inline styling.
    mutating func visitTable(_ table: Table) {
        var headerCells: [NSAttributedString] = []
        for cell in table.head.children { headerCells.append(renderCell(cell, bold: true)) }
        var rows: [[NSAttributedString]] = []
        for row in table.body.rows {
            var r: [NSAttributedString] = []
            for cell in row.children { r.append(renderCell(cell, bold: false)) }
            rows.append(r)
        }
        // `MarkdownRenderer` now serves only PRINTING (the on-screen preview is a
        // WKWebView). Tables print as a drawn bordered-grid image — paper can't
        // scroll or select, so the static grid is correct.
        let image = MarkdownTableRenderer.image(header: headerCells, rows: rows, theme: theme)
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(origin: .zero, size: image.size)
        let para = bodyParagraph(spacingAfter: 14, spacingBefore: 6)
        let attStr = NSMutableAttributedString(attachment: attachment)
        attStr.addAttribute(.paragraphStyle, value: para,
                            range: NSRange(location: 0, length: attStr.length))
        out.append(attStr)
        out.append(NSAttributedString(string: "\n\n"))
    }

    /// Render a single table cell's inline content into a standalone attributed
    /// string (reuses the inline visitor machinery via a nested builder).
    private func renderCell(_ cell: Markup, bold: Bool) -> NSAttributedString {
        var nested = AttributedStringBuilder(theme: theme)
        nested.bold = bold
        for child in cell.children { nested.visit(child) }
        return nested.out
    }
}
