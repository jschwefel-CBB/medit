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
    }

    /// Prefer the bundle display name when running as a real .app.
    private func displayName(default fallback: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "medit"
    }

    // MARK: Documents

    /// Open an untitled document at launch when there's nothing to restore.
    public func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

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
