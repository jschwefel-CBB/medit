# Files & Languages (1.3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the user explicit control over how medit interprets a document — manual syntax language selection, shebang-based detection, encoding/line-ending choice (Reinterpret vs Convert), and reaction to on-disk changes — with the status bar as the interactive hub.

**Architecture:** Correctness lives in pure value types (`LanguageCatalog`, `ShebangDetector`, `LineEndings`, `EncodingCatalog`, `ExternalChangeResolver`) tested exhaustively like `TextSearch`. The status bar's language/encoding/line-ending labels become clickable popups that emit callbacks to `EditorViewController`, which owns document mutations on `TextDocument`. New behaviors are covered by headless editor smoke tests; render-regression guards are retained.

**Tech Stack:** Swift, AppKit, XCTest, local SwiftPM package `MeditKit`.

**SAFETY (every task):** A live instance of medit may be running. NEVER run `pkill`, `open`, or launch/reinstall the app. Verify ONLY with `cd /Users/jschwefel/repositories/medit && swift build` and `swift test`. Use plain `git commit` (NO `-c` identity override). Work from `/Users/jschwefel/repositories/medit` on branch `feature/files-and-languages-1.3`. **NEVER create any `superpowers/` path** (a pre-commit hook blocks it); design docs are in `docs/specs/` and `docs/plans/`.

Spec: `docs/specs/2026-06-15-files-and-languages-1.3-design.md`.

---

## File Structure

New pure-logic units (one responsibility each, fully tested):
- `Sources/MeditKit/LanguageCatalog.swift` — common + full language lists, display names.
- `Sources/MeditKit/ShebangDetector.swift` — first-line shebang → language id.
- `Sources/MeditKit/LineEndings.swift` — detect/normalize LF vs CRLF.
- `Sources/MeditKit/EncodingCatalog.swift` — user-selectable encodings.
- `Sources/MeditKit/ExternalChangeResolver.swift` — policy × dirty → action.

Modified:
- `TextDocument.swift` — `languageOverride`, `detectedLanguage`, `lineEnding`, `originalData`, `reinterpret`/`convert`/`setLineEnding`, NSFilePresenter callbacks.
- `StatusBarView.swift` — language/encoding/line-ending become clickable popups with callbacks.
- `EditorViewController.swift` — build menus, route choices to the document, reload banner, refresh.
- `EditorWindowController.swift` — reload banner host / actions if needed.
- `Preferences.swift` (+ `externalChangePolicy`), `PreferencesWindowController.swift`.

---

## Task 1: LanguageCatalog

**Files:**
- Create: `Sources/MeditKit/LanguageCatalog.swift`, `Tests/MeditKitTests/LanguageCatalogTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MeditKitTests/LanguageCatalogTests.swift`:

```swift
import XCTest
@testable import MeditKit

final class LanguageCatalogTests: XCTestCase {

    func testCommonListIsNonEmpty() {
        XCTAssertGreaterThan(LanguageCatalog.common.count, 10)
    }

    func testEveryCommonEntryHasIdAndName() {
        for entry in LanguageCatalog.common {
            XCTAssertFalse(entry.id.isEmpty)
            XCTAssertFalse(entry.displayName.isEmpty)
        }
    }

    func testFullListIsSupersetOfCommon() {
        let allIds = Set(LanguageCatalog.all.map { $0.id })
        for entry in LanguageCatalog.common {
            XCTAssertTrue(allIds.contains(entry.id), "common id \(entry.id) missing from all")
        }
    }

    func testDisplayNameKnownIds() {
        XCTAssertEqual(LanguageCatalog.displayName(for: "swift"), "Swift")
        XCTAssertEqual(LanguageCatalog.displayName(for: "cpp"), "C++")
        XCTAssertEqual(LanguageCatalog.displayName(for: "objectivec"), "Objective-C")
        XCTAssertEqual(LanguageCatalog.displayName(for: "xml"), "HTML/XML")
        XCTAssertEqual(LanguageCatalog.displayName(for: "javascript"), "JavaScript")
    }

    func testDisplayNameUnknownIdTitlecases() {
        XCTAssertEqual(LanguageCatalog.displayName(for: "haskell"), "Haskell")
    }

    func testCommonContainsSwiftAndPython() {
        let ids = LanguageCatalog.common.map { $0.id }
        XCTAssertTrue(ids.contains("swift"))
        XCTAssertTrue(ids.contains("python"))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter LanguageCatalogTests 2>&1 | grep -E "error:|cannot find"`
Expected: `cannot find 'LanguageCatalog' in scope`.

- [ ] **Step 3: Implement LanguageCatalog**

Create `Sources/MeditKit/LanguageCatalog.swift`:

```swift
import Foundation

/// The source of truth for the language picker: a curated common list, the full
/// list, and display-name formatting. Pure value data, fully tested. IDs are the
/// highlight.js identifiers HighlighterSwift expects.
public enum LanguageCatalog {

    public struct Language: Equatable {
        public let id: String
        public let displayName: String
        public init(id: String, displayName: String) {
            self.id = id
            self.displayName = displayName
        }
    }

    /// Curated, commonly-used languages (shown at the top level of the menu).
    public static let common: [Language] = [
        Language(id: "swift", displayName: "Swift"),
        Language(id: "python", displayName: "Python"),
        Language(id: "javascript", displayName: "JavaScript"),
        Language(id: "typescript", displayName: "TypeScript"),
        Language(id: "json", displayName: "JSON"),
        Language(id: "yaml", displayName: "YAML"),
        Language(id: "markdown", displayName: "Markdown"),
        Language(id: "bash", displayName: "Shell"),
        Language(id: "xml", displayName: "HTML/XML"),
        Language(id: "css", displayName: "CSS"),
        Language(id: "scss", displayName: "SCSS"),
        Language(id: "c", displayName: "C"),
        Language(id: "cpp", displayName: "C++"),
        Language(id: "objectivec", displayName: "Objective-C"),
        Language(id: "go", displayName: "Go"),
        Language(id: "rust", displayName: "Rust"),
        Language(id: "java", displayName: "Java"),
        Language(id: "kotlin", displayName: "Kotlin"),
        Language(id: "ruby", displayName: "Ruby"),
        Language(id: "php", displayName: "PHP"),
        Language(id: "sql", displayName: "SQL"),
        Language(id: "toml", displayName: "TOML"),
        Language(id: "ini", displayName: "INI"),
        Language(id: "diff", displayName: "Diff"),
        Language(id: "lua", displayName: "Lua"),
        Language(id: "perl", displayName: "Perl"),
        Language(id: "makefile", displayName: "Makefile"),
        Language(id: "dockerfile", displayName: "Dockerfile"),
    ]

    /// A broad set of additional highlight.js languages for the "All Languages…"
    /// submenu. (Not exhaustive of all ~190, but a deep, alphabetized selection;
    /// the common list above is merged in and de-duplicated.)
    private static let additional: [Language] = [
        Language(id: "ada", displayName: "Ada"),
        Language(id: "apache", displayName: "Apache"),
        Language(id: "applescript", displayName: "AppleScript"),
        Language(id: "asciidoc", displayName: "AsciiDoc"),
        Language(id: "awk", displayName: "Awk"),
        Language(id: "clojure", displayName: "Clojure"),
        Language(id: "cmake", displayName: "CMake"),
        Language(id: "coffeescript", displayName: "CoffeeScript"),
        Language(id: "crystal", displayName: "Crystal"),
        Language(id: "csharp", displayName: "C#"),
        Language(id: "dart", displayName: "Dart"),
        Language(id: "elixir", displayName: "Elixir"),
        Language(id: "elm", displayName: "Elm"),
        Language(id: "erlang", displayName: "Erlang"),
        Language(id: "fortran", displayName: "Fortran"),
        Language(id: "fsharp", displayName: "F#"),
        Language(id: "graphql", displayName: "GraphQL"),
        Language(id: "groovy", displayName: "Groovy"),
        Language(id: "haskell", displayName: "Haskell"),
        Language(id: "haxe", displayName: "Haxe"),
        Language(id: "julia", displayName: "Julia"),
        Language(id: "latex", displayName: "LaTeX"),
        Language(id: "less", displayName: "Less"),
        Language(id: "lisp", displayName: "Lisp"),
        Language(id: "matlab", displayName: "MATLAB"),
        Language(id: "nginx", displayName: "Nginx"),
        Language(id: "nim", displayName: "Nim"),
        Language(id: "nix", displayName: "Nix"),
        Language(id: "ocaml", displayName: "OCaml"),
        Language(id: "powershell", displayName: "PowerShell"),
        Language(id: "prolog", displayName: "Prolog"),
        Language(id: "protobuf", displayName: "Protocol Buffers"),
        Language(id: "puppet", displayName: "Puppet"),
        Language(id: "r", displayName: "R"),
        Language(id: "scala", displayName: "Scala"),
        Language(id: "scheme", displayName: "Scheme"),
        Language(id: "smalltalk", displayName: "Smalltalk"),
        Language(id: "tcl", displayName: "Tcl"),
        Language(id: "vbnet", displayName: "VB.NET"),
        Language(id: "verilog", displayName: "Verilog"),
        Language(id: "vhdl", displayName: "VHDL"),
        Language(id: "vim", displayName: "Vim Script"),
        Language(id: "wasm", displayName: "WebAssembly"),
        Language(id: "zig", displayName: "Zig"),
    ]

    /// The full list = common ∪ additional, de-duplicated by id, alphabetized by
    /// display name.
    public static let all: [Language] = {
        var seen = Set<String>()
        var result: [Language] = []
        for lang in common + additional where !seen.contains(lang.id) {
            seen.insert(lang.id)
            result.append(lang)
        }
        return result.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }()

    /// A tidy display name for a highlight.js id (used by the status bar and
    /// menus). Falls back to title-casing the id.
    public static func displayName(for id: String) -> String {
        if let entry = all.first(where: { $0.id == id }) { return entry.displayName }
        switch id {
        case "cpp": return "C++"
        case "objectivec": return "Objective-C"
        case "xml": return "HTML/XML"
        case "javascript": return "JavaScript"
        case "typescript": return "TypeScript"
        default: return id.prefix(1).uppercased() + id.dropFirst()
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter LanguageCatalogTests 2>&1 | grep -E "Executed|failed"`
Expected: `Executed 6 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/MeditKit/LanguageCatalog.swift Tests/MeditKitTests/LanguageCatalogTests.swift
git commit -m "Add LanguageCatalog: common + full language lists, display names"
```

---

## Task 2: ShebangDetector + detectedLanguage

**Files:**
- Create: `Sources/MeditKit/ShebangDetector.swift`, `Tests/MeditKitTests/ShebangDetectorTests.swift`
- Modify: `Sources/MeditKit/TextDocument.swift`

- [ ] **Step 1: Write the failing ShebangDetector test**

Create `Tests/MeditKitTests/ShebangDetectorTests.swift`:

```swift
import XCTest
@testable import MeditKit

final class ShebangDetectorTests: XCTestCase {

    private func lang(_ firstLine: String) -> String? {
        ShebangDetector.language(forFirstLine: firstLine)
    }

    func testEnvPython() { XCTAssertEqual(lang("#!/usr/bin/env python"), "python") }
    func testDirectPython3() { XCTAssertEqual(lang("#!/usr/bin/python3"), "python") }
    func testBinSh() { XCTAssertEqual(lang("#!/bin/sh"), "bash") }
    func testBinBash() { XCTAssertEqual(lang("#!/bin/bash"), "bash") }
    func testEnvZsh() { XCTAssertEqual(lang("#!/usr/bin/env zsh"), "bash") }
    func testEnvNode() { XCTAssertEqual(lang("#!/usr/bin/env node"), "javascript") }
    func testEnvRuby() { XCTAssertEqual(lang("#!/usr/bin/env ruby"), "ruby") }
    func testDirectPerl() { XCTAssertEqual(lang("#!/usr/bin/perl"), "perl") }
    func testEnvLua() { XCTAssertEqual(lang("#!/usr/bin/env lua"), "lua") }
    func testEnvPhp() { XCTAssertEqual(lang("#!/usr/bin/env php"), "php") }

    func testNoShebangReturnsNil() { XCTAssertNil(lang("import os")) }
    func testEmptyReturnsNil() { XCTAssertNil(lang("")) }
    func testShebangUnknownInterpreterReturnsNil() { XCTAssertNil(lang("#!/usr/bin/env brainfuck")) }
    func testLeadingSpacesStillDetected() { XCTAssertEqual(lang("#!  /usr/bin/env python"), "python") }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ShebangDetectorTests 2>&1 | grep -E "error:|cannot find"`
Expected: `cannot find 'ShebangDetector' in scope`.

- [ ] **Step 3: Implement ShebangDetector**

Create `Sources/MeditKit/ShebangDetector.swift`:

```swift
import Foundation

/// Maps a script's shebang first line to a highlight.js language id. Pure value
/// logic, fully tested. Returns nil when there's no shebang or the interpreter
/// isn't recognized.
public enum ShebangDetector {

    /// interpreter executable name → language id.
    private static let interpreters: [String: String] = [
        "python": "python", "python2": "python", "python3": "python",
        "sh": "bash", "bash": "bash", "zsh": "bash", "dash": "bash", "ksh": "bash",
        "node": "javascript", "nodejs": "javascript",
        "ruby": "ruby",
        "perl": "perl",
        "lua": "lua",
        "php": "php",
        "awk": "awk",
        "tclsh": "tcl",
        "Rscript": "r",
    ]

    public static func language(forFirstLine firstLine: String) -> String? {
        guard firstLine.hasPrefix("#!") else { return nil }
        // Strip "#!", split into tokens.
        let rest = firstLine.dropFirst(2)
        let tokens = rest.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard !tokens.isEmpty else { return nil }

        // The interpreter is either the first token's basename, or — for
        // "/usr/bin/env python" — the token after "env".
        func basename(_ path: String) -> String {
            (path as NSString).lastPathComponent
        }

        var interpreterToken = basename(tokens[0])
        if interpreterToken == "env", tokens.count >= 2 {
            interpreterToken = basename(tokens[1])
        }
        return interpreters[interpreterToken]
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter ShebangDetectorTests 2>&1 | grep -E "Executed|failed"`
Expected: `Executed 14 tests, with 0 failures`.

- [ ] **Step 5: Commit ShebangDetector**

```bash
git add Sources/MeditKit/ShebangDetector.swift Tests/MeditKitTests/ShebangDetectorTests.swift
git commit -m "Add ShebangDetector: first-line shebang to language id"
```

- [ ] **Step 6: Wire detectedLanguage into TextDocument**

In `Sources/MeditKit/TextDocument.swift`, the current `highlightLanguage` is:

```swift
    public var highlightLanguage: String? {
        guard let url = fileURL else { return nil }
        return LanguageMap.language(forURL: url)
    }
```

Replace it with a detection chain (extension → shebang):

```swift
    /// Auto-detected language: file extension first, then a shebang on the first
    /// line. nil when neither matches.
    public var detectedLanguage: String? {
        if let url = fileURL, let byExt = LanguageMap.language(forURL: url) {
            return byExt
        }
        let firstLine = text.prefix(while: { $0 != "\n" })
        return ShebangDetector.language(forFirstLine: String(firstLine))
    }

    /// The language used for highlighting: a manual override wins, else the
    /// detected language. (languageOverride is added in Task 3.)
    public var highlightLanguage: String? {
        detectedLanguage
    }
```

(Task 3 changes the last property to `languageOverride ?? detectedLanguage`.)

- [ ] **Step 7: Build + test**

Run: `swift build 2>&1 | grep -E "error:|Build complete"` → `Build complete!`
Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests, with"` → all pass.

- [ ] **Step 8: Commit the wiring**

```bash
git add Sources/MeditKit/TextDocument.swift
git commit -m "TextDocument: detect language by extension then shebang"
```

---

## Task 3: Manual language override + status-bar language popup

**Files:**
- Modify: `Sources/MeditKit/TextDocument.swift`, `Sources/MeditKit/StatusBarView.swift`, `Sources/MeditKit/EditorViewController.swift`, `Tests/MeditKitTests/EditorSmokeTests.swift`

- [ ] **Step 1: Write the failing smoke test for the override**

In `Tests/MeditKitTests/EditorSmokeTests.swift`, add inside the class:

```swift
    func testManualLanguageOverrideWinsOverDetection() {
        let controller = makeWindowController(text: "print('hi')")
        guard let editor = controller.editorForTesting else { return XCTFail("no editor") }
        controller.showWindow(nil)
        // Force a manual override and confirm the document reports it.
        editor.setLanguageOverrideForTesting("rust")
        XCTAssertEqual(controller.documentForTesting?.highlightLanguage, "rust")
        // Auto-detect clears it (untitled doc with no extension/shebang -> nil).
        editor.setLanguageOverrideForTesting(nil)
        XCTAssertNil(controller.documentForTesting?.highlightLanguage)
    }
```

- [ ] **Step 2: Add languageOverride to TextDocument**

In `Sources/MeditKit/TextDocument.swift`, add a property near `fileEncoding`:

```swift
    /// Manual language override (nil = auto-detect). Session-only; not persisted.
    public var languageOverride: String?
```

Change `highlightLanguage` to honor it:

```swift
    public var highlightLanguage: String? {
        languageOverride ?? detectedLanguage
    }
```

- [ ] **Step 3: Add the test hooks**

In `Sources/MeditKit/EditorViewController.swift`, add near the other `ForTesting`
hooks:

```swift
    func setLanguageOverrideForTesting(_ id: String?) { setLanguageOverride(id) }
```

In `Sources/MeditKit/EditorWindowController.swift`, add near `editorForTesting`:

```swift
    /// Test hook: the underlying document.
    var documentForTesting: TextDocument? { textDocument }
```

And expose it from the controller used in tests — the smoke test reaches the
document via the window controller. Add to `EditorWindowController`:
(already covered by `documentForTesting` above).

In `EditorSmokeTests.swift`, the helper returns an `EditorWindowController`; add a
convenience at the top of the test if needed:
`controller.documentForTesting` is available from the line above.

- [ ] **Step 4: Implement setLanguageOverride in the editor**

In `Sources/MeditKit/EditorViewController.swift`, add:

```swift
    /// Apply a manual language override (nil = auto-detect), re-highlight, and
    /// refresh the status bar.
    func setLanguageOverride(_ id: String?) {
        document?.languageOverride = id
        highlighter?.setLanguage(document?.highlightLanguage)
        updateStatusBar()
    }
```

- [ ] **Step 5: Make the status-bar language label a popup**

In `Sources/MeditKit/StatusBarView.swift`, replace the `languageLabel`
`NSTextField` with a click-driven popup. Add a callback property and convert the
label to a button-like control. Concretely:

Add to the class:

```swift
    /// Called when the user picks a language id from the popup. "auto" means
    /// auto-detect; "plaintext" means no highlighting; otherwise a highlight.js id.
    public var onLanguagePick: ((String) -> Void)?
```

Change `languageLabel` from a label to a `NSPopUpButton` styled inline. Replace:

```swift
    private let languageLabel = StatusBarView.makeLabel(align: .right)
```

with:

```swift
    private let languageButton = StatusBarView.makeInlineButton()
```

Add the factory + menu builder:

```swift
    private static func makeInlineButton() -> NSButton {
        let b = NSButton(title: "", target: nil, action: nil)
        b.isBordered = false
        b.bezelStyle = .inline
        b.font = .systemFont(ofSize: 11)
        b.contentTintColor = .secondaryLabelColor
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    @objc private func languageButtonClicked() {
        let menu = NSMenu()
        let auto = NSMenuItem(title: "Auto-Detect", action: #selector(pickLanguage(_:)), keyEquivalent: "")
        auto.representedObject = "auto"; auto.target = self
        menu.addItem(auto)
        let plain = NSMenuItem(title: "Plain Text", action: #selector(pickLanguage(_:)), keyEquivalent: "")
        plain.representedObject = "plaintext"; plain.target = self
        menu.addItem(plain)
        menu.addItem(.separator())
        for lang in LanguageCatalog.common {
            let item = NSMenuItem(title: lang.displayName, action: #selector(pickLanguage(_:)), keyEquivalent: "")
            item.representedObject = lang.id; item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let all = NSMenuItem(title: "All Languages…", action: nil, keyEquivalent: "")
        let allMenu = NSMenu()
        for lang in LanguageCatalog.all {
            let item = NSMenuItem(title: lang.displayName, action: #selector(pickLanguage(_:)), keyEquivalent: "")
            item.representedObject = lang.id; item.target = self
            allMenu.addItem(item)
        }
        all.submenu = allMenu
        menu.addItem(all)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: languageButton.bounds.height), in: languageButton)
    }

    @objc private func pickLanguage(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { onLanguagePick?(id) }
    }
```

Wire the button's action in `init` (after it's created): set
`languageButton.target = self; languageButton.action = #selector(languageButtonClicked)`,
and use `languageButton` in the `NSStackView` in place of `languageLabel`.

Update `update(...)` to set the button title instead of the label:

```swift
        languageButton.title = language
```

- [ ] **Step 6: Connect the status bar callback in the editor**

In `Sources/MeditKit/EditorViewController.swift`, where the status bar is created
in `loadView` (search for `StatusBarView()`), add after creation:

```swift
        statusBar.onLanguagePick = { [weak self] pick in
            switch pick {
            case "auto": self?.setLanguageOverride(nil)
            case "plaintext": self?.setLanguageOverride("plaintext")
            default: self?.setLanguageOverride(pick)
            }
        }
```

Note: `highlighter?.setLanguage("plaintext")` — confirm the highlighter treats an
unknown id as no highlighting (it already falls back to plain styling for nil/unknown
language; "plaintext" is not a highlight.js id so it renders plain). The status bar
shows "Plain Text" for a "plaintext" override; update `updateStatusBar` so the label
maps "plaintext" → "Plain Text" and a real id → its display name.

In `updateStatusBar()` (replace the existing language line):

```swift
        let overrideOrDetected = document?.highlightLanguage
        let language: String
        switch overrideOrDetected {
        case .none: language = "Plain Text"
        case .some("plaintext"): language = "Plain Text"
        case .some(let id): language = LanguageCatalog.displayName(for: id)
        }
```

(Remove the old `displayLanguageName` private method — `LanguageCatalog.displayName`
replaces it. Delete the method and any other call to it.)

- [ ] **Step 7: Build + test**

Run: `swift build 2>&1 | grep -E "error:|Build complete"` → `Build complete!`
Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests, with"` → all pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/MeditKit/TextDocument.swift Sources/MeditKit/StatusBarView.swift Sources/MeditKit/EditorViewController.swift Sources/MeditKit/EditorWindowController.swift Tests/MeditKitTests/EditorSmokeTests.swift
git commit -m "Add manual language override via status-bar popup"
```

---

## Task 4: LineEndings + EncodingCatalog

**Files:**
- Create: `Sources/MeditKit/LineEndings.swift`, `Tests/MeditKitTests/LineEndingsTests.swift`
- Create: `Sources/MeditKit/EncodingCatalog.swift`, `Tests/MeditKitTests/EncodingCatalogTests.swift`

- [ ] **Step 1: Write the failing LineEndings test**

Create `Tests/MeditKitTests/LineEndingsTests.swift`:

```swift
import XCTest
@testable import MeditKit

final class LineEndingsTests: XCTestCase {

    func testDetectLF() { XCTAssertEqual(LineEndings.detect("a\nb\nc"), .lf) }
    func testDetectCRLF() { XCTAssertEqual(LineEndings.detect("a\r\nb\r\nc"), .crlf) }
    func testDetectMixedDominant() {
        // 2 CRLF vs 1 LF -> CRLF dominant
        XCTAssertEqual(LineEndings.detect("a\r\nb\r\nc\nd"), .crlf)
    }
    func testDetectNoBreaksDefaultsLF() { XCTAssertEqual(LineEndings.detect("abc"), .lf) }
    func testDetectEmptyDefaultsLF() { XCTAssertEqual(LineEndings.detect(""), .lf) }

    func testNormalizeToCRLF() {
        XCTAssertEqual(LineEndings.normalize("a\nb\nc", to: .crlf), "a\r\nb\r\nc")
    }
    func testNormalizeToLF() {
        XCTAssertEqual(LineEndings.normalize("a\r\nb\r\nc", to: .lf), "a\nb\nc")
    }
    func testNormalizeMixedToLF() {
        XCTAssertEqual(LineEndings.normalize("a\r\nb\nc", to: .lf), "a\nb\nc")
    }
    func testNormalizeIdempotent() {
        XCTAssertEqual(LineEndings.normalize("a\nb", to: .lf), "a\nb")
    }
    func testNormalizeNoBreaks() {
        XCTAssertEqual(LineEndings.normalize("abc", to: .crlf), "abc")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter LineEndingsTests 2>&1 | grep -E "error:|cannot find"`
Expected: `cannot find 'LineEndings' in scope`.

- [ ] **Step 3: Implement LineEndings**

Create `Sources/MeditKit/LineEndings.swift`:

```swift
import Foundation

/// Detect and normalize a string's line endings. Pure value logic, fully tested.
public enum LineEnding: String {
    case lf   // "\n"
    case crlf // "\r\n"

    public var string: String { self == .crlf ? "\r\n" : "\n" }
}

public enum LineEndings {

    /// Dominant line ending of `text`. Defaults to `.lf` when there are no breaks.
    public static func detect(_ text: String) -> LineEnding {
        let ns = text as NSString
        var crlf = 0
        var lf = 0
        var i = 0
        while i < ns.length {
            let c = ns.character(at: i)
            if c == 13 { // \r
                if i + 1 < ns.length, ns.character(at: i + 1) == 10 { crlf += 1; i += 2; continue }
            } else if c == 10 { // \n
                lf += 1
            }
            i += 1
        }
        if crlf == 0 && lf == 0 { return .lf }
        return crlf > lf ? .crlf : .lf
    }

    /// Normalize all line endings in `text` to `target`.
    public static func normalize(_ text: String, to target: LineEnding) -> String {
        // First collapse everything to LF, then expand if needed.
        let lfOnly = text.replacingOccurrences(of: "\r\n", with: "\n")
                         .replacingOccurrences(of: "\r", with: "\n")
        if target == .lf { return lfOnly }
        return lfOnly.replacingOccurrences(of: "\n", with: "\r\n")
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter LineEndingsTests 2>&1 | grep -E "Executed|failed"`
Expected: `Executed 10 tests, with 0 failures`.

- [ ] **Step 5: Write the failing EncodingCatalog test**

Create `Tests/MeditKitTests/EncodingCatalogTests.swift`:

```swift
import XCTest
@testable import MeditKit

final class EncodingCatalogTests: XCTestCase {

    func testListIsNonEmpty() {
        XCTAssertGreaterThan(EncodingCatalog.selectable.count, 2)
    }

    func testContainsUTF8AndLatin1() {
        let encodings = EncodingCatalog.selectable.map { $0.encoding }
        XCTAssertTrue(encodings.contains(.utf8))
        XCTAssertTrue(encodings.contains(.isoLatin1))
    }

    func testDisplayNamesMatchDetector() {
        for entry in EncodingCatalog.selectable {
            XCTAssertEqual(entry.displayName, TextEncodingDetector.displayName(for: entry.encoding))
        }
    }
}
```

- [ ] **Step 6: Run to verify it fails**

Run: `swift test --filter EncodingCatalogTests 2>&1 | grep -E "error:|cannot find"`
Expected: `cannot find 'EncodingCatalog' in scope`.

- [ ] **Step 7: Implement EncodingCatalog**

Create `Sources/MeditKit/EncodingCatalog.swift`:

```swift
import Foundation

/// The user-selectable text encodings for the status-bar encoding picker. Pure
/// value data; display names reuse TextEncodingDetector.displayName.
public enum EncodingCatalog {

    public struct Entry {
        public let encoding: String.Encoding
        public var displayName: String { TextEncodingDetector.displayName(for: encoding) }
        public init(_ encoding: String.Encoding) { self.encoding = encoding }
    }

    public static let selectable: [Entry] = [
        Entry(.utf8),
        Entry(.utf16),
        Entry(.isoLatin1),
        Entry(.ascii),
    ]
}
```

- [ ] **Step 8: Run to verify it passes**

Run: `swift test --filter EncodingCatalogTests 2>&1 | grep -E "Executed|failed"`
Expected: `Executed 3 tests, with 0 failures`.

- [ ] **Step 9: Commit**

```bash
git add Sources/MeditKit/LineEndings.swift Sources/MeditKit/EncodingCatalog.swift Tests/MeditKitTests/LineEndingsTests.swift Tests/MeditKitTests/EncodingCatalogTests.swift
git commit -m "Add LineEndings + EncodingCatalog (pure, tested)"
```

---

## Task 5: Encoding / line-ending picker (TextDocument + status bar)

**Files:**
- Modify: `Sources/MeditKit/TextDocument.swift`, `Sources/MeditKit/StatusBarView.swift`, `Sources/MeditKit/EditorViewController.swift`, `Tests/MeditKitTests/TextDocumentEncodingTests.swift` (new)

- [ ] **Step 1: Write the failing TextDocument encoding test**

Create `Tests/MeditKitTests/TextDocumentEncodingTests.swift`:

```swift
import XCTest
@testable import MeditKit

final class TextDocumentEncodingTests: XCTestCase {

    func testReinterpretReDecodesOriginalBytes() throws {
        // 0xE9 is 'é' in Latin-1, invalid as lone UTF-8 -> auto-detect picks Latin-1.
        let data = Data([0x63, 0x61, 0x66, 0xE9]) // "caf<E9>"
        let doc = TextDocument()
        try doc.read(from: data, ofType: "public.plain-text")
        XCTAssertEqual(doc.text, "café")
        XCTAssertEqual(doc.fileEncoding, .isoLatin1)

        // Reinterpreting the SAME bytes as UTF-8 would fail decode; reinterpret
        // is a no-op-or-replace that must not crash and should keep valid text.
        doc.reinterpret(as: .isoLatin1) // re-decode as latin1 again -> still "café"
        XCTAssertEqual(doc.text, "café")
    }

    func testConvertChangesSaveEncodingNotText() {
        let doc = TextDocument()
        doc.setTextForTesting("hello")
        doc.fileEncoding = .utf8
        doc.convert(to: .isoLatin1)
        XCTAssertEqual(doc.fileEncoding, .isoLatin1)
        XCTAssertEqual(doc.text, "hello", "convert must not alter the text")
    }

    func testSetLineEndingNormalizesText() {
        let doc = TextDocument()
        doc.setTextForTesting("a\nb\nc")
        doc.setLineEnding(.crlf)
        XCTAssertEqual(doc.lineEnding, .crlf)
        XCTAssertEqual(doc.text, "a\r\nb\r\nc")
        doc.setLineEnding(.lf)
        XCTAssertEqual(doc.text, "a\nb\nc")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter TextDocumentEncodingTests 2>&1 | grep -E "error:|cannot find|has no member"`
Expected: errors about missing `reinterpret`/`convert`/`setLineEnding`/`lineEnding`.

- [ ] **Step 3: Add encoding/line-ending state + operations to TextDocument**

In `Sources/MeditKit/TextDocument.swift`:

Add properties near `fileEncoding`:

```swift
    /// Line ending used on save (detected on read; default LF).
    public var lineEnding: LineEnding = .lf
    /// The original file bytes from the last read, for Reinterpret.
    public private(set) var originalData: Data?
```

In `read(from:ofType:)`, after decoding, capture the original bytes and detect the
line ending. Find the existing body (it sets `self.text`, `self.fileEncoding`,
`self.writesBOM`) and add:

```swift
        self.originalData = data
        self.lineEnding = LineEndings.detect(self.text)
```

In `data(ofType:)`, before encoding, normalize the text to the chosen line ending.
The current method ends with `return TextEncodingDetector.encode(text, as: fileEncoding, includeBOM: writesBOM)`. Change the saved text to honor the line ending — operate on a local copy so the editor's in-memory text isn't mutated by save:

```swift
        var outText = self.text
        if Preferences.shared.stripTrailingWhitespaceOnSave {
            outText = TextHygiene.cleaned(outText, stripTrailing: true, ensureFinalNewline: true)
        }
        outText = LineEndings.normalize(outText, to: lineEnding)
        return TextEncodingDetector.encode(outText, as: fileEncoding, includeBOM: writesBOM)
```

(If the file already has the strip-on-save logic mutating `self.text`, replace that
with the local `outText` approach above so save never disturbs the caret. Read the
current `data(ofType:)` and adapt.)

Add the operations:

```swift
    /// Re-decode the original file bytes as `encoding` (fixes a wrong auto-detect).
    /// No-op if there are no original bytes or decode fails.
    public func reinterpret(as encoding: String.Encoding) {
        guard let data = originalData,
              let decoded = String(bytes: data, encoding: encoding) else { return }
        self.text = decoded
        self.fileEncoding = encoding
        self.lineEnding = LineEndings.detect(decoded)
        editorWindowController?.documentTextDidReload()
        updateChangeCount(.changeDone)
    }

    /// Keep the current text; write it in `encoding` on the next save.
    public func convert(to encoding: String.Encoding) {
        guard encoding != fileEncoding else { return }
        self.fileEncoding = encoding
        updateChangeCount(.changeDone)
    }

    /// Set the save line ending and normalize the in-memory text to match.
    public func setLineEnding(_ ending: LineEnding) {
        guard ending != lineEnding else { return }
        self.lineEnding = ending
        let normalized = LineEndings.normalize(text, to: ending)
        if normalized != text {
            self.text = normalized
            editorWindowController?.documentTextDidReload()
            updateChangeCount(.changeDone)
        }
    }
```

- [ ] **Step 4: Run to verify the document tests pass**

Run: `swift test --filter TextDocumentEncodingTests 2>&1 | grep -E "Executed|failed"`
Expected: `Executed 3 tests, with 0 failures`.

- [ ] **Step 5: Add encoding + line-ending popups to the status bar**

In `Sources/MeditKit/StatusBarView.swift`, mirror the language popup pattern:
- Convert `encodingLabel` to an inline button `encodingButton` with menu of
  `EncodingCatalog.selectable`; each picked encoding offers Reinterpret/Convert via
  a nested two-item submenu ("Reinterpret as <name>" / "Convert to <name>").
- Add a new inline button `lineEndingButton` (LF / CRLF) after encoding.
- Callbacks:

```swift
    public var onReinterpret: ((String.Encoding) -> Void)?
    public var onConvert: ((String.Encoding) -> Void)?
    public var onLineEndingPick: ((LineEnding) -> Void)?
```

Build the encoding menu so each encoding entry has a submenu:

```swift
    @objc private func encodingButtonClicked() {
        let menu = NSMenu()
        for entry in EncodingCatalog.selectable {
            let item = NSMenuItem(title: entry.displayName, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let re = NSMenuItem(title: "Reinterpret as \(entry.displayName)", action: #selector(reinterpretPicked(_:)), keyEquivalent: "")
            re.representedObject = entry.encoding.rawValue; re.target = self
            let conv = NSMenuItem(title: "Convert to \(entry.displayName)", action: #selector(convertPicked(_:)), keyEquivalent: "")
            conv.representedObject = entry.encoding.rawValue; conv.target = self
            sub.addItem(re); sub.addItem(conv)
            item.submenu = sub
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: encodingButton.bounds.height), in: encodingButton)
    }

    @objc private func reinterpretPicked(_ s: NSMenuItem) {
        if let raw = s.representedObject as? UInt { onReinterpret?(String.Encoding(rawValue: raw)) }
    }
    @objc private func convertPicked(_ s: NSMenuItem) {
        if let raw = s.representedObject as? UInt { onConvert?(String.Encoding(rawValue: raw)) }
    }

    @objc private func lineEndingButtonClicked() {
        let menu = NSMenu()
        for ending in [LineEnding.lf, .crlf] {
            let item = NSMenuItem(title: ending == .lf ? "LF" : "CRLF", action: #selector(lineEndingPicked(_:)), keyEquivalent: "")
            item.representedObject = ending.rawValue; item.target = self
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: lineEndingButton.bounds.height), in: lineEndingButton)
    }
    @objc private func lineEndingPicked(_ s: NSMenuItem) {
        if let raw = s.representedObject as? String, let e = LineEnding(rawValue: raw) { onLineEndingPick?(e) }
    }
```

Extend `update(...)` to also set the line-ending button title. Change the signature
to include the line ending:

```swift
    public func update(line: Int, column: Int, language: String, encoding: String,
                       lineEnding: LineEnding, overwrite: Bool) {
        positionLabel.stringValue = "Ln \(line), Col \(column)"
        languageButton.title = language
        encodingButton.title = encoding
        lineEndingButton.title = (lineEnding == .lf) ? "LF" : "CRLF"
        modeLabel.stringValue = overwrite ? "OVR" : "INS"
    }
```

Add `lineEndingButton` to the stack (after `encodingButton` + a `sep()`), wire its
target/action in init, and wire the encoding button's action.

- [ ] **Step 6: Wire the callbacks + updateStatusBar in the editor**

In `Sources/MeditKit/EditorViewController.swift` where the status bar is created:

```swift
        statusBar.onReinterpret = { [weak self] enc in
            self?.document?.reinterpret(as: enc)
            self?.rehighlightAndRefresh()
        }
        statusBar.onConvert = { [weak self] enc in
            self?.document?.convert(to: enc)
            self?.updateStatusBar()
        }
        statusBar.onLineEndingPick = { [weak self] ending in
            self?.document?.setLineEnding(ending)
            self?.updateStatusBar()
        }
```

Add a small helper:

```swift
    private func rehighlightAndRefresh() {
        if let storage = textView.textStorage {
            textView.string = document?.text ?? textView.string
            _ = storage
        }
        highlighter?.highlightNow()
        updateStatusBar()
        ruler?.needsDisplay = true
    }
```

Update `updateStatusBar()` to pass the line ending; change the `statusBar.update(...)`
call to include `lineEnding: document?.lineEnding ?? .lf`.

- [ ] **Step 7: Build + test**

Run: `swift build 2>&1 | grep -E "error:|Build complete"` → `Build complete!`
Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests, with"` → all pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/MeditKit/TextDocument.swift Sources/MeditKit/StatusBarView.swift Sources/MeditKit/EditorViewController.swift Tests/MeditKitTests/TextDocumentEncodingTests.swift
git commit -m "Add encoding (Reinterpret/Convert) + line-ending picker in status bar"
```

---

## Task 6: ExternalChangeResolver + externalChangePolicy preference

**Files:**
- Create: `Sources/MeditKit/ExternalChangeResolver.swift`, `Tests/MeditKitTests/ExternalChangeResolverTests.swift`
- Modify: `Sources/MeditKit/Preferences.swift`, `Tests/MeditKitTests/PreferencesTests.swift`, `Sources/MeditKit/PreferencesWindowController.swift`

- [ ] **Step 1: Write the failing resolver test**

Create `Tests/MeditKitTests/ExternalChangeResolverTests.swift`:

```swift
import XCTest
@testable import MeditKit

final class ExternalChangeResolverTests: XCTestCase {

    func testNotifyAlwaysBanner() {
        XCTAssertEqual(ExternalChangeResolver.action(policy: .notify, isDirty: false), .banner)
        XCTAssertEqual(ExternalChangeResolver.action(policy: .notify, isDirty: true), .banner)
    }

    func testPromptCleanReloadsSilently() {
        XCTAssertEqual(ExternalChangeResolver.action(policy: .prompt, isDirty: false), .reloadSilently)
    }

    func testPromptDirtyPrompts() {
        XCTAssertEqual(ExternalChangeResolver.action(policy: .prompt, isDirty: true), .prompt)
    }

    func testAutoCleanReloadsSilently() {
        XCTAssertEqual(ExternalChangeResolver.action(policy: .autoIfClean, isDirty: false), .reloadSilently)
    }

    func testAutoDirtyPrompts() {
        XCTAssertEqual(ExternalChangeResolver.action(policy: .autoIfClean, isDirty: true), .prompt)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ExternalChangeResolverTests 2>&1 | grep -E "error:|cannot find"`
Expected: `cannot find 'ExternalChangeResolver' in scope`.

- [ ] **Step 3: Implement ExternalChangeResolver**

Create `Sources/MeditKit/ExternalChangeResolver.swift`:

```swift
import Foundation

/// Decides how to respond when the open file changes on disk, given the policy
/// and whether the document has unsaved edits. Pure value logic, fully tested.
public enum ExternalChangePolicy: String, CaseIterable {
    case notify       // non-blocking banner; never auto-acts
    case prompt       // modal Reload/Keep; reload silently if clean
    case autoIfClean  // reload silently if clean; prompt if dirty
}

public enum ExternalChangeResolver {

    public enum Action: Equatable {
        case banner          // show the non-blocking banner
        case prompt          // show the modal Reload/Keep alert
        case reloadSilently  // just reload, no UI
    }

    public static func action(policy: ExternalChangePolicy, isDirty: Bool) -> Action {
        switch policy {
        case .notify:
            return .banner
        case .prompt:
            return isDirty ? .prompt : .reloadSilently
        case .autoIfClean:
            return isDirty ? .prompt : .reloadSilently
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter ExternalChangeResolverTests 2>&1 | grep -E "Executed|failed"`
Expected: `Executed 5 tests, with 0 failures`.

- [ ] **Step 5: Add the externalChangePolicy preference**

In `Sources/MeditKit/Preferences.swift`, add to `Key`:

```swift
        static let externalChangePolicy = "externalChangePolicy"
```

Add to `registerDefaults()`:

```swift
            Key.externalChangePolicy: ExternalChangePolicy.notify.rawValue,
```

Add the property:

```swift
    public var externalChangePolicy: ExternalChangePolicy {
        get { ExternalChangePolicy(rawValue: defaults.string(forKey: Key.externalChangePolicy) ?? "") ?? .notify }
        set { defaults.set(newValue.rawValue, forKey: Key.externalChangePolicy); didChange() }
    }
```

In `Tests/MeditKitTests/PreferencesTests.swift`, add:

```swift
    func testExternalChangePolicyDefaultsNotifyAndPersists() {
        XCTAssertEqual(prefs.externalChangePolicy, .notify)
        prefs.externalChangePolicy = .autoIfClean
        XCTAssertEqual(Preferences(defaults: defaults).externalChangePolicy, .autoIfClean)
    }
```

- [ ] **Step 6: Add the Settings popup**

In `Sources/MeditKit/PreferencesWindowController.swift`, add (matching the existing
control pattern — read the file first to match layout/anchoring conventions):

Property:

```swift
    private var externalChangePopup: NSPopUpButton!
```

In `buildUI()` create a labeled popup with items "Notify", "Prompt", "Auto-reload
if clean" mapped to the three policy cases; anchor it below the last existing
control and re-anchor anything that followed.

In `syncFromPrefs()`:

```swift
        switch prefs.externalChangePolicy {
        case .notify: externalChangePopup.selectItem(at: 0)
        case .prompt: externalChangePopup.selectItem(at: 1)
        case .autoIfClean: externalChangePopup.selectItem(at: 2)
        }
```

Add an action that writes back:

```swift
    @objc private func externalChangePolicyChanged(_ sender: Any?) {
        switch externalChangePopup.indexOfSelectedItem {
        case 1: prefs.externalChangePolicy = .prompt
        case 2: prefs.externalChangePolicy = .autoIfClean
        default: prefs.externalChangePolicy = .notify
        }
    }
```

- [ ] **Step 7: Build + test + commit**

Run: `swift build 2>&1 | grep -E "error:|Build complete"` → `Build complete!`
Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests, with"` → all pass.

```bash
git add Sources/MeditKit/ExternalChangeResolver.swift Sources/MeditKit/Preferences.swift Sources/MeditKit/PreferencesWindowController.swift Tests/MeditKitTests/ExternalChangeResolverTests.swift Tests/MeditKitTests/PreferencesTests.swift
git commit -m "Add ExternalChangeResolver + externalChangePolicy preference"
```

---

## Task 7: External-change detection (NSFilePresenter) + reload banner

**Files:**
- Modify: `Sources/MeditKit/TextDocument.swift`, `Sources/MeditKit/EditorViewController.swift`, `Tests/MeditKitTests/EditorSmokeTests.swift`
- Create: `Sources/MeditKit/ReloadBanner.swift`

- [ ] **Step 1: Create the reload banner view**

Create `Sources/MeditKit/ReloadBanner.swift`:

```swift
import AppKit

/// A thin non-blocking banner shown at the top of the editor when the file
/// changes on disk. Has a message, a Reload button, and a dismiss control.
public final class ReloadBanner: NSView {

    public var onReload: (() -> Void)?
    public var onDismiss: (() -> Void)?

    private let label = NSTextField(labelWithString: "")

    public override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 28) }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.18).cgColor

        label.font = .systemFont(ofSize: 11)
        label.lineBreakMode = .byTruncatingTail
        let reload = NSButton(title: "Reload", target: self, action: #selector(reloadTapped))
        reload.bezelStyle = .rounded
        reload.controlSize = .small
        let dismiss = NSButton(title: "✕", target: self, action: #selector(dismissTapped))
        dismiss.bezelStyle = .inline
        dismiss.isBordered = false

        let stack = NSStackView(views: [label, NSView(), reload, dismiss])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func show(message: String) {
        label.stringValue = message
        isHidden = false
    }

    public func hide() { isHidden = true }

    @objc private func reloadTapped() { onReload?() }
    @objc private func dismissTapped() { onDismiss?() }
}
```

- [ ] **Step 2: Host the banner in the editor (zero-height when hidden)**

In `Sources/MeditKit/EditorViewController.swift`, add the banner to the container in
`loadView` ABOVE the find bar (so order is: reload banner / find bar / scroll view /
status bar). Add stored properties:

```swift
    private var reloadBanner: ReloadBanner?
    private var reloadBannerHeightConstraint: NSLayoutConstraint?
```

Create and constrain it like the find bar (collapsed to 0 height while hidden using
an active 0-height constraint; on show, deactivate to let intrinsic 28pt apply). Add
methods:

```swift
    func showReloadBanner(message: String) {
        guard let banner = reloadBanner else { return }
        banner.show(message: message)
        reloadBannerHeightConstraint?.isActive = false
        view.layoutSubtreeIfNeeded()
    }

    func hideReloadBanner() {
        guard let banner = reloadBanner else { return }
        banner.hide()
        reloadBannerHeightConstraint?.constant = 0
        reloadBannerHeightConstraint?.isActive = true
        view.layoutSubtreeIfNeeded()
    }
```

Wire `banner.onReload = { [weak self] in self?.document?.revertToSavedSafely(); self?.hideReloadBanner() }`
and `banner.onDismiss = { [weak self] in self?.hideReloadBanner() }`.

Add `revertToSavedSafely()` to `TextDocument`:

```swift
    /// Reload from disk, refreshing the editor. Safe to call from the banner.
    public func revertToSavedSafely() {
        guard let url = fileURL, let type = fileType else { return }
        try? revert(toContentsOf: url, ofType: type)
    }
```

- [ ] **Step 3: Detect external changes via NSFilePresenter on TextDocument**

In `Sources/MeditKit/TextDocument.swift`, override the presenter callbacks
(`NSDocument` is already an `NSFilePresenter`):

```swift
    public override func presentedItemDidChange() {
        // Called on a background queue; marshal to main.
        DispatchQueue.main.async { [weak self] in
            self?.handleExternalChange(deleted: false)
        }
    }

    public override func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.handleExternalChange(deleted: true)
            completionHandler(nil)
        }
    }

    private func handleExternalChange(deleted: Bool) {
        if deleted {
            // Keep the buffer; mark modified so it can be re-saved.
            updateChangeCount(.changeDone)
            editorWindowController?.editorForExternalChange?.showReloadBanner(message: "The file has been moved or deleted.")
            return
        }
        let policy = Preferences.shared.externalChangePolicy
        switch ExternalChangeResolver.action(policy: policy, isDirty: isDocumentEdited) {
        case .reloadSilently:
            revertToSavedSafely()
        case .banner:
            editorWindowController?.editorForExternalChange?.showReloadBanner(message: "This file has changed on disk.")
        case .prompt:
            presentReloadPrompt()
        }
    }

    private func presentReloadPrompt() {
        let alert = NSAlert()
        alert.messageText = "This file has changed on disk."
        alert.informativeText = "Reload it and discard your unsaved changes, or keep your version?"
        alert.addButton(withTitle: "Reload")
        alert.addButton(withTitle: "Keep My Version")
        if alert.runModal() == .alertFirstButtonReturn {
            revertToSavedSafely()
        }
    }
```

Add an accessor on `EditorWindowController` so the document can reach the editor:

```swift
    /// The editor view controller, for external-change banner display.
    var editorForExternalChange: EditorViewController? { editor }
```

- [ ] **Step 4: Add a smoke test for the banner**

In `Tests/MeditKitTests/EditorSmokeTests.swift`, add:

```swift
    func testReloadBannerShowsAndHidesWithoutBreakingRender() {
        let controller = makeWindowController(text: "content")
        guard let window = controller.window, let editor = controller.editorForTesting else { return XCTFail("no editor") }
        window.setFrame(NSRect(x: 0, y: 0, width: 900, height: 600), display: true)
        controller.showWindow(nil)
        window.layoutIfNeeded()
        editor.showReloadBanner(message: "This file has changed on disk.")
        window.layoutIfNeeded()
        if let tv = controller.focusedTextView {
            XCTAssertGreaterThan(tv.frame.width, 100, "editor collapsed when banner shown")
            XCTAssertEqual(tv.string, "content")
        }
        editor.hideReloadBanner()
        window.layoutIfNeeded()
    }
```

- [ ] **Step 5: Build + test**

Run: `swift build 2>&1 | grep -E "error:|Build complete"` → `Build complete!`
Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests, with"` → all pass.

> The raw NSFilePresenter callback (actual on-disk change) is verified manually,
> not in tests; the resolver decision logic (Task 6) and the banner show/hide
> (above) are the tested parts.

- [ ] **Step 6: Commit**

```bash
git add Sources/MeditKit/ReloadBanner.swift Sources/MeditKit/TextDocument.swift Sources/MeditKit/EditorViewController.swift Sources/MeditKit/EditorWindowController.swift Tests/MeditKitTests/EditorSmokeTests.swift
git commit -m "Add external-change detection + reload banner"
```

---

## Task 8: Version bump to 1.3.0 + README + tag

**Files:**
- Modify: `App/Info.plist`, `App/medit.xcodeproj/project.pbxproj`, `README.md`

- [ ] **Step 1: Bump version strings**

In `App/Info.plist`, change `CFBundleShortVersionString` from `1.2.1` to `1.3.0`.
In `App/medit.xcodeproj/project.pbxproj`, change BOTH `MARKETING_VERSION = 1.2.1;`
to `1.3.0`.

- [ ] **Step 2: Update README**

In `README.md`, add to the **Features** list:

```markdown
- **Manual language selection** — click the language in the status bar to override
  syntax highlighting; "Auto-Detect" returns control. Detection also reads shebang
  lines (e.g. `#!/usr/bin/env python`) for extension-less scripts.
- **Encoding & line endings** — click the encoding in the status bar to Reinterpret
  (re-decode the file bytes) or Convert (re-encode on save); choose LF or CRLF.
- **Reload on external change** — medit notices when an open file changes on disk
  and offers to reload (a banner by default; Prompt / Auto-reload-if-clean in
  Settings). A deleted file keeps your buffer so you can re-save it.
```

- [ ] **Step 3: Build, full test**

Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests, with"` → all pass.
Run (optional, no launch): `cd App && xcodebuild -project medit.xcodeproj -scheme medit -configuration Debug -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"` → `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add App/Info.plist App/medit.xcodeproj/project.pbxproj README.md
git commit -m "Bump version to 1.3.0; document 1.3 features"
```

- [ ] **Step 5: Tag (GATED — only after the user confirms)**

> Do NOT tag/merge/reinstall until the user approves (a live instance may be
> running). When approved:

```bash
git tag -a v1.3.0 -m "medit 1.3.0 — files & languages: manual language selection, shebang detection, encoding/line-ending picker, reload-on-external-change."
git describe --tags
```

---

## Self-Review

**Spec coverage:**
- Manual language selection (status-bar popup, common+All, Auto-Detect, override
  wins, session-only) → Tasks 1 + 3. ✓
- Shebang detection → Task 2. ✓
- Encoding picker Reinterpret vs Convert → Tasks 4 + 5. ✓
- Line-ending LF/CRLF picker (normalize on pick) → Tasks 4 + 5. ✓
- Reload-on-change (Notify default; Prompt/Auto options; deleted keeps buffer) →
  Tasks 6 + 7. ✓
- externalChangePolicy preference → Task 6. ✓
- Status bar interactive for language/encoding/line-ending → Tasks 3 + 5. ✓
- Pure tested units (LanguageCatalog, ShebangDetector, LineEndings,
  EncodingCatalog, ExternalChangeResolver) → Tasks 1/2/4/6. ✓
- Render regression (banner/status bar) → Task 7 smoke test + existing guards. ✓
- Version 1.3.0 + README + tag → Task 8. ✓

**Placeholder scan:** No TBD/TODO. The "read the file first to match the pattern"
notes (PreferencesWindowController layout, TextDocument.data placement) are
deliberate integration guidance with concrete code, not placeholders.

**Type consistency:** `LanguageCatalog.displayName(for:)`/`.common`/`.all`,
`ShebangDetector.language(forFirstLine:)`, `LineEndings.detect`/`.normalize` +
`LineEnding`, `EncodingCatalog.selectable` + `Entry`,
`ExternalChangeResolver.action(policy:isDirty:)` + `ExternalChangePolicy` +
`Action` are used identically across tasks/tests. `TextDocument` additions
(`languageOverride`, `detectedLanguage`, `lineEnding`, `originalData`,
`reinterpret(as:)`, `convert(to:)`, `setLineEnding(_:)`, `revertToSavedSafely()`)
and editor methods (`setLanguageOverride`, `rehighlightAndRefresh`,
`showReloadBanner`/`hideReloadBanner`) are consistent.
