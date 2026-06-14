# medit

A native macOS text editor — an AppKit reimplementation of [gedit](https://gedit-technology.github.io/apps/gedit/),
built to replace the Homebrew GTK build with something that actually feels like a
Mac app: real menus and shortcuts, native file dialogs, native tabs, and no GTK
runtime.

**Status:** working. Open, edit, and save text files with tabs, syntax
highlighting, line numbers, word wrap, and find/replace (with regex).

Targets **macOS 14 (Sonoma)** and later.

---

## Building & running

medit is a local Swift package (`MeditKit` — all the app logic, fully testable)
plus a thin Xcode app target that wraps it in a `.app` bundle.

### In Xcode (to run the app)

```sh
open App/medit.xcodeproj
```

Then press **Run** (⌘R). Xcode resolves the [HighlighterSwift](https://github.com/smittytone/HighlighterSwift)
dependency automatically on first build.

### From the command line

Build and test the library:

```sh
swift build
swift test
```

Build the app bundle without opening Xcode:

```sh
cd App
xcodebuild -project medit.xcodeproj -scheme medit -configuration Debug build
```

---

## Features

- **Tabs** — native macOS window tabbing. New tab via ⌘T, the **File** menu, the
  always-visible tab bar's **+** button, or the editor's right-click menu.
- **Syntax highlighting** — ~190 languages via
  [HighlighterSwift](https://github.com/smittytone/HighlighterSwift) (highlight.js),
  auto-detected from the file extension. Theme follows the system light/dark
  appearance.
- **Line numbers** — a toggleable gutter (⇧⌘L).
- **Word wrap** — toggleable from the **View** menu.
- **Find & Replace** — a custom in-editor bar (⌘F / ⌥⌘F) with **regex** and
  **match-case** toggles, a match count, and `$1` capture-group replacement —
  things Apple's native find bar UI can't do.
- **Find in All Tabs** — search across every open document at once (⇧⌘F), with
  regex; click a result to jump to it. (gedit can't do this.)
- **Preferences** — font, appearance (System / Light / Dark), default word wrap,
  line-number visibility, and tab width. (⌘,)
- **Faithful file handling** — encoding detection on open (UTF-8, UTF-16/32 with
  BOM, ISO Latin-1 fallback) with faithful round-trip on save; recent files;
  unsaved-changes prompts; drag-and-drop; session restore. Sandboxed with
  user-selected file access.

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘N | New document |
| ⌘T | New tab |
| ⌘O | Open… |
| ⌘S / ⇧⌘S | Save / Save As… |
| ⌘W | Close |
| ⌘F | Find (with regex) |
| ⌥⌘F | Find & Replace |
| ⌘G / ⇧⌘G | Find next / previous |
| ⇧⌘F | Find in all tabs |
| ⇧⌘L | Toggle line numbers |
| ⌃⌘F | Enter full screen |
| ⌘, | Settings |

---

## Architecture

```
medit/
├── Package.swift              Local SwiftPM package + HighlighterSwift dependency
├── Sources/MeditKit/          All app logic (the testable library)
│   ├── App lifecycle          AppDelegate, MainMenu
│   ├── Documents/windows      TextDocument (NSDocument), EditorWindowController,
│   │                          EditorViewController
│   ├── Editor pieces          LineNumberRulerView, SyntaxHighlightingController,
│   │                          FindReplaceBar, EditorColors
│   ├── Pure logic (tested)    TextEncodingDetector, LanguageMap, TextSearch,
│   │                          Preferences
│   └── Cross-tab search       FindInTabsCoordinator
├── Tests/MeditKitTests/       46 tests (logic + headless editor smoke tests)
├── App/                       Thin Xcode app target
│   ├── medit.xcodeproj        Depends on the local ../  package
│   ├── main.swift             @main entry — boots NSApplication
│   ├── Info.plist             Document types, bundle identity
│   ├── medit.entitlements     App Sandbox + user-selected file access
│   └── Assets.xcassets        App icon
└── Tools/IconGen/             Core Graphics icon generator (iconmaker.swift)
```

The design keeps the GUI-free logic (encoding, language mapping, search,
preferences) in small, independently testable units, with the AppKit layer
built on top. `swift test` exercises both the logic and the editor view
lifecycle headlessly.

## App icon

The icon — a pencil over lined paper in the macOS squircle — is generated from
`Tools/IconGen/iconmaker.swift`, a self-contained Core Graphics program that
renders the full size set and the color variants. Re-render with:

```sh
cd Tools/IconGen
swiftc -O -framework AppKit iconmaker.swift -o iconmaker
./iconmaker iconset blue iconset_out
```
