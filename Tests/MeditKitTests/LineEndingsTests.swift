import XCTest
@testable import MeditKit

final class LineEndingsTests: XCTestCase {

    func testDetectLF() { XCTAssertEqual(LineEndings.detect("a\nb\nc"), .lf) }
    func testDetectCRLF() { XCTAssertEqual(LineEndings.detect("a\r\nb\r\nc"), .crlf) }
    func testDetectMixedDominant() {
        // 2 CRLF vs 1 LF -> CRLF dominant
        XCTAssertEqual(LineEndings.detect("a\r\nb\r\nc\nd"), .crlf)
    }
    func testDetectNoBreaksDefaultsLF() { XCTAssertEqual(LineEndings.detect("abc"), .lf) }
    func testDetectEmptyDefaultsLF() { XCTAssertEqual(LineEndings.detect(""), .lf) }

    func testNormalizeToCRLF() {
        XCTAssertEqual(LineEndings.normalize("a\nb\nc", to: .crlf), "a\r\nb\r\nc")
    }
    func testNormalizeToLF() {
        XCTAssertEqual(LineEndings.normalize("a\r\nb\r\nc", to: .lf), "a\nb\nc")
    }
    func testNormalizeMixedToLF() {
        XCTAssertEqual(LineEndings.normalize("a\r\nb\nc", to: .lf), "a\nb\nc")
    }
    func testNormalizeIdempotent() {
        XCTAssertEqual(LineEndings.normalize("a\nb", to: .lf), "a\nb")
    }
    func testNormalizeNoBreaks() {
        XCTAssertEqual(LineEndings.normalize("abc", to: .crlf), "abc")
    }
}
