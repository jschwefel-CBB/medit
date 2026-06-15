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

    public init(preferences: Preferences = .shared) {
        self.prefs = preferences
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "Settings"
        super.init(window: window)
        window.delegate = self
        window.center()
        buildUI()
        syncFromPrefs()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: UI

    private func buildUI() {
        guard let content = window?.contentView else { return }

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

        [fontTitle, fontLabel, fontButton, appearanceTitle, appearancePopup,
         lineNumbersCheck, wrapCheck, spacesCheck, pcKeysCheck, autoIndentCheck, autoCloseCheck,
         stripWSCheck, tabTitle, tabWidthField]
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

    /// Apply the chosen appearance to the whole app.
    private func applyAppAppearance() {
        switch prefs.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
