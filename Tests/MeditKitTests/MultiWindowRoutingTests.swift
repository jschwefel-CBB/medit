import XCTest
import AppKit
@testable import MeditKit

/// Deterministic, headless coverage of the multi-window routing contract.
///
/// The actual "⇧⌘N spawns a separate window vs ⌘N adds a tab" behavior involves
/// NSDocumentController spawning/displaying document windows, which hangs or
/// behaves unreliably under headless XCTest (no full app run loop / window server).
/// That live behavior is covered by the AutoPilot plan `uitests/multi-window.json`.
/// Here we verify the deterministic pieces the routing depends on: the window's
/// tabbingMode (the mechanism that lets New Window stay separate) and the per-window
/// snapshot accessors used by session save/restore.
final class MultiWindowRoutingTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }

    private func freshController(text: String = "") -> EditorWindowController {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "medit.mw.\(UUID().uuidString)")!)
        let doc = TextDocument()
        doc.setTextForTesting(text)
        let wc = EditorWindowController(document: doc, preferences: prefs)
        _ = wc.window
        wc.loadViewIfNeededForTesting()
        return wc
    }

    func testWindowUsesAutomaticTabbingNotForcedPreferred() throws {
        // .automatic (not .preferred) is what stops AppKit from auto-merging a new
        // window into the existing tab group — the prerequisite for New Window.
        let wc = freshController()
        XCTAssertEqual(wc.window?.tabbingMode, .automatic,
                       "windows must use .automatic tabbing so New Window can stay separate")
    }

    func testActiveTabURLReflectsTheDocumentURL() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("medit-active-\(UUID().uuidString).txt")
        try "x".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let prefs = Preferences(defaults: UserDefaults(suiteName: "medit.mw.\(UUID().uuidString)")!)
        let doc = TextDocument()
        doc.fileURL = tmp
        let wc = EditorWindowController(document: doc, preferences: prefs)
        _ = wc.window
        wc.loadViewIfNeededForTesting()

        // A lone window (no tab group) reports its own document as the active tab.
        XCTAssertEqual(wc.activeTabURL?.lastPathComponent, tmp.lastPathComponent)
        XCTAssertEqual(wc.tabDocumentURLs.map(\.lastPathComponent), [tmp.lastPathComponent])
    }

    func testSidebarRootBookmarksRoundTripThroughWindowController() throws {
        let wc = freshController()

        // Bookmark a real temp folder, restore it into this window, read it back.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("medit-sb-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bm = try dir.bookmarkData(options: [.withSecurityScope])

        wc.restoreSidebarRoots([bm])
        XCTAssertEqual(wc.sidebarRootBookmarks.count, 1,
                       "the window's sidebar should report one restored root")
    }
}
