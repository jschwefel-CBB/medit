import XCTest
import AppKit
import WebKit
@testable import MeditKit

/// Regression guard: dropping a file onto a **rendered** Markdown preview must
/// open it, exactly as dropping onto the editor does.
///
/// The bug: while the preview is showing it covers the editor and
/// `scrollView.isHidden = true`. A hidden view receives no drag events, so the
/// drop landed on the `WKWebView`, which had no file-drop handling and ignored
/// it. Since auto-preview became the default, that is the normal state of every
/// Markdown document — so file drops appeared broken outright.
///
/// **Cross-check with `uitests/drop-files-onto-preview.json`.** The GUI plan
/// performs a real Finder drag and asserts the user-visible outcome (a new tab).
/// It cannot see *why* a drop was refused. These tests assert the structural
/// preconditions that plan depends on — the preview is a `PreviewWebView`, it
/// registers both drag types, and its drop callback is wired — so a unit pass
/// and a GUI pass cannot both be wrong in the same direction. `drop-files-onto-
/// editor.json` passed 18/18 while this was broken, because it never opens a
/// Markdown file and so never shows the preview.
final class PreviewDropTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }

    /// Build a controller the way opening a `.md` file does: auto-preview on.
    private func makeMarkdownController() -> EditorWindowController {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "medit.drop.\(UUID().uuidString)")!)
        prefs.autoShowPreviewForMarkdown = true

        let doc = TextDocument()
        doc.setTextForTesting("# Heading\n\nBody text.")
        doc.languageOverride = "markdown"

        let wc = EditorWindowController(document: doc, preferences: prefs)
        _ = wc.window
        wc.loadViewIfNeededForTesting()
        return wc
    }

    /// The precondition that made the bug possible, asserted directly: with the
    /// preview up, the editor is hidden and cannot receive drags. If this ever
    /// stops being true the preview no longer needs its own drop handling — but
    /// while it *is* true, the preview must handle drops itself.
    func testPreviewCoversTheEditorSoTheEditorCannotReceiveDrops() throws {
        let wc = makeMarkdownController()
        let editor = try XCTUnwrap(wc.editorForTesting)
        XCTAssertTrue(editor.isPreviewVisible, "precondition: auto-preview should be showing")
        XCTAssertTrue(editor.textView.enclosingScrollView?.isHidden == true,
                      "the editor must be hidden behind the preview — that is why the preview needs its own drop handling")
    }

    /// The preview must be the drop-capable subclass, not a bare `WKWebView`.
    func testPreviewIsADropCapableWebView() throws {
        let wc = makeMarkdownController()
        let editor = try XCTUnwrap(wc.editorForTesting)
        let wv = try XCTUnwrap(editor.previewWebViewForTesting)
        XCTAssertTrue(wv is PreviewWebView,
                      "a bare WKWebView ignores file drops; the preview must be a PreviewWebView")
    }

    /// Both drag types are required. A single-file Finder drag advertises
    /// `.fileURL`; a *multi*-file drag advertises only the legacy filenames type.
    /// Omit either and that shape of drop never reaches `draggingEntered`.
    func testPreviewRegistersBothFileDragTypes() throws {
        let wc = makeMarkdownController()
        let editor = try XCTUnwrap(wc.editorForTesting)
        let wv = try XCTUnwrap(editor.previewWebViewForTesting)

        let registered = wv.registeredDraggedTypes
        XCTAssertTrue(registered.contains(.fileURL),
                      "single-file drags advertise .fileURL")
        XCTAssertTrue(registered.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType")),
                      "multi-file drags advertise only the legacy NSFilenamesPboardType")
    }

    /// A drop must actually reach the open-files handler. This is the seam the GUI
    /// plan exercises end-to-end; here we assert the callback is wired at all.
    func testDroppedFilesReachTheOpenFilesHandler() throws {
        let wc = makeMarkdownController()
        let editor = try XCTUnwrap(wc.editorForTesting)
        let wv = try XCTUnwrap(editor.previewWebViewForTesting as? PreviewWebView)

        var received: [URL] = []
        wv.onOpenFiles = { received = $0 }

        let urls = [URL(fileURLWithPath: "/tmp/one.txt"), URL(fileURLWithPath: "/tmp/two.txt")]
        wv.performFileDropForTesting(urls)

        XCTAssertEqual(received, urls, "a preview drop must forward its file URLs to the open handler")
    }

    /// The editor keeps its own drop handling — the fix must not move it.
    func testEditorStillRegistersFileDragTypes() throws {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "medit.drop2.\(UUID().uuidString)")!)
        prefs.autoShowPreviewForMarkdown = false
        let doc = TextDocument()
        doc.setTextForTesting("plain text")
        let wc = EditorWindowController(document: doc, preferences: prefs)
        _ = wc.window
        wc.loadViewIfNeededForTesting()
        wc.window?.makeKeyAndOrderFront(nil)

        let tv = try XCTUnwrap(wc.editorForTesting?.textView as? EditorTextView)
        let registered = tv.registeredDraggedTypes
        XCTAssertTrue(registered.contains(.fileURL))
        XCTAssertTrue(registered.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType")))
    }
}
