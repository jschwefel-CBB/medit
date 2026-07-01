# medit — Product Brief

**Version:** 2.7.3 | **Platform:** macOS | **License:** MIT

---

## What it is

medit is a native macOS text editor built in Swift and AppKit. It brings the simplicity of gedit — the classic GNOME editor — to macOS without the GTK port baggage. No Electron. No cross-platform compromises. A real Mac app.

---

## The problem it solves

macOS has two ends of the editor spectrum: heavyweight IDEs (Xcode, VS Code) and bare-bones system tools (TextEdit). Users who want a fast, capable, single-file or small-project editor — something you can open instantly, paste into, and close — have no great native option. BBEdit and Nova are powerful but priced as professional tools. TextEdit is primitive. Everything in between is an Electron port.

medit fills that gap: a lightweight, polished, Mac-native editor for developers and writers who want a tool that does the job and gets out of the way.

---

## Target user

- Developers who live in IDEs but need a fast scratch editor for quick edits, logs, config files, and notes
- Writers and content creators who want Markdown with live preview in a lightweight app
- Former Linux users (gedit, nano, Kate) who moved to Mac and miss a simple GUI editor
- Anyone who opens TextEdit, immediately regrets it, and closes it

---

## Core features

### Editing
- Full-featured text editing on NSTextView — native macOS text engine
- Syntax highlighting for common languages (auto-detected from extension and shebang)
- Line numbers
- Find & Replace with regex support
- Go to Line
- Word count, sort lines, change case
- Column/block selection
- Indentation control (tabs vs. spaces, indent width)
- Show invisibles (whitespace characters)
- Bracket matching and colorization
- Line endings control (LF / CRLF)
- Encoding detection and control
- External-change detection with reload prompt

### Markdown
- Live Markdown preview via WKWebView — full HTML+CSS rendering
- Light and Dark mode aware (respects system appearance)
- Markdown style bar (shortcuts for bold, italic, headers, code, links, tables)
- Markdown table rendering
- Print support (static TextKit path for reliable output)

### File and folder management
- Folders pane sidebar — browse a folder tree, open files with a double-click
- Recent Files pane
- Drag files onto the app or Dock to open them as tabs
- Open multiple files — they open as tabs in one window, not scattered windows

### Window and session management
- Tabs by default (⌘N opens a new tab in the current window)
- New Window (⇧⌘N) for explicit multi-window workflows
- Full workspace session restore — window grouping, active tab, per-window sidebar folder, window frames
- Open an already-open file → focuses its existing tab, anywhere across windows

### Preferences
- Light/Dark appearance override (independent of system)
- Font family and size
- Tab/space indentation settings
- Per-toggle controls for features users might want off

---

## Technical facts

| | |
|---|---|
| Language | Swift |
| UI framework | AppKit |
| Architecture | Universal binary (x86_64 + arm64) |
| macOS requirement | macOS 13 Ventura+ |
| Sandbox | App Sandbox ON (files.user-selected.read-write + security-scoped bookmarks) |
| Signing | Hardened runtime; ad-hoc for direct distribution |
| Distribution | GitHub Releases (direct download .zip) |
| App Store | Pre-staged; pending Apple Developer account |
| CI | GitHub Actions — `swift test` (387 tests + AutoPilot GUI suite) |
| License | MIT |

---

## Current release

**v2.7.3** — Drag-to-open fix. Dragging files from Finder onto the editor text area or the Folders sidebar now opens them as tabs. Root cause was NSTextView's internal drag-registration pipeline silently resetting any direct `registerForDraggedTypes` call on every property change; fixed by overriding `acceptableDragTypes`, `updateDragTypeRegistration`, `dragOperation(for:type:)`, and `readSelection(from:type:)` directly on the text view subclass.

---

## Version arc

| Version | What shipped |
|---|---|
| 2.0 | Markdown preview + printing |
| 2.1 | Markdown style bar |
| 2.2 | Recent Files pane + drag-drop and window fixes |
| 2.3 | Session restore, word count, sort/case transforms |
| 2.4 | Column/block editing |
| 2.4.1 | Block-select status bar indicator |
| 2.5.0 | User Manual + App Store preparation |
| 2.6.0 | Markdown preview rewritten to WKWebView (HTML+CSS); appearance-at-launch fix; print clipping fix |
| 2.6.1 | Keyboard scroll fixes for preview and editor |
| 2.6.2 | Caret scroll-into-view on open |
| 2.7.0 | Multi-window support (⇧⌘N); full workspace session restore |
| 2.7.1 | Multi-file open → tabs (not scattered windows); sidebar open regression fix |
| 2.7.3 | Drag files from Finder onto editor text area or sidebar → opens as tabs |

---

## What's not in scope

medit is not an IDE. No debugger, no language server, no extensions marketplace, no git integration. It is an editor. The scope is intentionally narrow so the core experience stays fast and focused.
