import AppKit

/// A thin status bar shown at the bottom of an editor window. Dumb display: the
/// editor pushes values in. Shows position, language, encoding, and insert mode.
public final class StatusBarView: NSView {

    private let positionLabel = StatusBarView.makeLabel(align: .left)
    private let languageLabel = StatusBarView.makeLabel(align: .right)
    private let encodingLabel = StatusBarView.makeLabel(align: .right)
    private let modeLabel = StatusBarView.makeLabel(align: .right)

    public override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 22) }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let stack = NSStackView(views: [positionLabel, NSView(), languageLabel, sep(), encodingLabel, sep(), modeLabel])
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
        languageLabel.stringValue = language
        encodingLabel.stringValue = encoding
        modeLabel.stringValue = overwrite ? "OVR" : "INS"
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
}
