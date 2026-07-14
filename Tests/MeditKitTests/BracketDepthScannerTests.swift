import XCTest
@testable import MeditKit

final class BracketDepthScannerTests: XCTestCase {

    private func depths(_ s: String) -> [Int] {
        BracketDepthScanner.scan(s).map(\.depth)
    }

    func testNestedSameFamilyDepths() {
        XCTAssertEqual(depths("(())"), [0, 1, 1, 0])
    }

    func testMixedFamiliesShareDepth() {
        XCTAssertEqual(depths("([{}])"), [0, 1, 2, 2, 1, 0])
    }

    func testAdjacentClosers() {
        XCTAssertEqual(depths("{{}}"), [0, 1, 1, 0])
    }

    func testStrayCloserIsUnmatched() {
        let hits = BracketDepthScanner.scan(")")
        XCTAssertEqual(hits.count, 1)
        XCTAssertTrue(hits[0].unmatched)
        XCTAssertFalse(hits[0].isOpen)
        XCTAssertEqual(hits[0].depth, 0)
    }

    func testFamilyMismatchCloserIsUnmatched() {
        let hits = BracketDepthScanner.scan("(]")
        XCTAssertEqual(hits.count, 2)
        XCTAssertTrue(hits[0].isOpen); XCTAssertFalse(hits[0].unmatched); XCTAssertEqual(hits[0].depth, 0)
        XCTAssertFalse(hits[1].isOpen); XCTAssertTrue(hits[1].unmatched)
    }

    func testUnclosedOpenerKeepsDepthNotUnmatched() {
        let hits = BracketDepthScanner.scan("((")
        XCTAssertEqual(hits.map(\.depth), [0, 1])
        XCTAssertFalse(hits.contains { $0.unmatched })
    }

    func testEmptyAndNoBrackets() {
        XCTAssertTrue(BracketDepthScanner.scan("").isEmpty)
        XCTAssertTrue(BracketDepthScanner.scan("no brackets here").isEmpty)
    }

    func testOffsetsAreCharacterOffsets() {
        let hits = BracketDepthScanner.scan("a(b)c")
        XCTAssertEqual(hits.map(\.offset), [1, 3])
    }

    func testMultibyteOffsets() {
        // Offsets are CHARACTER offsets, not UTF-16 units.
        let hits = BracketDepthScanner.scan("😀(x)")
        XCTAssertEqual(hits.map(\.offset), [1, 3])
        XCTAssertEqual(hits.map(\.kind), ["(", ")"])
        // utf16Offset diverges from offset past the surrogate pair: 😀 is 2 UTF-16
        // units, so '(' sits at 2 and ')' at 4. This is the value the colorizer
        // paints NSRanges with — if it drifted, rainbow colors would land on the
        // wrong characters in any document containing emoji/CJK.
        XCTAssertEqual(hits.map(\.utf16Offset), [2, 4])
    }

    func testUTF16OffsetsMatchCharacterOffsetsForASCII() {
        let hits = BracketDepthScanner.scan("a(b)c")
        XCTAssertEqual(hits.map(\.utf16Offset), hits.map(\.offset))
    }

    func testKindAndIsOpenRecorded() {
        let hits = BracketDepthScanner.scan("[]")
        XCTAssertEqual(hits[0].kind, "["); XCTAssertTrue(hits[0].isOpen)
        XCTAssertEqual(hits[1].kind, "]"); XCTAssertFalse(hits[1].isOpen)
    }

    func testLargeInputSanity() {
        let s = String(repeating: "(a)", count: 5000)
        let hits = BracketDepthScanner.scan(s)
        XCTAssertEqual(hits.count, 10000)
        XCTAssertTrue(hits.allSatisfy { $0.depth == 0 && !$0.unmatched })
    }
}
