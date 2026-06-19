import Foundation

/// Persists the set of files open at the end of a session so they can be reopened
/// on next launch. Independent of macOS state restoration (which medit opts out of
/// to keep explicit control of window placement). Mirrors `RecentFilesStore`.
public final class SessionStore {

    public static let shared = SessionStore()

    private let prefs: Preferences

    public init(preferences: Preferences = .shared) {
        self.prefs = preferences
    }

    /// The files saved from the last session, in order.
    public var files: [URL] {
        prefs.lastSessionFiles.map { URL(fileURLWithPath: $0) }
    }

    /// Replace the saved session with the given open files (order preserved,
    /// deduplicated by standardized path). Pass `[]` to record an empty session.
    public func record(_ urls: [URL]) {
        var seen = Set<String>()
        var paths: [String] = []
        for url in urls where url.isFileURL {
            let key = url.standardizedFileURL.resolvingSymlinksInPath().path
            if seen.insert(key).inserted { paths.append(url.path) }
        }
        prefs.lastSessionFiles = paths
    }

    public func clear() {
        prefs.lastSessionFiles = []
    }
}
