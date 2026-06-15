import AppKit

/// A thin status bar shown at the bottom of an editor window. Dumb display: the
/// editor pushes values in. Shows position, language, encoding, and insert mode.
public final class StatusBarView: NSView {

    /// Called when the user picks a language id from the popup. "auto" means
    /// auto-detect; "plaintext" means no highlighting; otherwise a highlight.js id.
    public var onLanguagePick: ((String) -> Void)?

    private let positionLabel = StatusBarView.makeLabel(align: .left)
    private let languageButton = StatusBarView.makeInlineButton()
    private let encodingLabel = StatusBarView.makeLabel(align: .right)
    private let modeLabel = StatusBarView.makeLabel(align: .right)

    public override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 22) }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        languageButton.target = self
        languageButton.action = #selector(languageButtonClicked)

        let stack = NSStackView(views: [positionLabel, NSView(), languageButton, sep(), encodingLabel, sep(), modeLabel])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Top hairline.
        let top = NSBox(); top.boxType = .separator; top.translatesAutoresizingMaskIntoConstraints = false
        addSubview(top)
        NSLayoutConstraint.activate([
            top.leadingAnchor.constraint(equalTo: leadingAnchor),
            top.trailingAnchor.constraint(equalTo: trailingAnchor),
            top.topAnchor.constraint(equalTo: topAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func update(line: Int, column: Int, language: String, encoding: String, overwrite: Bool) {
        positionLabel.stringValue = "Ln \(line), Col \(column)"
        languageButton.title = language
        encodingLabel.stringValue = encoding
        modeLabel.stringValue = overwrite ? "OVR" : "INS"
    }

    @objc private func languageButtonClicked() {
        let menu = NSMenu()
        let auto = NSMenuItem(title: "Auto-Detect", action: #selector(pickLanguage(_:)), keyEquivalent: "")
        auto.representedObject = "auto"; auto.target = self
        menu.addItem(auto)
        let plain = NSMenuItem(title: "Plain Text", action: #selector(pickLanguage(_:)), keyEquivalent: "")
        plain.representedObject = "plaintext"; plain.target = self
        menu.addItem(plain)
        menu.addItem(.separator())
        for lang in LanguageCatalog.common {
            let item = NSMenuItem(title: lang.displayName, action: #selector(pickLanguage(_:)), keyEquivalent: "")
            item.representedObject = lang.id; item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let all = NSMenuItem(title: "All Languages…", action: nil, keyEquivalent: "")
        let allMenu = NSMenu()
        for lang in LanguageCatalog.all {
            let item = NSMenuItem(title: lang.displayName, action: #selector(pickLanguage(_:)), keyEquivalent: "")
            item.representedObject = lang.id; item.target = self
            allMenu.addItem(item)
        }
        all.submenu = allMenu
        menu.addItem(all)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: languageButton.bounds.height), in: languageButton)
    }

    @objc private func pickLanguage(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { onLanguagePick?(id) }
    }

    private func sep() -> NSView {
        let v = NSBox(); v.boxType = .separator; v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: 12).isActive = true
        return v
    }

    private static func makeLabel(align: NSTextAlignment) -> NSTextField {
        let f = NSTextField(labelWithString: "")
        f.font = .systemFont(ofSize: 11)
        f.textColor = .secondaryLabelColor
        f.alignment = align
        f.translatesAutoresizingMaskIntoConstraints = false
        return f
    }

    private static func makeInlineButton() -> NSButton {
        let b = NSButton(title: "", target: nil, action: nil)
        b.isBordered = false
        b.bezelStyle = .inline
        b.font = .systemFont(ofSize: 11)
        b.contentTintColor = .secondaryLabelColor
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }
}
