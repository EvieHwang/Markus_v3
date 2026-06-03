# Feature Declaration — Rendered Theme Polish

## What

Replace the partial custom `MarkdownThemeFactory` theme with `Theme.gitHub` as the base, overriding only the `text` and `heading1`–`heading6` properties to preserve Dynamic Type-aware sizing. All other block elements — table cell padding and alternating-row backgrounds, code block backgrounds and rounded corners, blockquote left-border styling, paragraph line spacing and margins, link color, list item spacing, and thematic break dividers — come from the GitHub theme without custom code.

## Why

The current `MarkdownThemeFactory.makeTheme()` configures only text, code inline, strong, emphasis, and headings. Every other block element renders with the library's bare minimum defaults: tables have no cell padding, code blocks have no background, blockquotes are unstyled, and paragraphs have no spacing. The GitHub theme is a complete, polished, widely-recognized standard for markdown rendering. Using it as a base delivers all of those missing treatments for free while keeping the one meaningful custom behavior already in place: heading sizes that scale with the user's Dynamic Type accessibility setting.

## Success

- Tables render with 6pt vertical and 13pt horizontal cell padding, alternating row backgrounds, and a visible border — matching `Theme.gitHub`.
- Code blocks render with a secondary background, rounded corners, and horizontal scrolling for long lines.
- Blockquotes render with a left-border accent and a secondary background tint.
- Paragraphs have consistent line spacing and bottom margin.
- Links render in the GitHub-defined blue (light/dark-mode adaptive).
- Thematic breaks render as a styled divider with margins.
- Heading font sizes still scale proportionally when the user changes their Dynamic Type size in iOS Settings — the rendered view reflects the change on next appearance without an app restart.
- No visual regression in existing heading, inline code, strong, or emphasis rendering.

## Shape touched

- **Rendered view** — `MarkdownThemeFactory.swift` only. No changes to `RenderedView.swift` or any other file.

## Out of scope

- Raw editor, mode switcher, document model, document browser entry.
- Custom color palette beyond what `Theme.gitHub` provides.
- Any new block element types not already supported by swift-markdown-ui.
- Changes to VoiceOver traits or any other accessibility metadata (covered by feature 8).
