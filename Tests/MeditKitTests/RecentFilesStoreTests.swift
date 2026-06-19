import XCTest
@testable import MeditKit

final class RecentFilesStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var prefs: Preferences!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "medit.recent.\(UUID().uuidString)")!
        prefs = Preferences(defaults: defaults)
    }

    private func url(_ p: String) -> URL { URL(fileURLWithPath: p) }

    func testRecordAddsMostRecentFirst() {
        let s = RecentFilesStore(preferences: prefs)
        s.record(url("/a.txt"))
        s.record(url("/b.txt"))
        XCTAssertEqual(s.urls.map(\.path), ["/b.txt", "/a.txt"])
    }

    func testRecordMovesExistingToFront() {
        let s = RecentFilesStore(preferences: prefs)
        s.record(url("/a.txt"))
        s.record(url("/b.txt"))
        s.record(url("/a.txt"))   // re-open a
        XCTAssertEqual(s.urls.map(\.path), ["/a.txt", "/b.txt"])
    }

    func testRecordDedupesByStandardizedPath() {
        let s = RecentFilesStore(preferences: prefs)
        s.record(url("/dir/a.txt"))
        s.record(url("/dir/./a.txt"))   // same file, non-standard path
        XCTAssertEqual(s.urls.count, 1)
    }

    func testCapDropsOldest() {
        let s = RecentFilesStore(preferences: prefs, maxItems: 3)
        for i in 1...5 { s.record(url("/f\(i).txt")) }
        XCTAssertEqual(s.urls.map(\.path), ["/f5.txt", "/f4.txt", "/f3.txt"])
    }

    func testRemove() {
        let s = RecentFilesStore(preferences: prefs)
        s.record(url("/a.txt")); s.record(url("/b.txt"))
        s.remove(url("/a.txt"))
        XCTAssertEqual(s.urls.map(\.path), ["/b.txt"])
    }

    func testClear() {
        let s = RecentFilesStore(preferences: prefs)
        s.record(url("/a.txt")); s.record(url("/b.txt"))
        s.clear()
        XCTAssertTrue(s.urls.isEmpty)
    }

    func testPersistsAcrossInstances() {
        let s1 = RecentFilesStore(preferences: prefs)
        s1.record(url("/a.txt")); s1.record(url("/b.txt"))
        let s2 = RecentFilesStore(preferences: prefs)   // fresh store, same defaults
        XCTAssertEqual(s2.urls.map(\.path), ["/b.txt", "/a.txt"])
    }

    func testPostsNotificationOnMutation() {
        let s = RecentFilesStore(preferences: prefs)
        let exp = expectation(forNotification: RecentFilesStore.didChangeNotification, object: nil, handler: nil)
        s.record(url("/a.txt"))
        wait(for: [exp], timeout: 1)
    }
}
