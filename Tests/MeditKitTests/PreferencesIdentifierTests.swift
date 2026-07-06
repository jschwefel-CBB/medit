import XCTest
import AppKit
@testable import MeditKit

/// Guards the AutoPilot-testability rule: every interactive control in the
/// Settings window must carry a stable `settings.*` accessibility identifier,
/// so UI tests can target it deterministically and a new control can't ship
/// without one. Mirrors `PreferencesTooltipTests` for the identifier dimension.
final class PreferencesIdentifierTests: XCTestCase {

    private func makeController() -> PreferencesWindowController {
        let defaults = UserDefaults(suiteName: "medit.tests.ids.\(UUID().uuidString)")!
        return PreferencesWindowController(preferences: Preferences(defaults: defaults))
    }

    func testEveryInteractiveControlHasAStableIdentifier() {
        let controller = makeController()
        let controls = controller.interactiveControlsForTesting()

        // Sanity: the walker should find the full set of controls, not zero.
        XCTAssertGreaterThanOrEqual(controls.count, 25,
            "expected the Settings window's interactive controls; found \(controls.count)")

        let missing = controls.filter {
            ($0.accessibilityIdentifier() ?? "").isEmpty
        }
        let missingNames = missing.map { ($0 as? NSButton)?.title ?? $0.className }
        XCTAssertTrue(missing.isEmpty,
            "every Settings control needs an accessibility identifier; missing on: \(missingNames)")
    }

    func testIdentifiersUseTheSettingsPrefixConvention() {
        let controller = makeController()
        for control in controller.interactiveControlsForTesting() {
            let id = control.accessibilityIdentifier() ?? ""
            let name = (control as? NSButton)?.title ?? control.className
            XCTAssertTrue(id.hasPrefix("settings."),
                "Settings control identifier should be namespaced 'settings.*': got '\(id)' on \(name)")
        }
    }

    func testIdentifiersAreUnique() {
        let controller = makeController()
        let ids = controller.interactiveControlsForTesting()
            .compactMap { $0.accessibilityIdentifier() }
            .filter { !$0.isEmpty }
        let duplicates = Dictionary(grouping: ids, by: { $0 })
            .filter { $1.count > 1 }
            .keys
            .sorted()
        XCTAssertTrue(duplicates.isEmpty,
            "Settings control identifiers must be unique; duplicated: \(duplicates)")
    }
}
