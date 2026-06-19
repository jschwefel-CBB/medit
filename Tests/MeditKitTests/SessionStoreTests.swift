import XCTest
@testable import MeditKit

final class SessionStoreTests: XCTestCase {
    private var prefs: Preferences!

    override func setUp() {
        super.setUp()
        prefs = Preferences(defaults: UserDefaults(suiteName: "medit.session.\(UUID().uuidString)")!)
    }

    private func url(_ p: String) -> URL { URL(fileURLWithPath: p) }

    func testRecordStoresOpenFilesInOrder() {
        let s = SessionStore(preferences: prefs)
        s.record([url("/a.txt"), url("/b.txt")])
        XCTAssertEqual(s.files.map(\.path), ["/a.txt", "/b.txt"])
    }

    func testRecordDedupesByPath() {
        let s = SessionStore(preferences: prefs)
        s.record([url("/a.txt"), url("/a.txt"), url("/b.txt")])
        XCTAssertEqual(s.files.map(\.path), ["/a.txt", "/b.txt"])
    }

    func testRecordIgnoresEmpty() {
        let s = SessionStore(preferences: prefs)
        s.record([url("/a.txt")])
        s.record([])   // closing everything records an empty session
        XCTAssertTrue(s.files.isEmpty)
    }

    func testPersistsAcrossInstances() {
        let s1 = SessionStore(preferences: prefs)
        s1.record([url("/a.txt"), url("/b.txt")])
        let s2 = SessionStore(preferences: prefs)
        XCTAssertEqual(s2.files.map(\.path), ["/a.txt", "/b.txt"])
    }

    func testClear() {
        let s = SessionStore(preferences: prefs)
        s.record([url("/a.txt")])
        s.clear()
        XCTAssertTrue(s.files.isEmpty)
    }
}
