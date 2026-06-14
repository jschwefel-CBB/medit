# medit

**A native macOS text editor — a clean-room AppKit reimplementation of the gedit experience.**

medit gives you the simple, no-friction editing of [gedit](https://gedit-technology.github.io/apps/gedit/)
without the GTK baggage on macOS: real Mac menus and keyboard shortcuts, native
file dialogs, native window tabs, a proper app icon, and no 60-package Homebrew
runtime. It's a scratchpad and a code editor that feels like it belongs on the
Mac.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-AppKit-orange)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

**Status:** working, v1.1.0. Open, edit, and save text files with tabs, syntax
highlighting, line numbers, word wrap, find/replace (with regex), and
PC-style navigation keys.

Targets **macOS 14 (Sonoma)** and later. Apple Silicon and Intel.

---

## Table of contents

- [Features](#features)
- [Install](#install)
- [Build from source](#build-from-source)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Architecture](#architecture)
- [App icon](#app-icon)
- [Relationship to gedit](#relationship-to-gedit)
- [Contributing](#contributing)
- [License](#license)
- [Acknowledgements](#acknowledgements)

---

## Features

- **Native window tabs** — macOS tabbing with an always-visible tab bar and **+**
  button. Open a tab via ⌘T, the **File** menu, the **+**, or the editor's
  right-click menu.
- **Syntax highlighting** — ~190 languages via
  [HighlighterSwift](https://github.com/smittytone/HighlighterSwift) (highlight.js),
  auto-detected from the file extension. The theme follows the system light/dark
  appearance automatically.
- **Line numbers** — a toggleable gutter (⇧⌘L).
- **Word wrap** — toggleable from the **View** menu.
- **Find & Replace** — a custom in-editor bar (⌘F / ⌥⌘F) with **regex** and
  **match-case** toggles, a live match count, and `$1` capture-group replacement.
  (Apple's built-in find bar can't expose regex in its UI; this one can.)
- **Find in All Tabs** — search across every open document at once (⇧⌘F), with
  regex; click a result to jump straight to it.
- **PC-style navigation keys** — Home/End move to the start/end of the line
  (Ctrl for the whole document, Shift to extend the selection); **Insert** toggles
  overwrite ("type-over") mode with a block caret, Shift+Insert pastes, Ctrl+Insert
  copies. On by default; toggle it off in **Settings** to restore macOS-native
  Home/End.
- **Preferences** — font, appearance (System / Light / Dark), default word wrap,
  line-number visibility, tab width, and the PC-keys toggle (⌘,).
- **Faithful file handling** — encoding detection on open (UTF-8, UTF-16/32 with
  BOM, ISO Latin-1 fallback) with faithful round-trip on save; recent files;
  unsaved-changes prompts; drag-and-drop; session restore. Runs sandboxed with
  user-selected file access.

## Install

medit isn't notarized or distributed through the App Store — build it yourself
(it's a couple of commands; see below), or if a release `.app` is attached to a
[GitHub release](../../releases), download it and drag it to `/Applications`.

Because a self-built app is **ad-hoc signed** (not signed with an Apple Developer
ID), the first launch is gated by Gatekeeper. To open it:

1. Right-click `medit.app` → **Open**, then confirm — or
2. Run once from the terminal: `xattr -dr com.apple.quarantine /Applications/medit.app`

After the first open it launches normally and appears in Launchpad and Spotlight.

## Build from source

medit is a local Swift package (`MeditKit` — all the app logic, fully testable)
plus a thin Xcode app target that wraps it in a `.app` bundle. The only external
dependency is HighlighterSwift, resolved automatically by Swift Package Manager.

### Run the app (Xcode)

```sh
open App/medit.xcodeproj
```

Press **Run** (⌘R). Xcode resolves HighlighterSwift on the first build.

### Build & test the library (command line)

```sh
swift build
swift test          # 68 tests: pure logic + headless editor smoke tests
```

### Build the app bundle without opening Xcode

```sh
cd App
xcodebuild -project medit.xcodeproj -scheme medit -configuration Release \
  build CODE_SIGNING_ALLOWED=NO
```

The built `medit.app` lands in the Xcode DerivedData `Release` products folder.
To install it, copy it to `/Applications`, ad-hoc sign, and de-quarantine:

```sh
cp -R "$(xcodebuild -project medit.xcodeproj -scheme medit -configuration Release \
  -showBuildSettings 2>/dev/null | awk '/BUILT_PRODUCTS_DIR/{print $3}')/medit.app" /Applications/
codesign --force --deep --sign - /Applications/medit.app
xattr -dr com.apple.quarantine /Applications/medit.app
```

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
| Home / End | Line start / end |
| Shift+Home / Shift+End | Extend selection to line start / end |
| Ctrl+Home / Ctrl+End | Document start / end |
| Insert | Toggle overwrite mode |
| Shift+Insert / Ctrl+Insert | Paste / Copy |
| ⌃⌘F | Enter full screen |
| ⌘, | Settings |

> **Note on the Insert key:** Mac keyboards label the Insert-position key as
> **Help**, and the OS reports it that way (hardware keyCode 114). medit detects
> it by keyCode, so a PC keyboard's Insert key works as expected.

## Architecture

```
medit/
├── Package.swift              Local SwiftPM package + HighlighterSwift dependency
├── Sources/MeditKit/          All app logic (the testable library)
│   ├── App lifecycle          AppDelegate, MainMenu
│   ├── Documents / windows    TextDocument (NSDocument), EditorWindowController,
│   │                          EditorViewController, EditorTextView
│   ├── Editor pieces          LineNumberRulerView, SyntaxHighlightingController,
│   │                          FindReplaceBar, EditorColors
│   ├── Pure logic (tested)    TextEncodingDetector, LanguageMap, TextSearch,
│   │                          KeyboardNavigator, Preferences
│   └── Cross-tab search       FindInTabsCoordinator
├── Tests/MeditKitTests/       68 tests (logic + headless editor smoke tests)
├── App/                       Thin Xcode app target
│   ├── medit.xcodeproj        Depends on the local ../  package
│   ├── main.swift             Entry point — boots NSApplication
│   ├── Info.plist             Document types, bundle identity
│   ├── medit.entitlements     App Sandbox + user-selected file access
│   └── Assets.xcassets        App icon
├── Tools/IconGen/             Core Graphics icon generator (iconmaker.swift)
└── docs/superpowers/          Design specs + implementation plans
```

The design deliberately keeps the GUI-free logic — encoding detection, language
mapping, search/replace, key navigation, preferences — in small, independently
testable units, with the AppKit layer built on top. `swift test` exercises both
the pure logic and the editor's view lifecycle **headlessly**, so the whole suite
runs without launching the app.

Two pieces are worth calling out for contributors:

- **`KeyboardNavigator`** is pure value logic (`String` + `NSRange` → `NSRange`)
  with the current line supplied by an injected closure, so all of the Home/End
  selection math is unit-tested without any AppKit.
- **`EditorTextView`** is the only place that touches raw key handling and caret
  drawing. The editor builds its `NSTextView` stack manually (rather than via
  `NSTextView.scrollableTextView()`) specifically so this subclass can be used —
  the assembly intentionally mirrors the factory's TextKit wiring.

## App icon

The icon — a pencil over lined paper in the macOS squircle — is **generated**, not
hand-drawn: `Tools/IconGen/iconmaker.swift` is a self-contained Core Graphics
program that renders the full icon size set and the color variants. Re-render it
with:

```sh
cd Tools/IconGen
swiftc -O -framework AppKit iconmaker.swift -o iconmaker
./iconmaker iconset blue iconset_out      # writes 16…1024 px PNGs
./iconmaker preview previews              # 256 px color variants to compare
```

## Relationship to gedit

medit is **inspired by** gedit but is a **clean-room reimplementation**. No gedit
source code, resources, UI files, or text were read, copied, or ported. Every
Swift file here was written from scratch, and the app icon was generated by the
program in `Tools/IconGen/`. medit reproduces *observable behavior* (tabs, line
numbers, find/replace, an editing scratchpad) and nods to the original's
pencil-and-paper icon *concept* — not its implementation.

Because of that, medit is **not a derivative work of gedit** and is **not bound by
gedit's GPL license**; it is released under the MIT license below. "gedit" is the
name of the GNOME project; medit is an independent project and is not affiliated
with or endorsed by it.

## Contributing

Contributions are welcome. A few ground rules that keep the codebase healthy:

- **Tests first.** The GUI-free logic (in `Sources/MeditKit`) is fully unit-tested;
  new behavior there should come with tests, and the editor's view behavior is
  covered by headless smoke tests in `Tests/MeditKitTests/EditorSmokeTests.swift`.
  Run `swift test` before opening a PR — it must stay green.
- **Keep units small and focused.** Pure logic stays free of AppKit so it can be
  tested headlessly; the AppKit layer sits on top.
- **Match the existing style.** Look at neighboring files (`TextSearch.swift`,
  `Preferences.swift`) for the house patterns.

Design specs and implementation plans live under `docs/superpowers/` if you want
to see how a feature was reasoned about before it was built.

## License

medit is released under the **MIT License** — see [LICENSE](LICENSE). You're free
to use, modify, and redistribute it, including commercially, with attribution.

The bundled syntax-highlighting dependency,
[HighlighterSwift](https://github.com/smittytone/HighlighterSwift), is MIT-licensed
and wraps [highlight.js](https://highlightjs.org) (BSD-3-Clause).

## Acknowledgements

- [gedit](https://gedit-technology.github.io/apps/gedit/) — the inspiration.
- [HighlighterSwift](https://github.com/smittytone/HighlighterSwift) and
  [highlight.js](https://highlightjs.org) — syntax highlighting.
