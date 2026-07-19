import XCTest
import AppKit
import WebKit
@testable import MeditKit

/// Regression guard for the "⌃⇥ needs two presses on a rendered `.md` page, one
/// press in text mode" bug. While the preview is showing, its `WKWebView` is first
/// responder and WebKit's own `performKeyEquivalent` swallowed the first Ctrl+Tab
/// (it returns *handled* without switching), so the menu's Show Next Tab didn't
/// fire until the second press. `PreviewWebView` now decides the chord itself and
/// drives the window's native tab switch on the FIRST press.
///
/// The *decision* (`tabSwitchIntent`) is pure and tested exhaustively here — this
/// is what fails without the fix. The *effect* (`selectNextTab`) only moves the
/// selection on-screen, so it is verified end-to-end by
/// `uitests/ctrl-tab-switches-tab-in-preview.json` against the real app. (An
/// on-`handled`-only assertion would be worthless: WebKit's swallow also returns
/// handled, so it can't tell fixed from broken — hence the pure split.)
final class PreviewTabSwitchTests: XCTestCase {

    private let tab = PreviewWebView.tabKeyCode
    private typealias Intent = PreviewWebView.TabSwitchIntent

    // MARK: The decision — this is the fix, in isolation.

    func testCtrlTabIsNextWhenMultipleTabs() {
        XCTAssertEqual(PreviewWebView.tabSwitchIntent(keyCode: tab, flags: [.control], tabCount: 2), .next)
    }

    func testCtrlShiftTabIsPreviousWhenMultipleTabs() {
        XCTAssertEqual(PreviewWebView.tabSwitchIntent(keyCode: tab, flags: [.control, .shift], tabCount: 2),
                       .previous)
    }

    /// The bug's precondition: with a single tab there is nothing to switch to, so
    /// the chord must fall through (not be swallowed into a no-op switch).
    func testCtrlTabIsNoneWithSingleTab() {
        XCTAssertEqual(PreviewWebView.tabSwitchIntent(keyCode: tab, flags: [.control], tabCount: 1), .none)
    }

    /// Negative controls: only ⌃⇥ / ⌃⇧⇥ count. A plain Tab, ⌘⇥, or ⌥⇥ must not be
    /// treated as a tab switch, or normal focus/typing would break.
    func testOnlyControlTabCounts() {
        XCTAssertEqual(PreviewWebView.tabSwitchIntent(keyCode: tab, flags: [], tabCount: 3), .none)
        XCTAssertEqual(PreviewWebView.tabSwitchIntent(keyCode: tab, flags: [.command], tabCount: 3), .none)
        XCTAssertEqual(PreviewWebView.tabSwitchIntent(keyCode: tab, flags: [.option], tabCount: 3), .none)
        // A non-Tab key with Control held is not a tab switch either.
        XCTAssertEqual(PreviewWebView.tabSwitchIntent(keyCode: 0, flags: [.control], tabCount: 3), .none)
    }

    // MARK: The wiring — one real press does not crash and is claimed.

    /// A light integration check: with a genuine two-tab group the override runs
    /// through `selectNextTab` and reports the chord handled. (It does not assert
    /// the resulting selection — that is headless-unreliable and is the AP plan's
    /// job — only that the fix path executes without crashing.)
    func testPerformKeyEquivalentHandlesCtrlTabWithoutCrashing() throws {
        _ = NSApplication.shared
        let prefs = Preferences(defaults: UserDefaults(suiteName: "medit.tab.\(UUID().uuidString)")!)
        let docA = TextDocument(); docA.setTextForTesting("# A")
        let docB = TextDocument(); docB.setTextForTesting("# B")
        let wcA = EditorWindowController(document: docA, preferences: prefs)
        let wcB = EditorWindowController(document: docB, preferences: prefs)
        guard let winA = wcA.window, let winB = wcB.window else { throw XCTSkip("no window") }
        winA.addTabbedWindow(winB, ordered: .above)
        guard let group = winA.tabGroup, group.windows.count > 1 else {
            throw XCTSkip("tab group did not form headlessly")
        }
        let wv = PreviewWebView(frame: .zero, configuration: WKWebViewConfiguration())
        winA.contentView?.addSubview(wv)

        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.control],
                                     timestamp: 0, windowNumber: 0, context: nil,
                                     characters: "\t", charactersIgnoringModifiers: "\t",
                                     isARepeat: false, keyCode: tab)
        XCTAssertTrue(wv.performKeyEquivalent(with: event!),
                      "the preview must claim ⌃⇥ so it acts on the first press")
        _ = wcA; _ = wcB
    }
}
