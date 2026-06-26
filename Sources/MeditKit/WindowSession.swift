import Foundation

/// One window's persisted session: its ordered tabs, which tab was frontmost, the
/// security-scoped bookmarks of the folders open in its sidebar, and its frame.
/// Pure value type — no AppKit — so it round-trips and is unit-tested in isolation.
public struct WindowSession: Codable, Equatable {
    public var tabPaths: [String]
    public var activeTabPath: String?
    public var sidebarFolderBookmarks: [Data]
    public var frame: String

    public init(tabPaths: [String], activeTabPath: String?,
                sidebarFolderBookmarks: [Data], frame: String) {
        self.tabPaths = tabPaths
        self.activeTabPath = activeTabPath
        self.sidebarFolderBookmarks = sidebarFolderBookmarks
        self.frame = frame
    }
}

/// Encode/decode the grouped session, and migrate the pre-multi-window flat list.
public enum SessionCodec {
    public static func encode(_ windows: [WindowSession]) -> Data {
        (try? JSONEncoder().encode(windows)) ?? Data()
    }

    public static func decode(_ data: Data) -> [WindowSession] {
        (try? JSONDecoder().decode([WindowSession].self, from: data)) ?? []
    }

    /// Old sessions stored a flat list of file paths (one global window of tabs).
    /// Restore them as exactly that: a single window holding all those tabs.
    public static func migrateFlat(_ paths: [String]) -> [WindowSession] {
        guard !paths.isEmpty else { return [] }
        return [WindowSession(tabPaths: paths, activeTabPath: nil,
                              sidebarFolderBookmarks: [], frame: "")]
    }
}
