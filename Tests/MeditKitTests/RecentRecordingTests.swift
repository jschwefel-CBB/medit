import XCTest
@testable import MeditKit

final class RecentRecordingTests: XCTestCase {
    func testSettingFileURLRecordsToSharedStore() {
        // Use a fresh defaults-backed store so we don't pollute the real list.
        let defaults = UserDefaults(suiteName: "medit.recrec.\(UUID().uuidString)")!
        let prefs = Preferences(defaults: defaults)
        // Point the shared store at this prefs is not possible (it's .shared);
        // instead verify the document calls record by checking the shared list grows.
        let before = RecentFilesStore.shared.urls.count
        let doc = TextDocument()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID().uuidString).txt")
        try? Data("x".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        doc.fileURL = tmp
        XCTAssertTrue(RecentFilesStore.shared.urls.contains(where: { $0.path == tmp.path }),
                      "setting fileURL should record it in the shared recent list")
        _ = before; _ = prefs
        // cleanup: remove our temp entry from the shared list
        RecentFilesStore.shared.remove(tmp)
    }
}
