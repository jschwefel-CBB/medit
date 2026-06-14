import XCTest
@testable import MeditKit

final class TextEncodingDetectorTests: XCTestCase {

    // MARK: UTF-8

    func testPlainASCIIDecodesAsUTF8() throws {
        let data = Data("hello world\n".utf8)
        let result = try XCTUnwrap(TextEncodingDetector.decode(data))
        XCTAssertEqual(result.string, "hello world\n")
        XCTAssertEqual(result.encoding, .utf8)
        XCTAssertFalse(result.hadBOM)
    }

    func testMultibyteUTF8Decodes() throws {
        let original = "café — naïve — 🚀 — 日本語"
        let data = Data(original.utf8)
        let result = try XCTUnwrap(TextEncodingDetector.decode(data))
        XCTAssertEqual(result.string, original)
        XCTAssertEqual(result.encoding, .utf8)
    }

    func testEmptyDataDecodesAsEmptyUTF8() throws {
        let result = try XCTUnwrap(TextEncodingDetector.decode(Data()))
        XCTAssertEqual(result.string, "")
        XCTAssertEqual(result.encoding, .utf8)
    }

    // MARK: BOM handling

    func testUTF8BOMIsDetectedAndStripped() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("ok".utf8))
        let result = try XCTUnwrap(TextEncodingDetector.decode(data))
        XCTAssertEqual(result.string, "ok", "BOM must not appear in the decoded string")
        XCTAssertEqual(result.encoding, .utf8)
        XCTAssertTrue(result.hadBOM)
    }

    func testUTF16LEBOMIsDetected() throws {
        let original = "hi"
        // NSString encodes a BOM when asked for utf16 (platform endianness).
        let data = try XCTUnwrap((original as NSString).data(using: String.Encoding.utf16.rawValue))
        let result = try XCTUnwrap(TextEncodingDetector.decode(data))
        XCTAssertEqual(result.string, original)
        XCTAssertTrue(result.encoding == .utf16 || result.encoding == .utf16LittleEndian || result.encoding == .utf16BigEndian)
        XCTAssertTrue(result.hadBOM)
    }

    // MARK: Latin-1 fallback

    func testLatin1FallbackForNonUTF8Bytes() throws {
        // 0xE9 is 'é' in ISO Latin-1 but an invalid lone byte in UTF-8.
        let data = Data([0x63, 0x61, 0x66, 0xE9]) // "caf<0xE9>"
        let result = try XCTUnwrap(TextEncodingDetector.decode(data))
        XCTAssertEqual(result.string, "café")
        XCTAssertEqual(result.encoding, .isoLatin1)
        XCTAssertFalse(result.hadBOM)
    }

    // MARK: Round-trip via encode

    func testEncodeRoundTripUTF8() throws {
        let text = "round trip ☕️\n"
        let data = TextEncodingDetector.encode(text, as: .utf8, includeBOM: false)
        let back = try XCTUnwrap(TextEncodingDetector.decode(data))
        XCTAssertEqual(back.string, text)
        XCTAssertEqual(back.encoding, .utf8)
    }

    func testEncodeUTF8WithBOMRoundTrips() throws {
        let text = "bom me"
        let data = TextEncodingDetector.encode(text, as: .utf8, includeBOM: true)
        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF])
        let back = try XCTUnwrap(TextEncodingDetector.decode(data))
        XCTAssertEqual(back.string, text)
        XCTAssertTrue(back.hadBOM)
    }
}
