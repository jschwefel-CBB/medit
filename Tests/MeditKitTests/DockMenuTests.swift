import XCTest
import AppKit
@testable import MeditKit

/// The Dock icon's right-click menu. Its items must target the app delegate
/// directly (not the first responder): the Dock menu is shown while the app may
/// be inactive with no key window, so a responder-chain action would find no
/// target and the item would render disabled.
final class DockMenuTests: XCTestCase {

    override func setUp() { super.setUp(); _ = NSApplication.shared }

    func testDockMenuOffersNewWindowAndNewTab() {
        let delegate = AppDelegate()
        guard let menu = delegate.applicationDockMenu(NSApp) else {
            return XCTFail("no dock menu")
        }
        XCTAssertEqual(menu.items.map(\.title), ["New Window", "New Tab"])
    }

    /// Each item must have an explicit target, or it will be greyed out when the
    /// app is inactive — which is precisely when the Dock menu is used.
    func testDockMenuItemsTargetTheDelegateDirectly() {
        let delegate = AppDelegate()
        guard let menu = delegate.applicationDockMenu(NSApp) else {
            return XCTFail("no dock menu")
        }
        for item in menu.items {
            XCTAssertTrue(item.target === delegate,
                          "'\(item.title)' must target the delegate, not the responder chain")
            XCTAssertNotNil(item.action, "'\(item.title)' has no action")
        }
    }
}
