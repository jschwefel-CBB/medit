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

        // Apply the saved Light/Dark/System appearance preference at launch.
        // Without this the app only ever followed the system appearance until the
        // user opened Settings (which is the only other place that applied it).
        AppAppearance.applyToApp(Preferences.shared.appearance)

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
            // BUT never close documents the user actually opened at launch (files
            // passed via openFiles / launchFiles) — only the macOS-restored ones.
            if resetting, !self.didOpenFilesAtLaunch { self.closeAllRestoredDocuments() }
            // Reopen the previous session's files (unless files were opened at
            // launch, something was already restored, or we're resetting state).
            if !resetting, !self.didOpenFilesAtLaunch { self.reopenLastSessionIfEnabled() }
            // Don't open a blank tab if files were opened/restored at launch.
            if !self.didOpenFilesAtLaunch { self.openUntitledIfNoDocuments() }
            self.openLaunchFolderIfRequested()
            self.openLaunchFilesIfRequested()
            // Track session changes from here on.
            self.observeSessionChanges()
        }
    }

    // MARK: Session restore

    /// Reopen the previous session's full workspace (windows, their tabs, active
    /// tab, sidebar folders, and frames). Only runs when the pref is on and no
    /// documents are already open.
    private func reopenLastSessionIfEnabled() {
        guard Preferences.shared.reopenLastSession,
              NSDocumentController.shared.documents.isEmpty else { return }
        let windows = SessionStore.shared.windows
        guard !windows.isEmpty else { return }
        didOpenFilesAtLaunch = true   // suppress the untitled-open
        for win in windows { restoreOneWindow(win) }
    }

    /// Open one saved window: its tabs in order, then select the active tab, set the
    /// sidebar folders, and apply the frame. Missing files are skipped; a window with
    /// no surviving files is not created.
    private func restoreOneWindow(_ session: WindowSession) {
        let urls = session.tabPaths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard let first = urls.first else { return }

        NSDocumentController.shared.openDocument(withContentsOf: first, display: true) { doc, _, error in
            if let error { NSApp.presentError(error) }
            guard let wc = doc?.windowControllers.first as? EditorWindowController else { return }
            // Remaining files become tabs in THIS window. Because tabbingMode is
            // .automatic, a separate openDocument elsewhere makes a separate window;
            // openFiles(at:) adds tabs only within this window.
            for url in urls.dropFirst() {
                if EditorWindowController.focusIfAlreadyOpen(url) { continue }
                wc.openFiles(at: [url])
            }
            wc.restoreSidebarRoots(session.sidebarFolderBookmarks)
            wc.applyFrame(session.frame)
            if let active = session.activeTabPath {
                EditorWindowController.focusIfAlreadyOpen(URL(fileURLWithPath: active))
            }
        }
    }

    /// Snapshot one WindowSession per editor tab-group to the session store. Called
    /// whenever documents are opened/closed and at termination.
    @objc private func snapshotSession() {
        var seenGroups = Set<ObjectIdentifier>()
        var windows: [WindowSession] = []
        for window in NSApp.windows {
            guard let wc = window.windowController as? EditorWindowController else { continue }
            let groupKey = ObjectIdentifier(window.tabGroup ?? window)
            guard seenGroups.insert(groupKey).inserted else { continue }
            let tabs = wc.tabDocumentURLs.map(\.path)
            guard !tabs.isEmpty else { continue }   // skip a group with only untitled docs
            windows.append(WindowSession(
                tabPaths: tabs,
                activeTabPath: wc.activeTabURL?.path,
                sidebarFolderBookmarks: wc.sidebarRootBookmarks,
                frame: NSStringFromRect(window.frame)))
        }
        SessionStore.shared.record(windows)
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

    /// If launched with `--open-files <paths…>` (GUI test driver hook), open those
    /// files as tabs in the front window via `openFiles(at:)` — the SAME entry
    /// point the sidebar and editor-drag use. Lets autopilot exercise the
    /// open-into-tabs path that NSOpenPanel / Finder-drag normally drive. Guarded
    /// so it runs at most once.
    private var didOpenLaunchFiles = false
    private func openLaunchFilesIfRequested() {
        guard !didOpenLaunchFiles else { return }
        let paths = LaunchReset.requestedFilesToOpen(in: CommandLine.arguments)
        guard !paths.isEmpty else { return }
        didOpenLaunchFiles = true
        openUntitledIfNoDocuments()
        // Fire after launch fully settles (not in the launch async block) so this
        // faithfully mirrors a runtime sidebar/drag open rather than a launch-time
        // re-entrant one.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard let controller = NSApp.mainWindow?.windowController as? EditorWindowController
                ?? NSApp.windows.compactMap({ $0.windowController as? EditorWindowController }).first
            else { return }
            controller.openFiles(at: paths.map { URL(fileURLWithPath: $0) })
        }
    }

    /// Close every open document without saving — used only under --reset-state
    /// to discard any session that macOS restored before launch.
    private func closeAllRestoredDocuments() {
        for document in NSDocumentController.shared.documents {
            document.close()
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

    /// Intercept open requests for directories: AppKit/`NSDocumentController` would
    /// otherwise try to open a folder as a document and fail ("cannot open files
    /// in the folder format"). Route directories to the sidebar instead and hand
    /// the rest to the normal document machinery.
    public func application(_ sender: NSApplication, openFiles filenames: [String]) {
        didOpenFilesAtLaunch = true
        var documentURLs: [URL] = []
        for path in filenames {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                openFolderInFrontWindow(URL(fileURLWithPath: path, isDirectory: true))
            } else {
                documentURLs.append(URL(fileURLWithPath: path))
            }
        }
        openFilesAsTabsInFrontWindow(documentURLs)
        sender.reply(toOpenOrPrint: .success)
    }

    /// Open `urls` as TABS in the front editor window via the same
    /// `EditorWindowController.openFiles(at:)` path the sidebar / editor-drop use.
    /// Creating one host (a blank untitled) first if none exists. Then replace a
    /// lone pristine untitled so we don't leave a stray blank tab.
    ///
    /// Routing every Finder/launch/app-icon-drag open through `openFiles(at:)` is
    /// what keeps multi-file opens as TABS under `tabbingMode = .automatic`: that
    /// method calls `addTabbedWindow` explicitly. Opening each file with an
    /// independent `openDocument(display:true)` (the old approach) relied on the
    /// `.preferred` force-merge and scattered the files into separate windows once
    /// the mode changed — the v2.7.0 regression this fixes.
    private func openFilesAsTabsInFrontWindow(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        openUntitledIfNoDocuments()
        guard let controller = NSApp.mainWindow?.windowController as? EditorWindowController
            ?? NSApp.windows.compactMap({ $0.windowController as? EditorWindowController }).first
        else { return }
        controller.openFiles(at: urls)
        // Replace a lone pristine Untitled host once the requested files have
        // opened. The open is async (openDocument), so retry until the files we
        // asked for are actually open (a stable condition — not the transient
        // pristine count), then trim a single leftover blank tab.
        scheduleLonePristineUntitledCleanup(awaiting: urls, retriesLeft: 12)
    }

    /// Once the `awaiting` files are all open, close a single leftover pristine
    /// (empty, never-edited) Untitled document so the open flow doesn't leave a
    /// stray blank tab. Retries on the main runloop while the async opens are
    /// still in flight (continuation is gated on "have the requested files
    /// appeared yet", which is monotonic — so a transient extra untitled can't
    /// abandon the cleanup), up to the retry budget. No-op when there is no lone
    /// pristine untitled or it's the only document.
    private func scheduleLonePristineUntitledCleanup(awaiting urls: [URL], retriesLeft: Int) {
        let openPaths = Set(NSDocumentController.shared.documents.compactMap { $0.fileURL?.standardizedFileURL.path })
        let allRequestedOpen = urls.allSatisfy { openPaths.contains($0.standardizedFileURL.path) }
        if allRequestedOpen {
            let pristine = NSDocumentController.shared.documents
                .compactMap { $0 as? TextDocument }
                .filter { $0.isPristineUntitled }
            // Trim a lone blank tab only when real files sit beside it.
            if pristine.count == 1, !openPaths.isEmpty { pristine[0].close() }
            return
        }
        guard retriesLeft > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.scheduleLonePristineUntitledCleanup(awaiting: urls, retriesLeft: retriesLeft - 1)
        }
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

    // MARK: Select All / Copy

    /// The editor window controller for the frontmost window, if any.
    private var frontEditor: EditorWindowController? {
        (NSApp.mainWindow ?? NSApp.keyWindow)?.windowController as? EditorWindowController
    }

    /// Send a standard editing selector down the responder chain, but only if the
    /// responder that would receive it says it is currently valid.
    ///
    /// `NSApp.sendAction(_:to:from:)` **bypasses validation**. For a `target: nil`
    /// menu item AppKit would first ask the responder chain via
    /// `validateUserInterfaceItem(_:)` and grey the item out when the answer is no,
    /// so the action never fires. Re-dispatching by hand skips that step — and
    /// `NSTextView.copy(_:)` with an empty selection is *not* a no-op: it clears
    /// the pasteboard. Forcing it destroyed the user's clipboard on a ⌘C that
    /// should have done nothing at all.
    ///
    /// Validating first restores the behavior a plain `target: nil` item had.
    static func sendValidatedAction(_ selector: Selector, from sender: Any?) {
        // Find the responder AppKit would dispatch to: the first one, walking up
        // from the first responder, that implements the selector.
        var responder = (NSApp.keyWindow ?? NSApp.mainWindow)?.firstResponder
        while let current = responder, !current.responds(to: selector) {
            responder = current.nextResponder
        }
        guard let handler = responder else { return }

        // Ask that responder whether the action is valid right now, exactly as
        // AppKit would before enabling a `target: nil` menu item.
        if let validator = handler as? NSUserInterfaceValidations {
            let probe = NSMenuItem(title: "", action: selector, keyEquivalent: "")
            guard validator.validateUserInterfaceItem(probe) else { return }
        }
        NSApp.sendAction(selector, to: nil, from: sender)
    }

    /// Edit ▸ Select All and Edit ▸ Copy are targeted here rather than left to the
    /// responder chain, because the chain cannot deliver them into the Markdown
    /// preview: `WKWebView` is first responder and swallows `selectAll:`/`copy:`,
    /// handling them against internal state that is not the page's DOM selection.
    ///
    /// The window controller decides what "focused area" means and, when the
    /// preview is hidden, hands the action straight back to the responder chain so
    /// the editor's native NSTextView behavior is untouched. A window that isn't an
    /// editor (e.g. Settings) falls back to the chain too, so text fields there
    /// still select and copy normally.
    /// Deliberately NOT named `selectAll:`/`copy:`. The fallback below re-dispatches
    /// the standard selectors through the responder chain, and `AppDelegate` is the
    /// chain's last resort — sharing a name would make that call re-enter this
    /// method and spin forever.
    @IBAction public func selectAllCommand(_ sender: Any?) {
        if let front = frontEditor {
            front.selectAllInFocusedArea(sender)
        } else {
            AppDelegate.sendValidatedAction(#selector(NSText.selectAll(_:)), from: sender)
        }
    }

    @IBAction public func copyCommand(_ sender: Any?) {
        if let front = frontEditor {
            front.copyFromFocusedArea(sender)
        } else {
            AppDelegate.sendValidatedAction(#selector(NSText.copy(_:)), from: sender)
        }
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

extension AppAppearance {
    /// Apply this appearance choice to the whole app (`NSApp.appearance`). Shared by
    /// launch (AppDelegate) and the Settings panel so both honor the same mapping.
    public static func applyToApp(_ appearance: AppAppearance) {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
