# Requirements: accessibility-8

## Changelog

**Revision 1 (adversarial round 1):**
- AC-2.2 revised and AC-2.5 added: VoiceOver heading rotor must behaviorally navigate to heading elements (not just trait presence). *Addresses adversarial F-002.*
- AC-4.9 added: VoiceOver focus must move to an appropriate document element when the deletion banner disappears. *Addresses adversarial F-003.*
- AC-4.6 revised: "Dismiss" deletion banner label must be context-specific (e.g., "Dismiss file deleted notice") rather than the bare word "Dismiss". *Addresses adversarial F-004.*
- AC-3.6 added: Computed raw editor font size has a minimum floor of 1pt. *Addresses adversarial F-005.*

---

## Overview

Five focused accessibility fixes across the rendered view, raw editor, mode switcher, and conflict/lifecycle UI. Each fix closes a concrete gap against WCAG 2.1 AA and Apple HIG.

---

## Concern 1 — Restore standard link behavior in RenderedView

### Background

`RenderedView` currently installs an `OpenURLAction` override that intercepts all link taps and routes them to `onTap(nil)`, which transitions the document to raw edit mode instead of following the link. This is non-standard and surprises VoiceOver users activating a link element.

### User stories

**US-1.1 — Sighted user taps a link**
As a user reading a rendered document that contains a hyperlink, when I tap the link, the system opens the URL in the default handler (Safari for http/https, the appropriate app for other URL schemes). The document does not switch to raw mode.

**US-1.2 — VoiceOver user activates a link**
As a VoiceOver user navigating by swipe to a link element and double-tapping to activate it, when I activate the link, the system opens the URL in the default handler. The document does not switch to raw mode.

**US-1.3 — Sighted user taps a non-link area**
As a sighted user, when I tap any area of the rendered document that is not a link, the document switches to raw edit mode as before.

**US-1.4 — VoiceOver "Edit" action still works**
As a VoiceOver user, the "Edit" custom accessibility action on the rendered view still transitions to raw mode, giving the accessible edit path that the link-activation path no longer provides.

### Acceptance criteria

- AC-1.1: Given a rendered document containing an `[http://example.com](http://example.com)` link, when a sighted user taps the link text, `openURL` is called with `http://example.com` and no mode switch occurs.
- AC-1.2: Given VoiceOver is enabled and a rendered document contains a link, when VoiceOver double-taps the link, `openURL` is called with the link's URL and no mode switch occurs.
- AC-1.3: Given a rendered document, when a user taps a region that is not a link, the document mode transitions to `.raw`.
- AC-1.4: Given VoiceOver is enabled, when the VoiceOver "Edit" accessibility action is invoked on the rendered view, the document mode transitions to `.raw`.
- AC-1.5: The `simulateLinkTap(_:)` method on `RenderedView` (used by existing tests) no longer triggers `onTap`; the URL is handled by the environment's `openURL` instead. (Tests that relied on the old behavior must be updated to reflect the corrected semantics.)

### Edge cases and failure modes

- EC-1.1: A link with a `mailto:` scheme opens the system mail composer rather than Safari. No mode switch occurs.
- EC-1.2: A link with a custom app scheme (e.g., `obsidian://`) is passed to `openURL`; if no app is registered, the OS silently ignores it. No crash, no mode switch.
- EC-1.3: A link occupies the full width of a line. Tapping anywhere on that line opens the URL; no mode switch occurs.
- EC-1.4: A rendered document with no links: all taps continue to trigger the mode switch as before.

### Out of scope

- Link long-press behavior (e.g., preview popover) is not part of this feature.
- Adding `.isLink` traits to inline link elements is explicitly out of scope (see declaration).
- Changing the VoiceOver rotor behavior for links beyond what the standard `openURL` environment provides.

---

## Concern 2 — Add heading traits to MarkdownThemeFactory (H1–H6)

### Background

`MarkdownThemeFactory.makeTheme()` currently styles H1–H6 headings visually but does not attach `.accessibilityAddTraits(.isHeader)`. VoiceOver's heading-navigation rotor requires this trait to find heading elements; without it, VoiceOver users cannot navigate long documents by heading.

### User stories

**US-2.1 — VoiceOver heading rotor navigation**
As a VoiceOver user reading a rendered document that contains multiple headings, I can set the VoiceOver rotor to "Headings" and swipe up/down to jump between H1–H6 elements in sequence, without visiting body text between them.

**US-2.2 — All heading levels are reachable**
As a VoiceOver user, every heading level (H1, H2, H3, H4, H5, H6) present in the document is reachable via the headings rotor.

**US-2.3 — Body text is not announced as a heading**
As a VoiceOver user using the headings rotor, body paragraphs, list items, and code blocks are not included in the rotor navigation sequence.

### Acceptance criteria

- AC-2.1: Given a rendered document containing at least one heading of each level (H1–H6), each heading view's accessibility traits include `.isHeader`.
- AC-2.2: Given VoiceOver is enabled and the headings rotor is selected, swiping down with the rotor set to "Headings" moves focus sequentially through each H1–H6 element in document order — verified by an XCUITest that queries for heading-trait elements and confirms the expected count and order match the document's heading structure. *Addresses adversarial F-002.*
- AC-2.3: Given a rendered document that contains headings and body paragraphs, body paragraph views do not carry the `.isHeader` trait.
- AC-2.4: Heading trait assignment does not alter visual rendering — font size, weight, and margins remain as specified by the existing `makeTheme()` configuration.
- AC-2.5: Given a rendered document with H1–H6 headings, an XCUITest using the VoiceOver headings rotor (or equivalent `XCUIElementQuery` for elements with `.isHeader` trait) returns elements in the same order and count as the headings in the source document. A test that passes solely by checking modifier application on the view returned by the builder is insufficient — the criterion requires end-to-end behavioral verification that the trait reaches the element VoiceOver focuses. *Addresses adversarial F-002.*

### Edge cases and failure modes

- EC-2.1: A document with only one heading level (e.g., all H2): that single level is reachable via the rotor; no error or crash occurs because other levels are absent.
- EC-2.2: A document with no headings: the headings rotor shows no elements; no crash or error.
- EC-2.3: A heading at the very end of the document: rotor navigation wraps or stops at that heading; no crash.
- EC-2.4: Dynamic Type size changes do not remove the `.isHeader` trait from re-rendered headings.

### Out of scope

- Per-list-item accessibility traits (no MarkdownUI theme hook available without reimplementing rendering).
- Custom heading IDs or anchor links.

---

## Concern 3 — Fix Dynamic Type live update in MarkdownEditorTextView

### Background

`MarkdownEditorTextView.configureAppearance()` reads `UIFont.preferredFont(forTextStyle: .body).pointSize` at initialization time and does not observe `UIContentSizeCategory.didChangeNotification`. Changing the Dynamic Type size in Settings → Accessibility while the app is open has no effect on the raw editor until the app is restarted. WCAG 1.4.4 requires text to scale without loss of content or functionality.

### User stories

**US-3.1 — Live Dynamic Type resize in the raw editor**
As a user who changes the text size in Settings → Accessibility → Larger Text while Markus is open (either via the Settings app or the Control Center shortcut), when I return to Markus without restarting it, the raw editor's font reflects the new size without requiring an app restart.

**US-3.2 — Restart-free type scaling**
As a user who begins editing a document in the raw editor and then changes the system text size, the editor's text reflows to the new size. My cursor position and document content are preserved.

### Acceptance criteria

- AC-3.1: Given the raw editor is visible and the system Dynamic Type size is at the default ("Large"), when the system text size is changed to "Accessibility Extra Extra Extra Large", the raw editor's font point size updates to `UIFont.preferredFont(forTextStyle: .body).pointSize - 2` at the new category within the same app session without a restart.
- AC-3.2: Given the raw editor is visible, when the system text size is changed, the editor's `font` property and `typingAttributes[.font]` both reflect the new computed size.
- AC-3.3: Given the user changes the text size while editing (with an active cursor), after the resize the document text is unchanged and the cursor remains in the document.
- AC-3.4: Given the raw editor is not visible (rendered mode is active) when the text size changes, switching to raw mode after the change shows the updated font size without requiring additional action.
- AC-3.5: The notification observer is removed when the view is deallocated (no retain cycle or dangling observer).
- AC-3.6: The computed raw editor font size (i.e., `UIFont.preferredFont(forTextStyle: .body).pointSize - 2`) has a minimum floor of 1pt regardless of the Dynamic Type category. If the formula yields a value less than 1pt, the font is set to 1pt. This ensures WCAG 1.4.4 compliance is unconditional for any current or future Dynamic Type category. *Addresses adversarial F-005.*

### Edge cases and failure modes

- EC-3.1: Rapid successive Dynamic Type changes (e.g., via the accessibility slider) result in the editor reflecting the final size; intermediate sizes do not cause visible glitches or crashes.
- EC-3.2: The "SFMono-Regular" font is unavailable at the new size; the fallback `UIFont.monospacedSystemFont` is used instead, as in the initialization path.
- EC-3.3: Dynamic Type is changed while a conflict sheet or deletion banner is presented; the raw editor correctly reflects the new size when the sheet is dismissed and raw mode is shown.

### Out of scope

- The rendered view's Dynamic Type live update is already handled via `@Environment(\.dynamicTypeSize)` in `RenderedView` and is not part of this concern.
- Font selection (SF Mono vs. system monospaced) is unchanged; only the size update is in scope.

---

## Concern 4 — Add accessibility labels and hints to DetectorSurfaces buttons

### Background

The conflict sheet buttons ("Keep Mine", "Keep Theirs", "Discard Mine") and deletion banner buttons ("Save As", "Dismiss") currently carry only `.accessibilityIdentifier` attributes, which are test hooks and are not announced by VoiceOver. WCAG 4.1.2 requires interactive controls to have accessible names. "Discard Mine" carries additional destructive risk that warrants an explicit hint.

### User stories

**US-4.1 — VoiceOver reads conflict sheet button names**
As a VoiceOver user presented with the conflict sheet, when VoiceOver focuses each button, it announces a meaningful label describing the action: what will be kept and what will be discarded.

**US-4.2 — VoiceOver reads a hint on "Discard Mine"**
As a VoiceOver user considering the "Discard Mine" option, VoiceOver announces a hint that explains the action is irreversible and that local edits will be lost.

**US-4.3 — VoiceOver reads deletion banner button names**
As a VoiceOver user presented with the deletion banner, when VoiceOver focuses the "Save As" and "Dismiss" buttons, each announces a meaningful label that identifies the specific action and context.

**US-4.4 — UI test identifiers are preserved**
As a developer running UI tests, the `.accessibilityIdentifier` values `ConflictKeepMine`, `ConflictKeepTheirs`, `ConflictDiscardMine`, `DeletionBannerSaveAs`, and `DeletionBannerDismiss` remain unchanged on the respective buttons.

**US-4.5 — VoiceOver focus moves to document after banner dismissal**
As a VoiceOver user whose focus is on the deletion banner when it is programmatically dismissed (e.g., after "Dismiss" is tapped or "Save As" resolves), VoiceOver focus moves to an appropriate element in the document rather than remaining stuck on the now-invisible banner controls.

### Acceptance criteria

- AC-4.1: The "Keep Mine" button has `.accessibilityLabel` set to a non-empty string that communicates keeping the user's local version (e.g., "Keep My Version").
- AC-4.2: The "Keep Theirs" button has `.accessibilityLabel` set to a non-empty string that communicates keeping the incoming version (e.g., "Keep Their Version").
- AC-4.3: The "Discard Mine" button has `.accessibilityLabel` set to a non-empty string that communicates discarding the user's local changes (e.g., "Discard My Changes").
- AC-4.4: The "Discard Mine" button has `.accessibilityHint` set to a non-empty string that explains the action is irreversible and local edits will be lost (e.g., "Your local edits cannot be recovered after this action.").
- AC-4.5: The "Save As" button in the deletion banner has `.accessibilityLabel` set to a non-empty string that communicates saving the document to a new location (e.g., "Save to New Location").
- AC-4.6: The "Dismiss" button in the deletion banner has `.accessibilityLabel` set to a context-specific string that identifies what is being dismissed — not the bare word "Dismiss" alone. The label must name the context (e.g., "Dismiss file deleted notice"). This satisfies WCAG 2.4.6 (Headings and Labels), which requires labels to be descriptive enough to identify the control's purpose. *Addresses adversarial F-004.*
- AC-4.7: All five `.accessibilityIdentifier` values listed in US-4.4 are present on the respective buttons and unchanged from their current values.
- AC-4.8: The conflict sheet's title text ("This file changed on another device") and subtitle remain unchanged in their visual presentation and are accessible to VoiceOver.
- AC-4.9: When the deletion banner is dismissed programmatically (whether by the "Dismiss" button action, by a "Save As" resolution, or by any other programmatic path), a `UIAccessibility.post(notification: .layoutChanged, ...)` or `.screenChanged` notification is posted so that VoiceOver focus moves to a defined element in the document (e.g., the rendered or raw content view) rather than remaining on the now-invisible banner controls. VoiceOver must not be in a stuck-focus or focus-on-invisible-element state after banner dismissal. *Addresses adversarial F-003.*

### Edge cases and failure modes

- EC-4.1: The conflict sheet is displayed and VoiceOver is not running: the labels and hints are present in the accessibility tree but have no visible effect on sighted users.
- EC-4.2: The deletion banner appears, the user changes the VoiceOver focus to the banner, and then the banner is dismissed programmatically: VoiceOver focus returns to the document without a crash or stuck-focus state. (Mechanism: AC-4.9's notification handles this.)
- EC-4.3: The conflict sheet is presented over the raw editor; VoiceOver focus lands on sheet buttons first, not on the editor content behind the sheet.

### Out of scope

- Adding `.accessibilityLabel` to the conflict sheet's descriptive text elements (they are `Text` views and already readable by VoiceOver).
- Changing the visible button labels; only the VoiceOver-announced labels change.
- Any changes to the `fileExporter` sheet triggered by "Save As".

---

## Concern 5 — Post VoiceOver announcements on mode switches in DocumentView

### Background

`DocumentView` transitions between `.rendered` and `.raw` modes via the toolbar button, the VoiceOver "Edit" action, and swipe gestures. None of these transitions currently post a `UIAccessibility.post(notification: .announcement, ...)` call. A VoiceOver user who triggers a mode switch receives no feedback that the surface changed.

### User stories

**US-5.1 — Announcement on switch to raw mode**
As a VoiceOver user, when I switch from rendered to raw mode (via the toolbar "eye" button inverse, the tap-to-edit path, the VoiceOver "Edit" action, or an L→R swipe), VoiceOver announces that the app is now in raw editing mode.

**US-5.2 — Announcement on switch to rendered mode**
As a VoiceOver user, when I switch from raw to rendered mode (via the toolbar "eye" button, an R→L swipe), VoiceOver announces that the app is now in rendered/preview mode.

**US-5.3 — Announcement is heard, not just posted**
As a VoiceOver user who has just invoked the mode switch, the announcement is heard even if VoiceOver focus moves as part of the transition. The announcement is not lost because it arrives after focus settles.

### Acceptance criteria

- AC-5.1: When the mode transitions from `.rendered` to `.raw` by any path (toolbar, tap, "Edit" action, swipe), `UIAccessibility.post(notification: .announcement, argument:)` is called with a non-empty string describing the raw/edit mode (e.g., "Editing mode").
- AC-5.2: When the mode transitions from `.raw` to `.rendered` by any path (toolbar, swipe), `UIAccessibility.post(notification: .announcement, argument:)` is called with a non-empty string describing the rendered/preview mode (e.g., "Preview mode").
- AC-5.3: The announcement fires once per mode transition, not once per triggering path. (If two code paths transition to raw, each transition fires one announcement, not two simultaneous announcements.)
- AC-5.4: The announcement text is localizable (passed through `NSLocalizedString` or equivalent).
- AC-5.5: Mode transitions that occur because of the initial `onAppear` setup (DC-4 initial mode selection) do not post an announcement, since the user has not yet interacted with the document.
- AC-5.6: All existing mode-switch behaviors are preserved: scroll-anchor seeding, save triggering, and focus-on-appear in raw mode are unaffected.

### Edge cases and failure modes

- EC-5.1: VoiceOver is not enabled when the mode switch occurs: `UIAccessibility.post(notification: .announcement, ...)` is a no-op when VoiceOver is off; no error or crash results.
- EC-5.2: The user switches modes rapidly (tap raw, immediately tap rendered): two distinct announcements fire in sequence. The second does not cancel or suppress the first in an observable way; the OS queues them.
- EC-5.3: A mode switch is triggered while a conflict sheet is being dismissed: the announcement fires when the mode change actually takes effect; no double-announcement.
- EC-5.4: The initial mode is `.raw` (empty or large file): no announcement fires because the initial mode assignment is not a user-triggered mode switch.

### Out of scope

- Announcing the scroll position within a mode.
- Changing the toolbar button labels or icons.
- Announcing that a conflict sheet or deletion banner has appeared (that is governed by the system sheet/banner presentation machinery).

---

## Cross-cutting constraints

- CC-1: All five changes are additive to the accessibility tree; no existing `.accessibilityIdentifier` values are removed or renamed.
- CC-2: All existing unit and UI tests continue to pass after this feature is implemented.
- CC-3: Visual rendering (colors, fonts, layout) is unchanged by this feature; only accessibility metadata and event posting are added.
- CC-4: The feature does not introduce new user-facing settings or require any user action to activate; all improvements are always-on.

---

Requirements stable — no architectural feedback to incorporate
