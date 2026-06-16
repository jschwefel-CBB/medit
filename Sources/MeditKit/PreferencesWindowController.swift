import AppKit

/// The Settings window. Edits the shared `Preferences`; changes propagate to all
/// open editors via `Preferences.didChangeNotification`. Built programmatically
/// with a simple top-down stacked layout (no nib).
public final class PreferencesWindowController: NSWindowController, NSWindowDelegate {

    private let prefs: Preferences
    private var fontLabel: NSTextField!
    private var appearancePopup: NSPopUpButton!
    private var lineNumbersCheck: NSButton!
    private var wrapCheck: NSButton!
    private var showStatusBarCheck: NSButton!
    private var showInvisiblesCheck: NSButton!
    private var paddingField: NSTextField!
    private var rainbowBracketsCheck: NSButton!
    private var emphasizePairCheck: NSButton!
    private var emphasisStylePopup: NSPopUpButton!
    private var smartQuotesCheck: NSButton!
    private var smartDashesCheck: NSButton!
    private var textReplacementCheck: NSButton!
    private var spellingCorrectionCheck: NSButton!
    private var smartInsertDeleteCheck: NSButton!
    private var continuousSpellCheck: NSButton!
    private var spacesCheck: NSButton!
    private var tabWidthField: NSTextField!
    private var pcKeysCheck: NSButton!
    private var autoIndentCheck: NSButton!
    private var autoCloseCheck: NSButton!
    private var stripWSCheck: NSButton!
    private var externalChangePopup: NSPopUpButton!
    private var sortFoldersFirstCheck: NSButton!
    private var sortAscendingCheck: NSButton!
    private var openOnSingleClickCheck: NSButton!
    private var sidebarOnRightCheck: NSButton!
    private var confirmDeleteCheck: NSButton!
    private var revealActiveFileCheck: NSButton!

    public init(preferences: Preferences = .shared) {
        self.prefs = preferences
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Settings"
        window.minSize = NSSize(width: 460, height: 300)
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

    /// Vertical row stacker: each appended view is pinned below the previous one
    /// at the left margin, so adding/reordering rows needs no anchor surgery.
    private final class RowStacker {
        let container: NSView
        private let leftInset: CGFloat
        private let topInset: CGFloat
        private var last: NSLayoutAnchor<NSLayoutYAxisAnchor>
        private(set) var lastView: NSView?
        init(container: NSView, topInset: CGFloat, leftInset: CGFloat) {
            self.container = container
            self.leftInset = leftInset
            self.topInset = topInset
            self.last = container.topAnchor
            self.lastView = nil
        }
        /// Pin `view` below the previous row. `indent` shifts the leading edge
        /// (e.g. checkboxes under a header). `gap` is the vertical spacing.
        func add(_ view: NSView, gap: CGFloat = 10, indent: CGFloat = 0) {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
            let topConstant = (lastView == nil) ? topInset : gap
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: last, constant: topConstant),
                view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: leftInset + indent),
            ])
            last = view.bottomAnchor
            lastView = view
        }
        /// Pin a label+control pair on one row (control to the right of the label).
        func addRow(label: NSView, control: NSView, gap: CGFloat = 14,
                    controlLeading: CGFloat = 8, controlWidth: CGFloat? = nil, indent: CGFloat = 0) {
            label.translatesAutoresizingMaskIntoConstraints = false
            control.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(label)
            container.addSubview(control)
            let topConstant = (lastView == nil) ? topInset : gap
            var cons: [NSLayoutConstraint] = [
                label.topAnchor.constraint(equalTo: last, constant: topConstant),
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: leftInset + indent),
                control.centerYAnchor.constraint(equalTo: label.centerYAnchor),
                control.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: controlLeading),
            ]
            if let w = controlWidth { cons.append(control.widthAnchor.constraint(equalToConstant: w)) }
            NSLayoutConstraint.activate(cons)
            last = label.bottomAnchor
            lastView = label
        }
        /// Close the document view's height at the last row.
        func finish(bottomInset: CGFloat) {
            guard let lastView else { return }
            lastView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: bottomInset).isActive = true
        }
    }

    private func buildUI() {
        guard let windowContent = window?.contentView else { return }
        let content = FlippedView()
        content.translatesAutoresizingMaskIntoConstraints = false

        func label(_ s: String) -> NSTextField {
            let f = NSTextField(labelWithString: s)
            f.alignment = .right
            f.translatesAutoresizingMaskIntoConstraints = false
            return f
        }
        func header(_ s: String) -> NSTextField {
            let f = NSTextField(labelWithString: s)
            f.font = .boldSystemFont(ofSize: 12)
            f.textColor = .secondaryLabelColor
            f.translatesAutoresizingMaskIntoConstraints = false
            return f
        }
        func check(_ title: String, _ action: Selector) -> NSButton {
            NSButton(checkboxWithTitle: title, target: self, action: action)
        }

        // Build all controls.
        fontLabel = NSTextField(labelWithString: "")
        let fontButton = NSButton(title: "Change…", target: self, action: #selector(chooseFont))
        fontButton.bezelStyle = .rounded

        appearancePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        appearancePopup.addItems(withTitles: ["System", "Light", "Dark"])
        appearancePopup.target = self
        appearancePopup.action = #selector(appearanceChanged)

        lineNumbersCheck = check("Show line numbers", #selector(checkChanged))
        wrapCheck = check("Wrap long lines", #selector(checkChanged))
        showStatusBarCheck = check("Show status bar", #selector(checkChanged))
        showInvisiblesCheck = check("Show invisibles", #selector(checkChanged))
        rainbowBracketsCheck = check("Rainbow brackets", #selector(checkChanged))
        emphasizePairCheck = check("Emphasize enclosing pair at caret", #selector(checkChanged))
        emphasisStylePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        emphasisStylePopup.addItems(withTitles: ["Bold", "Underline", "Background"])
        emphasisStylePopup.target = self
        emphasisStylePopup.action = #selector(emphasisStyleChanged)

        let paddingTitle = label("Text padding:")
        paddingField = NSTextField()
        paddingField.formatter = paddingFormatter()
        paddingField.target = self
        paddingField.action = #selector(paddingChanged)

        smartQuotesCheck = check("Smart quotes", #selector(smartSubstChanged))
        smartDashesCheck = check("Smart dashes", #selector(smartSubstChanged))
        textReplacementCheck = check("Automatic text replacement", #selector(smartSubstChanged))
        spellingCorrectionCheck = check("Correct spelling automatically", #selector(smartSubstChanged))
        smartInsertDeleteCheck = check("Smart copy/paste spacing", #selector(smartSubstChanged))
        continuousSpellCheck = check("Check spelling while typing", #selector(smartSubstChanged))

        spacesCheck = check("Insert spaces instead of tabs", #selector(checkChanged))
        let tabTitle = label("Tab width:")
        tabWidthField = NSTextField()
        tabWidthField.formatter = integerFormatter()
        tabWidthField.target = self
        tabWidthField.action = #selector(tabWidthChanged)
        pcKeysCheck = check("PC-style Home/End/Insert keys", #selector(checkChanged))
        autoIndentCheck = check("Auto-indent new lines", #selector(checkChanged))
        autoCloseCheck = check("Auto-close brackets", #selector(checkChanged))
        stripWSCheck = check("Strip trailing whitespace on save", #selector(checkChanged))

        externalChangePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        externalChangePopup.addItems(withTitles: ["Notify", "Prompt", "Auto-reload if clean"])
        externalChangePopup.target = self
        externalChangePopup.action = #selector(externalChangePolicyChanged)

        sortFoldersFirstCheck = check("Sort folders first", #selector(sidebarCheckChanged))
        sortAscendingCheck = check("Sort A→Z (off = Z→A)", #selector(sidebarCheckChanged))
        openOnSingleClickCheck = check("Open on single click", #selector(sidebarCheckChanged))
        sidebarOnRightCheck = check("Sidebar on the right", #selector(sidebarCheckChanged))
        confirmDeleteCheck = check("Confirm before deleting", #selector(sidebarCheckChanged))
        revealActiveFileCheck = check("Reveal the active file", #selector(sidebarCheckChanged))

        // Stack everything top-down with section headers.
        let leftMargin: CGFloat = 20
        let checkIndent: CGFloat = 90      // align checkboxes under a label column
        let stack = RowStacker(container: content, topInset: 24, leftInset: leftMargin)

        stack.addRow(label: label("Font:"), control: fontLabel, controlWidth: nil)
        // Put the Change… button on the same baseline as the font label.
        content.addSubview(fontButton)
        fontButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            fontButton.centerYAnchor.constraint(equalTo: fontLabel.centerYAnchor),
            fontButton.leadingAnchor.constraint(equalTo: fontLabel.trailingAnchor, constant: 8),
        ])
        stack.addRow(label: label("Appearance:"), control: appearancePopup, controlWidth: 140)

        stack.add(header("Editor"), gap: 18)
        stack.add(lineNumbersCheck, indent: checkIndent)
        stack.add(wrapCheck, indent: checkIndent)
        stack.add(showStatusBarCheck, indent: checkIndent)
        stack.add(showInvisiblesCheck, indent: checkIndent)
        stack.addRow(label: paddingTitle, control: paddingField, controlWidth: 60)

        stack.add(header("Brackets"), gap: 18)
        stack.add(rainbowBracketsCheck, indent: checkIndent)
        stack.add(emphasizePairCheck, indent: checkIndent)
        stack.addRow(label: label("Enclosing-pair emphasis:"), control: emphasisStylePopup, controlWidth: 140)

        stack.add(header("Smart Substitutions"), gap: 18)
        stack.add(smartQuotesCheck, indent: checkIndent)
        stack.add(smartDashesCheck, indent: checkIndent)
        stack.add(textReplacementCheck, indent: checkIndent)
        stack.add(spellingCorrectionCheck, indent: checkIndent)
        stack.add(smartInsertDeleteCheck, indent: checkIndent)
        stack.add(continuousSpellCheck, indent: checkIndent)

        stack.add(header("Indentation"), gap: 18)
        stack.add(spacesCheck, indent: checkIndent)
        stack.addRow(label: tabTitle, control: tabWidthField, controlWidth: 60)
        stack.add(pcKeysCheck, indent: checkIndent)
        stack.add(autoIndentCheck, indent: checkIndent)
        stack.add(autoCloseCheck, indent: checkIndent)
        stack.add(stripWSCheck, indent: checkIndent)

        stack.add(header("Files"), gap: 18)
        stack.addRow(label: label("On external change:"), control: externalChangePopup, controlWidth: 180)

        stack.add(header("Sidebar"), gap: 18)
        stack.add(sortFoldersFirstCheck, indent: checkIndent)
        stack.add(sortAscendingCheck, indent: checkIndent)
        stack.add(openOnSingleClickCheck, indent: checkIndent)
        stack.add(sidebarOnRightCheck, indent: checkIndent)
        stack.add(confirmDeleteCheck, indent: checkIndent)
        stack.add(revealActiveFileCheck, indent: checkIndent)

        stack.finish(bottomInset: -20)
        content.widthAnchor.constraint(equalToConstant: 460).isActive = true

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

    private func paddingFormatter() -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .none
        f.minimum = 0
        f.maximum = 40
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
        showStatusBarCheck.state = prefs.showStatusBar ? .on : .off
        showInvisiblesCheck.state = prefs.showInvisibles ? .on : .off
        paddingField.integerValue = prefs.editorPadding
        rainbowBracketsCheck.state = prefs.rainbowBrackets ? .on : .off
        emphasizePairCheck.state = prefs.emphasizeEnclosingPair ? .on : .off
        switch prefs.enclosingPairEmphasisStyle {
        case .bold: emphasisStylePopup.selectItem(at: 0)
        case .underline: emphasisStylePopup.selectItem(at: 1)
        case .background: emphasisStylePopup.selectItem(at: 2)
        }
        smartQuotesCheck.state = prefs.smartQuotes ? .on : .off
        smartDashesCheck.state = prefs.smartDashes ? .on : .off
        textReplacementCheck.state = prefs.automaticTextReplacement ? .on : .off
        spellingCorrectionCheck.state = prefs.automaticSpellingCorrection ? .on : .off
        smartInsertDeleteCheck.state = prefs.smartInsertDelete ? .on : .off
        continuousSpellCheck.state = prefs.continuousSpellChecking ? .on : .off
        spacesCheck.state = prefs.insertSpacesForTab ? .on : .off
        tabWidthField.integerValue = prefs.tabWidth
        pcKeysCheck.state = prefs.pcStyleNavigationKeys ? .on : .off
        autoIndentCheck.state = prefs.autoIndent ? .on : .off
        autoCloseCheck.state = prefs.autoCloseBrackets ? .on : .off
        stripWSCheck.state = prefs.stripTrailingWhitespaceOnSave ? .on : .off
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
        revealActiveFileCheck.state = prefs.syncSidebarWithActiveTab ? .on : .off
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
        prefs.showStatusBar = showStatusBarCheck.state == .on
        prefs.showInvisibles = showInvisiblesCheck.state == .on
        prefs.rainbowBrackets = rainbowBracketsCheck.state == .on
        prefs.emphasizeEnclosingPair = emphasizePairCheck.state == .on
        prefs.insertSpacesForTab = spacesCheck.state == .on
        prefs.pcStyleNavigationKeys = pcKeysCheck.state == .on
        prefs.autoIndent = autoIndentCheck.state == .on
        prefs.autoCloseBrackets = autoCloseCheck.state == .on
        prefs.stripTrailingWhitespaceOnSave = stripWSCheck.state == .on
    }

    @objc private func smartSubstChanged(_ sender: NSButton) {
        prefs.smartQuotes = smartQuotesCheck.state == .on
        prefs.smartDashes = smartDashesCheck.state == .on
        prefs.automaticTextReplacement = textReplacementCheck.state == .on
        prefs.automaticSpellingCorrection = spellingCorrectionCheck.state == .on
        prefs.smartInsertDelete = smartInsertDeleteCheck.state == .on
        prefs.continuousSpellChecking = continuousSpellCheck.state == .on
    }

    @objc private func tabWidthChanged(_ sender: Any?) {
        prefs.tabWidth = max(1, tabWidthField.integerValue)
    }

    @objc private func paddingChanged(_ sender: Any?) {
        prefs.editorPadding = paddingField.integerValue
    }

    @objc private func emphasisStyleChanged(_ sender: Any?) {
        switch emphasisStylePopup.indexOfSelectedItem {
        case 1: prefs.enclosingPairEmphasisStyle = .underline
        case 2: prefs.enclosingPairEmphasisStyle = .background
        default: prefs.enclosingPairEmphasisStyle = .bold
        }
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
        prefs.syncSidebarWithActiveTab = revealActiveFileCheck.state == .on
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
