# Markdown Kitchen Sink — every element

A fixture exercising every Markdown element medit's preview renders. Open it and
press ⇧⌘V to review the rendering.

## Headings

# Heading 1
## Heading 2
### Heading 3
#### Heading 4
##### Heading 5
###### Heading 6

## Inline formatting

Plain text with **bold**, *italic*, ***bold italic***, ~~strikethrough~~, and
`inline code`. A [link to example.com](https://example.com), an
autolink <https://swift.org>, and a [reference link][ref].

[ref]: https://www.markdownguide.org

Hard line break below this line (two trailing spaces):  
…and this is the next line.

## Lists

Unordered:

- First item
- Second item
  - Nested item A
  - Nested item B
    - Deeper still
- Third item

Ordered:

1. One
2. Two
   1. Two-point-one
   2. Two-point-two
3. Three

Task list (GFM):

- [ ] Unchecked task
- [x] Checked task
- [ ] Another to do
  - [x] A checked subtask

## Blockquotes

> A single-line quote.

> A multi-paragraph quote.
>
> Second paragraph, with **bold** and a [link](https://example.com) inside.
>
> > A nested quote inside a quote.

## Code

Inline: use `let x = 1` or `git status` in a sentence.

Fenced block (no language):

```
func greet(_ name: String) -> String {
    return "Hello, \(name)!"
}
```

Fenced block (with a language hint):

```swift
struct Point {
    var x: Double
    var y: Double
    func distance(to other: Point) -> Double {
        ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot()
    }
}
```

Indented code block:

    indented line one
    indented line two

## Tables (GFM)

| Left | Center | Right |
|:-----|:------:|------:|
| a    | b      | c     |
| longer cell | mid | 42 |
| `code` | **bold** | *italic* |

A simple two-column table:

| Key | Value |
|-----|-------|
| name | medit |
| kind | editor |

## Thematic breaks

Above the rule.

---

Between rules.

***

Below the rule.

## Mixed / nesting

1. An ordered item with **bold**, a `code span`, and a [link](https://example.com).
2. An item containing a quote:
   > Quoted text inside a list item.
3. An item containing a code block:
   ```
   nested in a list
   ```

- A bullet with a task list under it:
  - [x] done
  - [ ] not done

## Edge cases

Text with an ampersand & a less-than < and a greater-than > to check escaping.

Emoji and unicode: ✓ ✗ → ★ — “curly quotes” and an em–dash.

A very long paragraph to check wrapping and line height: Lorem ipsum dolor sit
amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et
dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco
laboris nisi ut aliquip ex ea commodo consequat.

The end.
