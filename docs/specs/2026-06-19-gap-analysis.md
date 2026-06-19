# medit — Competitive Gap Analysis (June 2026)

**Scope:** medit is a **gedit-class** simple native editor. This compares it only
against peers of **similar or lower** complexity — simple editors and Markdown
viewers/editors across macOS, Windows, and Linux. **VS Code, Sublime, full IDEs,
and Kate's IDE-tier features are explicitly out of scope** (medit does not aim for
that market).

Peers surveyed: **macOS** — CotEditor, BBEdit (free tier), TextEdit, TextMate,
MacDown, Typora, OneMarkdown. **Windows** — Notepad++, modern Notepad,
Notepad2/3/4. **Linux** — gedit (v49), GNOME Text Editor, Geany, Mousepad, Pluma,
Leafpad. (Kate included for reference but treated as above-tier.)

---

## What medit has today (v2.2.0)

Syntax highlighting (72 languages via highlight.js) · regex find/replace with
case toggle · **find in all tabs** · Go to Line · native window **tabs** ·
multi-root **sidebar file browser** · **Recent Files** pane · **Markdown rendered
preview** (native, GFM, custom-drawn) · **Markdown formatting toolbar** ·
printing (rendered MD + plain w/ line numbers) · line numbers · status bar
(position/encoding/language/line-ending/wrap) · auto-indent · auto-close brackets ·
rainbow brackets + enclosing-pair emphasis · show invisibles · multiple
**encodings** with reinterpret-vs-convert · **line-ending** detection/conversion ·
reload-on-external-change · light/dark themes · spell check / smart quotes etc. ·
strip-trailing-whitespace-on-save · drag-and-drop open (single + multi) · window
frame persistence · PC-style navigation keys.

---

## Table-stakes (what nearly every peer has) — medit status

| Feature | Peers have it | medit |
|---|---|---|
| Syntax highlighting | ~all (except TextEdit, Notepad, Leafpad) | ✅ 72 langs |
| Find/replace + **regex** | ~all serious editors | ✅ |
| Multiple encodings (open/save) | universal | ✅ (+ reinterpret vs convert) |
| Line-ending CRLF/LF/CR convert | ~all | ✅ |
| Tabs / multi-document | ~all | ✅ native |
| Themes incl. dark mode | ~all | ✅ |
| Auto-indent | universal | ✅ |
| Printing | universal | ✅ (incl. rendered MD) |
| Line numbers, bracket match, word wrap, zoom | ~all | ✅ (zoom = ?) |
| Go-to-line + status bar | ~all | ✅ |
| Spell check | most | ✅ |
| **Session restore (reopen last files)** | **near-universal now** | ⚠️ **GAP (see below)** |
| **Word/char count** | common (gedit, N++, CotEditor, BBEdit) | ❌ **GAP** |

**medit clears almost every table-stakes line** — a strong position for its tier.
Two table-stakes gaps stand out (below).

---

## Gaps — ranked by how expected they are in this tier

### Tier 1 — table-stakes medit is MISSING (fix these first)

1. **Session restore of open files/tabs.** Near-universal now: gedit, Geany,
   Pluma, Mousepad reopen last files; **GNOME Text Editor and modern Windows
   Notepad made *unsaved-draft* restore a signature feature**. medit currently
   only restores the window **frame** — and **2.2.0's `isRestorable = false`
   actively stops macOS from reopening last session's documents.** So medit went
   slightly *backwards* here. **Highest-value gap.** Options: re-enable doc
   restoration (decoupled from frame), or persist the open-file list ourselves and
   reopen on launch.

2. **Word count / document statistics.** Live char/word/line count is in
   CotEditor (live in status bar), BBEdit, gedit, Notepad++, Pluma. It's a
   *surprisingly common gap* (Mousepad, GNOME TE, TextEdit lack it) — which makes
   it both expected and an easy win. medit has none. Cheap to add to the existing
   status bar.

### Tier 2 — common in the tier; deliberate choice whether to add

3. **Sort lines + Change Case.** Standard "text munging" in gedit (core Sort +
   Change Case plugins), CotEditor, BBEdit, TextMate, Geany, Pluma, Notepad++.
   medit has neither. Small, self-contained, very on-brand for a gedit emulator.

4. **Editor split view (same document or two docs side-by-side).** Real split in
   Kate, Geany, Notepad++ (2-view), CotEditor, BBEdit; gedit has tab-groups.
   medit's only split is the *Markdown source+preview* split (and that's on an
   unshipped branch). A general editor split is a moderate effort.

5. **Snippets.** gedit *used* to (removed in v49), CotEditor/TextMate/Geany/Pluma
   have them. Genuinely useful but more than a quick win; lower priority for the
   tier (and current gedit no longer has it).

### Tier 3 — Markdown-specific (medit is already differentiating here)

6. **Live/inline (WYSIWYG) Markdown editing.** Owned by Typora; OneMarkdown does
   inline rich rendering. We deliberately scoped to *rendered preview + style bar*
   (the planned "edit the rendered view" was assessed as a multi-session,
   file-corruption-risk epic and deferred — split view was chosen instead). Not a
   gap so much as a known, deliberate boundary.

7. **Mermaid / LaTeX math / diagrams in Markdown.** Typora, OneMarkdown render
   these. medit's preview doesn't. Optional polish, not table-stakes.

### Tier 4 — differentiators

- **Column/rectangular block editing** — **wanted, but DEFERRED to a future
  version** (decided 2026-06-19): genuinely useful for scraping aligned terminal
  output. NSTextView collapses multiple zero-width carets to one, so block *typing
  into empty columns* needs a custom rectangular-caret model (a real sub-project) —
  deferred out of 2.3. The pure `ColumnSelection` model + tests are in the tree as
  the foundation. See the 2.3 Editor Essentials spec.
- **Multi-cursor** — only Notepad++ & Kate (and gedit *lost* it in v49). Not
  expected of a gedit-class app. **Deliberate non-goal.**
- **Minimap** — essentially no simple editor in-tier has it (a VS Code/Sublime
  thing). **Skip.**
- **Macros / "filter through shell command" / scripting** — TextMate, BBEdit
  (paid), Kate, N++. Power-user territory; out of tier.
- **Plugin system** — N++, Geany, (old) gedit. Big architectural commitment;
  current gedit gutted its Python plugins, so even the emulation target moved
  away. **Skip for now.**

---

## Where medit is already AHEAD of its closest peers

- **CotEditor** (the closest native macOS peer) has **no rendered Markdown
  preview** and **no folder/file-tree sidebar**. medit has **both**.
- **gedit / GNOME Text Editor** have **no Markdown preview**; GNOME TE has no
  sidebar and no word count either.
- medit's **Recent Files sidebar pane**, **rainbow brackets + enclosing-pair
  emphasis**, **reinterpret-vs-convert encoding distinction**, and **find-in-all-
  tabs** are all at or above the tier norm.

**Strategic read:** medit's combination of *CotEditor-class native core +
rendered Markdown preview + folder sidebar* is a lane **no single simple native
editor cleanly owns today**. That's the differentiation to protect.

---

## Recommended priority order

1. **Fix session restore** (reopen last files/tabs; reconcile with the 2.2.0
   `isRestorable=false` change) — table-stakes, and we regressed it.
2. **Word count in the status bar** — table-stakes-ish, cheap, high visibility.
3. **Sort Lines + Change Case** (Edit menu) — small, on-brand, expected.
4. **Editor split view** — moderate; rounds out the "complete simple editor" feel.
5. (Optional) Markdown Mermaid/math; snippets — only if the roadmap wants them.

Everything in Tier 4 is a deliberate **non-goal** for medit's tier and should be
left out unless a specific user need arises.
