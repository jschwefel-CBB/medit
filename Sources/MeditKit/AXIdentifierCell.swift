import AppKit

extension NSControl {
    /// Set an accessibility identifier that is actually **vended through the AX
    /// API** to external tools (VoiceOver, AutoPilot), not just stored on the
    /// control object.
    ///
    /// For cell-based controls — `NSButton` (checkbox and push), `NSTextField`,
    /// `NSPopUpButton` — AppKit reads `AXIdentifier` off the control's *cell*.
    /// Calling `setAccessibilityIdentifier` on the control alone leaves the
    /// identifier empty in the live AX tree (`dump-axtree`/`find` report no
    /// match) even though `accessibilityIdentifier()` returns it in-process.
    /// Setting it on both the control and its cell makes the identifier
    /// resolvable by UI tests. Non-cell controls simply get it set twice, which
    /// is harmless.
    func setTestAXIdentifier(_ identifier: String) {
        setAccessibilityIdentifier(identifier)
        cell?.setAccessibilityIdentifier(identifier)
    }
}
