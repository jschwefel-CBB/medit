# medit

A native macOS text editor — a Cocoa/AppKit reimplementation of gedit, built to
replace the Homebrew GTK build with something that actually feels like a Mac app.

**Status:** early development.

## Building

medit is structured as a local Swift package (`MeditKit`, all the app logic) plus
a thin Xcode app target. To build the library and run its tests:

```sh
swift build
swift test
```

The Xcode app target (under `App/`) opens the same package as a local dependency.

## Dependency

Syntax highlighting is provided by
[HighlighterSwift](https://github.com/smittytone/HighlighterSwift) (a maintained
highlight.js wrapper), resolved automatically via Swift Package Manager.

## Targets macOS 14 (Sonoma) and later.
