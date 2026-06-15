import XCTest
@testable import MeditKit

/// Tests the guard that prevents the reload banner from firing on a file's own
/// open/save (the false-positive bug) — it must only report a genuine on-disk
/// change (newer mtime AND different bytes).
final class ExternalChangeGuardTests: XCTestCase {

    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("medit-ecg-\(UUID().uuidString).txt")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    /// Build a document "loaded" from `bytes` at `tempURL`, with the recorded
    /// modification date captured from the file on disk.
    private func makeLoadedDoc(_ bytes: Data) throws -> TextDocument {
        try bytes.write(to: tempURL)
        let doc = TextDocument()
        try doc.read(from: bytes, ofType: "public.plain-text")
        // Associate the URL so the guard can stat the file; NSDocument exposes
        // fileURL as settable.
        doc.fileURL = tempURL
        doc.setOriginalDataForTesting(bytes)
        doc.captureModificationDateForTesting()
        return doc
    }

    func testNoChangeReportsNotGenuine() throws {
        let doc = try makeLoadedDoc(Data("hello".utf8))
        // No modification at all -> not a genuine change (the open false-positive).
        XCTAssertFalse(doc.isGenuineExternalChangeForTesting(url: tempURL))
    }

    func testSameContentReportsNotGenuine() throws {
        let doc = try makeLoadedDoc(Data("hello".utf8))
        // Re-write identical bytes (e.g. a touch / our own atomic save).
        try Data("hello".utf8).write(to: tempURL)
        XCTAssertFalse(doc.isGenuineExternalChangeForTesting(url: tempURL),
                       "same content must not count as a change (the open/save false positive)")
    }

    func testDifferentContentReportsGenuine() throws {
        let doc = try makeLoadedDoc(Data("hello".utf8))
        // Write genuinely different bytes — content is the authoritative signal.
        try Data("hello world, edited externally".utf8).write(to: tempURL)
        XCTAssertTrue(doc.isGenuineExternalChangeForTesting(url: tempURL),
                      "different bytes on disk is a genuine external change")
    }

    func testGenuineChangeIsNotReReportedTwice() throws {
        let doc = try makeLoadedDoc(Data("hello".utf8))
        try Data("changed".utf8).write(to: tempURL)
        XCTAssertTrue(doc.isGenuineExternalChangeForTesting(url: tempURL))
        // The change was adopted as the new baseline; a second check with no
        // further edit must report false.
        XCTAssertFalse(doc.isGenuineExternalChangeForTesting(url: tempURL),
                       "the same change must not be reported again")
    }
}
