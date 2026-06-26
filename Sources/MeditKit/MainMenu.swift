import AppKit

/// Builds medit's menu bar programmatically (no storyboard). Standard macOS
/// layout — App / File / Edit / Find / View / Window / Help — wired to the
/// document-architecture first-responder actions so the editor behaves like a
/// native Mac app (real ⌘-shortcuts, undo/cut/copy/paste, services, etc.).
public enum MainMenu {

    public static func build(appName: String) -> NSMenu {
        let mainMenu = NSMenu()

        mainMenu.addItem(appMenuItem(appName: appName))
        mainMenu.addItem(fileMenuItem())
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(findMenuItem())
        mainMenu.addItem(viewMenuItem())
        mainMenu.addItem(windowMenuItem())
        mainMenu.addItem(helpMenuItem(appName: appName))

        return mainMenu
    }

    // MARK: App menu

    private static func appMenuItem(appName: String) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu()

        menu.addItem(withTitle: "About \(appName)",
                     action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…",
                                  action: #selector(AppDelegate.showPreferences(_:)), keyEquivalent: ",")
        menu.addItem(settings)
        menu.addItem(.separator())

        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu()
        services.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        menu.addItem(services)
        menu.addItem(.separator())

        menu.addItem(withTitle: "Hide \(appName)",
                     action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others",
                                    action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)
        menu.addItem(withTitle: "Show All",
                     action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(appName)",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        item.submenu = menu
        return item
    }

    // MARK: File

    private static func fileMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "File")

        // ⌘N = new TAB (tabs are the default). ⌘T = new tab too (explicit). New
        // Window (⇧⌘N) is the only path that makes a separate window.
        menu.addItem(withTitle: "New",
                     action: #selector(EditorWindowController.newTabFromMenu(_:)), keyEquivalent: "n")
        menu.addItem(withTitle: "New Tab",
                     action: #selector(EditorWindowController.newWindowForTab(_:)), keyEquivalent: "t")
        let newWindow = NSMenuItem(title: "New Window",
                                   action: #selector(EditorWindowController.newWindowFromMenu(_:)), keyEquivalent: "n")
        newWindow.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(newWindow)
        menu.addItem(withTitle: "Open…",
                     action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        let openFolder = NSMenuItem(title: "Open Folder…",
                                    action: #selector(EditorWindowController.openFolder(_:)), keyEquivalent: "o")
        openFolder.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(openFolder)

        let openRecent = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        let clear = NSMenuItem(title: "Clear Menu",
                               action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        recentMenu.addItem(clear)
        openRecent.submenu = recentMenu
        menu.addItem(openRecent)
        menu.addItem(.separator())

        menu.addItem(withTitle: "Close",
                     action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        menu.addItem(withTitle: "Save…",
                     action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        let saveAs = NSMenuItem(title: "Save As…",
                                action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "S")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(saveAs)
        menu.addItem(withTitle: "Revert to Saved",
                     action: #selector(NSDocument.revertToSaved(_:)), keyEquivalent: "")
        menu.addItem(.separator())

        menu.addItem(withTitle: "Page Setup…",
                     action: #selector(NSDocument.runPageLayout(_:)), keyEquivalent: "P")
        menu.addItem(withTitle: "Print…",
                     action: #selector(NSDocument.printDocument(_:)), keyEquivalent: "p")

        item.submenu = menu
        return item
    }

    // MARK: Edit

    private static func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Edit")

        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        menu.addItem(.separator())

        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())

        let goToLine = NSMenuItem(title: "Go to Line…",
                                  action: #selector(EditorViewController.goToLine(_:)), keyEquivalent: "l")
        goToLine.keyEquivalentModifierMask = [.command]
        menu.addItem(goToLine)
        menu.addItem(.separator())

        // Text transforms submenu (sort lines / change case).
        let textItem = NSMenuItem(title: "Text", action: nil, keyEquivalent: "")
        let textMenu = NSMenu(title: "Text")
        let sortAsc = NSMenuItem(title: "Sort Lines Ascending",
                                 action: #selector(EditorWindowController.sortLinesAscending(_:)), keyEquivalent: "")
        let sortDesc = NSMenuItem(title: "Sort Lines Descending",
                                  action: #selector(EditorWindowController.sortLinesDescending(_:)), keyEquivalent: "")
        textMenu.addItem(sortAsc)
        textMenu.addItem(sortDesc)
        textMenu.addItem(.separator())
        textMenu.addItem(NSMenuItem(title: "Make Upper Case",
                                    action: #selector(EditorWindowController.makeUpperCase(_:)), keyEquivalent: ""))
        textMenu.addItem(NSMenuItem(title: "Make Lower Case",
                                    action: #selector(EditorWindowController.makeLowerCase(_:)), keyEquivalent: ""))
        textMenu.addItem(NSMenuItem(title: "Capitalize",
                                    action: #selector(EditorWindowController.makeTitleCase(_:)), keyEquivalent: ""))
        textItem.submenu = textMenu
        menu.addItem(textItem)

        let columnMode = NSMenuItem(title: "Column Selection Mode",
                                    action: #selector(EditorWindowController.toggleColumnSelectionMode(_:)), keyEquivalent: "b")
        columnMode.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(columnMode)
        menu.addItem(.separator())

        // Spelling & substitutions submenu (native).
        let spelling = NSMenuItem(title: "Spelling and Grammar", action: nil, keyEquivalent: "")
        let spellingMenu = NSMenu(title: "Spelling and Grammar")
        spellingMenu.addItem(withTitle: "Show Spelling and Grammar",
                             action: #selector(NSText.showGuessPanel(_:)), keyEquivalent: ":")
        spellingMenu.addItem(withTitle: "Check Document Now",
                             action: #selector(NSText.checkSpelling(_:)), keyEquivalent: ";")
        spellingMenu.addItem(.separator())
        spellingMenu.addItem(withTitle: "Check Spelling While Typing",
                             action: #selector(NSTextView.toggleContinuousSpellChecking(_:)), keyEquivalent: "")
        spelling.submenu = spellingMenu
        menu.addItem(spelling)

        item.submenu = menu
        return item
    }

    // MARK: Find

    private static func findMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Find")

        // Custom Find & Replace bar (supports regex, which Apple's find bar UI
        // does not). Routed to EditorViewController via the responder chain.
        let find = NSMenuItem(title: "Find…",
                              action: #selector(EditorViewController.showFindBar(_:)), keyEquivalent: "f")
        find.keyEquivalentModifierMask = [.command]
        menu.addItem(find)

        let findReplace = NSMenuItem(title: "Find and Replace…",
                                     action: #selector(EditorViewController.showFindReplaceBar(_:)), keyEquivalent: "f")
        findReplace.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(findReplace)

        let findNext = NSMenuItem(title: "Find Next",
                                  action: #selector(EditorViewController.findNextMatch(_:)), keyEquivalent: "g")
        findNext.keyEquivalentModifierMask = [.command]
        menu.addItem(findNext)

        let findPrev = NSMenuItem(title: "Find Previous",
                                  action: #selector(EditorViewController.findPreviousMatch(_:)), keyEquivalent: "G")
        findPrev.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(findPrev)

        let jump = NSMenuItem(title: "Jump to Selection",
                              action: #selector(NSResponder.centerSelectionInVisibleArea(_:)), keyEquivalent: "j")
        jump.keyEquivalentModifierMask = [.command]
        menu.addItem(jump)
        menu.addItem(.separator())

        let allTabs = NSMenuItem(title: "Find in All Tabs…",
                                 action: #selector(EditorWindowController.findInAllTabs(_:)), keyEquivalent: "f")
        allTabs.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(allTabs)

        item.submenu = menu
        return item
    }

    // MARK: View

    private static func viewMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "View")

        let sidebar = NSMenuItem(title: "Show Sidebar",
                                 action: #selector(EditorWindowController.toggleSidebarVisible(_:)), keyEquivalent: "0")
        sidebar.keyEquivalentModifierMask = [.command, .control]
        menu.addItem(sidebar)

        let recentPane = NSMenuItem(title: "Show Recent Files in Sidebar",
                                    action: #selector(EditorWindowController.toggleSidebarPane(_:)), keyEquivalent: "")
        menu.addItem(recentPane)
        menu.addItem(.separator())

        let lineNumbers = NSMenuItem(title: "Show Line Numbers",
                                     action: #selector(EditorWindowController.toggleLineNumbers(_:)), keyEquivalent: "l")
        lineNumbers.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(lineNumbers)

        let wrap = NSMenuItem(title: "Wrap Lines",
                              action: #selector(EditorWindowController.toggleWordWrap(_:)), keyEquivalent: "")
        menu.addItem(wrap)

        let statusBar = NSMenuItem(title: "Show Status Bar",
                                   action: #selector(EditorWindowController.toggleStatusBar(_:)), keyEquivalent: "")
        menu.addItem(statusBar)

        let docStats = NSMenuItem(title: "Show Word Count",
                                  action: #selector(EditorWindowController.toggleDocumentStats(_:)), keyEquivalent: "")
        menu.addItem(docStats)

        let invisibles = NSMenuItem(title: "Show Invisibles",
                                    action: #selector(EditorWindowController.toggleInvisibles(_:)), keyEquivalent: "")
        menu.addItem(invisibles)

        let rainbow = NSMenuItem(title: "Rainbow Brackets",
                                 action: #selector(EditorWindowController.toggleRainbowBrackets(_:)), keyEquivalent: "")
        menu.addItem(rainbow)

        let preview = NSMenuItem(title: "Show Markdown Preview",
                                 action: #selector(EditorWindowController.toggleMarkdownPreview(_:)), keyEquivalent: "V")
        preview.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(preview)

        let autoPreview = NSMenuItem(title: "Auto-Show Preview for Markdown",
                                     action: #selector(EditorWindowController.toggleAutoShowMarkdownPreview(_:)), keyEquivalent: "")
        menu.addItem(autoPreview)

        let mdToolbar = NSMenuItem(title: "Show Markdown Toolbar",
                                   action: #selector(EditorWindowController.toggleMarkdownToolbar(_:)), keyEquivalent: "")
        menu.addItem(mdToolbar)

        let hiddenFiles = NSMenuItem(title: "Show Hidden Files",
                                     action: #selector(EditorWindowController.toggleHiddenFiles(_:)), keyEquivalent: "")
        menu.addItem(hiddenFiles)
        let revealActive = NSMenuItem(title: "Reveal Active File in Sidebar",
                                      action: #selector(EditorWindowController.toggleRevealActiveFile(_:)), keyEquivalent: "")
        menu.addItem(revealActive)
        menu.addItem(.separator())

        // Standard full-screen toggle (⌃⌘F).
        let fullScreen = NSMenuItem(title: "Enter Full Screen",
                                    action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        menu.addItem(fullScreen)

        item.submenu = menu
        return item
    }

    // MARK: Window

    private static func windowMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Window")

        menu.addItem(withTitle: "Minimize",
                     action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom",
                     action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        // Native tab management items get inserted by AppKit when tabbing is on,
        // but provide the standard "Bring All to Front".
        menu.addItem(withTitle: "Bring All to Front",
                     action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")

        item.submenu = menu
        NSApp.windowsMenu = menu
        return item
    }

    // MARK: Help

    private static func helpMenuItem(appName: String) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Help")
        menu.addItem(withTitle: "\(appName) Help",
                     action: #selector(NSApplication.showHelp(_:)), keyEquivalent: "?")
        item.submenu = menu
        NSApp.helpMenu = menu
        return item
    }
}
