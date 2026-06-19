import AppKit

public protocol MarkdownStyleBarDelegate: AnyObject {
    func styleBar(_ bar: MarkdownStyleBar, didInvoke action: MarkdownStyleBar.Action)
}

/// A horizontal formatting toolbar for Markdown documents. Each button asks the
/// delegate to apply a Markdown transform to the editor's current selection.
/// Styled and sized like the find bar; collapses to zero height when hidden.
public final class MarkdownStyleBar: NSView {

    public enum Action: String, CaseIterable {
        case bold, italic, strikethrough, code, link
        case heading, bullet, ordered, quote, codeBlock

        var symbol: String {
            switch self {
            case .bold: return "bold"
            case .italic: return "italic"
            case .strikethrough: return "strikethrough"
            case .code: return "chevron.left.forwardslash.chevron.right"
            case .link: return "link"
            case .heading: return "textformat.size"
            case .bullet: return "list.bullet"
            case .ordered: return "list.number"
            case .quote: return "text.quote"
            case .codeBlock: return "curlybraces"
            }
        }
        var fallback: String {
            switch self {
            case .bold: return "B"; case .italic: return "I"; case .strikethrough: return "S"
            case .code: return "</>"; case .link: return "🔗"; case .heading: return "H"
            case .bullet: return "•"; case .ordered: return "1."; case .quote: return "❝"
            case .codeBlock: return "{ }"
            }
        }
        var help: String {
            switch self {
            case .bold: return "Bold (wrap in **)"
            case .italic: return "Italic (wrap in *)"
            case .strikethrough: return "Strikethrough (wrap in ~~)"
            case .code: return "Inline code (wrap in `)"
            case .link: return "Insert link [text](url)"
            case .heading: return "Heading"
            case .bullet: return "Bullet list"
            case .ordered: return "Numbered list"
            case .quote: return "Blockquote"
            case .codeBlock: return "Code block (``` fence)"
            }
        }
    }

    public weak var delegate: MarkdownStyleBarDelegate?

    public override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 30)
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }
    public required init?(coder: NSCoder) { super.init(coder: coder); build() }

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 10, bottom: 2, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Group inline buttons, a divider, then block buttons.
        let inline: [Action] = [.bold, .italic, .strikethrough, .code, .link]
        let blocks: [Action] = [.heading, .bullet, .ordered, .quote, .codeBlock]
        for a in inline { stack.addArrangedSubview(button(for: a)) }
        stack.addArrangedSubview(divider())
        for a in blocks { stack.addArrangedSubview(button(for: a)) }

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // Hairline at the bottom edge.
        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sep)
        NSLayoutConstraint.activate([
            sep.leadingAnchor.constraint(equalTo: leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: trailingAnchor),
            sep.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func button(for action: Action) -> NSButton {
        let b: NSButton
        if let img = NSImage(systemSymbolName: action.symbol, accessibilityDescription: action.help) {
            b = NSButton(image: img, target: self, action: #selector(invoke(_:)))
            b.imagePosition = .imageOnly
        } else {
            b = NSButton(title: action.fallback, target: self, action: #selector(invoke(_:)))
        }
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.toolTip = action.help
        b.setAccessibilityHelp(action.help)
        b.setAccessibilityIdentifier("mdStyle.\(action.rawValue)")
        b.tag = Action.allCases.firstIndex(of: action) ?? 0
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 26).isActive = true
        b.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return b
    }

    private func divider() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.heightAnchor.constraint(equalToConstant: 18).isActive = true
        box.widthAnchor.constraint(equalToConstant: 1).isActive = true
        return box
    }

    @objc private func invoke(_ sender: NSButton) {
        let action = Action.allCases[sender.tag]
        delegate?.styleBar(self, didInvoke: action)
    }

    /// Test hook: invoke an action as if its button were clicked.
    public func invokeForTesting(_ action: Action) {
        delegate?.styleBar(self, didInvoke: action)
    }
}
