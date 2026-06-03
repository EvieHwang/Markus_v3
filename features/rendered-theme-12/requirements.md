# Requirements — Rendered Theme Polish (rendered-theme-12)

## Context

`MarkdownThemeFactory.makeTheme()` currently builds a `Theme()` from scratch,
configuring only `text`, `code` (inline), `strong`, `emphasis`, and
`heading1`–`heading6`. Every other block element (tables, code blocks,
blockquotes, paragraphs, links, list items, thematic breaks) falls back to
swift-markdown-ui's bare defaults, producing unstyled or minimally styled
output.

This feature replaces that approach with `Theme.gitHub` as the starting point,
then overrides only `text` and `heading1`–`heading6` to preserve the existing
Dynamic Type-aware sizing contract. The `code`, `strong`, and `emphasis`
overrides are removed; `Theme.gitHub`'s built-in definitions for those inline
elements become the active definitions. All block elements not listed in the
overrides come from `Theme.gitHub` unchanged and require no new code.

The only file changed is `MarkdownThemeFactory.swift`. No changes are made to
`RenderedView.swift` or any other file.

---

## User Stories and Acceptance Criteria

### US-1 — Table rendering

**As a reader viewing a markdown file with a GFM table, I want the table to
render with visible structure so I can distinguish cells and rows at a glance.**

#### AC-1.1 — Cell padding
Table cells carry 6 pt vertical padding and 13 pt horizontal padding, matching
`Theme.gitHub`'s `tableCell` configuration. A table with multi-word cell
content must not appear compressed edge-to-edge.

#### AC-1.2 — Alternating row backgrounds
Even-indexed rows and odd-indexed rows render with visually distinct background
fills. The specific colors are those supplied by `Theme.gitHub`'s
`tableRow` style (secondary-system-fill level), not a custom palette.

#### AC-1.3 — Table border
A table with at least one header row renders a visible border demarcating the
header from the body rows. The border is the one supplied by `Theme.gitHub`.

#### Edge case — empty table body
A GFM table consisting of only a header row and the alignment row (no data
rows) must not crash or produce an empty-space anomaly. Alternating-row logic
produces no output because there are zero data rows.

#### Edge case — single-column table
A table with one column and multiple rows still renders with cell padding and
alternating backgrounds on each row.

---

### US-2 — Code block rendering

**As a reader viewing a markdown file with fenced code blocks, I want code
blocks to be visually distinct from prose so I can identify them without
reading the fence markers.**

#### AC-2.1 — Background color
A fenced code block renders with a secondary-background fill (the exact color
token used by `Theme.gitHub`'s `codeBlock` style). The background is distinct
from the surrounding prose background in both light mode and dark mode.

#### AC-2.2 — Rounded corners
The code block's bounding rectangle has rounded corners. The exact corner
radius is the one supplied by `Theme.gitHub`.

#### AC-2.3 — Horizontal scrolling for long lines
A fenced code block containing a line longer than the viewport width is
scrollable horizontally so the full line is reachable without wrapping.

#### Edge case — empty fenced block
A fenced code block with no content between the fences (` ``` ``` `) renders
the block frame (background, rounded corners) without crashing. The block may
have zero height or minimal height as determined by `Theme.gitHub`.

---

### US-3 — Blockquote rendering

**As a reader viewing a markdown file with blockquotes, I want blockquotes to
be visually distinguished from prose so I can identify quoted or highlighted
passages at a glance.**

#### AC-3.1 — Left-border accent
A blockquote renders with a left-border accent. The accent color and width are
those supplied by `Theme.gitHub`'s `blockquote` style.

#### AC-3.2 — Background tint
A blockquote renders with a secondary-background tint inside its bounding
rectangle. The tint is the one supplied by `Theme.gitHub`.

#### Edge case — nested blockquote
A blockquote nested inside another blockquote (two levels of `>`) renders
without crashing. Visual nesting behavior (indentation, repeated borders) is
whatever `Theme.gitHub` produces; no custom nesting logic is required.

---

### US-4 — Paragraph spacing

**As a reader viewing a markdown file with multiple paragraphs, I want
consistent vertical spacing between paragraphs so prose is easy to scan.**

#### AC-4.1 — Bottom margin
Each paragraph block has a non-zero bottom margin as supplied by `Theme.gitHub`'s
`paragraph` style. Two consecutive paragraphs must not run together without
visible separation.

#### AC-4.2 — Line spacing
Within a paragraph, adjacent lines have a line-height multiplier greater than
1.0 (the exact value is whatever `Theme.gitHub` supplies), making body text
readable without crowding.

#### Edge case — single-line paragraph
A document containing only a single line of prose renders with the paragraph
style applied and does not have an anomalous trailing margin that differs from
a multi-line paragraph's trailing margin.

---

### US-5 — Link color

**As a reader viewing a markdown file that contains hyperlinks, I want links to
be visually distinguishable from surrounding text so I know they are
actionable.**

#### AC-5.1 — Foreground color in light mode
In a light-mode rendering context, a link renders in the foreground color
defined by `Theme.gitHub`'s link style (GitHub blue: `#0969DA`, or its
semantic equivalent as resolved by the library under `.light` trait collection).
The color must not be identical to the body text foreground color.

#### AC-5.2 — Foreground color in dark mode
In a dark-mode rendering context, the link foreground color resolves to
`Theme.gitHub`'s dark-mode link value (GitHub blue: `#58A6FF`, or its semantic
equivalent as resolved by the library under `.dark` trait collection). The
color must not be identical to the dark-mode body text foreground color.

#### Edge case — link with custom title text
A link whose display text differs from its URL still renders entirely in the
link foreground color (every character of the title, not just the first).

---

### US-6 — Thematic break (horizontal rule) rendering

**As a reader viewing a markdown file that contains `---` dividers, I want
thematic breaks to render as visible dividers so I can identify section
boundaries.**

#### AC-6.1 — Styled divider
A thematic break (`---`, `***`, or `___`) renders as a horizontal line or
styled divider as supplied by `Theme.gitHub`'s `thematicBreak` style. It must
not render as an empty gap indistinguishable from extra paragraph spacing.

#### AC-6.2 — Top and bottom margins
The thematic break has non-zero top and bottom margins as supplied by
`Theme.gitHub`, creating visible separation from adjacent content blocks.

---

### US-7 — List item spacing

**As a reader viewing a markdown file with bullet or numbered lists, I want
consistent spacing between list items so lists are easy to scan.**

#### AC-7.1 — Item spacing
List items in a loose list (items separated by blank lines in source) have
visible inter-item spacing as supplied by `Theme.gitHub`'s list or listItem
style. A loose list must not render identically to a tight list (no blank lines
in source).

#### AC-7.2 — Tight list
List items in a tight list (no blank lines between items in source) render
without the extra inter-item spacing applied to loose lists.

---

### US-8 — Dynamic Type heading scaling preserved

**As a user with a non-default Dynamic Type accessibility size, I want heading
text in the rendered view to scale proportionally with the rest of the text so
the typographic hierarchy remains consistent at any text size.**

#### AC-8.1 — Body font tied to UIFont.preferredFont(forTextStyle: .body)
`MarkdownThemeFactory.bodyFont()` continues to return
`UIFont.preferredFont(forTextStyle: .body)`. Its `pointSize` equals the current
system body text size. This contract is unchanged by the migration to
`Theme.gitHub`.

#### AC-8.2 — Heading sizes proportional to body
`MarkdownThemeFactory.headingFont(level:)` continues to return fonts whose
`pointSize` equals `bodyFont().pointSize` multiplied by the em factors below.
The factors are unchanged by the migration:

| Level | Em factor |
|-------|-----------|
| 1     | 2.00      |
| 2     | 1.50      |
| 3     | 1.25      |
| 4     | 1.00      |
| 5     | 0.875     |
| 6     | 0.85      |

Acceptable tolerance: ±0.5 pt (rounding from floating-point arithmetic).

#### AC-8.3 — Monotonic heading hierarchy
`headingFont(level: 1).pointSize` > `headingFont(level: 2).pointSize` >
`headingFont(level: 3).pointSize` ≥ `headingFont(level: 4).pointSize` >
`headingFont(level: 5).pointSize` > `headingFont(level: 6).pointSize`.
This invariant holds at every Dynamic Type size from xSmall to
accessibilityExtraExtraExtraLarge.

#### AC-8.4 — Theme reflects Dynamic Type change on next appearance
`MarkdownThemeFactory.makeTheme()` is called at body-build time inside
`RenderedView`, which reads `@Environment(\.dynamicTypeSize)`. A change to the
Dynamic Type size in iOS Settings causes the rendered view to call
`makeTheme()` again on the next view body evaluation, picking up the new
`UIFont.preferredFont(forTextStyle: .body)` size. No app restart is required.

#### Edge case — Accessibility Extra Extra Extra Large
At the largest Dynamic Type accessibility size, `bodyFont().pointSize` is
large but still finite. `headingFont(level: 1)` is larger than body by the
same 2.0× factor. No overflow or negative size can result because all sizes
are derived by multiplication (never subtraction).

---

### US-9 — No visual regression in preserved inline styles

**As a reader viewing a markdown file with inline code, bold, italic, or mixed
content, I want those elements to continue rendering correctly after the theme
migration.**

#### AC-9.1 — Inline code
Inline code (backtick-wrapped spans) continues to render in a monospaced font.
The font size is `Theme.gitHub`'s inline code size (em(0.85) or library
equivalent). This is a behavioral equivalence: the rendered text is visually
distinguishable from surrounding prose by typeface.

#### AC-9.2 — Bold (strong)
Bold-marked text continues to render at a heavier font weight than the
surrounding body text. `Theme.gitHub` defines this weight; the requirement is
that the weight is heavier than body, not a specific weight value.

#### AC-9.3 — Italic (emphasis)
Italic-marked text continues to render in an italic or oblique font style.
`Theme.gitHub` defines this style; the requirement is that the style differs
from upright body text.

#### AC-9.4 — makeTheme() does not crash
`MarkdownThemeFactory.makeTheme()` returns a `Theme` value without crashing or
throwing at any call site. This is a smoke-level requirement satisfied by any
successful construction.

---

## Failure Modes (what must NOT happen)

**FM-1** — `makeTheme()` must not return `Theme()` (a blank base theme).
Building from `Theme()` strips all `Theme.gitHub` block styling. Verified by
confirming code blocks, blockquotes, and tables do not render with bare-default
(zero-padding, no background) appearance.

**FM-2** — The `text` override must not be removed. Removing it causes the
rendered view to inherit `Theme.gitHub`'s fixed text size instead of the
Dynamic Type-scaled size from `UIFont.preferredFont(forTextStyle: .body)`.

**FM-3** — The `heading1`–`heading6` overrides must not be removed. Removing
them causes headings to inherit `Theme.gitHub`'s fixed point sizes, breaking
the Dynamic Type scaling contract (AC-8.1 through AC-8.3).

**FM-4** — Heading sizes must not revert to fixed point values. A heading
configured as `.fontSize(.pt(24))` or any other absolute value fails AC-8.4
because it does not track Dynamic Type changes.

**FM-5** — `RenderedView.swift` must not be modified. The feature scope is
`MarkdownThemeFactory.swift` only (declaration.md, Shape section). Any change
to `RenderedView.swift` is out of scope and must not appear in the diff.

**FM-6** — A `Theme.gitHub` block element must not be reimplemented as a custom
override. If a block element's styling is already correct in `Theme.gitHub`,
adding a custom override to reproduce its appearance introduces duplication and
maintenance risk. The correct implementation is the absence of a custom
override for that element.

**FM-7** — The `code`, `strong`, and `emphasis` inline overrides present in the
current `makeTheme()` must not be ported to the new implementation. They are
subsumed by `Theme.gitHub`'s built-in definitions; redefining them is a
violation of FM-6.

**FM-8** — Block element styling must not depend on hard-coded color literals
(e.g., `Color(red:green:blue:)`). All colors used in overrides must come from
`Theme.gitHub` (inherited), `Color.primary`, semantic system colors, or
adaptive `Color` constructions that resolve correctly in both light and dark
mode.

---

## Out of Scope

Consistent with the feature declaration:

- **Raw editor** — no changes to `MarkdownEditorTextView.swift` or any raw-mode
  component.
- **Mode switcher** — no changes to transition logic.
- **Document model** — no changes to file access or persistence.
- **Document browser entry** — no changes to app launch or file selection.
- **Custom color palette** — no colors beyond what `Theme.gitHub` provides are
  introduced. If a color from `Theme.gitHub` is undesirable in a future
  iteration, that is a separate feature.
- **New block element types** — only element types already supported by
  swift-markdown-ui 2.4.1 are in scope. Adding support for custom renderers
  (e.g., definition lists, footnotes) is not part of this feature.
- **VoiceOver traits** — `accessibilityAddTraits(.isHeader)` is already present
  on heading builders and must be preserved, but any broader accessibility
  metadata work (landmark roles, list semantics, link activation) is covered by
  feature accessibility-8 and is not in scope here.
- **iPad / Mac layout** — responsive layout (max content width, slide-over
  widths) is covered by backlog item 11 and is not in scope.
- **Inline code, strong, and emphasis overrides** — these are removed in the
  migration (subsumed by `Theme.gitHub`). No new behavior for them is required.

---

Requirements stable — no architectural feedback to incorporate
