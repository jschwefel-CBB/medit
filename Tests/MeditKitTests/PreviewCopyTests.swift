import XCTest
import AppKit
import WebKit
@testable import MeditKit

/// Regression guard: an **auto-opened** Markdown preview must hold first
/// responder, or ⌘C copies nothing.
///
/// The bug: `showPreview(true)` runs from `viewDidLoad` when
/// `autoShowPreviewForMarkdown` is on, but `view.window` is nil there — so
/// `view.window?.makeFirstResponder(webView)` silently no-opped. The preview
/// rendered, took no focus, and Select All / ⌘C went to whatever else held first
/// responder. Toggling the preview off and on appeared to "fix" it only because
/// by then the view was in a window.
///
/// **Why every prior check missed it.** The old version of this file called
/// `windowController.copy(nil)` directly, proving only that the method worked
/// *if invoked*. The AutoPilot plan `preview-copy-test.json` launches with
/// `--no-auto-preview` and opens the preview from the View menu. Manual testing
/// did the same. All three entered through a door the user never uses. These
/// tests deliberately enter through auto-preview, and assert the *state* the
/// GUI plan depends on — so a unit pass and a GUI pass cannot both be wrong in
/// the same direction.
final class PreviewCopyTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }

    /// Build a controller the way opening a `.md` file does: auto-preview on, so
    /// `showPreview(true)` fires from `viewDidLoad` while `view.window` is nil.
    private func makeAutoPreviewController() -> EditorWindowController {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "medit.autoprev.\(UUID().uuidString)")!)
        prefs.autoShowPreviewForMarkdown = true

        let doc = TextDocument()
        doc.setTextForTesting("# Heading\n\nUNIQUESENTINEL preview body text.")
        doc.languageOverride = "markdown"

        let wc = EditorWindowController(document: doc, preferences: prefs)
        _ = wc.window                    // viewDidLoad -> auto-preview, no window yet
        wc.loadViewIfNeededForTesting()
        return wc
    }

    /// Drive the window through the appearance cycle a real launch performs.
    private func present(_ wc: EditorWindowController) {
        wc.window?.makeKeyAndOrderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }

    /// The bug, stated directly. Everything else about preview copy follows from
    /// this: if the web view isn't first responder, ⌘C never reaches it.
    func testAutoOpenedPreviewTakesFirstResponder() throws {
        let wc = makeAutoPreviewController()
        let editor = try XCTUnwrap(wc.editorForTesting)
        XCTAssertTrue(editor.isPreviewVisible, "precondition: auto-preview should be showing")

        present(wc)

        let wv = try XCTUnwrap(editor.previewWebViewForTesting)
        XCTAssertTrue(wc.window?.firstResponder === wv,
                      "an auto-opened preview must hold first responder, else ⌘C does nothing")
    }

    /// Guards the mechanism, not just the symptom: a focus request made before the
    /// view has a window must be deferred and applied, never dropped.
    func testFocusRequestedBeforeWindowExistsIsApplied() throws {
        let wc = makeAutoPreviewController()
        let editor = try XCTUnwrap(wc.editorForTesting)
        let wv = try XCTUnwrap(editor.previewWebViewForTesting)

        // The request was made in viewDidLoad with no window. It must survive.
        present(wc)

        XCTAssertTrue(wc.window?.firstResponder === wv,
                      "the deferred first-responder request was dropped")
    }

    /// Hiding the preview must hand focus back so typing resumes. This path always
    /// worked; assert it so the fix can't regress it.
    func testTogglingPreviewOffRestoresEditorFocus() throws {
        let wc = makeAutoPreviewController()
        let editor = try XCTUnwrap(wc.editorForTesting)
        present(wc)

        editor.showPreview(false)
        XCTAssertTrue(wc.window?.firstResponder === editor.textView,
                      "hiding the preview must return focus to the editor")
    }

    /// Re-showing the preview from the menu (the path that always worked) must
    /// still focus the web view — the fix must not special-case only the deferred
    /// path.
    func testReShowingPreviewFocusesTheWebView() throws {
        let wc = makeAutoPreviewController()
        let editor = try XCTUnwrap(wc.editorForTesting)
        present(wc)

        editor.showPreview(false)
        editor.showPreview(true)

        let wv = try XCTUnwrap(editor.previewWebViewForTesting)
        XCTAssertTrue(wc.window?.firstResponder === wv,
                      "re-showing the preview must focus the web view")
    }

    /// End-to-end: the auto-opened, focused preview renders selectable text — the
    /// precondition the AutoPilot plan's Select All + ⌘C relies on.
    func testAutoOpenedPreviewRendersSelectableText() throws {
        let wc = makeAutoPreviewController()
        let editor = try XCTUnwrap(wc.editorForTesting)
        present(wc)
        let wv = try XCTUnwrap(editor.previewWebViewForTesting)

        var rendered = false
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, !rendered {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            let done = expectation(description: "render")
            wv.evaluateJavaScript("document.body.innerText.indexOf('UNIQUESENTINEL') >= 0") { r, _ in
                rendered = (r as? Bool) == true
                done.fulfill()
            }
            _ = XCTWaiter().wait(for: [done], timeout: 1)
        }
        try XCTSkipUnless(rendered, "WKWebView did not render (headless / no window server)")

        let selected = expectation(description: "selection")
        var length = 0
        wv.evaluateJavaScript("document.execCommand('selectAll'); window.getSelection().toString().length") { r, _ in
            length = (r as? NSNumber)?.intValue ?? 0
            selected.fulfill()
        }
        wait(for: [selected], timeout: 5)
        XCTAssertGreaterThan(length, 0, "the rendered preview must have selectable text")
    }
}
