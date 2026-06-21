import XCTest
import AppKit
@testable import MeditKit

/// Headless integration: opening a Markdown document with a table and showing the
/// preview must place a live, selectable `MarkdownTableView` subview at a real
/// frame. This exercises the actual EditorViewController wiring (not just the pure
/// helpers), proving the embedded-subview integration without any screen capture.
final class MarkdownTablePreviewSmokeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    private func makeController(text: String) -> EditorWindowController {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "medit.tablesmoke.\(UUID().uuidString)")!)
        let document = TextDocument()
        document.setTextForTesting(text)
        let controller = EditorWindowController(document: document, preferences: prefs)
        _ = controller.window
        controller.loadViewIfNeededForTesting()
        // Give the window a real size so preview layout yields non-zero frames.
        controller.window?.setContentSize(NSSize(width: 700, height: 500))
        return controller
    }

    private let tableDoc = """
    # Heading

    Intro prose.

    | Fruit  | Qty |
    | ------ | --- |
    | Apples | 5   |
    | Pears  | 12  |

    Outro prose.
    """

    func testShowingPreviewPlacesSelectableTableSubview() {
        let controller = makeController(text: tableDoc)
        guard let editor = controller.editorForTesting else { return XCTFail("no editor") }
        controller.window?.makeKeyAndOrderFront(nil)

        editor.showPreview(true)
        XCTAssertTrue(editor.isPreviewVisible)

        XCTAssertEqual(editor.tableSubviewCountForTesting, 1,
                       "one table in the doc should place one live table subview")
        XCTAssertTrue(editor.firstTableIsSelectableForTesting,
                      "the embedded table view should hold selectable text")
        let frame = editor.firstTableSubviewFrameForTesting
        XCTAssertNotNil(frame)
        XCTAssertGreaterThan(frame!.width, 0)
        XCTAssertGreaterThan(frame!.height, 0)
    }

    func testHidingPreviewTearsDownTableSubviews() {
        let controller = makeController(text: tableDoc)
        guard let editor = controller.editorForTesting else { return XCTFail("no editor") }
        editor.showPreview(true)
        XCTAssertEqual(editor.tableSubviewCountForTesting, 1)
        // Toggling the preview off then on rebuilds the subviews cleanly (no leak,
        // no double-placement).
        editor.showPreview(false)
        editor.showPreview(true)
        XCTAssertEqual(editor.tableSubviewCountForTesting, 1, "table persists across re-show")
    }

    func testDocumentWithNoTablePlacesNoSubviews() {
        let controller = makeController(text: "# Just prose\n\nNo tables here at all.")
        guard let editor = controller.editorForTesting else { return XCTFail("no editor") }
        editor.showPreview(true)
        XCTAssertEqual(editor.tableSubviewCountForTesting, 0)
    }
}
