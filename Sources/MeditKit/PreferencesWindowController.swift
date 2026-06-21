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
    private var showDocumentStatsCheck: NSButton!
    private var reopenLastSessionCheck: NSButton!
    private var paddingField: NSTextField!
    private var rainbowBracketsCheck: NSButton!
    private var emphasizePairCheck: NSButton!
    private var autoRefreshPreviewCheck: NSButton!
    private var autoShowPreviewCheck: NSButton!
    private var showMarkdownToolbarCheck: NSButton!
    private var printLineNumbersCheck: NSButton!
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
    private var indentBetweenBracketsCheck: NSButton!
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
    /// A circular ⓘ help button that is muted gray at rest and brightens to the
    /// control accent color while the pointer is over it — discoverable on
    /// approach without a permanent column of blue.
    private final class HoverHelpButton: NSButton {
        private var tracking: NSTrackingArea?
        var restColor: NSColor = .secondaryLabelColor { didSet { if !hovering { contentTintColor = restColor } } }
        var hoverColor: NSColor = .controlAccentColor
        private var hovering = false

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let t = NSTrackingArea(rect: bounds,
                                   options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                   owner: self, userInfo: nil)
            addTrackingArea(t); tracking = t
        }
        override func mouseEntered(with event: NSEvent) {
            hovering = true; contentTintColor = hoverColor
        }
        override func mouseExited(with event: NSEvent) {
            hovering = false; contentTintColor = restColor
        }
    }

    /// Owns the shared help popover and the per-button help text, and shows the
    /// text in a popover anchored to the clicked ⓘ button. One instance per
    /// Settings window. Keeps help text discoverable without the slow,
    /// non-obvious system tooltip hover.
    private final class HelpButtonController: NSObject {
        static let axIdentifier = "settingsHelpButton"
        private let popover = NSPopover()
        private var textByButton: [ObjectIdentifier: String] = [:]
        private let textField = NSTextField(wrappingLabelWithString: "")

        override init() {
            super.init()
            popover.behavior = .transient
            popover.animates = true
            let vc = NSViewController()
            let container = NSView()
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.isEditable = false
            textField.isSelectable = false
            textField.drawsBackground = false
            textField.font = .systemFont(ofSize: 12)
            textField.preferredMaxLayoutWidth = 240
            container.addSubview(textField)
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
                textField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
                textField.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
                textField.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
                container.widthAnchor.constraint(equalToConstant: 264),
            ])
            vc.view = container
            popover.contentViewController = vc
        }

        /// Build a circular ⓘ help button (gray at rest, accent on hover) bound to `text`.
        func makeButton(text: String) -> NSButton {
            let button = HoverHelpButton()
            button.target = self
            button.action = #selector(show(_:))
            if let image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Help") {
                button.image = image
                button.isBordered = false
                button.imagePosition = .imageOnly
                (button.cell as? NSButtonCell)?.imageScaling = .scaleProportionallyDown
            } else {
                button.title = "?"
                button.bezelStyle = .helpButton
            }
            button.contentTintColor = button.restColor   // gray at rest; HoverHelpButton brightens on hover
            button.setAccessibilityHelp(text)
            button.toolTip = text                     // hover still works too
            // Shared id marks it as a help button (walkers exclude these); the
            // AXHelp text disambiguates individual buttons for UI tests.
            button.setAccessibilityIdentifier(HelpButtonController.axIdentifier)
            textByButton[ObjectIdentifier(button)] = text
            return button
        }

        @objc private func show(_ sender: NSButton) {
            guard let text = textByButton[ObjectIdentifier(sender)] else { return }
            if popover.isShown { popover.close() }
            textField.stringValue = text
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxX)
        }
    }

    private let helpButtons = HelpButtonController()

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

        // Build all controls. Each interactive control carries a help tooltip
        // (macOS standard): a short phrase describing the setting's effect,
        // sentence case, no trailing period. A test guards that none are missing.
        fontLabel = NSTextField(labelWithString: "")
        let fontButton = NSButton(title: "Change…", target: self, action: #selector(chooseFont))
        fontButton.bezelStyle = .rounded
        fontButton.toolTip = "Choose the editor's font family and size"

        appearancePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        appearancePopup.addItems(withTitles: ["System", "Light", "Dark"])
        appearancePopup.target = self
        appearancePopup.action = #selector(appearanceChanged)
        appearancePopup.toolTip = "Match the system appearance, or force a light or dark theme"

        lineNumbersCheck = check("Show line numbers", #selector(checkChanged))
        lineNumbersCheck.toolTip = "Display a line-number gutter down the left edge"
        wrapCheck = check("Wrap long lines", #selector(checkChanged))
        wrapCheck.toolTip = "Wrap text to the window width instead of scrolling horizontally"
        showStatusBarCheck = check("Show status bar", #selector(checkChanged))
        showStatusBarCheck.toolTip = "Show the bottom bar with line/column, language, and encoding"
        showInvisiblesCheck = check("Show invisibles", #selector(checkChanged))
        showInvisiblesCheck.toolTip = "Reveal spaces, tabs, and line breaks as faint marks"
        showDocumentStatsCheck = check("Show word/line count in status bar", #selector(checkChanged))
        showDocumentStatsCheck.toolTip = "Show a live word, line, and character count (and selection count) in the status bar"
        reopenLastSessionCheck = check("Reopen last session's files at launch", #selector(checkChanged))
        reopenLastSessionCheck.toolTip = "When medit starts, reopen the files you had open when you last quit"
        rainbowBracketsCheck = check("Rainbow brackets", #selector(checkChanged))
        rainbowBracketsCheck.toolTip = "Color brackets by nesting depth so matching pairs are easy to spot"
        emphasizePairCheck = check("Emphasize enclosing pair at caret", #selector(checkChanged))
        emphasizePairCheck.toolTip = "Highlight the bracket pair that surrounds the cursor"
        emphasisStylePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        emphasisStylePopup.addItems(withTitles: ["Bold", "Underline", "Background"])
        emphasisStylePopup.target = self
        emphasisStylePopup.action = #selector(emphasisStyleChanged)
        emphasisStylePopup.toolTip = "How the enclosing pair is emphasized: bold, underline, or background"

        autoRefreshPreviewCheck = check("Auto-refresh preview", #selector(checkChanged))
        autoRefreshPreviewCheck.toolTip = "Keep the Markdown preview up to date as you edit or the file changes"
        autoShowPreviewCheck = check("Auto-show preview for Markdown", #selector(checkChanged))
        autoShowPreviewCheck.toolTip = "Open the rendered preview automatically when you open a Markdown file"
        showMarkdownToolbarCheck = check("Show formatting toolbar", #selector(checkChanged))
        showMarkdownToolbarCheck.toolTip = "Show a formatting toolbar above Markdown documents for one-click bold, lists, headings, and more"
        printLineNumbersCheck = check("Print line numbers (plain text)", #selector(checkChanged))
        printLineNumbersCheck.toolTip = "Add line numbers and a filename header when printing plain or source files"

        let paddingTitle = label("Text padding:")
        paddingField = NSTextField()
        paddingField.formatter = paddingFormatter()
        paddingField.target = self
        paddingField.action = #selector(paddingChanged)
        paddingField.toolTip = "Blank space between the text and the editor's edges, in points"

        smartQuotesCheck = check("Smart quotes", #selector(smartSubstChanged))
        smartQuotesCheck.toolTip = "Convert straight quotes to curly typographic quotes as you type"
        smartDashesCheck = check("Smart dashes", #selector(smartSubstChanged))
        smartDashesCheck.toolTip = "Convert double hyphens to en and em dashes as you type"
        textReplacementCheck = check("Automatic text replacement", #selector(smartSubstChanged))
        textReplacementCheck.toolTip = "Apply your macOS text-replacement shortcuts while typing"
        spellingCorrectionCheck = check("Correct spelling automatically", #selector(smartSubstChanged))
        spellingCorrectionCheck.toolTip = "Fix misspellings automatically as you type"
        smartInsertDeleteCheck = check("Smart copy/paste spacing", #selector(smartSubstChanged))
        smartInsertDeleteCheck.toolTip = "Adjust spaces automatically when cutting and pasting words"
        continuousSpellCheck = check("Check spelling while typing", #selector(smartSubstChanged))
        continuousSpellCheck.toolTip = "Underline misspelled words as you type"

        spacesCheck = check("Insert spaces instead of tabs", #selector(checkChanged))
        spacesCheck.toolTip = "Indent with spaces rather than tab characters"
        let tabTitle = label("Tab width:")
        tabWidthField = NSTextField()
        tabWidthField.formatter = integerFormatter()
        tabWidthField.target = self
        tabWidthField.action = #selector(tabWidthChanged)
        tabWidthField.toolTip = "Number of spaces a tab represents"
        pcKeysCheck = check("PC-style Home/End/Insert keys", #selector(checkChanged))
        pcKeysCheck.toolTip = "Home/End jump to line start/end, and Insert toggles overwrite"
        autoIndentCheck = check("Auto-indent new lines", #selector(checkChanged))
        autoIndentCheck.toolTip = "Match the previous line's indentation on Return"
        indentBetweenBracketsCheck = check("Indent between brackets on Return", #selector(checkChanged))
        indentBetweenBracketsCheck.toolTip = "Pressing Return between a bracket pair opens an indented line between them"
        autoCloseCheck = check("Auto-close brackets", #selector(checkChanged))
        autoCloseCheck.toolTip = "Type an opening bracket and the matching closing one is inserted"
        stripWSCheck = check("Strip trailing whitespace on save", #selector(checkChanged))
        stripWSCheck.toolTip = "Remove trailing spaces and tabs from each line when saving"

        externalChangePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        externalChangePopup.addItems(withTitles: ["Notify", "Prompt", "Auto-reload if clean"])
        externalChangePopup.target = self
        externalChangePopup.action = #selector(externalChangePolicyChanged)
        externalChangePopup.toolTip = "What to do when a file changes on disk outside medit"

        sortFoldersFirstCheck = check("Sort folders first", #selector(sidebarCheckChanged))
        sortFoldersFirstCheck.toolTip = "List folders above files in the sidebar"
        sortAscendingCheck = check("Sort A→Z (off = Z→A)", #selector(sidebarCheckChanged))
        sortAscendingCheck.toolTip = "Sort sidebar entries alphabetically; turn off to reverse"
        openOnSingleClickCheck = check("Open on single click", #selector(sidebarCheckChanged))
        openOnSingleClickCheck.toolTip = "Open files with a single click instead of a double click"
        sidebarOnRightCheck = check("Sidebar on the right", #selector(sidebarCheckChanged))
        sidebarOnRightCheck.toolTip = "Place the file sidebar on the right side of the window"
        confirmDeleteCheck = check("Confirm before deleting", #selector(sidebarCheckChanged))
        confirmDeleteCheck.toolTip = "Ask for confirmation before moving an item to the Trash"
        revealActiveFileCheck = check("Reveal the active file", #selector(sidebarCheckChanged))
        revealActiveFileCheck.toolTip = "Select the current document in the sidebar as you switch tabs"

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
        stack.add(showDocumentStatsCheck, indent: checkIndent)
        stack.add(showInvisiblesCheck, indent: checkIndent)
        stack.addRow(label: paddingTitle, control: paddingField, controlWidth: 60)

        stack.add(header("Brackets"), gap: 18)
        stack.add(rainbowBracketsCheck, indent: checkIndent)
        stack.add(emphasizePairCheck, indent: checkIndent)
        stack.addRow(label: label("Enclosing-pair emphasis:"), control: emphasisStylePopup, controlWidth: 140)

        stack.add(header("Markdown"), gap: 18)
        stack.add(showMarkdownToolbarCheck, indent: checkIndent)
        stack.add(autoShowPreviewCheck, indent: checkIndent)
        stack.add(autoRefreshPreviewCheck, indent: checkIndent)

        stack.add(header("Printing"), gap: 18)
        stack.add(printLineNumbersCheck, indent: checkIndent)

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
        stack.add(indentBetweenBracketsCheck, indent: checkIndent)
        stack.add(autoCloseCheck, indent: checkIndent)
        stack.add(stripWSCheck, indent: checkIndent)

        stack.add(header("Files"), gap: 18)
        stack.add(reopenLastSessionCheck, indent: checkIndent)
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

        // Make help discoverable: place a standard ⓘ help button after each
        // interactive control, showing that control's help text in a popover on
        // click (the slow system tooltip alone wasn't obvious enough).
        attachHelpButtons(in: content)

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

    /// After layout, attach a ⓘ help button trailing every interactive control,
    /// using that control's existing `toolTip` as the popover text (single source
    /// of truth — no duplicated help strings). Help buttons themselves are
    /// skipped so we don't recurse.
    private func attachHelpButtons(in content: NSView) {
        // Snapshot the controls first; we mutate the tree while iterating.
        var controls: [NSControl] = []
        func walk(_ v: NSView) {
            if v is NSButton, v.accessibilityHelp() != nil,
               (v as? NSControl)?.toolTip == nil { /* skip our help buttons */ }
            if let popup = v as? NSPopUpButton { controls.append(popup) }
            else if let button = v as? NSButton, !(button.image?.isTemplate == true && button.title.isEmpty),
                    button.toolTip != nil { controls.append(button) }
            else if let field = v as? NSTextField, field.isEditable { controls.append(field) }
            v.subviews.forEach(walk)
        }
        walk(content)

        for control in controls {
            guard let text = control.toolTip, !text.isEmpty else { continue }
            let help = helpButtons.makeButton(text: text)
            help.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(help)
            NSLayoutConstraint.activate([
                help.leadingAnchor.constraint(equalTo: control.trailingAnchor, constant: 6),
                help.centerYAnchor.constraint(equalTo: control.centerYAnchor),
                help.widthAnchor.constraint(equalToConstant: 16),
                help.heightAnchor.constraint(equalToConstant: 16),
            ])
        }
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
        showDocumentStatsCheck.state = prefs.showDocumentStats ? .on : .off
        reopenLastSessionCheck.state = prefs.reopenLastSession ? .on : .off
        showInvisiblesCheck.state = prefs.showInvisibles ? .on : .off
        paddingField.integerValue = prefs.editorPadding
        rainbowBracketsCheck.state = prefs.rainbowBrackets ? .on : .off
        emphasizePairCheck.state = prefs.emphasizeEnclosingPair ? .on : .off
        autoRefreshPreviewCheck.state = prefs.autoRefreshPreview ? .on : .off
        autoShowPreviewCheck.state = prefs.autoShowPreviewForMarkdown ? .on : .off
        showMarkdownToolbarCheck.state = prefs.showMarkdownToolbar ? .on : .off
        printLineNumbersCheck.state = prefs.printLineNumbers ? .on : .off
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
        indentBetweenBracketsCheck.state = prefs.indentBetweenBrackets ? .on : .off
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
        prefs.showDocumentStats = showDocumentStatsCheck.state == .on
        prefs.reopenLastSession = reopenLastSessionCheck.state == .on
        prefs.showInvisibles = showInvisiblesCheck.state == .on
        prefs.rainbowBrackets = rainbowBracketsCheck.state == .on
        prefs.emphasizeEnclosingPair = emphasizePairCheck.state == .on
        prefs.autoRefreshPreview = autoRefreshPreviewCheck.state == .on
        prefs.autoShowPreviewForMarkdown = autoShowPreviewCheck.state == .on
        prefs.showMarkdownToolbar = showMarkdownToolbarCheck.state == .on
        prefs.printLineNumbers = printLineNumbersCheck.state == .on
        prefs.insertSpacesForTab = spacesCheck.state == .on
        prefs.pcStyleNavigationKeys = pcKeysCheck.state == .on
        prefs.autoIndent = autoIndentCheck.state == .on
        prefs.indentBetweenBrackets = indentBetweenBracketsCheck.state == .on
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
        AppAppearance.applyToApp(prefs.appearance)
    }

    // MARK: Testing

    /// Every interactive setting control in the window (checkboxes, popups, and
    /// editable value fields), found by walking the built view tree. Used by the
    /// tooltip-coverage test so a new control can't ship without a help tooltip.
    /// Excludes static labels/headers and the read-only font label.
    public func interactiveControlsForTesting() -> [NSControl] {
        guard let root = window?.contentView else { return [] }
        var found: [NSControl] = []
        func walk(_ view: NSView) {
            // Skip the ⓘ help buttons — they decorate the real controls and are
            // not themselves settings.
            if (view as? NSControl)?.accessibilityIdentifier() == HelpButtonController.axIdentifier {
                return
            }
            // Order matters: NSPopUpButton is an NSButton subclass, so match it
            // first. The only plain NSButtons in this window are the setting
            // checkboxes and the font "Change…" button — all want a tooltip.
            if let popup = view as? NSPopUpButton {
                found.append(popup)
            } else if let button = view as? NSButton {
                found.append(button)
            } else if let field = view as? NSTextField, field.isEditable {
                found.append(field)
            }
            view.subviews.forEach(walk)
        }
        walk(root)
        return found
    }

    /// The help text of every ⓘ help button in the window. Used by the help-button
    /// coverage test to prove each setting has a clickable, discoverable help
    /// affordance (not just a slow hover tooltip).
    public func helpButtonTextsForTesting() -> [String] {
        guard let root = window?.contentView else { return [] }
        var texts: [String] = []
        func walk(_ view: NSView) {
            if let button = view as? NSButton,
               button.accessibilityIdentifier() == HelpButtonController.axIdentifier,
               let help = button.accessibilityHelp() {
                texts.append(help)
            }
            view.subviews.forEach(walk)
        }
        walk(root)
        return texts
    }
}
