import AppKit

/// A small modal sheet asking for a line number. Calls `onGo` with the parsed
/// line; the caller validates the range and returns true on success (dismiss)
/// or false (invalid — keep the sheet open and beep).
public final class GoToLineSheet: NSObject {

    private var panel: NSPanel?
    private var field: NSTextField!
    private var onGo: ((Int) -> Bool)?

    /// Present the sheet on `window`. `onGo` receives the entered line number and
    /// returns whether navigation succeeded.
    public func present(on window: NSWindow, onGo: @escaping (Int) -> Bool) {
        self.onGo = onGo
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 100),
                            styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Go to Line"

        let label = NSTextField(labelWithString: "Line:")
        label.translatesAutoresizingMaskIntoConstraints = false
        field = NSTextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setAccessibilityIdentifier("goToLineField")
        field.formatter = {
            let f = NumberFormatter(); f.numberStyle = .none; f.allowsFloats = false; f.minimum = 1
            return f
        }()
        let go = NSButton(title: "Go", target: self, action: #selector(goTapped))
        go.keyEquivalent = "\r"
        go.bezelStyle = .rounded
        go.translatesAutoresizingMaskIntoConstraints = false
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.keyEquivalent = "\u{1b}"
        cancel.bezelStyle = .rounded
        cancel.translatesAutoresizingMaskIntoConstraints = false

        let content = panel.contentView!
        [label, field, go, cancel].forEach { content.addSubview($0) }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            label.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            field.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            field.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            field.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            cancel.trailingAnchor.constraint(equalTo: go.leadingAnchor, constant: -8),
            cancel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            go.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            go.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])

        self.panel = panel
        window.beginSheet(panel) { _ in }
        panel.makeFirstResponder(field)
    }

    @objc private func goTapped() {
        guard let window = panel?.sheetParent, let panel = panel else { return }
        let value = field.integerValue
        if value >= 1, onGo?(value) == true {
            window.endSheet(panel)
            self.panel = nil
        } else {
            NSSound.beep()   // invalid / out of range — keep sheet open
        }
    }

    @objc private func cancelTapped() {
        guard let window = panel?.sheetParent, let panel = panel else { return }
        window.endSheet(panel)
        self.panel = nil
    }
}
