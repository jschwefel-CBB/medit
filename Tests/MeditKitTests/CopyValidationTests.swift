import XCTest
import AppKit
@testable import MeditKit

/// Regression guard: routing Copy/Select All through the app delegate must not
/// bypass AppKit's validation.
///
/// `NSApp.sendAction(_:to:from:)` skips `validateUserInterfaceItem(_:)`. For a
/// `target: nil` menu item AppKit asks the responder chain first and greys the
/// item out when the answer is no, so the action never fires. Re-dispatching by
/// hand skipped that — and `NSTextView.copy(_:)` with an empty selection is not
/// a no-op: **it clears the pasteboard**. A ⌘C that should have done nothing
/// destroyed the user's clipboard.
///
/// Cross-check: `uitests/edge-copy-nothing-selected.json` asserts the
/// user-visible outcome (clipboard survives). This asserts the AppKit contract
/// that makes it true.
final class CopyValidationTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }

    /// The AppKit behavior this whole guard exists for. If Apple ever makes
    /// `copy:` a true no-op on an empty selection, this test tells us the guard
    /// is no longer load-bearing.
    func testNSTextViewCopyWithEmptySelectionClearsThePasteboard() {
        let tv = NSTextView(frame: .init(x: 0, y: 0, width: 200, height: 100))
        tv.string = "MARKER"
        tv.setSelectedRange(NSRange(location: 0, length: 0))

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("MARKER", forType: .string)

        tv.copy(nil)

        XCTAssertNil(NSPasteboard.general.string(forType: .string),
                     "documents WHY validation is required: copy: with no selection wipes the pasteboard")
    }

    /// And the reason AppKit never calls it: the item does not validate.
    func testNSTextViewDoesNotValidateCopyWithEmptySelection() {
        let tv = NSTextView(frame: .init(x: 0, y: 0, width: 200, height: 100))
        tv.string = "MARKER"
        tv.setSelectedRange(NSRange(location: 0, length: 0))

        let item = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        XCTAssertFalse(tv.validateUserInterfaceItem(item),
                       "copy: must not validate with an empty selection — this is what disables ⌘C")
    }

    /// With a selection, it validates and copies. The guard must not over-block.
    func testNSTextViewValidatesCopyWithASelection() {
        let tv = NSTextView(frame: .init(x: 0, y: 0, width: 200, height: 100))
        tv.string = "MARKER"
        tv.setSelectedRange(NSRange(location: 0, length: 6))

        let item = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        XCTAssertTrue(tv.validateUserInterfaceItem(item),
                      "copy: must validate when text is selected, or the guard would block real copies")
    }
}
