import XCTest
@testable import MeditKit

final class LanguageCatalogTests: XCTestCase {

    func testCommonListIsNonEmpty() {
        XCTAssertGreaterThan(LanguageCatalog.common.count, 10)
    }

    func testEveryCommonEntryHasIdAndName() {
        for entry in LanguageCatalog.common {
            XCTAssertFalse(entry.id.isEmpty)
            XCTAssertFalse(entry.displayName.isEmpty)
        }
    }

    func testFullListIsSupersetOfCommon() {
        let allIds = Set(LanguageCatalog.all.map { $0.id })
        for entry in LanguageCatalog.common {
            XCTAssertTrue(allIds.contains(entry.id), "common id \(entry.id) missing from all")
        }
    }

    func testDisplayNameKnownIds() {
        XCTAssertEqual(LanguageCatalog.displayName(for: "swift"), "Swift")
        XCTAssertEqual(LanguageCatalog.displayName(for: "cpp"), "C++")
        XCTAssertEqual(LanguageCatalog.displayName(for: "objectivec"), "Objective-C")
        XCTAssertEqual(LanguageCatalog.displayName(for: "xml"), "HTML/XML")
        XCTAssertEqual(LanguageCatalog.displayName(for: "javascript"), "JavaScript")
    }

    func testDisplayNameUnknownIdTitlecases() {
        XCTAssertEqual(LanguageCatalog.displayName(for: "haskell"), "Haskell")
    }

    func testCommonContainsSwiftAndPython() {
        let ids = LanguageCatalog.common.map { $0.id }
        XCTAssertTrue(ids.contains("swift"))
        XCTAssertTrue(ids.contains("python"))
    }
}
