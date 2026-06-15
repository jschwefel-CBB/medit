import Foundation

/// User-selectable window/syntax appearance.
public enum AppAppearance: String, CaseIterable {
    case system
    case light
    case dark
}

/// Typed wrapper over `UserDefaults` for medit's settings. A single shared
/// instance (`Preferences.shared`) backs the live app; tests inject an
/// ephemeral `UserDefaults` suite. Any setter posts `Preferences.didChange`
/// so open editors can react.
public final class Preferences {

    public static let shared = Preferences(defaults: .standard)

    /// Posted whenever any preference changes.
    public static let didChangeNotification = Notification.Name("medit.preferencesDidChange")

    public static let minFontSize: CGFloat = 6
    public static let maxFontSize: CGFloat = 96

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        registerDefaults()
    }

    private enum Key {
        static let showLineNumbers = "showLineNumbers"
        static let wrapLines = "wrapLines"
        static let showStatusBar = "showStatusBar"
        static let pcStyleNavigationKeys = "pcStyleNavigationKeys"
        static let appearance = "appearance"
        static let fontName = "fontName"
        static let fontSize = "fontSize"
        static let tabWidth = "tabWidth"
        static let insertSpacesForTab = "insertSpacesForTab"
        static let autoIndent = "autoIndent"
        static let autoCloseBrackets = "autoCloseBrackets"
        static let stripTrailingWhitespaceOnSave = "stripTrailingWhitespaceOnSave"
        static let showInvisibles = "showInvisibles"
        static let lightThemeName = "lightThemeName"
        static let darkThemeName = "darkThemeName"
        static let externalChangePolicy = "externalChangePolicy"
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Key.showLineNumbers: true,
            Key.wrapLines: false,
            Key.showStatusBar: true,
            Key.pcStyleNavigationKeys: true,
            Key.appearance: AppAppearance.system.rawValue,
            Key.fontName: "Menlo",
            Key.fontSize: 13.0,
            Key.tabWidth: 4,
            Key.insertSpacesForTab: true,
            Key.autoIndent: true,
            Key.autoCloseBrackets: true,
            Key.stripTrailingWhitespaceOnSave: true,
            Key.showInvisibles: false,
            Key.lightThemeName: "atom-one-light",
            Key.darkThemeName: "atom-one-dark",
            Key.externalChangePolicy: ExternalChangePolicy.notify.rawValue
        ])
    }

    private func didChange() {
        NotificationCenter.default.post(name: Preferences.didChangeNotification, object: self)
    }

    // MARK: Properties

    public var showLineNumbers: Bool {
        get { defaults.bool(forKey: Key.showLineNumbers) }
        set { defaults.set(newValue, forKey: Key.showLineNumbers); didChange() }
    }

    public var wrapLines: Bool {
        get { defaults.bool(forKey: Key.wrapLines) }
        set { defaults.set(newValue, forKey: Key.wrapLines); didChange() }
    }

    public var showStatusBar: Bool {
        get { defaults.bool(forKey: Key.showStatusBar) }
        set { defaults.set(newValue, forKey: Key.showStatusBar); didChange() }
    }

    public var pcStyleNavigationKeys: Bool {
        get { defaults.bool(forKey: Key.pcStyleNavigationKeys) }
        set { defaults.set(newValue, forKey: Key.pcStyleNavigationKeys); didChange() }
    }

    public var appearance: AppAppearance {
        get { AppAppearance(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Key.appearance); didChange() }
    }

    public var fontName: String {
        get { defaults.string(forKey: Key.fontName) ?? "Menlo" }
        set { defaults.set(newValue, forKey: Key.fontName); didChange() }
    }

    public var fontSize: CGFloat {
        get { CGFloat(defaults.double(forKey: Key.fontSize)) }
        set {
            let clamped = min(max(newValue, Preferences.minFontSize), Preferences.maxFontSize)
            defaults.set(Double(clamped), forKey: Key.fontSize)
            didChange()
        }
    }

    public var tabWidth: Int {
        get { defaults.integer(forKey: Key.tabWidth) }
        set { defaults.set(max(1, newValue), forKey: Key.tabWidth); didChange() }
    }

    public var insertSpacesForTab: Bool {
        get { defaults.bool(forKey: Key.insertSpacesForTab) }
        set { defaults.set(newValue, forKey: Key.insertSpacesForTab); didChange() }
    }

    public var autoIndent: Bool {
        get { defaults.bool(forKey: Key.autoIndent) }
        set { defaults.set(newValue, forKey: Key.autoIndent); didChange() }
    }

    public var autoCloseBrackets: Bool {
        get { defaults.bool(forKey: Key.autoCloseBrackets) }
        set { defaults.set(newValue, forKey: Key.autoCloseBrackets); didChange() }
    }

    public var stripTrailingWhitespaceOnSave: Bool {
        get { defaults.bool(forKey: Key.stripTrailingWhitespaceOnSave) }
        set { defaults.set(newValue, forKey: Key.stripTrailingWhitespaceOnSave); didChange() }
    }

    public var showInvisibles: Bool {
        get { defaults.bool(forKey: Key.showInvisibles) }
        set { defaults.set(newValue, forKey: Key.showInvisibles); didChange() }
    }

    public var lightThemeName: String {
        get { defaults.string(forKey: Key.lightThemeName) ?? "atom-one-light" }
        set { defaults.set(newValue, forKey: Key.lightThemeName); didChange() }
    }

    public var darkThemeName: String {
        get { defaults.string(forKey: Key.darkThemeName) ?? "atom-one-dark" }
        set { defaults.set(newValue, forKey: Key.darkThemeName); didChange() }
    }

    /// How medit reacts when an open file changes on disk.
    public var externalChangePolicy: ExternalChangePolicy {
        get { ExternalChangePolicy(rawValue: defaults.string(forKey: Key.externalChangePolicy) ?? "") ?? .notify }
        set { defaults.set(newValue.rawValue, forKey: Key.externalChangePolicy); didChange() }
    }

    /// The highlight.js theme name to use for the given effective appearance.
    public func highlightThemeName(forDarkMode darkMode: Bool) -> String {
        darkMode ? darkThemeName : lightThemeName
    }
}
