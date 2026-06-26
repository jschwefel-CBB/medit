import XCTest
@testable import MeditKit

final class SessionStoreTests: XCTestCase {
    private var prefs: Preferences!

    override func setUp() {
        super.setUp()
        prefs = Preferences(defaults: UserDefaults(suiteName: "medit.session.\(UUID().uuidString)")!)
    }

    private func window(_ paths: [String]) -> WindowSession {
        WindowSession(tabPaths: paths, activeTabPath: paths.last,
                      sidebarFolderBookmarks: [], frame: "{{0, 0}, {800, 600}}")
    }

    func testRecordStoresWindowsInOrder() {
        let s = SessionStore(preferences: prefs)
        let windows = [window(["/a.txt", "/b.txt"]), window(["/c.md"])]
        s.record(windows)
        XCTAssertEqual(s.windows, windows)
    }

    func testRecordEmptyStoresNoWindows() {
        let s = SessionStore(preferences: prefs)
        s.record([window(["/a.txt"])])
        s.record([])   // closing everything records an empty session
        XCTAssertTrue(s.windows.isEmpty)
    }

    func testPersistsAcrossInstances() {
        let s1 = SessionStore(preferences: prefs)
        let windows = [window(["/a.txt", "/b.txt"])]
        s1.record(windows)
        let s2 = SessionStore(preferences: prefs)
        XCTAssertEqual(s2.windows, windows)
    }

    func testClear() {
        let s = SessionStore(preferences: prefs)
        s.record([window(["/a.txt"])])
        s.clear()
        XCTAssertTrue(s.windows.isEmpty)
    }

    func testMigratesLegacyFlatList() {
        // A pre-multi-window session (flat list, no grouped data) restores as one window.
        prefs.lastSessionFiles = ["/a.txt", "/b.txt"]
        let s = SessionStore(preferences: prefs)
        XCTAssertEqual(s.windows.map(\.tabPaths), [["/a.txt", "/b.txt"]])
    }
}
