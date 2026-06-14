import AppKit

/// A vertical ruler that draws 1-based line numbers next to an `NSTextView`.
///
/// It enumerates line fragments via the layout manager and labels each
/// *logical* line (a soft-wrapped line shows a single number against its first
/// fragment). Width auto-sizes to the digit count. Colors follow the current
/// appearance via dynamic system colors.
public final class LineNumberRulerView: NSRulerView {

    private weak var textView: NSTextView?

    /// Font used for the numerals; kept slightly smaller than the editor font.
    public var font: NSFont {
        didSet { needsDisplay = true }
    }

    private var textColor: NSColor { .secondaryLabelColor }
    private var backgroundColor: NSColor { .textBackgroundColor }
    private var dividerColor: NSColor { .separatorColor }

    public init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        self.font = LineNumberRulerView.rulerFont(matching: textView.font)
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        self.clientView = textView
        ruleThickness = 40

        // Redraw when the text changes or the view scrolls/resizes.
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(invalidate),
                       name: NSText.didChangeNotification, object: textView)
        if let container = textView.textContainer,
           let lm = textView.layoutManager {
            _ = container; _ = lm
        }
        if let clipView = scrollView.contentView as NSClipView? {
            clipView.postsBoundsChangedNotifications = true
            nc.addObserver(self, selector: #selector(invalidate),
                           name: NSView.boundsDidChangeNotification, object: clipView)
        }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// Update the numeral font when the editor font changes.
    public func updateFont(matching editorFont: NSFont?) {
        font = LineNumberRulerView.rulerFont(matching: editorFont)
    }

    private static func rulerFont(matching editorFont: NSFont?) -> NSFont {
        let size = max(9, (editorFont?.pointSize ?? 13) - 2)
        return NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }

    @objc private func invalidate() { needsDisplay = true }

    // MARK: Drawing

    public override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        // Background + trailing divider.
        backgroundColor.setFill()
        rect.fill()
        dividerColor.setStroke()
        let divider = NSBezierPath()
        divider.move(to: NSPoint(x: bounds.maxX - 0.5, y: rect.minY))
        divider.line(to: NSPoint(x: bounds.maxX - 0.5, y: rect.maxY))
        divider.lineWidth = 1
        divider.stroke()

        let content = scrollView?.contentView
        let visibleRect = content?.bounds ?? textView.visibleRect
        let yInset = textView.textContainerInset.height
        let relativePoint = self.convert(NSPoint.zero, from: textView)

        let nsText = textView.string as NSString
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]

        // Determine the line number at the start of the visible character range
        // by counting newlines up to that point.
        var lineNumber = numberOfLines(in: nsText, upTo: charRange.location)

        let numberOfGlyphs = layoutManager.numberOfGlyphs
        var index = charRange.location
        let end = NSMaxRange(charRange)

        // Walk each logical line in the visible range. Only enter the loop when
        // there are glyphs to lay out; an empty document is handled solely by
        // the extra-line-fragment branch below (avoids querying glyph 0 when no
        // glyphs exist, which logs "_NSLayoutTreeLineFragmentRectForGlyphAtIndex
        // invalid glyph index").
        while numberOfGlyphs > 0 && index < end {
            let lineRange = nsText.lineRange(for: NSRange(location: index, length: 0))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: lineRange.location)
            guard glyphIndex < numberOfGlyphs else { break }

            var effectiveGlyphRange = NSRange()
            let fragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex,
                                                              effectiveRange: &effectiveGlyphRange)

            let y = relativePoint.y + yInset + fragmentRect.minY
            let label = "\(lineNumber)" as NSString
            let labelSize = label.size(withAttributes: attributes)
            let drawRect = NSRect(x: bounds.width - labelSize.width - 5,
                                  y: y + (fragmentRect.height - labelSize.height) / 2,
                                  width: labelSize.width,
                                  height: labelSize.height)
            label.draw(in: drawRect, withAttributes: attributes)

            lineNumber += 1
            let nextIndex = NSMaxRange(lineRange)
            if nextIndex <= index { break }   // no progress guard
            index = nextIndex
        }

        // Handle the implicit final empty line (file ends with a newline).
        if nsText.length == 0 || (nsText.length > 0 && nsText.character(at: nsText.length - 1) == unichar(10)) {
            // Draw the trailing line number if the extra line fragment is visible.
            let extraRect = layoutManager.extraLineFragmentRect
            if extraRect.height > 0 {
                let y = relativePoint.y + yInset + extraRect.minY
                let label = "\(lineNumber)" as NSString
                let labelSize = label.size(withAttributes: attributes)
                let drawRect = NSRect(x: bounds.width - labelSize.width - 5,
                                      y: y + (extraRect.height - labelSize.height) / 2,
                                      width: labelSize.width,
                                      height: labelSize.height)
                label.draw(in: drawRect, withAttributes: attributes)
            }
        }

        adjustWidth(forLineCount: lineNumber)
    }

    /// Count 1-based line number at a character offset (number of newlines
    /// before `location`, plus one).
    private func numberOfLines(in text: NSString, upTo location: Int) -> Int {
        guard location > 0 else { return 1 }
        var count = 1
        let scanRange = NSRange(location: 0, length: min(location, text.length))
        text.enumerateSubstrings(in: scanRange, options: [.byLines, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }

    /// Grow the ruler so the widest visible number fits.
    private func adjustWidth(forLineCount maxLine: Int) {
        let digits = max(2, "\(maxLine)".count)
        let sample = String(repeating: "8", count: digits) as NSString
        let width = sample.size(withAttributes: [.font: font]).width + 12
        if abs(width - ruleThickness) > 0.5 {
            ruleThickness = ceil(width)
        }
    }
}
