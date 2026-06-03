# Spec Summary — Rendered Theme Polish (rendered-theme-12)

## Feature

The current markdown rendered view uses a partial custom theme that only styles headings, body text, inline code, bold, and italic. Every other block element — tables, code blocks, blockquotes, paragraphs, links, list items, and thematic breaks — renders with the library's bare-minimum defaults: no cell padding in tables, no background on code blocks, plain-text blockquotes, no paragraph spacing. This feature replaces that partial theme with `Theme.gitHub` as the base, inheriting its polished treatment of all those elements for free, while preserving the one meaningful custom behavior already in place: heading sizes that scale with the user's Dynamic Type accessibility setting in iOS Settings.

## What it does

When a user opens a rendered Markdown document, all block elements now render with GitHub-style visual treatment: tables have padded cells and alternating row backgrounds that make rows easy to scan; code blocks have a secondary background fill and rounded corners; blockquotes have a left-border accent and a tinted background; paragraphs have consistent line spacing and bottom margins; links render in GitHub blue with proper light/dark mode adaptation; thematic break dividers have appropriate margins. Heading sizes continue to scale proportionally if the user changes their text size in iOS Accessibility settings. No other part of the app changes — the editor, file handling, and mode switching are untouched.

## Risks carried

No risks acknowledged.

## Out of scope

- Raw editor, mode switcher, document model, document browser entry.
- Custom color palette beyond what `Theme.gitHub` provides.
- Any new block element types not already supported by swift-markdown-ui.
- VoiceOver trait changes (covered by feature 8).

## Build preview

1 wave, 1 task. The entire feature is a single method edit in a single file (`MarkdownThemeFactory.swift`). Comfortably fits in one short build session with margin to spare. No new dependencies, no new files, no deploy path changes.

## Next step

Start a new session and run `/build feature-name: rendered-theme-12`.
