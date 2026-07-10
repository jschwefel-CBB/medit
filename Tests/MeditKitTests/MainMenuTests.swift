import XCTest
import AppKit
@testable import MeditKit

/// Guards the File-menu shortcut contract. These are load-bearing: the AutoPilot
/// GUI plans drive menu items *by title* (`menuPath: ["File", "New Tab"]`) and the
/// README/MANUAL shortcut tables document the key equivalents, so a silent rename
/// or shortcut change breaks the test suite and the docs at the same time.
final class MainMenuTests: XCTestCase {

    /// `NSApp.delegate` is weak, so this holds the only strong reference for the
    /// lifetime of each test. Assigning a temporary would deallocate it before
    /// `MainMenu.build` reads it back, and the delegate requirement would trip.
    private var delegate: AppDelegate?

    /// `MainMenu.build` touches `NSApp.servicesMenu`, which traps if NSApplication
    /// has never been instantiated. Without this the suite passes only when some
    /// earlier test happens to have created NSApp first — an order dependency.
    ///
    /// It also requires a delegate to target Copy/Select All at, mirroring
    /// `main.swift`, which assigns one before `applicationDidFinishLaunching` runs
    /// the build. `AppDelegate.init` is inert — the side effects all live in
    /// `applicationDidFinishLaunching`, which nothing here calls.
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        let delegate = AppDelegate()
        self.delegate = delegate
        NSApp.delegate = delegate
    }

    /// Leaving a delegate installed would leak this test's `AppDelegate` into
    /// whatever runs next against the shared NSApp.
    override func tearDown() {
        NSApp.delegate = nil
        delegate = nil
        super.tearDown()
    }

    private func submenu(_ title: String) -> NSMenu {
        let main = MainMenu.build(appName: "medit")
        guard let found = main.items.first(where: { $0.submenu?.title == title })?.submenu else {
            XCTFail("no \(title) menu")
            return NSMenu()
        }
        return found
    }

    private func fileMenu() -> NSMenu { submenu("File") }

    private func item(_ title: String, in menu: NSMenu) -> NSMenuItem? {
        menu.items.first { $0.title == title }
    }

    // MARK: Shortcut contract

    func testNewWindowIsCommandN() {
        guard let newWindow = item("New Window", in: fileMenu()) else {
            return XCTFail("File ▸ New Window missing")
        }
        XCTAssertEqual(newWindow.keyEquivalent, "n")
        XCTAssertEqual(newWindow.keyEquivalentModifierMask, [.command],
                       "New Window must be plain ⌘N — no shift")
        XCTAssertEqual(newWindow.action, #selector(EditorWindowController.newWindowFromMenu(_:)))
    }

    func testNewTabIsCommandT() {
        guard let newTab = item("New Tab", in: fileMenu()) else {
            return XCTFail("File ▸ New Tab missing")
        }
        XCTAssertEqual(newTab.keyEquivalent, "t")
        XCTAssertEqual(newTab.keyEquivalentModifierMask, [.command])
        XCTAssertEqual(newTab.action, #selector(EditorWindowController.newWindowForTab(_:)))
    }

    /// The old "New" item (⌘N → new tab) was removed when ⌘N became New Window.
    /// If it comes back it will shadow New Window's shortcut.
    func testNoStandaloneNewItem() {
        XCTAssertNil(item("New", in: fileMenu()),
                     "File ▸ New was removed; ⌘T already opens a new untitled document")
    }

    /// ⇧⌘N is retired. Nothing in the File menu should claim it.
    func testNothingUsesShiftCommandN() {
        for item in fileMenu().items {
            let isShiftCmdN = item.keyEquivalent.lowercased() == "n"
                && item.keyEquivalentModifierMask.contains(.shift)
                && item.keyEquivalentModifierMask.contains(.command)
            XCTAssertFalse(isShiftCmdN, "⇧⌘N is retired but '\(item.title)' still claims it")
        }
    }

    /// Two items sharing a key equivalent means one of them silently never fires.
    func testFileMenuHasNoDuplicateShortcuts() {
        var seen: [String: String] = [:]   // "mods+key" -> first title that claimed it
        for item in fileMenu().items where !item.keyEquivalent.isEmpty {
            let key = "\(item.keyEquivalentModifierMask.rawValue)+\(item.keyEquivalent)"
            if let existing = seen[key] {
                XCTFail("'\(item.title)' collides with '\(existing)' on the same shortcut")
            }
            seen[key] = item.title
        }
    }

    // MARK: Titles the AutoPilot plans depend on

    /// uitests/*.json drive these by exact title via `menuPath`. A rename here
    /// silently breaks the GUI suite, which is why it's asserted.
    func testMenuTitlesUsedByGUITestPlansExist() {
        let file = fileMenu()
        for title in ["New Window", "New Tab", "Open…", "Close", "Print…"] {
            XCTAssertNotNil(item(title, in: file), "GUI plans reference File ▸ \(title)")
        }
    }

    // MARK: Copy / Select All must bypass the responder chain

    /// The bug this guards: with a nil target AppKit walks the responder chain and
    /// the preview's WKWebView — first responder, position 0 — swallows `copy:` and
    /// `selectAll:`, handling them against internal state that is not the DOM
    /// selection. `MainMenu.build` asserts the delegate exists, but `assert` is
    /// compiled out of release builds, so only this test stops a nil target from
    /// shipping.
    func testCopyAndSelectAllTargetTheDelegateExplicitly() {
        let edit = submenu("Edit")
        for title in ["Copy", "Select All"] {
            guard let found = item(title, in: edit) else {
                XCTFail("Edit ▸ \(title) missing")
                continue
            }
            XCTAssertTrue(found.target === delegate,
                          "Edit ▸ \(title) must target the delegate; a nil target is "
                          + "swallowed by the preview's web view")
        }
    }

    /// Targeting the delegate only helps if the item invokes the delegate's own
    /// command, not `NSText`'s — the latter would be sent to the delegate, go
    /// unhandled, and disable the item.
    func testCopyAndSelectAllInvokeTheDelegateCommands() {
        let edit = submenu("Edit")
        XCTAssertEqual(item("Copy", in: edit)?.action,
                       #selector(AppDelegate.copyCommand(_:)))
        XCTAssertEqual(item("Select All", in: edit)?.action,
                       #selector(AppDelegate.selectAllCommand(_:)))
    }
}
