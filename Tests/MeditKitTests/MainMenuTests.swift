import XCTest
import AppKit
@testable import MeditKit

/// Guards the File-menu shortcut contract. These are load-bearing: the AutoPilot
/// GUI plans drive menu items *by title* (`menuPath: ["File", "New Tab"]`) and the
/// README/MANUAL shortcut tables document the key equivalents, so a silent rename
/// or shortcut change breaks the test suite and the docs at the same time.
final class MainMenuTests: XCTestCase {

    /// `MainMenu.build` touches `NSApp.servicesMenu`, which traps if NSApplication
    /// has never been instantiated. Without this the suite passes only when some
    /// earlier test happens to have created NSApp first — an order dependency.
    override func setUp() { super.setUp(); _ = NSApplication.shared }

    private func fileMenu() -> NSMenu {
        let main = MainMenu.build(appName: "medit")
        guard let file = main.items.first(where: { $0.submenu?.title == "File" })?.submenu else {
            XCTFail("no File menu")
            return NSMenu()
        }
        return file
    }

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
}
