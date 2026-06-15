import XCTest
@testable import MeditKit

final class EncodingCatalogTests: XCTestCase {

    func testListIsNonEmpty() {
        XCTAssertGreaterThan(EncodingCatalog.selectable.count, 2)
    }

    func testContainsUTF8AndLatin1() {
        let encodings = EncodingCatalog.selectable.map { $0.encoding }
        XCTAssertTrue(encodings.contains(.utf8))
        XCTAssertTrue(encodings.contains(.isoLatin1))
    }

    func testDisplayNamesMatchDetector() {
        for entry in EncodingCatalog.selectable {
            XCTAssertEqual(entry.displayName, TextEncodingDetector.displayName(for: entry.encoding))
        }
    }
}
