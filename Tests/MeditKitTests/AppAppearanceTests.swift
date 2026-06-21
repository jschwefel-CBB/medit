import XCTest
import AppKit
@testable import MeditKit

final class AppAppearanceTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }

    func testApplyToAppMapsEachCase() {
        AppAppearance.applyToApp(.light)
        XCTAssertEqual(NSApp.appearance?.name, .aqua)

        AppAppearance.applyToApp(.dark)
        XCTAssertEqual(NSApp.appearance?.name, .darkAqua)

        AppAppearance.applyToApp(.system)
        XCTAssertNil(NSApp.appearance, "system means follow the OS (nil app appearance)")
    }

    /// Mirrors what AppDelegate does at launch: read the saved appearance pref and
    /// apply it. Proves a saved "light" preference is honored on startup (the bug:
    /// the app previously only followed the system appearance until Settings opened).
    func testSavedLightPreferenceIsAppliedOnLaunch() {
        let suite = UserDefaults(suiteName: "medit.appearance.\(UUID().uuidString)")!
        let prefs = Preferences(defaults: suite)
        prefs.appearance = .light            // user chose Light previously

        // The launch path: applyToApp(prefs.appearance)
        AppAppearance.applyToApp(prefs.appearance)
        XCTAssertEqual(NSApp.appearance?.name, .aqua, "saved Light pref must apply at launch")

        AppAppearance.applyToApp(.system)    // reset shared state for other tests
    }
}
