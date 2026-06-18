import Foundation

/// User-selectable window/syntax appearance.
public enum AppAppearance: String, CaseIterable {
    case system
    case light
    case dark
}

/// How the caret's enclosing bracket pair is emphasized (rainbow brackets).
public enum EnclosingPairEmphasisStyle: String, CaseIterable {
    case bold
    case underline
    case background
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
        static let indentBetweenBrackets = "indentBetweenBrackets"
        static let autoCloseBrackets = "autoCloseBrackets"
        static let stripTrailingWhitespaceOnSave = "stripTrailingWhitespaceOnSave"
        static let showInvisibles = "showInvisibles"
        static let lightThemeName = "lightThemeName"
        static let darkThemeName = "darkThemeName"
        static let externalChangePolicy = "externalChangePolicy"
        static let showSidebar = "showSidebar"
        static let showHiddenFiles = "showHiddenFiles"
        static let syncSidebarWithActiveTab = "syncSidebarWithActiveTab"
        static let sidebarSortFoldersFirst = "sidebarSortFoldersFirst"
        static let sidebarSortAscending = "sidebarSortAscending"
        static let sidebarOpenOnSingleClick = "sidebarOpenOnSingleClick"
        static let sidebarOnRight = "sidebarOnRight"
        static let confirmBeforeDelete = "confirmBeforeDelete"
        static let sidebarRootBookmarks = "sidebarRootBookmarks"
        static let smartQuotes = "smartQuotes"
        static let smartDashes = "smartDashes"
        static let automaticTextReplacement = "automaticTextReplacement"
        static let automaticSpellingCorrection = "automaticSpellingCorrection"
        static let smartInsertDelete = "smartInsertDelete"
        static let continuousSpellChecking = "continuousSpellChecking"
        static let editorPadding = "editorPadding"
        static let rainbowBrackets = "rainbowBrackets"
        static let emphasizeEnclosingPair = "emphasizeEnclosingPair"
        static let enclosingPairEmphasisStyle = "enclosingPairEmphasisStyle"
        static let autoRefreshPreview = "autoRefreshPreview"
        static let autoShowPreviewForMarkdown = "autoShowPreviewForMarkdown"
        static let printLineNumbers = "printLineNumbers"
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
            Key.tabWidth: 2,
            Key.insertSpacesForTab: true,
            Key.autoIndent: true,
            Key.indentBetweenBrackets: true,
            Key.autoCloseBrackets: true,
            Key.stripTrailingWhitespaceOnSave: true,
            Key.showInvisibles: false,
            Key.lightThemeName: "atom-one-light",
            Key.darkThemeName: "atom-one-dark",
            Key.externalChangePolicy: ExternalChangePolicy.notify.rawValue,
            Key.showSidebar: false,
            Key.showHiddenFiles: false,
            Key.syncSidebarWithActiveTab: true,
            Key.sidebarSortFoldersFirst: true,
            Key.sidebarSortAscending: true,
            Key.sidebarOpenOnSingleClick: false,
            Key.sidebarOnRight: false,
            Key.confirmBeforeDelete: true,
            Key.sidebarRootBookmarks: [Data](),
            Key.smartQuotes: false,
            Key.smartDashes: false,
            Key.automaticTextReplacement: false,
            Key.automaticSpellingCorrection: false,
            Key.smartInsertDelete: false,
            Key.continuousSpellChecking: false,
            Key.editorPadding: 4,
            Key.rainbowBrackets: true,
            Key.emphasizeEnclosingPair: true,
            Key.enclosingPairEmphasisStyle: EnclosingPairEmphasisStyle.bold.rawValue,
            Key.autoRefreshPreview: true,
            Key.autoShowPreviewForMarkdown: false,
            Key.printLineNumbers: true
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
    /// Split a bracket pair onto three lines when Return is pressed between an
    /// opener and its matching closer (caret indented, closer pushed out).
    public var indentBetweenBrackets: Bool {
        get { defaults.bool(forKey: Key.indentBetweenBrackets) }
        set { defaults.set(newValue, forKey: Key.indentBetweenBrackets); didChange() }
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

    // MARK: Sidebar

    public var showSidebar: Bool {
        get { defaults.bool(forKey: Key.showSidebar) }
        set { defaults.set(newValue, forKey: Key.showSidebar); didChange() }
    }
    public var showHiddenFiles: Bool {
        get { defaults.bool(forKey: Key.showHiddenFiles) }
        set { defaults.set(newValue, forKey: Key.showHiddenFiles); didChange() }
    }
    public var syncSidebarWithActiveTab: Bool {
        get { defaults.bool(forKey: Key.syncSidebarWithActiveTab) }
        set { defaults.set(newValue, forKey: Key.syncSidebarWithActiveTab); didChange() }
    }
    public var sidebarSortFoldersFirst: Bool {
        get { defaults.bool(forKey: Key.sidebarSortFoldersFirst) }
        set { defaults.set(newValue, forKey: Key.sidebarSortFoldersFirst); didChange() }
    }
    public var sidebarSortAscending: Bool {
        get { defaults.bool(forKey: Key.sidebarSortAscending) }
        set { defaults.set(newValue, forKey: Key.sidebarSortAscending); didChange() }
    }
    public var sidebarOpenOnSingleClick: Bool {
        get { defaults.bool(forKey: Key.sidebarOpenOnSingleClick) }
        set { defaults.set(newValue, forKey: Key.sidebarOpenOnSingleClick); didChange() }
    }
    public var sidebarOnRight: Bool {
        get { defaults.bool(forKey: Key.sidebarOnRight) }
        set { defaults.set(newValue, forKey: Key.sidebarOnRight); didChange() }
    }
    public var confirmBeforeDelete: Bool {
        get { defaults.bool(forKey: Key.confirmBeforeDelete) }
        set { defaults.set(newValue, forKey: Key.confirmBeforeDelete); didChange() }
    }
    /// Security-scoped bookmarks for the sidebar's pinned root folders. Bookmarks
    /// (not plain paths) are what survive the app sandbox across launches.
    public var sidebarRootBookmarks: [Data] {
        get { (defaults.array(forKey: Key.sidebarRootBookmarks) as? [Data]) ?? [] }
        set { defaults.set(newValue, forKey: Key.sidebarRootBookmarks); didChange() }
    }

    // MARK: Editor smart behaviors
    // All default OFF — gedit-like plain-text behavior. Mirror NSTextView's
    // smart-substitution flags plus continuous spell-check (the red squiggles).

    public var smartQuotes: Bool {
        get { defaults.bool(forKey: Key.smartQuotes) }
        set { defaults.set(newValue, forKey: Key.smartQuotes); didChange() }
    }
    public var smartDashes: Bool {
        get { defaults.bool(forKey: Key.smartDashes) }
        set { defaults.set(newValue, forKey: Key.smartDashes); didChange() }
    }
    public var automaticTextReplacement: Bool {
        get { defaults.bool(forKey: Key.automaticTextReplacement) }
        set { defaults.set(newValue, forKey: Key.automaticTextReplacement); didChange() }
    }
    public var automaticSpellingCorrection: Bool {
        get { defaults.bool(forKey: Key.automaticSpellingCorrection) }
        set { defaults.set(newValue, forKey: Key.automaticSpellingCorrection); didChange() }
    }
    public var smartInsertDelete: Bool {
        get { defaults.bool(forKey: Key.smartInsertDelete) }
        set { defaults.set(newValue, forKey: Key.smartInsertDelete); didChange() }
    }
    public var continuousSpellChecking: Bool {
        get { defaults.bool(forKey: Key.continuousSpellChecking) }
        set { defaults.set(newValue, forKey: Key.continuousSpellChecking); didChange() }
    }
    /// Editor text-container inset (points), applied symmetrically. Clamped 0...40.
    public var editorPadding: Int {
        get { defaults.integer(forKey: Key.editorPadding) }
        set { defaults.set(min(40, max(0, newValue)), forKey: Key.editorPadding); didChange() }
    }

    // MARK: Rainbow brackets

    /// Master toggle for always-on depth coloring of brackets.
    public var rainbowBrackets: Bool {
        get { defaults.bool(forKey: Key.rainbowBrackets) }
        set { defaults.set(newValue, forKey: Key.rainbowBrackets); didChange() }
    }
    /// Emphasize the innermost pair enclosing the caret (on top of depth color).
    public var emphasizeEnclosingPair: Bool {
        get { defaults.bool(forKey: Key.emphasizeEnclosingPair) }
        set { defaults.set(newValue, forKey: Key.emphasizeEnclosingPair); didChange() }
    }
    /// How the enclosing pair is emphasized.
    public var enclosingPairEmphasisStyle: EnclosingPairEmphasisStyle {
        get { EnclosingPairEmphasisStyle(rawValue: defaults.string(forKey: Key.enclosingPairEmphasisStyle) ?? "") ?? .bold }
        set { defaults.set(newValue.rawValue, forKey: Key.enclosingPairEmphasisStyle); didChange() }
    }
    /// Keep the Markdown preview current from buffer edits and on-disk changes.
    public var autoRefreshPreview: Bool {
        get { defaults.bool(forKey: Key.autoRefreshPreview) }
        set { defaults.set(newValue, forKey: Key.autoRefreshPreview); didChange() }
    }
    /// Automatically show the preview when a Markdown document is opened.
    public var autoShowPreviewForMarkdown: Bool {
        get { defaults.bool(forKey: Key.autoShowPreviewForMarkdown) }
        set { defaults.set(newValue, forKey: Key.autoShowPreviewForMarkdown); didChange() }
    }
    /// Include line numbers and a filename header when printing plain/source files.
    public var printLineNumbers: Bool {
        get { defaults.bool(forKey: Key.printLineNumbers) }
        set { defaults.set(newValue, forKey: Key.printLineNumbers); didChange() }
    }

    /// The highlight.js theme name to use for the given effective appearance.
    public func highlightThemeName(forDarkMode darkMode: Bool) -> String {
        darkMode ? darkThemeName : lightThemeName
    }
}
