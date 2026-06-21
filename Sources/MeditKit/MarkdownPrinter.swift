import AppKit

/// Builds an `NSPrintOperation` that prints rendered Markdown (the formatted
/// preview, not the raw source) on white paper with page margins. Used by
/// `TextDocument.printOperation` for Markdown documents.
enum MarkdownPrinter {

    /// A paper-friendly light theme (black on white) regardless of app appearance.
    static func printTheme() -> MarkdownRenderer.Theme {
        let body: CGFloat = 11
        return MarkdownRenderer.Theme(
            baseFont: NSFont.systemFont(ofSize: body),
            monoFont: NSFont.monospacedSystemFont(ofSize: body - 1, weight: .regular),
            foreground: .black,
            secondary: NSColor(white: 0.35, alpha: 1),
            codeBackground: NSColor(white: 0.95, alpha: 1),
            headingColor: NSColor(srgbRed: 0.10, green: 0.30, blue: 0.55, alpha: 1),
            quoteBarColor: NSColor(srgbRed: 0.70, green: 0.40, blue: 0.30, alpha: 1),
            tableBorderColor: NSColor(white: 0.6, alpha: 1),
            linkColor: NSColor(srgbRed: 0.0, green: 0.3, blue: 0.8, alpha: 1),
            isDark: false)
    }

    static func operation(forMarkdown markdown: String,
                          info: NSPrintInfo = .shared) -> NSPrintOperation {
        let printInfo = info.copy() as! NSPrintInfo
        printInfo.horizontalPagination = .automatic
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        let margin: CGFloat = 48
        printInfo.leftMargin = margin; printInfo.rightMargin = margin
        printInfo.topMargin = margin; printInfo.bottomMargin = margin

        let pageWidth = printInfo.paperSize.width - margin * 2

        // A text view sized to the printable width, with our custom layout manager
        // so code panels / tables / rules print too.
        let storage = NSTextStorage()
        let layout = MarkdownPreviewLayoutManager()
        let theme = printTheme()
        layout.palette = .init(codePanel: theme.codeBackground, quoteBar: theme.quoteBarColor,
                               rule: theme.tableBorderColor, tableBorder: theme.tableBorderColor,
                               tableHeaderFill: theme.codeBackground)
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: pageWidth, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: 100),
                                  textContainer: container)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.backgroundColor = .white
        textView.drawsBackground = true
        textView.textStorage?.setAttributedString(
            MarkdownRenderer(theme: theme, tableMode: .static).render(markdown))
        textView.sizeToFit()

        let op = NSPrintOperation(view: textView, printInfo: printInfo)
        op.jobTitle = "Markdown"
        return op
    }

    /// Plain monospace printing for non-Markdown documents (medit doesn't use
    /// AppKit's default NSDocument printing, which is unimplemented here). When
    /// `lineNumbers` is true, prepends a filename header and numbers each line.
    static func plainTextOperation(_ text: String, info: NSPrintInfo = .shared,
                                   jobTitle: String, lineNumbers: Bool = false) -> NSPrintOperation {
        let printInfo = info.copy() as! NSPrintInfo
        printInfo.horizontalPagination = .automatic
        printInfo.verticalPagination = .automatic
        let margin: CGFloat = 48
        printInfo.leftMargin = margin; printInfo.rightMargin = margin
        printInfo.topMargin = margin; printInfo.bottomMargin = margin
        let pageWidth = printInfo.paperSize.width - margin * 2

        let mono = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let body = NSMutableAttributedString()

        if lineNumbers {
            // Filename header.
            let header = NSAttributedString(string: "\(jobTitle)\n\n", attributes: [
                .font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.black])
            body.append(header)
            // Right-aligned, gutter-style line numbers in a leading column.
            let lines = text.components(separatedBy: "\n")
            let width = String(max(1, lines.count)).count
            let para = NSMutableParagraphStyle()
            para.headIndent = CGFloat(width + 2) * 7   // hang wrapped lines past the gutter
            for (i, line) in lines.enumerated() {
                let num = String(format: "%\(width)d  ", i + 1)
                body.append(NSAttributedString(string: num, attributes: [
                    .font: mono, .foregroundColor: NSColor(white: 0.5, alpha: 1), .paragraphStyle: para]))
                body.append(NSAttributedString(string: line + "\n", attributes: [
                    .font: mono, .foregroundColor: NSColor.black, .paragraphStyle: para]))
            }
        } else {
            body.append(NSAttributedString(string: text, attributes: [
                .font: mono, .foregroundColor: NSColor.black]))
        }

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: 100))
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.backgroundColor = .white
        textView.drawsBackground = true
        textView.textStorage?.setAttributedString(body)
        textView.sizeToFit()

        let op = NSPrintOperation(view: textView, printInfo: printInfo)
        op.jobTitle = jobTitle
        return op
    }
}
