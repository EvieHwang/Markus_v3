# Declaration: editor-foundation-4

## What

Migrate `RawEditorView` from SwiftUI `TextEditor` to a `UITextView` subclass via `UIViewRepresentable`, and deliver two Roadmap features that require direct `UITextView` access in the same session: fractional scroll-anchor preservation across mode switches (Roadmap #4), and native editing polish — smart-quote/dash suppression, spell check on, and list continuation on return (Roadmap #6).

## Why

The walking skeleton used `TextEditor` as a deliberately lightweight placeholder. Roadmap #4 (scroll anchoring) and #6 (editing polish) both require direct `UITextView` access — scroll position control for #4, `UITextViewDelegate` and `UITextInputTraits` hooks for #6. Migrating once and delivering both features together avoids doing the `UIViewRepresentable` migration twice and establishes the editor foundation that all future Raw editor work builds on.

## Success

- Mode switches land near the correct position in the destination view: rendered → raw uses the tap point's fractional position in the scroll content; raw → rendered uses the fractional scroll position of the `UITextView`.
- The raw editor suppresses smart quotes and dashes, has spell check and autocorrect on, and continues list prefixes on return (unordered `- `, `* `, `+ ` and ordered `1. ` with auto-increment).
- The `UIViewRepresentable` migration is transparent to the user — same editing surface, better behaviors. No regression in existing walking-skeleton functionality.

## Shape touched

- **Raw editor** — primary; `RawEditorView` is replaced wholesale
- **Mode switcher** — reads/writes scroll anchor on mode transitions
- **Rendered view** — read-only scroll position access for the raw → rendered direction

## Out of scope

- Syntax highlighting or any visual formatting in the editor
- Markdown auto-formatting beyond list continuation (no auto-pairing of `**`, no heading insertion, no table auto-completion)
- `Cmd+/` keyboard shortcut
- Swipe-to-switch-mode (mode-switcher gesture layer, separate concern)
- Any user-configurable settings or toggles for editor behavior
- Accessibility labeling pass (Roadmap #7, Bundle C)
- Tab/shift-tab list indentation
