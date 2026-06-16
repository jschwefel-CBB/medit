import AppKit

/// The file-browser sidebar. This task is a minimal collapsible stub; the outline
/// view and file logic land in later tasks. Holds a reference to its window
/// controller so it can open files / read the active document later.
public final class SidebarViewController: NSViewController {

    private let prefs: Preferences
    weak var windowController: EditorWindowController?

    public init(preferences: Preferences = .shared) {
        self.prefs = preferences
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func loadView() {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        // Minimum sensible sidebar width.
        v.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        self.view = v
    }

    /// Build/teardown the file tree + watchers. Stub for now (Task 5/6 fill in).
    public func activate() {}
    public func deactivate() {}
}
