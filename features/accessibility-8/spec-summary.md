# Spec Summary: accessibility-8

## Feature

Markus is a markdown editor for iOS that opens and edits files wherever they already live, with no app-managed copies. This feature is the project's planned accessibility pass: a set of five targeted fixes that bring the app to WCAG 2.1 AA compliance across the four main user-facing surfaces. Each fix addresses a concrete gap — a VoiceOver user activating a link ended up in edit mode instead of following the link; heading elements were invisible to VoiceOver's navigation rotor; the raw editor's text didn't reflow if the user changed text size while the app was open; and several interactive controls had no accessible names. None of the five changes alter the visual experience for sighted users.

## What it does

- **Links open in the browser.** Tapping a link in the rendered view now opens it in Safari (or whatever the user's default browser is). Previously, link taps dropped the user into raw edit mode — a surprise, and especially confusing for VoiceOver users who expected link activation to navigate. Non-link taps still enter edit mode as before; the "Edit" action for VoiceOver remains in place.

- **Headings are navigable by VoiceOver.** The rendered view now exposes H1–H6 elements as headings in the accessibility tree. VoiceOver users can use the "Headings" rotor to jump between sections of a document, which is the standard iOS reading pattern for longer content.

- **Dynamic Type works live in the editor.** If a user changes their text size preference in Settings while Markus is open, the raw editor now reflows to the new size immediately. Previously the editor would only update after a restart.

- **Conflict and deletion controls have accessible names.** The conflict sheet buttons ("Keep Mine", "Keep Theirs", "Discard Mine") and the deletion banner controls now announce descriptive names to VoiceOver. "Discard Mine" includes a hint that local edits will be permanently lost. The "Dismiss" button on the deletion banner uses a context-specific label rather than the bare word. When the banner disappears, VoiceOver focus is moved to the document — users are no longer left focused on a control that no longer exists.

- **Mode switches are announced.** When the user switches between reading and editing (via toolbar, tap, or swipe), VoiceOver announces the new mode. Previously, mode transitions produced no audio feedback.

## Risks carried

No risks acknowledged. All adversarial findings (two HIGH, one MEDIUM, two LOW) were resolved before the spec was finalized.

## Out of scope

- Inline link accessibility traits (MarkdownUI renders these as `AttributedString` in `Text` views; iOS 16+ VoiceOver can navigate to them natively without forking the library)
- List item grouping and semantics (MarkdownUI provides no per-item theme hook)
- WKWebView-based rendering
- Accessibility audit of the system document browser (`UIDocumentBrowserViewController` is a system component)
- Any new user-facing settings or configuration

## Build preview

3 waves, 5 tasks. Wave 1 (T-001) handles the link-behavior change and its test corrections together, which is a sequencing constraint from the design. Wave 2 (T-002, T-003, T-004) runs three independent component fixes in parallel. Wave 3 (T-005) integrates the mode-switch announcements once the full test suite is clean. The DAG fits comfortably in one build session.

## Next step

Start a new session and run `/build feature-name: accessibility-8`.
