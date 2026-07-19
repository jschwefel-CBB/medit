import XCTest
import AppKit
@testable import MeditKit

/// Text-size zoom: ⌘+/⌘-/⌘0 and ⌥+scroll change the size of the editor font (and,
/// live, the preview via CSS `zoom`). These tests exercise the controller's zoom
/// commands and assert the user-visible result — the text view's actual point
/// size — not just the internal scale, so a scale that failed to reach the font
/// would be caught.
///
/// Cross-check: `uitests/text-size-zoom.json` drives the real menu items / keys
/// and screenshots the result; these unit tests pin the numeric behavior (steps,
/// clamps, reset) the GUI plan can't read.
final class TextZoomTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }

    private func makeEditor(baseSize: CGFloat = 13) -> EditorViewController {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "medit.zoom.\(UUID().uuidString)")!)
        prefs.fontName = "Menlo"
        prefs.fontSize = baseSize
        let doc = TextDocument()
        doc.setTextForTesting("some text to size")
        let wc = EditorWindowController(document: doc, preferences: prefs)
        _ = wc.window
        wc.loadViewIfNeededForTesting()
        return wc.editorForTesting!
    }

    /// The applied font size must equal the computed effective size — the internal
    /// scale and the visible result cannot silently diverge.
    func testEffectiveSizeMatchesAppliedFont() {
        let e = makeEditor(baseSize: 13)
        XCTAssertEqual(e.effectiveFontSizeForTesting, e.textViewPointSizeForTesting, accuracy: 0.001)
    }

    func testZoomInIncreasesSize() {
        let e = makeEditor(baseSize: 13)
        let before = e.textViewPointSizeForTesting
        e.zoomIn(nil)
        XCTAssertGreaterThan(e.zoomScaleForTesting, 1.0)
        XCTAssertGreaterThan(e.textViewPointSizeForTesting, before)
        XCTAssertEqual(e.effectiveFontSizeForTesting, e.textViewPointSizeForTesting, accuracy: 0.001,
                       "the visible font must track the zoom, not just the scale")
    }

    func testZoomOutDecreasesSize() {
        let e = makeEditor(baseSize: 13)
        let before = e.textViewPointSizeForTesting
        e.zoomOut(nil)
        XCTAssertLessThan(e.zoomScaleForTesting, 1.0)
        XCTAssertLessThan(e.textViewPointSizeForTesting, before)
    }

    func testActualSizeResetsToBase() {
        let e = makeEditor(baseSize: 13)
        e.zoomIn(nil); e.zoomIn(nil); e.zoomIn(nil)
        XCTAssertGreaterThan(e.textViewPointSizeForTesting, 13)
        e.actualSize(nil)
        XCTAssertEqual(e.zoomScaleForTesting, 1.0, accuracy: 0.001)
        XCTAssertEqual(e.textViewPointSizeForTesting, 13, accuracy: 0.001)
    }

    /// Zoom in must saturate, never run away — the scale caps and the font stays
    /// within the sane clamp.
    func testZoomInClampsAtMaximum() {
        let e = makeEditor(baseSize: 13)
        for _ in 0..<100 { e.zoomIn(nil) }
        XCTAssertLessThanOrEqual(e.zoomScaleForTesting, 3.0 + 0.001)
        XCTAssertLessThanOrEqual(e.textViewPointSizeForTesting, 96 + 0.001)
    }

    func testZoomOutClampsAtMinimum() {
        let e = makeEditor(baseSize: 13)
        for _ in 0..<100 { e.zoomOut(nil) }
        XCTAssertGreaterThanOrEqual(e.zoomScaleForTesting, 0.5 - 0.001)
        XCTAssertGreaterThanOrEqual(e.textViewPointSizeForTesting, 6 - 0.001)
    }

    /// ⌥+scroll steps once per accumulated-threshold crossing: a delta at the
    /// threshold zooms, a sub-threshold delta alone does not.
    func testScrollAtThresholdZoomsInSubThresholdDoesNot() {
        let e = makeEditor(baseSize: 13)

        e.zoomByScroll(1)                       // below the 3.0 threshold on its own
        XCTAssertEqual(e.zoomScaleForTesting, 1.0, accuracy: 0.001,
                       "a single sub-threshold scroll delta must not zoom")

        e.zoomByScroll(3)                       // now the accumulator (1+3) crosses
        XCTAssertGreaterThan(e.zoomScaleForTesting, 1.0, "crossing the threshold zooms in")
    }

    func testNegativeScrollZoomsOut() {
        let e = makeEditor(baseSize: 13)
        e.zoomByScroll(-6)   // two thresholds down
        XCTAssertLessThan(e.zoomScaleForTesting, 1.0)
    }

    /// The preview's ⌘-chord → zoom-command mapping (pure). ⌘+ and ⌘= both zoom in;
    /// Shift is allowed (⌘+ is ⌘⇧=) but Control/Option disqualify.
    func testPreviewZoomSelectorMapping() {
        XCTAssertEqual(PreviewWebView.zoomSelector(flags: [.command], characters: "="), Selector(("zoomIn:")))
        XCTAssertEqual(PreviewWebView.zoomSelector(flags: [.command], characters: "+"), Selector(("zoomIn:")))
        XCTAssertEqual(PreviewWebView.zoomSelector(flags: [.command, .shift], characters: "+"),
                       Selector(("zoomIn:")), "⌘+ is physically ⌘⇧=")
        XCTAssertEqual(PreviewWebView.zoomSelector(flags: [.command], characters: "-"), Selector(("zoomOut:")))
        XCTAssertEqual(PreviewWebView.zoomSelector(flags: [.command], characters: "0"), Selector(("actualSize:")))
        XCTAssertNil(PreviewWebView.zoomSelector(flags: [.command], characters: "a"))
        XCTAssertNil(PreviewWebView.zoomSelector(flags: [], characters: "+"), "no ⌘ = no zoom")
        XCTAssertNil(PreviewWebView.zoomSelector(flags: [.control, .command], characters: "+"),
                     "Control disqualifies")
    }

    /// The scroll entry point that the views actually call (`zoomScrollFromEvent:`)
    /// must forward a real scroll event's delta. Synthesizing an NSEvent whose
    /// `scrollingDeltaY` survives is environment-dependent, so skip (rather than
    /// fail) if the delta doesn't materialize — the delta→zoom math is covered by
    /// the `zoomByScroll` tests above regardless.
    func testScrollEventEntryPointForwardsDelta() throws {
        let e = makeEditor(baseSize: 13)
        let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                         wheelCount: 1, wheel1: 12, wheel2: 0, wheel3: 0)
        guard let cg, let event = NSEvent(cgEvent: cg), event.scrollingDeltaY != 0 else {
            throw XCTSkip("could not synthesize a scroll event with a nonzero delta")
        }
        e.zoomScrollFromEvent(event)
        XCTAssertGreaterThan(e.zoomScaleForTesting, 1.0, "an ⌥+scroll event must zoom via the shared entry point")
    }
}
