import XCTest
@testable import MeditKit

final class PreferencesTests: XCTestCase {

    private var defaults: UserDefaults!
    private var prefs: Preferences!

    override func setUp() {
        super.setUp()
        // Isolated, ephemeral defaults so tests never touch the real domain.
        let suite = "medit.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        prefs = Preferences(defaults: defaults)
    }

    override func tearDown() {
        prefs = nil
        defaults = nil
        super.tearDown()
    }

    func testDefaultsAreSane() {
        XCTAssertTrue(prefs.showLineNumbers)
        XCTAssertFalse(prefs.wrapLines)          // gedit default: no wrap
        XCTAssertEqual(prefs.appearance, .system)
        XCTAssertEqual(prefs.fontSize, 13, accuracy: 0.001)
        XCTAssertFalse(prefs.fontName.isEmpty)
        XCTAssertEqual(prefs.tabWidth, 4)
        XCTAssertTrue(prefs.insertSpacesForTab)
    }

    func testPCNavigationDefaultsOnAndPersists() {
        XCTAssertTrue(prefs.pcStyleNavigationKeys, "PC-style nav keys should default ON")
        prefs.pcStyleNavigationKeys = false
        let reloaded = Preferences(defaults: defaults)
        XCTAssertFalse(reloaded.pcStyleNavigationKeys)
    }

    func testShowStatusBarDefaultsOnAndPersists() {
        XCTAssertTrue(prefs.showStatusBar)
        prefs.showStatusBar = false
        XCTAssertFalse(Preferences(defaults: defaults).showStatusBar)
    }

    func testEditingAssistDefaultsOnAndPersist() {
        XCTAssertTrue(prefs.autoIndent)
        XCTAssertTrue(prefs.autoCloseBrackets)
        prefs.autoIndent = false
        prefs.autoCloseBrackets = false
        let r = Preferences(defaults: defaults)
        XCTAssertFalse(r.autoIndent)
        XCTAssertFalse(r.autoCloseBrackets)
    }

    func testStripOnSaveDefaultsOnAndPersists() {
        XCTAssertTrue(prefs.stripTrailingWhitespaceOnSave)
        prefs.stripTrailingWhitespaceOnSave = false
        XCTAssertFalse(Preferences(defaults: defaults).stripTrailingWhitespaceOnSave)
    }

    func testShowInvisiblesDefaultsOffAndPersists() {
        XCTAssertFalse(prefs.showInvisibles)
        prefs.showInvisibles = true
        XCTAssertTrue(Preferences(defaults: defaults).showInvisibles)
    }

    func testValuesPersistAndReload() {
        prefs.showLineNumbers = false
        prefs.wrapLines = true
        prefs.appearance = .dark
        prefs.fontSize = 16
        prefs.fontName = "Menlo"
        prefs.tabWidth = 2
        prefs.insertSpacesForTab = false

        // A fresh Preferences over the same defaults must see the saved values.
        let reloaded = Preferences(defaults: defaults)
        XCTAssertFalse(reloaded.showLineNumbers)
        XCTAssertTrue(reloaded.wrapLines)
        XCTAssertEqual(reloaded.appearance, .dark)
        XCTAssertEqual(reloaded.fontSize, 16, accuracy: 0.001)
        XCTAssertEqual(reloaded.fontName, "Menlo")
        XCTAssertEqual(reloaded.tabWidth, 2)
        XCTAssertFalse(reloaded.insertSpacesForTab)
    }

    func testAppearanceRawValueRoundTrips() {
        for appearance in AppAppearance.allCases {
            prefs.appearance = appearance
            let reloaded = Preferences(defaults: defaults)
            XCTAssertEqual(reloaded.appearance, appearance)
        }
    }

    func testFontSizeIsClampedToReasonableRange() {
        prefs.fontSize = 2          // absurdly small
        XCTAssertGreaterThanOrEqual(prefs.fontSize, Preferences.minFontSize)
        prefs.fontSize = 999        // absurdly large
        XCTAssertLessThanOrEqual(prefs.fontSize, Preferences.maxFontSize)
    }

    func testThemeNameMapsToAppearance() {
        prefs.appearance = .light
        XCTAssertEqual(prefs.highlightThemeName(forDarkMode: false), prefs.lightThemeName)
        prefs.appearance = .dark
        XCTAssertEqual(prefs.highlightThemeName(forDarkMode: true), prefs.darkThemeName)
    }

    func testExternalChangePolicyDefaultsNotifyAndPersists() {
        XCTAssertEqual(prefs.externalChangePolicy, .notify)
        prefs.externalChangePolicy = .autoIfClean
        XCTAssertEqual(Preferences(defaults: defaults).externalChangePolicy, .autoIfClean)
    }

    func testSidebarPrefsDefaults() {
        XCTAssertFalse(prefs.showSidebar)
        XCTAssertFalse(prefs.showHiddenFiles)
        XCTAssertTrue(prefs.syncSidebarWithActiveTab)
        XCTAssertTrue(prefs.sidebarSortFoldersFirst)
        XCTAssertTrue(prefs.sidebarSortAscending)
        XCTAssertFalse(prefs.sidebarOpenOnSingleClick)
        XCTAssertFalse(prefs.sidebarOnRight)
        XCTAssertTrue(prefs.confirmBeforeDelete)
    }

    func testShowSidebarPersists() {
        prefs.showSidebar = true
        XCTAssertTrue(Preferences(defaults: defaults).showSidebar)
    }

    func testSidebarRootBookmarksPersist() {
        let a = Data([1, 2, 3]); let b = Data([4, 5, 6])
        prefs.sidebarRootBookmarks = [a, b]
        XCTAssertEqual(Preferences(defaults: defaults).sidebarRootBookmarks, [a, b])
    }
}
