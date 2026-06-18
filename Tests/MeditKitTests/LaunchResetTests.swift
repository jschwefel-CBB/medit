import XCTest
@testable import MeditKit

final class LaunchResetTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "medit.tests.reset.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testFlagDetection() {
        XCTAssertTrue(LaunchReset.isRequested(in: ["medit", "--reset-state"]))
        XCTAssertTrue(LaunchReset.isRequested(in: ["--reset-state"]))
        XCTAssertFalse(LaunchReset.isRequested(in: ["medit"]))
        XCTAssertFalse(LaunchReset.isRequested(in: []))
    }

    func testClearDefaultsRemovesSidebarBookmarks() {
        // Seed a sidebar root bookmark and a preference, as a real session would.
        defaults.set([Data([1, 2, 3])], forKey: "sidebarRootBookmarks")
        defaults.set(7, forKey: "tabWidth")
        XCTAssertNotNil(defaults.array(forKey: "sidebarRootBookmarks"))

        LaunchReset.clearDefaults(defaults, bundleID: suiteName)

        // After reset the sidebar roots must be gone. A registered default may
        // legitimately surface an empty array rather than nil, so accept either
        // — what matters is that no roots survive.
        let roots = defaults.array(forKey: "sidebarRootBookmarks") ?? []
        XCTAssertTrue(roots.isEmpty, "sidebar roots must not survive a reset")
        // tabWidth was explicitly set to 7; after the domain wipe it must no
        // longer report that overridden value (it falls back to a registered
        // default of 0/2, never the 7 we set).
        XCTAssertNotEqual(defaults.integer(forKey: "tabWidth"), 7,
                          "domain wipe should clear the overridden pref")
    }

    func testClearDefaultsDisablesWindowRestoration() {
        LaunchReset.clearDefaults(defaults, bundleID: suiteName)
        XCTAssertFalse(defaults.bool(forKey: "NSQuitAlwaysKeepsWindows"),
                       "window restoration must be disabled under --reset-state")
    }

    func testClearDefaultsClearsWindowAutosaveFrames() {
        defaults.set("100 100 800 600 0 0 1440 900", forKey: "NSWindow Frame medit.editor.window")
        LaunchReset.clearDefaults(defaults, bundleID: suiteName)
        XCTAssertNil(defaults.string(forKey: "NSWindow Frame medit.editor.window"))
    }

    func testSavedStateDirectoryPath() {
        let url = LaunchReset.savedStateDirectory(bundleID: "com.jschwefel.medit")
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.path.hasSuffix("Saved Application State/com.jschwefel.medit.savedState"),
                      "got: \(url!.path)")
    }

    func testSavedStateDirectoryNilWithoutBundleID() {
        XCTAssertNil(LaunchReset.savedStateDirectory(bundleID: nil))
    }

    func testPerformIsNoOpWithoutFlag() {
        defaults.set([Data([9])], forKey: "sidebarRootBookmarks")
        LaunchReset.perform(arguments: ["medit"], bundleID: suiteName,
                            appName: "medit", defaults: defaults)
        XCTAssertNotNil(defaults.array(forKey: "sidebarRootBookmarks"),
                        "without the flag, nothing should be cleared")
    }

    func testPerformClearsWhenFlagPresent() {
        defaults.set([Data([9])], forKey: "sidebarRootBookmarks")
        LaunchReset.perform(arguments: ["medit", "--reset-state"],
                            bundleID: suiteName, appName: "medit", defaults: defaults)
        let roots = defaults.array(forKey: "sidebarRootBookmarks") ?? []
        XCTAssertTrue(roots.isEmpty)
    }

    func testAutosaveArtifactSelectionMatchesOnlyOwnFiles() throws {
        // Build a temp directory that mimics ~/Library/Autosave Information with a
        // mix of this app's files and an unrelated app's files.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("medit-autosave-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let mine = [
            "com.jschwefel.medit.plist",
            "Unsaved medit Document.txt",
            "Unsaved medit Document 2.txt",
        ]
        let theirs = [
            "com.apple.TextEdit.plist",
            "Unsaved TextEdit Document.txt",
            "com.other.app.plist",
        ]
        for name in mine + theirs {
            try Data("x".utf8).write(to: tmp.appendingPathComponent(name))
        }

        // Exercise the same name-matching logic against our controlled directory.
        let unsavedPrefix = "Unsaved medit Document"
        let bundleID = "com.jschwefel.medit"
        let entries = try FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)
        let matched = entries.filter { url in
            let n = url.lastPathComponent
            return n.contains(bundleID) || n.hasPrefix(unsavedPrefix)
        }.map { $0.lastPathComponent }.sorted()

        XCTAssertEqual(matched, mine.sorted(),
                       "only medit's own autosave files should match; got \(matched)")
    }

    func testAutosaveDirectoryResolves() {
        XCTAssertNotNil(LaunchReset.autosaveDirectory)
        XCTAssertTrue(LaunchReset.autosaveDirectory!.path.hasSuffix("Autosave Information"))
    }

    func testRequestedFolderToOpenParsing() {
        XCTAssertEqual(
            LaunchReset.requestedFolderToOpen(in: ["medit", "--open-folder", "/tmp/x"]),
            "/tmp/x")
        XCTAssertEqual(
            LaunchReset.requestedFolderToOpen(in: ["--reset-state", "--open-folder", "/a/b"]),
            "/a/b")
        XCTAssertNil(LaunchReset.requestedFolderToOpen(in: ["medit"]))
        XCTAssertNil(LaunchReset.requestedFolderToOpen(in: ["medit", "--open-folder"]),
                     "flag with no following path is nil")
        XCTAssertNil(LaunchReset.requestedFolderToOpen(in: ["medit", "--open-folder", ""]),
                     "empty path is nil")
    }
}
