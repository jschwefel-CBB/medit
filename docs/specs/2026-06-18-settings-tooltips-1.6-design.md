# medit 1.6 — Settings tooltips (design)

**Goal:** Every interactive control in the Settings window gets a help tooltip
that explains the setting's *effect* (not just restates its label), following
standard macOS conventions.

**Scope:** UI-text-only change in `PreferencesWindowController.buildUI()`. No
behavior, preference, or layout changes. Also a version bump to 1.6.0 and a
release. Section headers (bold labels) get no tooltip.

## Tooltip conventions (macOS standard)

- Set `control.toolTip` on each interactive control (`NSButton` checkbox,
  `NSPopUpButton`, `NSTextField` value field, and the font `Change…` button).
  AppKit shows the tooltip on hover after the standard delay.
- Short, plain-language, sentence case, **no trailing period** (Apple HIG style
  for help tags). Describe what the setting does / what turning it on changes —
  add information beyond the visible label.
- For the row-label fields (e.g. "Tab width:"), the tooltip goes on the *value
  control* (the field/popup), which is what the user hovers and interacts with.

## Controls and proposed tooltip text

**Top**
- Font `Change…` button → `Choose the editor's font family and size`
- Appearance popup → `Match the system appearance, or force a light or dark theme`

**Editor**
- Show line numbers → `Display a line-number gutter down the left edge`
- Wrap long lines → `Wrap text to the window width instead of scrolling horizontally`
- Show status bar → `Show the bottom bar with line/column, language, and encoding`
- Show invisibles → `Reveal spaces, tabs, and line breaks as faint marks`
- Text padding (field) → `Blank space between the text and the editor's edges, in points`

**Brackets**
- Rainbow brackets → `Color brackets by nesting depth so matching pairs are easy to spot`
- Emphasize enclosing pair at caret → `Highlight the bracket pair that surrounds the cursor`
- Enclosing-pair emphasis (popup) → `How the enclosing pair is emphasized: bold, underline, or background`

**Smart Substitutions**
- Smart quotes → `Convert straight quotes to curly typographic quotes as you type`
- Smart dashes → `Convert double hyphens to en and em dashes as you type`
- Automatic text replacement → `Apply your macOS text-replacement shortcuts while typing`
- Correct spelling automatically → `Fix misspellings automatically as you type`
- Smart copy/paste spacing → `Adjust spaces automatically when cutting and pasting words`
- Check spelling while typing → `Underline misspelled words as you type`

**Indentation**
- Insert spaces instead of tabs → `Indent with spaces rather than tab characters`
- Tab width (field) → `Number of spaces a tab represents`
- PC-style Home/End/Insert keys → `Home/End jump to line start/end, and Insert toggles overwrite`
- Auto-indent new lines → `Match the previous line's indentation on Return`
- Indent between brackets on Return → `Pressing Return between a bracket pair opens an indented line between them`
- Auto-close brackets → `Type an opening bracket and the matching closing one is inserted`
- Strip trailing whitespace on save → `Remove trailing spaces and tabs from each line when saving`

**Files**
- On external change (popup) → `What to do when a file changes on disk outside medit`

**Sidebar**
- Sort folders first → `List folders above files in the sidebar`
- Sort A→Z (off = Z→A) → `Sort sidebar entries alphabetically; turn off to reverse`
- Open on single click → `Open files with a single click instead of a double click`
- Sidebar on the right → `Place the file sidebar on the right side of the window`
- Confirm before deleting → `Ask for confirmation before moving an item to the Trash`
- Reveal the active file → `Select the current document in the sidebar as you switch tabs`

## Testing

- A unit/smoke test asserting every interactive control in the Settings window
  has a non-empty `toolTip` (so future controls can't ship without one). This is
  the durable guard the user asked for ("every setting item, unless good reason").
- `swift test` green; quick live hover check in the built app.

## Out of scope / dropped

- Per-doc-type indent overrides: **removed from the backlog**, not built.
