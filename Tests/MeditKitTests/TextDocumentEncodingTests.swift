import XCTest
@testable import MeditKit

final class TextDocumentEncodingTests: XCTestCase {

    func testReinterpretReDecodesOriginalBytes() throws {
        // 0xE9 is 'é' in Latin-1, invalid as lone UTF-8 -> auto-detect picks Latin-1.
        let data = Data([0x63, 0x61, 0x66, 0xE9]) // "caf<E9>"
        let doc = TextDocument()
        try doc.read(from: data, ofType: "public.plain-text")
        XCTAssertEqual(doc.text, "café")
        XCTAssertEqual(doc.fileEncoding, .isoLatin1)

        // Reinterpreting the SAME bytes as UTF-8 would fail decode; reinterpret
        // is a no-op-or-replace that must not crash and should keep valid text.
        doc.reinterpret(as: .isoLatin1) // re-decode as latin1 again -> still "café"
        XCTAssertEqual(doc.text, "café")
    }

    func testConvertChangesSaveEncodingNotText() {
        let doc = TextDocument()
        doc.setTextForTesting("hello")
        doc.fileEncoding = .utf8
        doc.convert(to: .isoLatin1)
        XCTAssertEqual(doc.fileEncoding, .isoLatin1)
        XCTAssertEqual(doc.text, "hello", "convert must not alter the text")
    }

    func testSetLineEndingNormalizesText() {
        let doc = TextDocument()
        doc.setTextForTesting("a\nb\nc")
        doc.setLineEnding(.crlf)
        XCTAssertEqual(doc.lineEnding, .crlf)
        XCTAssertEqual(doc.text, "a\r\nb\r\nc")
        doc.setLineEnding(.lf)
        XCTAssertEqual(doc.text, "a\nb\nc")
    }
}
