import XCTest
@testable import MeditKit

final class WindowSessionTests: XCTestCase {
    func testRoundTripPreservesStructure() {
        let windows = [
            WindowSession(tabPaths: ["/a.txt", "/b.txt"], activeTabPath: "/b.txt",
                          sidebarFolderBookmarks: [Data([1, 2, 3])], frame: "{{0, 0}, {800, 600}}"),
            WindowSession(tabPaths: ["/c.md"], activeTabPath: "/c.md",
                          sidebarFolderBookmarks: [], frame: "{{100, 100}, {500, 400}}"),
        ]
        let decoded = SessionCodec.decode(SessionCodec.encode(windows))
        XCTAssertEqual(decoded, windows)
    }

    func testMigrateFlatProducesOneWindowOfTabs() {
        let flat = ["/a.txt", "/b.txt", "/c.md"]
        let windows = SessionCodec.migrateFlat(flat)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].tabPaths, flat)
        XCTAssertNil(windows[0].activeTabPath)
        XCTAssertTrue(windows[0].sidebarFolderBookmarks.isEmpty)
    }

    func testDecodeOfGarbageReturnsEmpty() {
        XCTAssertEqual(SessionCodec.decode(Data([0xFF, 0x00])), [])
    }

    func testSessionStoreRoundTripAndFlatMigration() {
        let defaults = UserDefaults(suiteName: "medit.session.\(UUID().uuidString)")!
        let prefs = Preferences(defaults: defaults)
        let store = SessionStore(preferences: prefs)

        // Flat-only legacy state migrates to one window.
        prefs.lastSessionFiles = ["/x.txt", "/y.txt"]
        XCTAssertEqual(store.windows.map(\.tabPaths), [["/x.txt", "/y.txt"]])

        // Recording grouped windows supersedes the flat list.
        let grouped = [WindowSession(tabPaths: ["/x.txt"], activeTabPath: "/x.txt",
                                     sidebarFolderBookmarks: [], frame: "{{0, 0}, {800, 600}}")]
        store.record(grouped)
        XCTAssertEqual(store.windows, grouped)
    }
}
