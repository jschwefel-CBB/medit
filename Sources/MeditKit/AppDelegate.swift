import AppKit

/// Application delegate: installs the programmatic menu bar, owns the shared
/// Preferences window, and sets document-app behavior. The `@main` entry point
/// (in the app target's `main.swift`) assigns an instance of this as the
/// `NSApplication` delegate.
public final class AppDelegate: NSObject, NSApplicationDelegate {

    private var preferencesController: PreferencesWindowController?
    /// Set when files/folders are opened at launch (via `application(_:openFiles:)`),
    /// so the deferred "open a blank Untitled" step doesn't also fire and leave a
    /// stray empty tab next to the opened file.
    private var didOpenFilesAtLaunch = false

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let appName = ProcessInfo.processInfo.processName
        NSApp.mainMenu = MainMenu.build(appName: displayName(default: appName))
        NSApp.setActivationPolicy(.regular)

        // Under --reset-state (the GUI test driver), close any document that
        // AppKit/macOS restored from the previous session so the suite starts
        // from a guaranteed-blank Untitled window. macOS reopens the last
        // document from state outside our UserDefaults domain, so clearing
        // defaults is not enough — we close them here, after restoration has run.
        let resetting = LaunchReset.isRequested(in: CommandLine.arguments)
        if resetting { closeAllRestoredDocuments() }

        // Restore-last-session, else one blank tab. State restoration runs
        // around launch; we can't reliably know during
        // applicationShouldOpenUntitledFile whether a window was restored, so we
        // defer: after the runloop settles, open a single untitled document only
        // if nothing was restored. This avoids the "two tabs at launch" bug where
        // restoration AND an untitled-open both fire.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // A reopened document can arrive asynchronously after launch; under
            // --reset-state close it again here before deciding about untitled.
            if resetting { self.closeAllRestoredDocuments() }
            // Reopen the previous session's files (unless files were opened at
            // launch, something was already restored, or we're resetting state).
            if !resetting, !self.didOpenFilesAtLaunch { self.reopenLastSessionIfEnabled() }
            // Don't open a blank tab if files were opened/restored at launch.
            if !self.didOpenFilesAtLaunch { self.openUntitledIfNoDocuments() }
            self.openLaunchFolderIfRequested()
            // Track session changes from here on.
            self.observeSessionChanges()
        }
    }

    // MARK: Session restore

    /// Reopen files saved from the last session (most editors do this now). Only
    /// runs when the pref is on and no documents are already open.
    private func reopenLastSessionIfEnabled() {
        guard Preferences.shared.reopenLastSession,
              NSDocumentController.shared.documents.isEmpty else { return }
        let urls = SessionStore.shared.files.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        didOpenFilesAtLaunch = true   // suppress the untitled-open
        for url in urls {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { NSApp.presentError(error) }
            }
        }
    }

    /// Snapshot the currently-open file URLs to the session store. Called whenever
    /// documents are opened/closed and at termination.
    @objc private func snapshotSession() {
        let urls = NSDocumentController.shared.documents
            .compactMap { ($0 as? TextDocument)?.fileURL }
        SessionStore.shared.record(urls)
    }

    private func observeSessionChanges() {
        // NSDocumentController doesn't post a single "documents changed" event, so
        // snapshot on the lifecycle notifications that bracket open/close.
        let nc = NotificationCenter.default
        for name: NSNotification.Name in [NSWindow.didBecomeMainNotification, NSWindow.willCloseNotification] {
            nc.addObserver(self, selector: #selector(snapshotSession), name: name, object: nil)
        }
    }

    /// If launched with `--open-folder <path>` (GUI test driver hook), seed that
    /// folder as a sidebar root in the front window once it exists. Guarded so it
    /// runs at most once even if AppKit also delivers the path via openFiles.
    private var didOpenLaunchFolder = false
    private func openLaunchFolderIfRequested() {
        guard !didOpenLaunchFolder,
              let path = LaunchReset.requestedFolderToOpen(in: CommandLine.arguments) else { return }
        didOpenLaunchFolder = true
        openFolderInFrontWindow(URL(fileURLWithPath: path, isDirectory: true))
    }

    /// Close every open document without saving — used only under --reset-state
    /// to discard any session that macOS restored before launch.
    private func closeAllRestoredDocuments() {
        for document in NSDocumentController.shared.documents {
            document.close()
        }
    }

    /// When a file is opened, replace a *single* pristine (empty, never-edited)
    /// Untitled document by closing it — so opening a file into a fresh window
    /// doesn't leave a stray blank tab. If more than one untitled doc exists, or
    /// any has been touched, leave them all alone (open in a new tab instead).
    func closePristineUntitledDocuments(excluding opened: NSDocument) {
        let pristine = NSDocumentController.shared.documents
            .compactMap { $0 as? TextDocument }
            .filter { $0 !== opened && $0.isPristineUntitled }
        guard pristine.count == 1 else { return }
        pristine[0].close()
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

    /// Intercept open requests for directories: AppKit/`NSDocumentController` would
    /// otherwise try to open a folder as a document and fail ("cannot open files
    /// in the folder format"). Route directories to the sidebar instead and hand
    /// the rest to the normal document machinery.
    public func application(_ sender: NSApplication, openFiles filenames: [String]) {
        didOpenFilesAtLaunch = true
        var documentPaths: [String] = []
        for path in filenames {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                openFolderInFrontWindow(URL(fileURLWithPath: path, isDirectory: true))
            } else {
                documentPaths.append(path)
            }
        }
        for path in documentPaths {
            NSDocumentController.shared.openDocument(
                withContentsOf: URL(fileURLWithPath: path), display: true) { [weak self] doc, _, error in
                if let error { NSApp.presentError(error); return }
                guard let doc else { return }
                // Ensure the opened document's window is created and frontmost —
                // a freshly launched Untitled window can otherwise stay on top.
                if doc.windowControllers.isEmpty { doc.makeWindowControllers() }
                doc.showWindows()
                doc.windowControllers.first?.window?.makeKeyAndOrderFront(nil)
                // Replace a lone pristine Untitled tab/window with the opened file.
                self?.closePristineUntitledDocuments(excluding: doc)
            }
        }
        sender.reply(toOpenOrPrint: .success)
    }

    /// Open a folder as a sidebar root in the front editor window, creating one
    /// (a blank untitled document) if none exists yet.
    private func openFolderInFrontWindow(_ url: URL) {
        openUntitledIfNoDocuments()
        guard let controller = NSApp.mainWindow?.windowController as? EditorWindowController
            ?? NSApp.windows.compactMap({ $0.windowController as? EditorWindowController }).first
        else { return }
        controller.openFolder(at: url)
    }

    /// Clicking the Dock icon with no open windows should give a blank tab.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openUntitledIfNoDocuments() }
        return true
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    public func applicationWillTerminate(_ notification: Notification) {
        // Final, authoritative snapshot of the session for next-launch restore.
        if !LaunchReset.isRequested(in: CommandLine.arguments) { snapshotSession() }
    }

    /// Block AppKit's window/state restoration pass entirely under --reset-state,
    /// so no document window from a previous session is recreated. (Returns true
    /// for normal launches, preserving restore-last-session behavior.)
    public func applicationShouldRestoreApplicationState(_ app: NSApplication,
                                                         coder: NSCoder) -> Bool {
        !LaunchReset.isRequested(in: CommandLine.arguments)
    }

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
