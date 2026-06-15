import AppKit

/// A thin status bar shown at the bottom of an editor window. Dumb display: the
/// editor pushes values in. Shows position, language, encoding, and insert mode.
public final class StatusBarView: NSView {

    /// Called when the user picks a language id from the popup. "auto" means
    /// auto-detect; "plaintext" means no highlighting; otherwise a highlight.js id.
    public var onLanguagePick: ((String) -> Void)?

    /// Called when the user asks to re-decode the file bytes as a new encoding.
    public var onReinterpret: ((String.Encoding) -> Void)?
    /// Called when the user asks to re-encode (on next save) as a new encoding.
    public var onConvert: ((String.Encoding) -> Void)?
    /// Called when the user picks a line ending (LF / CRLF).
    public var onLineEndingPick: ((LineEnding) -> Void)?

    private let positionLabel = StatusBarView.makeLabel(align: .left)
    private let languageButton = StatusBarView.makeInlineButton()
    private let encodingButton = StatusBarView.makeInlineButton()
    private let lineEndingButton = StatusBarView.makeInlineButton()
    private let modeLabel = StatusBarView.makeLabel(align: .right)

    public override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 22) }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        languageButton.target = self
        languageButton.action = #selector(languageButtonClicked)
        encodingButton.target = self
        encodingButton.action = #selector(encodingButtonClicked)
        lineEndingButton.target = self
        lineEndingButton.action = #selector(lineEndingButtonClicked)

        let stack = NSStackView(views: [positionLabel, NSView(), languageButton, sep(), encodingButton, sep(), lineEndingButton, sep(), modeLabel])
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

    public func update(line: Int, column: Int, language: String, encoding: String,
                       lineEnding: LineEnding, overwrite: Bool) {
        positionLabel.stringValue = "Ln \(line), Col \(column)"
        languageButton.title = language
        encodingButton.title = encoding
        lineEndingButton.title = StatusBarView.lineEndingLabel(lineEnding)
        applyMode(overwrite: overwrite)
    }

    /// Short label with an OS hint, e.g. "LF (Unix/Linux)" / "CRLF (Windows)".
    private static func lineEndingLabel(_ ending: LineEnding) -> String {
        ending == .lf ? "LF (Unix/Linux)" : "CRLF (Windows)"
    }

    /// Style the INS/OVR field: plain in insert mode; an eye-catching (but not
    /// garish) filled accent "pill" in overwrite mode so the state is obvious.
    private func applyMode(overwrite: Bool) {
        if overwrite {
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            ]
            modeLabel.attributedStringValue = NSAttributedString(string: " OVR ", attributes: attrs)
            modeLabel.drawsBackground = true
            modeLabel.backgroundColor = NSColor.controlAccentColor
            modeLabel.wantsLayer = true
            modeLabel.layer?.cornerRadius = 3
            modeLabel.layer?.masksToBounds = true
        } else {
            modeLabel.drawsBackground = false
            modeLabel.layer?.backgroundColor = nil
            modeLabel.stringValue = "INS"
            modeLabel.textColor = .secondaryLabelColor
            modeLabel.font = .systemFont(ofSize: 11)
        }
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

    @objc private func encodingButtonClicked() {
        let menu = NSMenu()
        for entry in EncodingCatalog.selectable {
            let item = NSMenuItem(title: entry.displayName, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let re = NSMenuItem(title: "Reinterpret as \(entry.displayName)", action: #selector(reinterpretPicked(_:)), keyEquivalent: "")
            re.representedObject = entry.encoding.rawValue; re.target = self
            let conv = NSMenuItem(title: "Convert to \(entry.displayName)", action: #selector(convertPicked(_:)), keyEquivalent: "")
            conv.representedObject = entry.encoding.rawValue; conv.target = self
            sub.addItem(re); sub.addItem(conv)
            item.submenu = sub
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: encodingButton.bounds.height), in: encodingButton)
    }

    @objc private func reinterpretPicked(_ s: NSMenuItem) {
        if let raw = s.representedObject as? UInt { onReinterpret?(String.Encoding(rawValue: raw)) }
    }
    @objc private func convertPicked(_ s: NSMenuItem) {
        if let raw = s.representedObject as? UInt { onConvert?(String.Encoding(rawValue: raw)) }
    }

    @objc private func lineEndingButtonClicked() {
        let menu = NSMenu()
        for ending in [LineEnding.lf, .crlf] {
            let item = NSMenuItem(title: StatusBarView.lineEndingLabel(ending), action: #selector(lineEndingPicked(_:)), keyEquivalent: "")
            item.representedObject = ending.rawValue; item.target = self
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: lineEndingButton.bounds.height), in: lineEndingButton)
    }
    @objc private func lineEndingPicked(_ s: NSMenuItem) {
        if let raw = s.representedObject as? String, let e = LineEnding(rawValue: raw) { onLineEndingPick?(e) }
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
