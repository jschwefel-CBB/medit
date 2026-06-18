import XCTest
import AppKit
@testable import MeditKit

/// Guards the 1.6 rule: every interactive control in the Settings window must
/// carry a help tooltip, so a new control can't ship without one.
final class PreferencesTooltipTests: XCTestCase {

    private func makeController() -> PreferencesWindowController {
        let defaults = UserDefaults(suiteName: "medit.tests.tooltips.\(UUID().uuidString)")!
        return PreferencesWindowController(preferences: Preferences(defaults: defaults))
    }

    func testEveryInteractiveControlHasATooltip() {
        let controller = makeController()
        let controls = controller.interactiveControlsForTesting()

        // Sanity: the walker should find the full set of controls, not zero.
        XCTAssertGreaterThanOrEqual(controls.count, 25,
            "expected the Settings window's interactive controls; found \(controls.count)")

        let missing = controls.filter { ($0.toolTip ?? "").isEmpty }
        let names = missing.map { ($0 as? NSButton)?.title ?? $0.className }
        XCTAssertTrue(missing.isEmpty,
            "every Settings control needs a tooltip; missing on: \(names)")
    }

    func testTooltipsAreWellFormed() {
        let controller = makeController()
        for control in controller.interactiveControlsForTesting() {
            guard let tip = control.toolTip, !tip.isEmpty else { continue }
            // macOS help-tag convention: no trailing period.
            XCTAssertFalse(tip.hasSuffix("."),
                "tooltip should not end with a period: \(tip)")
            XCTAssertGreaterThan(tip.count, 8, "tooltip too terse: \(tip)")
        }
    }

    /// Discoverability guard (1.6.1): every setting control must have a clickable
    /// ⓘ help button carrying the same help text — the slow system tooltip alone
    /// wasn't obvious enough. One help button per interactive control.
    func testEveryControlHasAHelpButton() {
        let controller = makeController()
        let controlTexts = controller.interactiveControlsForTesting()
            .compactMap { $0.toolTip }.filter { !$0.isEmpty }.sorted()
        let helpTexts = controller.helpButtonTextsForTesting().sorted()

        XCTAssertEqual(helpTexts.count, controlTexts.count,
            "expected one ⓘ help button per setting control; controls=\(controlTexts.count) help=\(helpTexts.count)")
        // Every control's help text is presented by some help button.
        XCTAssertEqual(helpTexts, controlTexts,
            "help-button texts should match the controls' help text exactly")
    }
}
