import Foundation

/// Clean-slate logic for the `--reset-state` launch flag used by the GUI test
/// driver (autopilot). A plain `removePersistentDomain` is not enough: macOS
/// window/state restoration reopens the last document and the sidebar's
/// security-scoped bookmarks must be explicitly cleared so no folder roots
/// survive into the next launch. This type centralizes that so it can be unit
/// tested headlessly; the app target wires the filesystem/AppKit side effects
/// (deleting the saved-state directory, disabling NSQuitAlwaysKeepsWindows) on
/// top via `LaunchReset.savedStateDirectory(bundleID:)`.
public enum LaunchReset {

    /// The launch argument that triggers a clean baseline.
    public static let flag = "--reset-state"

    /// Whether the given process arguments request a state reset.
    public static func isRequested(in arguments: [String]) -> Bool {
        arguments.contains(flag)
    }

    /// The launch argument that opens a folder into the sidebar at startup,
    /// used by the GUI test driver to seed a sidebar root without the
    /// NSOpenPanel (a system dialog autopilot cannot drive). Usage:
    /// `--open-folder /path/to/dir`.
    public static let openFolderFlag = "--open-folder"

    /// Extract the folder path following `--open-folder`, or nil if absent.
    public static func requestedFolderToOpen(in arguments: [String]) -> String? {
        guard let i = arguments.firstIndex(of: openFolderFlag),
              i + 1 < arguments.count else { return nil }
        let path = arguments[i + 1]
        return path.isEmpty ? nil : path
    }

    /// The launch argument that opens one or more files as TABS in the front
    /// window via the same `EditorWindowController.openFiles(at:)` entry point the
    /// sidebar and editor-drag use. This lets the GUI test driver exercise the
    /// "open into tabs" path that NSOpenPanel / Finder-drag would normally drive
    /// but autopilot cannot. Usage: `--open-files /a.txt /b.txt /c.txt`. Every
    /// argument after the flag up to the next `--flag` (or end) is a file path.
    public static let openFilesFlag = "--open-files"

    /// Extract the list of file paths following `--open-files` (stopping at the
    /// next `--`-prefixed argument), or [] if the flag is absent.
    public static func requestedFilesToOpen(in arguments: [String]) -> [String] {
        guard let i = arguments.firstIndex(of: openFilesFlag) else { return [] }
        var paths: [String] = []
        var j = i + 1
        while j < arguments.count, !arguments[j].hasPrefix("--") {
            if !arguments[j].isEmpty { paths.append(arguments[j]) }
            j += 1
        }
        return paths
    }

    /// The launch argument that suppresses the auto-open of the Markdown preview at
    /// document open, regardless of the `autoShowPreviewForMarkdown` preference. This
    /// is a GUI-test hook: a plan that opens a `.md` file to drive the EDITOR (or to
    /// toggle the preview from a known off state) needs a deterministic starting point
    /// that does not depend on the user-facing default. Usage: `--no-auto-preview`.
    public static let noAutoPreviewFlag = "--no-auto-preview"

    /// Whether the given process arguments request suppressing auto-preview.
    public static func isAutoPreviewSuppressed(in arguments: [String]) -> Bool {
        arguments.contains(noAutoPreviewFlag)
    }

    /// Wipe every persisted preference for the app, including the sidebar root
    /// bookmarks, from the given defaults. Clearing the whole domain *and* the
    /// individual keys is deliberate belt-and-suspenders: `removePersistentDomain`
    /// can leave registered/volatile values in place within a running process,
    /// so we also null the keys that would otherwise restore window content.
    public static func clearDefaults(_ defaults: UserDefaults, bundleID: String?) {
        if let bundleID { defaults.removePersistentDomain(forName: bundleID) }
        // Explicitly drop the sidebar roots so no folder reappears in the tree.
        defaults.removeObject(forKey: "sidebarRootBookmarks")
        // Window/tab autosave frames would otherwise restore stale geometry.
        defaults.removeObject(forKey: "NSWindow Frame medit.editor.window")
        defaults.removeObject(forKey: "NSSplitView Subview Frames medit.sidebar.split")
        // Belt-and-suspenders: also disable AppKit's "keep windows" restoration.
        defaults.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        defaults.synchronize()
    }

    /// Path to AppKit's saved-application-state bundle for this app. Deleting it
    /// before launch prevents the previously open document from being restored.
    /// Returns nil if no bundle id or no home directory is available.
    public static func savedStateDirectory(bundleID: String?) -> URL? {
        guard let bundleID else { return nil }
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        return library?
            .appendingPathComponent("Saved Application State", isDirectory: true)
            .appendingPathComponent("\(bundleID).savedState", isDirectory: true)
    }

    /// The shared `~/Library/Autosave Information` directory. NSDocument with
    /// `autosavesInPlace` keeps untitled documents here and reopens them on next
    /// launch — that is why a previously edited Untitled document comes back even
    /// after the defaults domain is wiped.
    public static var autosaveDirectory: URL? {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Autosave Information", isDirectory: true)
    }

    /// Names of this app's own files inside the shared Autosave Information
    /// directory: the bundle's tracking plist plus the "Unsaved <app> Document"
    /// text files AppKit names from the bundle display name. Only files whose
    /// name contains the bundle id or starts with "Unsaved <appName>" are
    /// returned, so the shared directory's other apps are never touched.
    public static func autosaveArtifacts(bundleID: String?, appName: String) -> [URL] {
        guard let dir = autosaveDirectory,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else { return [] }
        let unsavedPrefix = "Unsaved \(appName) Document"
        return entries.filter { url in
            let name = url.lastPathComponent
            if let bundleID, name.contains(bundleID) { return true }
            return name.hasPrefix(unsavedPrefix)
        }
    }

    /// Perform the full clean-slate reset for a real app launch: clear defaults,
    /// remove the saved-state directory so no window is restored, and delete this
    /// app's autosaved untitled documents so no prior content reopens.
    public static func perform(arguments: [String], bundleID: String?,
                               appName: String, defaults: UserDefaults) {
        guard isRequested(in: arguments) else { return }
        clearDefaults(defaults, bundleID: bundleID)
        if let dir = savedStateDirectory(bundleID: bundleID) {
            try? FileManager.default.removeItem(at: dir)
        }
        for url in autosaveArtifacts(bundleID: bundleID, appName: appName) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
