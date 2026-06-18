import AppKit

/// A thin non-blocking banner shown at the top of the editor when the file
/// changes on disk. Has a message, a Reload button, and a dismiss control.
public final class ReloadBanner: NSView {

    public var onReload: (() -> Void)?
    public var onDismiss: (() -> Void)?

    private let label = NSTextField(labelWithString: "")

    public override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 28) }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.18).cgColor

        label.font = .systemFont(ofSize: 11)
        label.lineBreakMode = .byTruncatingTail
        label.setAccessibilityIdentifier("reloadBannerLabel")
        let reload = NSButton(title: "Reload", target: self, action: #selector(reloadTapped))
        reload.bezelStyle = .rounded
        reload.controlSize = .small
        reload.setAccessibilityIdentifier("reloadButton")
        let dismiss = NSButton(title: "✕", target: self, action: #selector(dismissTapped))
        dismiss.bezelStyle = .inline
        dismiss.isBordered = false
        dismiss.setAccessibilityIdentifier("dismissReloadButton")

        let stack = NSStackView(views: [label, NSView(), reload, dismiss])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func show(message: String) {
        label.stringValue = message
        isHidden = false
    }

    public func hide() { isHidden = true }

    @objc private func reloadTapped() { onReload?() }
    @objc private func dismissTapped() { onDismiss?() }
}
