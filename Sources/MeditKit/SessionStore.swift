import Foundation

/// Persists the per-window session (tabs, active tab, sidebar folders, frame) so
/// the full workspace reopens on next launch. Independent of macOS state
/// restoration (medit opts out to keep explicit window control). Migrates the old
/// flat `lastSessionFiles` list to one window of tabs on first read.
public final class SessionStore {

    public static let shared = SessionStore()

    private let prefs: Preferences

    public init(preferences: Preferences = .shared) {
        self.prefs = preferences
    }

    /// The saved windows. If the grouped store is empty but a legacy flat list
    /// exists, migrate it to a single window of tabs.
    public var windows: [WindowSession] {
        let grouped = SessionCodec.decode(prefs.sessionWindows)
        if !grouped.isEmpty { return grouped }
        return SessionCodec.migrateFlat(prefs.lastSessionFiles)
    }

    /// Replace the saved session with these windows.
    public func record(_ windows: [WindowSession]) {
        prefs.sessionWindows = SessionCodec.encode(windows)
    }

    public func clear() {
        prefs.sessionWindows = Data()
        prefs.lastSessionFiles = []
    }
}
