# medit 1.3 — Files & Languages

## Goal

Give the user explicit control over how medit interprets a document: choose the
syntax language manually, detect language from content (shebangs) when there's no
extension, pick/convert the text encoding and line endings, and react when a file
changes on disk. The status bar becomes the interactive hub for language,
encoding, and line endings.

These are the "Good fits" tier deferred from 1.2. The sidebar file browser is
**1.4**; the color scheme picker is **1.5** (both already brainstormed — see
roadmap note).

Ships as **medit 1.3.0** (backward-compatible features, SemVer minor). Each
feature is an independently-committable piece; version bump + tag when all land.

## Roadmap context (not built here)

- **1.4** — sidebar file browser, collapsible and fully hide-able.
- **1.5** — color scheme picker: full editor theme (bg + text + syntax) from the
  ~400 bundled highlight.js themes; Settings list with mini preview swatches;
  curated short list + "All Themes…"; one chosen scheme + a "Match system
  appearance" option that flips a light/dark pick. (Touches `EditorColors`, which
  is currently a hardcoded off-white, so the scheme must drive bg+fg, not just the
  highlighter.)

---

## Feature 1: Manual language selection

### Behavior
- The status bar's language label becomes a clickable popup. Its menu:
  - **Auto-Detect** (checkmark when active) — clears the override, returns to
    extension/content detection.
  - **Plain Text** — no highlighting.
  - A curated **common set** (~30): Swift, Python, JavaScript, TypeScript, JSON,
    YAML, Markdown, Shell, HTML/XML, CSS, SCSS, C, C++, Objective-C, Go, Rust,
    Java, Kotlin, Ruby, PHP, SQL, TOML, INI, Diff, Lua, Perl, Make, Dockerfile…
  - **All Languages…** → nested submenu with the full highlight.js list,
    alphabetized.
- Picking a language sets a per-document **override**; the editor re-highlights
  immediately; the chosen entry shows a checkmark.
- Override **wins** over detection until the user picks **Auto-Detect** (or
  another language). It is **per-document, session-only** — closing and reopening
  the file reverts to auto-detection.

### Architecture
- `TextDocument` gains `var languageOverride: String?` (nil = auto). The existing
  computed `highlightLanguage` becomes:
  `languageOverride ?? detectedLanguage` (where `detectedLanguage` is the
  extension/content logic — see Feature 2). Everything downstream already reads
  `highlightLanguage`, so highlighter + status bar follow the override for free.
- New `LanguageCatalog` (pure, tested) — the single source of truth: the curated
  common list (id + display name), the full list, and `displayName(for:)`. The
  ad-hoc `displayLanguageName` switch currently in `EditorViewController` moves
  here.
- `StatusBarView` language label → an `NSPopUpButton` styled as an inline label
  (or a label with a click handler that pops an `NSMenu`); it calls back to the
  editor with the chosen id, "auto", or "plaintext".
- `EditorViewController` builds the menu from `LanguageCatalog`, sets
  `document.languageOverride`, calls `highlighter?.setLanguage(...)` +
  `updateStatusBar()`, and marks the active selection.

### Tests
- `LanguageCatalogTests`: common list non-empty; every common id has a display
  name; full list ⊇ common; display-name lookups correct.
- `TextDocument` override (logic): with `languageOverride` set, `highlightLanguage`
  returns it; nil → falls back to detection.
- Editor smoke test: setting an override via the editor handler updates
  `highlightLanguage` and doesn't break rendering.

---

## Feature 2: Content-based detection (shebangs)

### Behavior
- When extension-based detection yields nothing (untitled, or unknown/extension-
  less file), inspect the **first line** for a shebang and map the interpreter to
  a language:
  - `#!/usr/bin/env python`, `#!/usr/bin/python3` → python
  - `#!/bin/sh`, `#!/bin/bash`, `#!/usr/bin/env zsh` → bash
  - `#!/usr/bin/env node` → javascript
  - `#!/usr/bin/env ruby` → ruby
  - `#!/usr/bin/perl` → perl
  - `#!/usr/bin/env lua` → lua
  - `#!/usr/bin/env php` → php
- Extension match always takes precedence over shebang. A manual override (Feature
  1) takes precedence over both.

### Architecture
- New `ShebangDetector` (pure, tested): `language(forFirstLine:) -> String?`.
- `TextDocument` gains a `detectedLanguage` that combines:
  `LanguageMap.language(forURL:)` ?? `ShebangDetector.language(forFirstLine: firstLine(of: text))`.
  `highlightLanguage` = `languageOverride ?? detectedLanguage`.
- The status bar refreshes after edits anyway (it already calls `updateStatusBar`
  on text change), so a freshly-typed shebang updates the language live.

### Tests
- `ShebangDetectorTests`: each interpreter form → expected language; bare
  `#!/bin/sh`; no shebang → nil; non-shebang first line → nil; `env`-style and
  direct-path forms; version-suffixed (`python3`).
- `TextDocument`: extension beats shebang; shebang used when no extension; override
  beats both.

---

## Feature 3: Encoding / line-ending picker

### Behavior
- The status bar's **encoding** label becomes a clickable popup (UTF-8, UTF-16,
  ISO Latin-1, ASCII…). A **separate** line-ending popup (LF / CRLF) sits beside
  it.
- Picking an **encoding** offers two operations (an action sheet / submenu):
  - **Reinterpret** — re-decode the *existing file bytes* as the chosen encoding
    (fixes mojibake from a wrong auto-detection). Only available for a
    saved/loaded file whose original bytes are known.
  - **Convert** — keep the current text; write it in the chosen encoding on the
    next save. Always available.
- Picking a **line ending** sets the EOL used on save (LF or CRLF); optionally
  normalizes the in-memory text's line endings immediately so the choice is
  visible. (Decision: normalize in-memory on pick, so Save writes consistently and
  the user sees the change reflected by the status bar.)

### Architecture
- `TextDocument`:
  - Already has `fileEncoding` + `writesBOM`. Add `lineEnding: LineEnding` (enum
    `.lf` / `.crlf`), detected on read (default `.lf`; `.crlf` if the loaded text
    contains `\r\n`).
  - Retain the **original file bytes** (`originalData: Data?`) from `read(from:)`
    so **Reinterpret** can re-decode them. `data(ofType:)` already encodes via
    `TextEncodingDetector.encode`; extend it to apply the chosen line ending and
    encoding.
  - `reinterpret(as encoding:)` — re-decode `originalData` with the new encoding,
    replace `text`, update `fileEncoding`. `convert(to encoding:)` — just set
    `fileEncoding` (applied on save).
  - `setLineEnding(_:)` — set `lineEnding`, normalize `text` EOLs to match.
- New `LineEndings` (pure, tested) helper: detect dominant EOL of a string;
  normalize a string to LF or CRLF. (`TextHygiene` already handles final-newline;
  keep EOL-normalization separate and tested.)
- `EncodingCatalog` (pure, tested): the user-selectable encodings (id +
  `String.Encoding` + display name), reusing `TextEncodingDetector.displayName`.
- `StatusBarView`: encoding popup + line-ending popup; callbacks to the editor.
- `EditorViewController`: build the menus, route Reinterpret/Convert and the EOL
  choice to `TextDocument`, re-highlight (encoding can change text) + refresh
  status bar.

### Tests
- `LineEndingsTests`: detect LF vs CRLF vs mixed (dominant wins); normalize LF→CRLF
  and CRLF→LF; empty string; no line breaks.
- `EncodingCatalog`: lists the expected encodings with correct display names.
- `TextDocument` (logic): `reinterpret(as:)` re-decodes original bytes (round-trip
  a known Latin-1 vs UTF-8 byte sequence); `convert(to:)` changes save encoding
  without altering text; `setLineEnding` normalizes EOLs.

---

## Feature 4: Reload-on-external-change

### Behavior
- medit watches the open document's file for on-disk changes (modification by
  another program). Default response is a **non-blocking banner** at the top of the
  editor: "This file has changed on disk." with a **Reload** button (and a dismiss
  ✕). It never reloads without an explicit click.
- A **Settings** preference `externalChangePolicy` chooses the response:
  - **Notify** (default) — the banner above.
  - **Prompt** — a modal alert: Reload (discard unsaved edits) / Keep My Version.
    If the document has no unsaved edits, reload silently.
  - **Auto-reload if clean** — if there are no unsaved edits, reload silently;
    only prompt when unsaved edits would be lost.
- **Deleted file**: if the file is removed/moved while open, keep the in-memory
  text and mark the document **modified** (so it can be re-saved back). Show a
  one-time notice in the banner ("The file has been moved or deleted.").

### Architecture
- `NSDocument` is already an `NSFilePresenter` and receives file-coordination
  callbacks. Prefer overriding `NSDocument.presentedItemDidChange()` and
  `presentedItemDidMove(to:)` / `accommodatePresentedItemDeletion(completionHandler:)`
  on `TextDocument` — the document-app-native path — rather than a raw
  `DispatchSource`. (If those prove unreliable in practice, fall back to a
  `DispatchSource.makeFileSystemObjectSource` on the `fileURL`; note which path was
  taken.) The callback marshals to the main thread and applies the policy.
- `TextDocument` (or the window controller) owns the watcher for its URL.
  `NSDocument` already exposes change tracking (`isDocumentEdited`); use it to
  decide clean-vs-dirty for the policies.
- A reload banner view (reuse the zero-height-collapse pattern used by the find
  bar / status bar) hosted in the editor container, shown on a detected change per
  policy.
- `Preferences` gains `externalChangePolicy` (enum stored as String; default
  `.notify`), surfaced as a small popup in Settings.
- Reload uses the existing `NSDocument` revert path (`revertToSaved` /
  `read(from:)`), which already refreshes the editor (`documentTextDidReload`).

### Tests
- The policy decision is pure: `ExternalChangeResolver.action(policy:isDirty:) ->
  {.reloadSilently, .prompt, .banner}` — tested across the policy × dirty matrix.
- `Preferences`: `externalChangePolicy` default `.notify`, persists.
- The NSFilePresenter / filesystem callback is I/O-timing-dependent and hard to
  unit-test headlessly; cover the *decision* logic (above) and the banner show/hide
  via an editor smoke test (simulate a detected change → banner appears, Reload
  calls revert path). Document that the raw FS callback is verified manually.

---

## Cross-cutting

**Status bar** becomes interactive for three fields (language, encoding, line
endings). It currently uses plain `NSTextField` labels in an `NSStackView`; the
three become clickable popups. Keep the position label and INS/OVR as plain text.
The "dumb display" boundary loosens slightly: the status bar now emits selection
callbacks to the editor (which owns the document mutations) — it does not mutate
the document itself.

**New preferences:** `externalChangePolicy` (default `.notify`). (Language and
encoding choices are per-document session state, NOT preferences.)

**New pure-logic units (all tested like TextSearch/TextHygiene):**
`LanguageCatalog`, `ShebangDetector`, `LineEndings`, `EncodingCatalog`,
`ExternalChangeResolver`.

**Render regression:** every status-bar/editor change must keep the existing
render smoke tests green (text visible, non-zero frame, ruler/find-bar/status-bar
behavior). Encoding reinterpret changes `text`, so re-highlighting must still
render.

## Testing strategy

Same as 1.2: correctness in pure, exhaustively-tested value units; editor/status-
bar behavior in headless smoke tests; render-regression guards retained. All via
`swift test`. The only piece not fully unit-testable is the NSFilePresenter /
filesystem-change callback (timing/IO) — its decision logic is extracted and
tested; the live callback is verified manually. No app launch in any test.

## Commit breakdown (independently-committable)

1. `LanguageCatalog` + tests.
2. `ShebangDetector` + tests; `TextDocument.detectedLanguage`.
3. Manual language override: `TextDocument.languageOverride` + status-bar language
   popup + editor wiring + smoke test.
4. `LineEndings` + `EncodingCatalog` + tests.
5. Encoding/line-ending picker: `TextDocument` reinterpret/convert/setLineEnding +
   status-bar popups + editor wiring.
6. `ExternalChangeResolver` + tests; `externalChangePolicy` preference.
7. External-change detection (NSFilePresenter callbacks on `TextDocument`) +
   reload banner + editor wiring + smoke test.
8. Version bump to 1.3.0 + README + tag (tag gated on user).

## Out of scope (→ later)

Sidebar file browser (1.4); color scheme picker (1.5); snippets; plugins;
multi-cursor; LSP/autocomplete.
