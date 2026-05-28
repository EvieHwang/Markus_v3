# Declaration: accessibility-8

## What

A focused accessibility pass across the four app surfaces that have known gaps against WCAG 2.1 AA and Apple HIG: the rendered view, the raw editor, the mode switcher, and the conflict/lifecycle UI.

Concretely, this feature does five things:

1. **Restore standard link behavior in the rendered view.** Remove the `OpenURLAction` override in `RenderedView` that currently redirects link taps to edit mode. Links open in the system default handler (Safari for http/https). The tap-to-edit behavior is preserved for non-link taps; the VoiceOver "Edit" action on the rendered view is preserved as the accessible path to editing.

2. **Add heading traits to the MarkdownUI theme.** Extend `MarkdownThemeFactory.makeTheme()` to add `.accessibilityAddTraits(.isHeader)` to all six heading builders (H1–H6). This lets VoiceOver users navigate a document by heading, which is the standard reading pattern on iOS.

3. **Fix Dynamic Type live update in the raw editor.** `MarkdownEditorTextView.configureAppearance()` currently snapshots the font at init time. Add a `UIContentSizeCategory.didChangeNotification` observer so the raw editor reflows its font when the user changes Dynamic Type while the app is running.

4. **Add accessibility labels to the conflict and deletion UI.** The conflict sheet buttons ("Keep Mine", "Keep Theirs", "Discard Mine") and the deletion banner buttons ("Save As", "Dismiss") currently carry only `.accessibilityIdentifier` (for UI tests) and no `.accessibilityLabel` or `.accessibilityHint`. Add explicit labels and, for "Discard Mine", a hint explaining the irreversible nature of the action.

5. **Announce mode switches to VoiceOver.** When the app transitions between rendered and raw mode, post a `UIAccessibility.post(notification: .announcement, ...)` so VoiceOver users know the surface has changed.

## Why

The constitution cites WCAG 2.1 AA as the accessibility standard. Each of the five items above maps to a concrete gap:

- **Link behavior**: the `OpenURLAction` override produces a surprise for VoiceOver users activating a link — they enter edit mode instead of following the link. Sighted users who know the app can anticipate this; VoiceOver users navigating by element cannot. Removing the override restores platform-expected behavior and eliminates an inconsistency between the VoiceOver "Edit" action and the link activation path.
- **Heading traits**: WCAG 1.3.1 (Info and Relationships, Level A) requires that structural semantics be conveyed programmatically. Headings with no `.isHeader` trait are invisible to VoiceOver's heading-navigation rotor — a real navigation regression for users of longer documents.
- **Dynamic Type live update**: WCAG 1.4.4 (Resize Text) requires text to scale to 200% without loss of content or functionality. The raw editor currently satisfies this at launch but not when the setting is changed mid-session.
- **Conflict/deletion labels**: WCAG 4.1.2 (Name, Role, Value) requires interactive controls to have accessible names. `.accessibilityIdentifier` is a test hook, not an accessible name.
- **Mode switch announcement**: without an announcement, a VoiceOver user who triggers a mode switch (via the toolbar or the "Edit" action) receives no feedback that the surface changed.

## Success

After this feature ships:

1. Tapping a link in the rendered view opens it in Safari (or the appropriate system handler). VoiceOver double-tapping a link does the same. Non-link taps continue to enter edit mode.
2. The VoiceOver heading-navigation rotor finds all H1–H6 elements in a rendered document and moves between them.
3. Changing the Dynamic Type size in Settings → Accessibility while Markus is open causes the raw editor to reflow its font without requiring an app restart.
4. VoiceOver reads a meaningful label for each button in the conflict sheet and the deletion banner. VoiceOver reads a hint on "Discard Mine" explaining that local edits will be lost.
5. Switching from rendered to raw mode (via toolbar, "Edit" action, or swipe) posts a VoiceOver announcement. Switching from raw to rendered does the same.
6. All existing unit and UI tests pass. The `.accessibilityIdentifier` values on the conflict/deletion buttons are preserved (UI tests depend on them).

## Shape touched

- **Rendered view** — remove `OpenURLAction` override; add heading traits via `MarkdownThemeFactory`
- **Raw editor** — Dynamic Type live update in `MarkdownEditorTextView`
- **Mode switcher** — VoiceOver announcements in `DocumentView` on mode transitions
- **Conflict & lifecycle UI** — accessibility labels and hints on `DetectorSurfaces` buttons

No changes to: Document browser entry, File access layer, Document model.

## Out of scope

- **Inline link accessibility traits** — MarkdownUI renders inline links as `AttributedString` with `.link` attributes inside `Text` views; iOS 16+ VoiceOver navigates these natively. Adding explicit `.isLink` traits would require forking MarkdownUI.
- **List item grouping/traits** — MarkdownUI provides no per-list-item theme hook without reimplementing the visual rendering.
- **WKWebView-based rendering** — out of scope for the project entirely.
- **Renaming or restructuring any existing VoiceOver identifiers** used by UI tests (`.accessibilityIdentifier` values are preserved).
- **Accessibility audit of the system document browser** — `UIDocumentBrowserViewController` is a system component; its accessibility is Apple's responsibility.
