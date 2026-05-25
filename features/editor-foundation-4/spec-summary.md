# Spec Summary: editor-foundation-4

## Feature

The walking skeleton used SwiftUI's `TextEditor` as a lightweight placeholder for the raw editing surface — intentionally minimal, with no access to the underlying UIKit layer. Two Roadmap features require direct UIKit control that `TextEditor` cannot provide: scroll-anchor preservation (Roadmap #4) needs to read and set scroll position, and native editing polish (Roadmap #6) needs to configure text input traits and intercept keystrokes. This feature delivers both together by first migrating `RawEditorView` to a proper `UITextView`-based implementation, then building the two features on top of that foundation. The migration is transparent to the user; the new behaviors are immediately noticeable.

## What it does

When a user switches from the formatted rendered view to the raw editor by tapping anywhere on the document, the raw editor opens scrolled to approximately the same position — the cursor lands near where the tap occurred, rather than always at the top. The reverse is equally smooth: tapping the eye icon to return to rendered view carries the scroll position across, so the user continues reading from roughly where they were editing. Both transitions include a brief cross-fade so there is no distracting jump from the top of the document.

In the raw editor itself, the user will notice three quality-of-life improvements compared to the walking skeleton:

1. **Smart quotes and em-dashes are suppressed.** Typing `"`, `'`, or `--` produces literal characters, which is what markdown source requires.
2. **Spell check and autocorrect are active.** Prose writers get red underlines on misspelled words and the QuickType correction bar, just as they would in Notes or Mail.
3. **List continuation works.** Pressing return at the end of a `- item`, `* item`, `+ item`, or `1. item` line automatically starts the next line with the same prefix (ordered lists increment the number). Pressing return on an empty list item exits the list. This is the one markdown-aware behavior in the editor.

## Risks carried

No risks acknowledged.

## Out of scope

- Syntax highlighting or any visual formatting in the editor
- Markdown auto-formatting beyond list continuation (no auto-pairing, no heading insertion)
- `Cmd+/` keyboard shortcut
- Swipe-to-switch-mode gesture
- Any user-configurable settings or toggles
- Accessibility labeling pass (Roadmap #7, Bundle C)
- Tab/shift-tab list indentation

## Build preview

4 waves, 7 tasks. Wave 1 (T-001–T-004) creates the four independent foundation types in parallel; Wave 2 (T-005) assembles them into the `UIViewRepresentable` bridge; Wave 3 (T-006) replaces `RawEditorView`; Wave 4 (T-007) wires the scroll-anchor state into `DocumentView` and `RenderedView`. The DAG fits comfortably in one build session.

## Next step

Start a new session and run `/build feature-name: editor-foundation-4`.
