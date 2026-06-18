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

    mutating func visitParagraph(_ paragraph: Paragraph) {
        defaultVisit(paragraph)
        out.append(NSAttributedString(string: "\n\n"))
    }
}
