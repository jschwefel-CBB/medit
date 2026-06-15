import AppKit

/// NSLayoutManager that, when `showInvisibles` is on, draws faint markers for
/// spaces (·) and tabs (⟶) over the text. Toggling the flag redraws via the
/// text view. Drawing markers does not modify the document text.
public final class InvisiblesLayoutManager: NSLayoutManager {

    public var showInvisibles: Bool = false

    private let markerAttributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor.tertiaryLabelColor,
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    ]

    public override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        if showInvisibles, let textStorage = textStorage {
            let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
            let string = textStorage.string as NSString
            string.enumerateSubstrings(in: charRange, options: [.byComposedCharacterSequences]) { sub, subRange, _, _ in
                guard let sub = sub else { return }
                let marker: String
                if sub == " " { marker = "·" }
                else if sub == "\t" { marker = "⟶" }
                else { return }
                let glyphRange = self.glyphRange(forCharacterRange: subRange, actualCharacterRange: nil)
                guard glyphRange.length > 0 else { return }
                var rect = self.boundingRect(forGlyphRange: NSRange(location: glyphRange.location, length: 1),
                                             in: self.textContainers.first ?? NSTextContainer())
                rect.origin.x += origin.x
                rect.origin.y += origin.y
                (marker as NSString).draw(at: rect.origin, withAttributes: self.markerAttributes)
            }
        }
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
    }
}
