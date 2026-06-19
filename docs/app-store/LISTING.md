# medit — Mac App Store Listing Copy

Draft metadata for the App Store Connect listing. Free app, Developer Tools
category. Fill these into App Store Connect when the account is live.

---

## Name (30 char max)

**Primary:** `medit`
**Fallback (if "medit" is taken):** `medit — Text Editor`

## Subtitle (30 char max)

`A native, no-fuss text editor`

*(Alternates: "Simple native code & text editor" · "Native editor with Markdown")*

## Promotional Text (170 char max — editable anytime without review)

`Fast, native macOS editing: syntax highlighting, regex find, a folder sidebar,
live Markdown preview, column editing, and word count. No clutter, no Electron.`

## Keywords (100 char max, comma-separated, no spaces needed)

`text editor,code editor,markdown,syntax highlighting,programmer,notepad,source,regex,native,sandbox`

*(99 chars — under the 100 limit. Drop "sandbox" or "notepad" if App Store counts
it differently.)*

## Description (4000 char max)

```
medit is a fast, native macOS text editor for code and plain text — the simple,
no-friction editing of a classic editor, built with AppKit so it feels like it
belongs on the Mac. No web view, no heavyweight runtime, no clutter.

EDITING
• Syntax highlighting for 70+ languages, auto-detected (and from shebang lines).
• Light/dark themes that follow your system appearance.
• Line numbers, soft word wrap, auto-indent, and auto-closing brackets.
• Rainbow brackets — matching pairs colored by depth, with the caret's pair
  emphasized.
• Show Invisibles, and strip-trailing-whitespace-on-save.

FIND & NAVIGATE
• A real regex find & replace bar with match-case and capture-group replacement.
• Find in All Tabs — search every open document at once and jump to a result.
• Go to Line.

MARKDOWN
• A natively rendered Markdown preview (no web view): full GitHub-Flavored
  Markdown with custom-drawn code panels, bordered tables, and heading rules.
• A one-click formatting toolbar for Markdown files.
• Print the rendered document, or plain text with optional line numbers.

POWER TOOLS
• Column (block) editing — select a vertical rectangle and type, delete, or
  copy across many rows at once. Great for tidying aligned terminal output.
• Sort Lines and Change Case.
• A live word / line / character count in the status bar.

FILES & SESSIONS
• An optional multi-root folder sidebar with a Recent Files pane.
• Native window tabs; drag files in from Finder to open them.
• Reopens your last session and remembers your window's size and position.
• Faithful encoding handling (UTF-8/16/32, BOM-aware) and LF/CRLF line endings.

medit runs in the macOS App Sandbox and collects no data of any kind. It's free
and open source under the MIT license.
```

## What's New (per-update; example for the launch build)

```
First App Store release of medit — a native, no-fuss macOS text editor with
syntax highlighting, regex find & replace, a folder sidebar with recent files,
native Markdown preview, column (block) editing, sort/case tools, and a live
word count.
```

## Support / Marketing URLs

- **Support URL:** the repository's Issues page (or a simple support page).
- **Marketing URL:** the repository README (or a project page).

## Privacy

- **Privacy nutrition label:** *Data Not Collected.*
- **Privacy policy URL:** a one-line "medit collects no data" page (App Store
  requires a URL even when nothing is collected).

## Category / rating / price

- **Category:** Developer Tools (matches `LSApplicationCategoryType`).
- **Age rating:** 4+.
- **Price:** Free (Tier 0), no in-app purchases.

## Character-count check

| Field | Limit | Draft length |
|-------|-------|--------------|
| Name | 30 | "medit" (5) / fallback (19) |
| Subtitle | 30 | "A native, no-fuss text editor" (29) |
| Promo text | 170 | ~150 |
| Keywords | 100 | 99 |

*(Verify exact lengths in App Store Connect; trim keywords first if over.)*
