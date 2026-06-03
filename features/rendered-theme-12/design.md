# Design — Rendered Theme Polish (rendered-theme-12)

## Overview

This feature replaces the `Theme()` base in `MarkdownThemeFactory.makeTheme()` with
`Theme.gitHub`, then removes the `code`, `strong`, and `emphasis` overrides (subsumed
by `Theme.gitHub`), and retains only the `text` and `heading1`–`heading6` overrides
that enforce Dynamic Type-aware sizing. The result is a theme that delivers complete
GitHub-style block-element rendering without any new custom code for tables,
blockquotes, code blocks, paragraph spacing, links, or thematic breaks.

No other file changes. `RenderedView.swift` is untouched.

---

## Components and Responsibilities

### `MarkdownThemeFactory` (sole component)

Location: `Markus_v3/Views/MarkdownThemeFactory.swift`

Responsible for:

- Producing the `MarkdownUI.Theme` value that `RenderedView` applies via
  `.markdownTheme(MarkdownThemeFactory.makeTheme())`.
- Exposing `bodyFont()` and `headingFont(level:)` as testable static entry points so
  the Dynamic Type contract can be verified without inspecting the SwiftUI view tree.

After this change the factory has three distinct zones:

| Zone | What it does |
|------|-------------|
| Base | `Theme.gitHub` — provides complete styling for all block and inline elements not overridden below |
| `text` override | Forces body text to track `UIFont.preferredFont(forTextStyle: .body)`, enabling Dynamic Type scaling |
| `heading1`–`heading6` overrides | Apply em-relative sizes and `.semibold` weight anchored to the body font size, preserving the typographic hierarchy at every Dynamic Type size; each heading retains `.isHeader` accessibility trait |

Removed overrides (now subsumed by `Theme.gitHub`):
- `.code { ... }` — `Theme.gitHub` provides monospaced inline code styling.
- `.strong { ... }` — `Theme.gitHub` provides semibold weight.
- `.emphasis { ... }` — `Theme.gitHub` provides italic style.

---

## Architectural Approach: `Theme.gitHub` Chaining

`Theme.gitHub` is a static computed property on `MarkdownUI.Theme` that returns a
fully-configured theme. In swift-markdown-ui 2.4.1 every theme-builder method
(`text`, `heading1`, `codeBlock`, `tableCell`, etc.) is defined on `Theme` with value
semantics: it copies the current theme, replaces the named element's style, and returns
the new theme. This means any sequence of `.element { ... }` calls chained on
`Theme.gitHub` produces a new `Theme` value that inherits every unmentioned element
from `Theme.gitHub` and replaces only the elements named in the chain.

The factory method becomes:

```swift
Theme.gitHub
    .text { ... }         // Dynamic Type body size
    .heading1 { ... }     // em-relative, semibold, .isHeader
    ...
    .heading6 { ... }
```

No element other than `text` and `heading1`–`heading6` appears in the chain. The
absence of an override for a given element is the active decision: it means that
element's rendering comes entirely from `Theme.gitHub` with no maintenance burden.

This is the minimal-override principle. Adding any override for an element whose
`Theme.gitHub` behavior is already correct is a violation of FM-6 (requirements.md)
and must not be done.

---

## Behavioral Constraints

These are observable properties of the system, not implementation call signatures.

**BC-1 — Tables are visually structured.**
A rendered GFM table has visible cell padding, alternating row backgrounds, and a
header-body border. The styling matches what `Theme.gitHub` produces in swift-markdown-ui
2.4.1.

**BC-2 — Code blocks are visually distinct from prose.**
A fenced code block has a filled background (distinct from the surrounding prose
background in both light and dark mode), rounded corners, and supports horizontal
scrolling for lines wider than the viewport.

**BC-3 — Blockquotes carry a left-border accent and secondary background tint.**
A blockquote is visually offset from prose by at least two cues (accent border and
background tint). Both cues come from `Theme.gitHub`.

**BC-4 — Paragraphs have consistent inter-paragraph spacing.**
Adjacent paragraphs are separated by visible vertical space. Text lines within a
paragraph have a line-height ratio greater than 1.0. Both values come from
`Theme.gitHub`.

**BC-5 — Links are visually distinct from body text.**
Link foreground color differs from body text foreground color in both light and dark
mode. The specific colors are those `Theme.gitHub` resolves for the active color
scheme.

**BC-6 — Thematic breaks render as styled dividers.**
A thematic break (`---`, `***`, `___`) produces a visible horizontal element with
non-zero margins. It is distinguishable from extra paragraph spacing.

**BC-7 — List item spacing reflects tight vs. loose source.**
A loose list (blank lines between items) has greater inter-item spacing than a tight
list (no blank lines). Both states use `Theme.gitHub`'s list/listItem spacing.

**BC-8 — Body font size equals the current system body text size.**
At any moment, the point size of the font returned by `MarkdownThemeFactory.bodyFont()`
equals the point size of the system's current body text preference. When the user
changes Dynamic Type size in iOS Settings, the rendered view reflects the new size on
next appearance without an app restart.

**BC-9 — Heading font sizes are proportional to body and form a strict hierarchy.**
Each heading level's point size equals `bodyFont().pointSize` multiplied by a fixed
em factor (2.00 / 1.50 / 1.25 / 1.00 / 0.875 / 0.85 for levels 1–6). The hierarchy
is strictly descending (H1 > H2 > H3 ≥ H4 > H5 > H6) at every Dynamic Type size from
xSmall to accessibilityExtraExtraExtraLarge.

**BC-10 — Inline code is rendered in a monospaced typeface.**
Backtick-wrapped inline code is visually distinguishable from surrounding prose by
typeface. The specific font is `Theme.gitHub`'s inline code definition.

**BC-11 — Bold text is heavier than body text.**
Text marked as strong renders at a font weight heavier than the surrounding body font
weight. The specific weight is `Theme.gitHub`'s strong definition.

**BC-12 — Italic text uses an italic or oblique style.**
Text marked as emphasis renders in an italic or oblique style. The specific style is
`Theme.gitHub`'s emphasis definition.

**BC-13 — `makeTheme()` completes without error.**
`MarkdownThemeFactory.makeTheme()` returns a `Theme` value at every call site. No
crash, no thrown error, no nil.

**BC-14 — No hard-coded color literals in overrides.**
Colors used in the `text` and heading overrides come from `Theme.gitHub` (inherited),
`Color.primary`, semantic system colors, or adaptive `Color` constructions. No
`Color(red:green:blue:)` or equivalent literal appears in the new code.

---

## Tests That Must Continue to Pass

All tests in `Markus_v3Tests/` must continue to pass. The tests directly relevant to
this feature are in `NativePolish6_TypographyAndMaterialTests.swift`:

| Test | Requirement traceability |
|------|--------------------------|
| `renderedViewBodyMatchesPreferredFont` | AC-8.1: `bodyFont()` point size equals `UIFont.preferredFont(forTextStyle: .body)` |
| `renderedViewBodyUsesBodyStyle` | AC-8.1: body font is not a hard-coded constant |
| `renderedViewHeadingLargerThanBody` | AC-8.2 / AC-8.3: H1 > body |
| `renderedViewHeadingDescent` | AC-8.3: H1 > H2 > H3 ≥ body |
| `renderedViewConstructible` | AC-9.4: `makeTheme()` does not crash |
| `renderedViewAtAccessibilityXL` | AC-8.2 edge case: no overflow or crash at max Dynamic Type size |
| `renderedViewAtAccessibilityXLNoClip` | AC-8.2 edge case: constructible with long content |

These tests call `MarkdownThemeFactory.bodyFont()` and `MarkdownThemeFactory.headingFont(level:)`
directly. Their contracts are unchanged by this feature (AC-8.1, AC-8.2, AC-8.3). The
`makeTheme()` change does not affect these static entry points.

The `RenderedViewTests` suite tests in `RenderedViewTests.swift` call
`MarkdownThemeFactory.makeTheme()` indirectly (via `RenderedView` construction). They
verify constructibility and tap routing; none of them assert on specific theme properties,
so they pass as long as `makeTheme()` does not crash (BC-13).

---

## Seam Relationships

### `MarkdownThemeFactory` → `RenderedView`

`RenderedView.body` calls `MarkdownThemeFactory.makeTheme()` once per body evaluation
and passes the result to `.markdownTheme(...)`. `RenderedView` reads
`@Environment(\.dynamicTypeSize)` to ensure SwiftUI re-evaluates the body when the
Dynamic Type size changes. This causes `makeTheme()` to be called again, picking up
the new `bodyFont().pointSize`. This seam is unchanged by this feature.

### `MarkdownThemeFactory` → test suite

`NativePolish6_TypographyAndMaterialTests.swift` drives `MarkdownThemeFactory.bodyFont()`
and `MarkdownThemeFactory.headingFont(level:)` directly via `RenderedViewTypographyProbe`.
These public static methods are the test-facing contract and must not be removed or
renamed. The probe explicitly does not inspect the SwiftUI view tree, which means
the internal change from `Theme()` to `Theme.gitHub` is invisible to it — the tests
pass by construction.

### `MarkdownThemeFactory` → `Theme.gitHub` (swift-markdown-ui 2.4.1)

`Theme.gitHub` is consumed as-is. This feature introduces no wrapper, subclass, or
indirection around it. If the library version is upgraded and `Theme.gitHub`'s behavior
changes, the behavioral constraints in this document (BC-1 through BC-7) are the
acceptance criteria against which any upgrade is validated.

---

## Pattern Registry Notes

Reuses pattern: **Conventional commits** — the commit for this feature is
`feat(rendered-theme-12): ...` per the constitution's commit pattern.

No other named patterns from `constitution.md`'s pattern registry apply to this
single-file, single-type change.

---

## What This Architecture Does Not Do

- Does not add any new Swift types, protocols, or extension files.
- Does not change `RenderedView.swift` or any other file outside `MarkdownThemeFactory.swift`.
- Does not introduce custom rendering for block elements handled by `Theme.gitHub`.
- Does not add platform-version guards: `Theme.gitHub` is available in
  swift-markdown-ui 2.4.1 which is already a project dependency.
- Does not affect the raw editor, mode switcher, document model, or document browser.

---

## Requirements Changes

Architecture stable — no requirements changes flagged.

The requirements document already specifies `Theme.gitHub` as the base, names the exact
overrides to keep (`text`, `heading1`–`heading6`), names the overrides to remove
(`code`, `strong`, `emphasis`), and constrains the implementation to `MarkdownThemeFactory.swift`
only. The architecture maps directly onto those constraints without friction.
