import AppKit

/// The Settings window. Edits the shared `Preferences`; changes propagate to all
/// open editors via `Preferences.didChangeNotification`. Built programmatically
/// with a simple stack layout (no nib).
public final class PreferencesWindowController: NSWindowController, NSWindowDelegate {

    private let prefs: Preferences
    private var fontLabel: NSTextField!
    private var appearancePopup: NSPopUpButton!
    private var lineNumbersCheck: NSButton!
    private var wrapCheck: NSButton!
    private var spacesCheck: NSButton!
    private var pcKeysCheck: NSButton!
    private var autoIndentCheck: NSButton!
    private var autoCloseCheck: NSButton!
    private var stripWSCheck: NSButton!
    private var tabWidthField: NSTextField!
    private var externalChangePopup: NSPopUpButton!
    private var sortFoldersFirstCheck: NSButton!
    private var sortAscendingCheck: NSButton!
    private var openOnSingleClickCheck: NSButton!
    private var sidebarOnRightCheck: NSButton!
    private var confirmDeleteCheck: NSButton!

    public init(preferences: Preferences = .shared) {
        self.prefs = preferences
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Settings"
        window.minSize = NSSize(width: 420, height: 240)
        super.init(window: window)
        window.delegate = self
        window.center()
        buildUI()
        syncFromPrefs()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: UI

    /// A top-left-origin container so the top-down Auto Layout below reads
    /// naturally and scrolls correctly inside an NSScrollView.
    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    private func buildUI() {
        guard let windowContent = window?.contentView else { return }
        // All controls live on this document view inside a scroll view, so the
        // settings scroll if they don't fit the window.
        let content = FlippedView()
        content.translatesAutoresizingMaskIntoConstraints = false

        func label(_ s: String) -> NSTextField {
            let f = NSTextField(labelWithString: s)
            f.alignment = .right
            f.translatesAutoresizingMaskIntoConstraints = false
            return f
        }

        // Font row
        let fontTitle = label("Font:")
        fontLabel = NSTextField(labelWithString: "")
        fontLabel.translatesAutoresizingMaskIntoConstraints = false
        let fontButton = NSButton(title: "Change…", target: self, action: #selector(chooseFont))
        fontButton.bezelStyle = .rounded
        fontButton.translatesAutoresizingMaskIntoConstraints = false

        // Appearance row
        let appearanceTitle = label("Appearance:")
        appearancePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        appearancePopup.translatesAutoresizingMaskIntoConstraints = false
        appearancePopup.addItems(withTitles: ["System", "Light", "Dark"])
        appearancePopup.target = self
        appearancePopup.action = #selector(appearanceChanged)

        // Checkboxes
        lineNumbersCheck = NSButton(checkboxWithTitle: "Show line numbers", target: self, action: #selector(checkChanged))
        wrapCheck = NSButton(checkboxWithTitle: "Wrap long lines", target: self, action: #selector(checkChanged))
        spacesCheck = NSButton(checkboxWithTitle: "Insert spaces instead of tabs", target: self, action: #selector(checkChanged))
        pcKeysCheck = NSButton(checkboxWithTitle: "PC-style Home/End/Insert keys",
                               target: self, action: #selector(checkChanged))
        pcKeysCheck.translatesAutoresizingMaskIntoConstraints = false
        autoIndentCheck = NSButton(checkboxWithTitle: "Auto-indent new lines",
                                   target: self, action: #selector(checkChanged))
        autoIndentCheck.translatesAutoresizingMaskIntoConstraints = false
        autoCloseCheck = NSButton(checkboxWithTitle: "Auto-close brackets",
                                  target: self, action: #selector(checkChanged))
        autoCloseCheck.translatesAutoresizingMaskIntoConstraints = false
        stripWSCheck = NSButton(checkboxWithTitle: "Strip trailing whitespace on save",
                                target: self, action: #selector(checkChanged))
        stripWSCheck.translatesAutoresizingMaskIntoConstraints = false
        [lineNumbersCheck, wrapCheck, spacesCheck].forEach { $0?.translatesAutoresizingMaskIntoConstraints = false }

        // Tab width
        let tabTitle = label("Tab width:")
        tabWidthField = NSTextField()
        tabWidthField.translatesAutoresizingMaskIntoConstraints = false
        tabWidthField.formatter = integerFormatter()
        tabWidthField.target = self
        tabWidthField.action = #selector(tabWidthChanged)

        // External-change policy row
        let externalChangeTitle = label("On external change:")
        externalChangePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        externalChangePopup.translatesAutoresizingMaskIntoConstraints = false
        externalChangePopup.addItems(withTitles: ["Notify", "Prompt", "Auto-reload if clean"])
        externalChangePopup.target = self
        externalChangePopup.action = #selector(externalChangePolicyChanged)

        // Sidebar checkboxes (everything that can reasonably be a toggle).
        sortFoldersFirstCheck = NSButton(checkboxWithTitle: "Sidebar: sort folders first",
                                         target: self, action: #selector(sidebarCheckChanged))
        sortAscendingCheck = NSButton(checkboxWithTitle: "Sidebar: sort A→Z (off = Z→A)",
                                      target: self, action: #selector(sidebarCheckChanged))
        openOnSingleClickCheck = NSButton(checkboxWithTitle: "Sidebar: open on single click",
                                          target: self, action: #selector(sidebarCheckChanged))
        sidebarOnRightCheck = NSButton(checkboxWithTitle: "Sidebar on the right",
                                       target: self, action: #selector(sidebarCheckChanged))
        confirmDeleteCheck = NSButton(checkboxWithTitle: "Sidebar: confirm before deleting",
                                      target: self, action: #selector(sidebarCheckChanged))
        [sortFoldersFirstCheck, sortAscendingCheck, openOnSingleClickCheck,
         sidebarOnRightCheck, confirmDeleteCheck].forEach { $0?.translatesAutoresizingMaskIntoConstraints = false }

        [fontTitle, fontLabel, fontButton, appearanceTitle, appearancePopup,
         lineNumbersCheck, wrapCheck, spacesCheck, pcKeysCheck, autoIndentCheck, autoCloseCheck,
         stripWSCheck, tabTitle, tabWidthField, externalChangeTitle, externalChangePopup,
         sortFoldersFirstCheck, sortAscendingCheck, openOnSingleClickCheck,
         sidebarOnRightCheck, confirmDeleteCheck]
            .forEach { content.addSubview($0!) }

        let leftCol: CGFloat = 110
        NSLayoutConstraint.activate([
            fontTitle.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            fontTitle.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            fontTitle.widthAnchor.constraint(equalToConstant: leftCol - 20),
            fontLabel.centerYAnchor.constraint(equalTo: fontTitle.centerYAnchor),
            fontLabel.leadingAnchor.constraint(equalTo: fontTitle.trailingAnchor, constant: 8),
            fontButton.centerYAnchor.constraint(equalTo: fontTitle.centerYAnchor),
            fontButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            appearanceTitle.topAnchor.constraint(equalTo: fontTitle.bottomAnchor, constant: 20),
            appearanceTitle.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            appearanceTitle.widthAnchor.constraint(equalToConstant: leftCol - 20),
            appearancePopup.centerYAnchor.constraint(equalTo: appearanceTitle.centerYAnchor),
            appearancePopup.leadingAnchor.constraint(equalTo: appearanceTitle.trailingAnchor, constant: 8),
            appearancePopup.widthAnchor.constraint(equalToConstant: 140),

            lineNumbersCheck.topAnchor.constraint(equalTo: appearanceTitle.bottomAnchor, constant: 20),
            lineNumbersCheck.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: leftCol),
            wrapCheck.topAnchor.constraint(equalTo: lineNumbersCheck.bottomAnchor, constant: 10),
            wrapCheck.leadingAnchor.constraint(equalTo: lineNumbersCheck.leadingAnchor),
            spacesCheck.topAnchor.constraint(equalTo: wrapCheck.bottomAnchor, constant: 10),
            spacesCheck.leadingAnchor.constraint(equalTo: lineNumbersCheck.leadingAnchor),
            pcKeysCheck.topAnchor.constraint(equalTo: spacesCheck.bottomAnchor, constant: 10),
            pcKeysCheck.leadingAnchor.constraint(equalTo: lineNumbersCheck.leadingAnchor),
            autoIndentCheck.topAnchor.constraint(equalTo: pcKeysCheck.bottomAnchor, constant: 10),
            autoIndentCheck.leadingAnchor.constraint(equalTo: lineNumbersCheck.leadingAnchor),
            autoCloseCheck.topAnchor.constraint(equalTo: autoIndentCheck.bottomAnchor, constant: 10),
            autoCloseCheck.leadingAnchor.constraint(equalTo: lineNumbersCheck.leadingAnchor),
            stripWSCheck.topAnchor.constraint(equalTo: autoCloseCheck.bottomAnchor, constant: 10),
            stripWSCheck.leadingAnchor.constraint(equalTo: lineNumbersCheck.leadingAnchor),

            tabTitle.topAnchor.constraint(equalTo: stripWSCheck.bottomAnchor, constant: 20),
            tabTitle.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            tabTitle.widthAnchor.constraint(equalToConstant: leftCol - 20),
            tabWidthField.centerYAnchor.constraint(equalTo: tabTitle.centerYAnchor),
            tabWidthField.leadingAnchor.constraint(equalTo: tabTitle.trailingAnchor, constant: 8),
            tabWidthField.widthAnchor.constraint(equalToConstant: 60),

            externalChangeTitle.topAnchor.constraint(equalTo: tabTitle.bottomAnchor, constant: 20),
            externalChangeTitle.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            externalChangeTitle.widthAnchor.constraint(equalToConstant: 130),
            externalChangePopup.centerYAnchor.constraint(equalTo: externalChangeTitle.centerYAnchor),
            externalChangePopup.leadingAnchor.constraint(equalTo: externalChangeTitle.trailingAnchor, constant: 8),
            externalChangePopup.widthAnchor.constraint(equalToConstant: 180),

            sortFoldersFirstCheck.topAnchor.constraint(equalTo: externalChangeTitle.bottomAnchor, constant: 18),
            sortFoldersFirstCheck.leadingAnchor.constraint(equalTo: lineNumbersCheck.leadingAnchor),
            sortAscendingCheck.topAnchor.constraint(equalTo: sortFoldersFirstCheck.bottomAnchor, constant: 10),
            sortAscendingCheck.leadingAnchor.constraint(equalTo: lineNumbersCheck.leadingAnchor),
            openOnSingleClickCheck.topAnchor.constraint(equalTo: sortAscendingCheck.bottomAnchor, constant: 10),
            openOnSingleClickCheck.leadingAnchor.constraint(equalTo: lineNumbersCheck.leadingAnchor),
            sidebarOnRightCheck.topAnchor.constraint(equalTo: openOnSingleClickCheck.bottomAnchor, constant: 10),
            sidebarOnRightCheck.leadingAnchor.constraint(equalTo: lineNumbersCheck.leadingAnchor),
            confirmDeleteCheck.topAnchor.constraint(equalTo: sidebarOnRightCheck.bottomAnchor, constant: 10),
            confirmDeleteCheck.leadingAnchor.constraint(equalTo: lineNumbersCheck.leadingAnchor),

            // Define the document view's size: fixed width, and a bottom anchored
            // below the last row so the scroll view knows the content height.
            content.widthAnchor.constraint(equalToConstant: 420),
            confirmDeleteCheck.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])

        // Host the content in a scroll view so Settings scroll if they don't fit.
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = content
        windowContent.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: windowContent.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: windowContent.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: windowContent.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: windowContent.bottomAnchor),
            // The document view's width tracks the scroll view (no horizontal scroll).
            content.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            content.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
        ])
    }

    private func integerFormatter() -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .none
        f.minimum = 1
        f.maximum = 16
        f.allowsFloats = false
        return f
    }

    // MARK: Sync

    private func syncFromPrefs() {
        fontLabel.stringValue = "\(prefs.fontName) \(Int(prefs.fontSize))"
        switch prefs.appearance {
        case .system: appearancePopup.selectItem(at: 0)
        case .light: appearancePopup.selectItem(at: 1)
        case .dark: appearancePopup.selectItem(at: 2)
        }
        lineNumbersCheck.state = prefs.showLineNumbers ? .on : .off
        wrapCheck.state = prefs.wrapLines ? .on : .off
        spacesCheck.state = prefs.insertSpacesForTab ? .on : .off
        pcKeysCheck.state = prefs.pcStyleNavigationKeys ? .on : .off
        autoIndentCheck.state = prefs.autoIndent ? .on : .off
        autoCloseCheck.state = prefs.autoCloseBrackets ? .on : .off
        stripWSCheck.state = prefs.stripTrailingWhitespaceOnSave ? .on : .off
        tabWidthField.integerValue = prefs.tabWidth
        switch prefs.externalChangePolicy {
        case .notify: externalChangePopup.selectItem(at: 0)
        case .prompt: externalChangePopup.selectItem(at: 1)
        case .autoIfClean: externalChangePopup.selectItem(at: 2)
        }
        sortFoldersFirstCheck.state = prefs.sidebarSortFoldersFirst ? .on : .off
        sortAscendingCheck.state = prefs.sidebarSortAscending ? .on : .off
        openOnSingleClickCheck.state = prefs.sidebarOpenOnSingleClick ? .on : .off
        sidebarOnRightCheck.state = prefs.sidebarOnRight ? .on : .off
        confirmDeleteCheck.state = prefs.confirmBeforeDelete ? .on : .off
        applyAppAppearance()
    }

    // MARK: Actions

    @objc private func chooseFont(_ sender: Any?) {
        let manager = NSFontManager.shared
        let current = NSFont(name: prefs.fontName, size: prefs.fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: prefs.fontSize, weight: .regular)
        manager.setSelectedFont(current, isMultiple: false)
        manager.target = self
        manager.action = #selector(changeFont(_:))
        manager.orderFrontFontPanel(sender)
    }

    /// Called by the shared font panel when the user picks a font.
    @objc public func changeFont(_ sender: Any?) {
        guard let manager = sender as? NSFontManager else { return }
        let current = NSFont(name: prefs.fontName, size: prefs.fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: prefs.fontSize, weight: .regular)
        let newFont = manager.convert(current)
        prefs.fontName = newFont.fontName
        prefs.fontSize = newFont.pointSize
        fontLabel.stringValue = "\(prefs.fontName) \(Int(prefs.fontSize))"
    }

    @objc private func appearanceChanged(_ sender: Any?) {
        switch appearancePopup.indexOfSelectedItem {
        case 1: prefs.appearance = .light
        case 2: prefs.appearance = .dark
        default: prefs.appearance = .system
        }
        applyAppAppearance()
    }

    @objc private func checkChanged(_ sender: NSButton) {
        prefs.showLineNumbers = lineNumbersCheck.state == .on
        prefs.wrapLines = wrapCheck.state == .on
        prefs.insertSpacesForTab = spacesCheck.state == .on
        prefs.pcStyleNavigationKeys = pcKeysCheck.state == .on
        prefs.autoIndent = autoIndentCheck.state == .on
        prefs.autoCloseBrackets = autoCloseCheck.state == .on
        prefs.stripTrailingWhitespaceOnSave = stripWSCheck.state == .on
    }

    @objc private func tabWidthChanged(_ sender: Any?) {
        prefs.tabWidth = max(1, tabWidthField.integerValue)
    }

    @objc private func externalChangePolicyChanged(_ sender: Any?) {
        switch externalChangePopup.indexOfSelectedItem {
        case 1: prefs.externalChangePolicy = .prompt
        case 2: prefs.externalChangePolicy = .autoIfClean
        default: prefs.externalChangePolicy = .notify
        }
    }

    @objc private func sidebarCheckChanged(_ sender: NSButton) {
        prefs.sidebarSortFoldersFirst = sortFoldersFirstCheck.state == .on
        prefs.sidebarSortAscending = sortAscendingCheck.state == .on
        prefs.sidebarOpenOnSingleClick = openOnSingleClickCheck.state == .on
        prefs.sidebarOnRight = sidebarOnRightCheck.state == .on
        prefs.confirmBeforeDelete = confirmDeleteCheck.state == .on
    }

    /// Apply the chosen appearance to the whole app.
    private func applyAppAppearance() {
        switch prefs.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
