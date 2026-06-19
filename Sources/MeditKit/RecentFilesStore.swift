import Foundation

/// Tracks the files the user has opened/saved in medit, most-recent-first,
/// deduplicated and capped, persisted in `Preferences`. Backs the sidebar's
/// Recent pane. Independent of the system Open Recent menu.
public final class RecentFilesStore {

    public static let didChangeNotification = Notification.Name("medit.recentFilesDidChange")

    /// Shared instance backing the live app (UserDefaults-standard).
    public static let shared = RecentFilesStore()

    private let prefs: Preferences
    private let maxItems: Int

    public init(preferences: Preferences = .shared, maxItems: Int = 30) {
        self.prefs = preferences
        self.maxItems = max(1, maxItems)
    }

    /// Recent file URLs, most-recent first. Paths that no longer resolve are kept
    /// (the view dims them); only explicit remove/clear drop entries.
    public var urls: [URL] {
        prefs.recentFilePaths.map { URL(fileURLWithPath: $0) }
    }

    private func standardized(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Move `url` to the front (dedup by standardized path), cap to `maxItems`.
    public func record(_ url: URL) {
        let key = standardized(url)
        var paths = prefs.recentFilePaths.filter { standardized(URL(fileURLWithPath: $0)) != key }
        paths.insert(url.path, at: 0)
        if paths.count > maxItems { paths = Array(paths.prefix(maxItems)) }
        prefs.recentFilePaths = paths
        notify()
    }

    public func remove(_ url: URL) {
        let key = standardized(url)
        prefs.recentFilePaths = prefs.recentFilePaths.filter { standardized(URL(fileURLWithPath: $0)) != key }
        notify()
    }

    public func clear() {
        prefs.recentFilePaths = []
        notify()
    }

    private func notify() {
        NotificationCenter.default.post(name: RecentFilesStore.didChangeNotification, object: self)
    }
}
