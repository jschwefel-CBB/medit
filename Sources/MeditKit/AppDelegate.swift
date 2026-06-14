import AppKit

/// Application delegate: installs the programmatic menu bar, owns the shared
/// Preferences window, and sets document-app behavior. The `@main` entry point
/// (in the app target's `main.swift`) assigns an instance of this as the
/// `NSApplication` delegate.
public final class AppDelegate: NSObject, NSApplicationDelegate {

    private var preferencesController: PreferencesWindowController?

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let appName = ProcessInfo.processInfo.processName
        NSApp.mainMenu = MainMenu.build(appName: displayName(default: appName))
        NSApp.setActivationPolicy(.regular)

        // Restore-last-session, else one blank tab. State restoration runs
        // around launch; we can't reliably know during
        // applicationShouldOpenUntitledFile whether a window was restored, so we
        // defer: after the runloop settles, open a single untitled document only
        // if nothing was restored. This avoids the "two tabs at launch" bug where
        // restoration AND an untitled-open both fire.
        DispatchQueue.main.async { [weak self] in
            self?.openUntitledIfNoDocuments()
        }
    }

    private func openUntitledIfNoDocuments() {
        guard NSDocumentController.shared.documents.isEmpty else { return }
        do {
            _ = try NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
        } catch {
            NSApp.presentError(error)
        }
    }

    /// Prefer the bundle display name when running as a real .app.
    private func displayName(default fallback: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "medit"
    }

    // MARK: Documents

    /// We handle untitled-at-launch ourselves in applicationDidFinishLaunching
    /// (deferred, after restoration), so suppress AppKit's automatic launch-time
    /// untitled open. But still allow opening untitled when the app is
    /// re-activated with no windows (e.g. clicking the Dock icon) — that path
    /// goes through applicationShouldHandleReopen below, not this one, so
    /// returning false here is safe for both launch and reopen.
    public func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    /// Clicking the Dock icon with no open windows should give a blank tab.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openUntitledIfNoDocuments() }
        return true
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: Preferences

    @IBAction public func showPreferences(_ sender: Any?) {
        if preferencesController == nil {
            preferencesController = PreferencesWindowController()
        }
        preferencesController?.showWindow(sender)
        preferencesController?.window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}
