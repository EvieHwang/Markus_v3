# Design: accessibility-8

## Overview

Five surgical accessibility fixes across four components. All changes are purely additive to the accessibility tree or replace a blocking override with platform-default behavior. No visual rendering changes. No new components created.

---

## Component 1 — RenderedView (`Markus_v3/Views/RenderedView.swift`)

### Behavioral constraints

- **Link activation opens the URL.** When a user (sighted or VoiceOver) activates any link element inside the rendered Markdown, the system's default URL handler opens the URL. The document mode does not change as a result of link activation.
- **Non-link taps enter raw mode.** A tap on any area of the rendered view that is not a link element triggers `onTap(fractionalY)`, which transitions the document to `.raw` mode. This path is unchanged.
- **VoiceOver "Edit" action enters raw mode.** The `.accessibilityAction(named: "Edit")` closure, which calls `onTap(nil)`, is unchanged. VoiceOver users retain a dedicated, clearly-labeled path to edit mode.
- **`simulateLinkTap` is a no-op.** After removing the `OpenURLAction` override, `simulateLinkTap(_:)` no longer has a meaningful behavior to simulate (the URL is dispatched to the system, not to this view's closure). The method body becomes empty or the method is removed entirely. Tests that previously used it to assert a mode switch must be updated to reflect that link taps do not switch modes.
- **Unregistered URL schemes produce no crash and no mode switch.** `mailto:`, custom-scheme, and unregistered scheme URLs are passed to the system; the OS handles or silently ignores them.

### Change

Remove the `.environment(\.openURL, OpenURLAction { _ in ... })` modifier block (lines 64–67 of current source). The SwiftUI `openURL` environment reverts to the default, which calls `UIApplication.shared.open(_:options:completionHandler:)`. The `.onTapGesture` modifier, the `.accessibilityAction`, and the swipe gesture are untouched.

Update `simulateLinkTap(_:)` to an empty body (or remove it), since its former behavior — calling `onTap(nil)` — is no longer the correct representation of link activation.

### Contracts

- `onTap: (Double?) -> Void` — called only on non-link taps. Not called on link activation. This is the same closure type as before; the behavioral contract narrows.
- The `openURL` environment is not overridden; SwiftUI resolves it from the system.
- `.accessibilityIdentifier("RenderedView")` is unchanged.
- `simulateTap()` is unchanged.

### Seam relationships

- `DocumentView` supplies the `onTap` closure to `RenderedView`. After this change, `DocumentView` receives no callback for link taps. No change to `DocumentView` is required for this concern.

---

## Component 2 — MarkdownThemeFactory (`Markus_v3/Views/MarkdownThemeFactory.swift`)

### Behavioral constraints

- **Each heading view carries the `.isHeader` accessibility trait.** For every rendered heading element (H1–H6), VoiceOver reports the element as a heading. The VoiceOver heading-navigation rotor finds and traverses these elements in document order.
- **Body text does not carry `.isHeader`.** Only elements produced by the `heading1`–`heading6` theme closures receive the trait. Paragraphs, list items, and code blocks are unaffected.
- **Visual output is unchanged.** Font size, weight, color, and margin on all heading levels remain exactly as currently configured.
- **Trait survives Dynamic Type changes.** Because the trait is applied inside the heading builder closure (evaluated at render time), and because `RenderedView` re-renders when `@Environment(\.dynamicTypeSize)` changes, the trait is present on every re-render.

### Change

In each of the six heading closures (`heading1` through `heading6`), append `.accessibilityAddTraits(.isHeader)` directly to `configuration.label` before or after the existing `.markdownMargin` and `.markdownTextStyle` modifiers. The trait must be applied to `configuration.label` (the heading's native view), not to a containing wrapper, so that MarkdownUI propagates it correctly into the accessibility tree.

Example shape for `heading1` (others follow the same pattern):

```swift
.heading1 { configuration in
    configuration.label
        .markdownMargin(top: 24, bottom: 16)
        .markdownTextStyle {
            FontWeight(.semibold)
            FontSize(.em(2.0))
        }
        .accessibilityAddTraits(.isHeader)
}
```

Apply identically to heading2 through heading6.

### Contracts

- `makeTheme() -> Theme` — return type and call site in `RenderedView` are unchanged. The returned `Theme` now includes `.isHeader` traits on all six heading levels.
- `headingFont(level:)` and `bodyFont()` are unchanged; existing typography tests need no updates for this concern.

### Seam relationships

- `RenderedView` calls `MarkdownThemeFactory.makeTheme()` at body-build time. No change to the call site.

Reuses pattern: **UX checklist** — Apple HIG requires structural roles to be reflected programmatically; `.isHeader` is the iOS accessibility primitive for heading semantics (WCAG 1.3.1 — Info and Relationships).

---

## Component 3 — MarkdownEditorTextView (`Markus_v3/Editor/MarkdownEditorTextView.swift`)

### Behavioral constraints

- **Font updates live, without restart.** When `UIContentSizeCategory.didChangeNotification` fires while the view exists, `configureAppearance()` is called on the main queue. The view's `font` and `typingAttributes[.font]` reflect the new Dynamic Type body size immediately within the same app session.
- **Cursor position is preserved.** Setting `font` and `typingAttributes[.font]` on a `UITextView` does not reset the selection range; the cursor remains at its pre-update position by construction. No explicit save-and-restore of `selectedRange` is needed, but the design explicitly names this as an observable invariant — if a future change to `configureAppearance()` replaces `attributedText` or sets `text = ...`, cursor preservation must be re-examined.
- **Observer lifecycle matches view lifecycle.** The notification observer is registered during `init` and removed in `deinit`. No dangling observer; no retain cycle. The capture list uses `[weak self]`.
- **Observer fires on main queue.** The observer is added with `queue: .main` so `configureAppearance()` and any UIKit mutations run on the main thread without an additional dispatch wrapper.
- **Raw editor is not visible during the change — still correct on return.** If the view is off-screen (rendered mode is active), the notification fires and `configureAppearance()` runs. When raw mode is subsequently shown, the font is already correct. No additional trigger in `MarkdownTextViewBridge` is needed.
- **Rapid successive changes converge to the final state.** Each notification invocation calls `configureAppearance()` independently. Intermediate states do not cause visible glitches or crashes.

### Change

Add a stored `NSObjectProtocol?` token property. In `init`, after the existing `configureTraits()` and `configureAppearance()` calls, register the observer:

```swift
private var dynamicTypeObserver: NSObjectProtocol?

// in init (both init variants, via a shared setup method or directly):
dynamicTypeObserver = NotificationCenter.default.addObserver(
    forName: UIContentSizeCategory.didChangeNotification,
    object: nil,
    queue: .main
) { [weak self] _ in
    self?.configureAppearance()
}
```

Add `deinit` to remove the observer:

```swift
deinit {
    if let token = dynamicTypeObserver {
        NotificationCenter.default.removeObserver(token)
    }
}
```

`configureAppearance()` is unchanged in its logic — it re-reads `UIFont.preferredFont(forTextStyle: .body).pointSize` on every call, which is the correct formula for picking up the new category.

### Contracts

- `configureAppearance()` — already `private`; its behavior is unchanged. It is now called from two sites: `init` and the notification handler.
- `deinit` — new addition; removes the stored observer token.

### Seam relationships

- `MarkdownTextViewBridge.Representable.makeUIView` creates a `MarkdownEditorTextView`. Lifecycle is UIKit-standard; `deinit` fires when `UIViewRepresentable` tears down the view. No change to `MarkdownTextViewBridge`.
- No change to `DocumentView` or `RawEditorView`.

---

## Component 4 — DetectorSurfaces (`Markus_v3/Views/DetectorSurfaces.swift`)

### Behavioral constraints

- **VoiceOver announces a meaningful label for each button.** Each of the five buttons has an `.accessibilityLabel` that communicates the action to a VoiceOver user in plain language. The visible button title (used for sighted users) is unchanged.
- **"Discard Mine" has an accessibility hint.** VoiceOver reads a hint on the "Discard Mine" button that explains the action is irreversible and that local edits will be permanently lost. No other button requires a hint.
- **All `.accessibilityIdentifier` values are preserved.** The identifiers `ConflictKeepMine`, `ConflictKeepTheirs`, `ConflictDiscardMine`, `DeletionBannerSaveAs`, and `DeletionBannerDismiss` remain on their respective buttons, unchanged. UI tests that query by identifier continue to pass.
- **`.accessibilityLabel` and `.accessibilityIdentifier` co-exist on the same button.** They serve different purposes — test hook vs. announced name — and do not conflict. Both modifiers must be present.
- **When VoiceOver is off, no observable change.** Labels and hints are present in the accessibility tree but have no effect on sighted users.

### Change

In `conflictSheet`:

```swift
Button("Keep Mine") { detector.resolveConflict(.keepMine) }
    .accessibilityIdentifier("ConflictKeepMine")
    .accessibilityLabel(String(localized: "Keep My Version",
                               comment: "VoiceOver label for conflict sheet Keep Mine button"))

Button("Keep Theirs") { detector.resolveConflict(.keepTheirs) }
    .accessibilityIdentifier("ConflictKeepTheirs")
    .accessibilityLabel(String(localized: "Keep Their Version",
                               comment: "VoiceOver label for conflict sheet Keep Theirs button"))

Button("Discard Mine", role: .destructive) { detector.resolveConflict(.discardMine) }
    .accessibilityIdentifier("ConflictDiscardMine")
    .accessibilityLabel(String(localized: "Discard My Changes",
                               comment: "VoiceOver label for conflict sheet Discard Mine button"))
    .accessibilityHint(String(localized: "Your local edits cannot be recovered after this action.",
                              comment: "VoiceOver hint for irreversible Discard Mine action"))
```

In `deletionBanner`:

```swift
Button("Save As") { showSaveAs = true }
    .accessibilityIdentifier("DeletionBannerSaveAs")
    .accessibilityLabel(String(localized: "Save to New Location",
                               comment: "VoiceOver label for deletion banner Save As button"))

Button("Dismiss") { detector.dismissDeletionBanner() }
    .accessibilityIdentifier("DeletionBannerDismiss")
    .accessibilityLabel(String(localized: "Dismiss",
                               comment: "VoiceOver label for deletion banner Dismiss button"))
```

### Contracts

- No change to button action closures or `ChangeDetector` API.
- No change to `DocumentView`'s overlay that instantiates `DetectorSurfaces`.

### Seam relationships

- `DetectorSurfaces` is a self-contained overlay inserted in `DocumentView`. The relationship is unchanged.

Reuses pattern: **UX checklist** — WCAG 4.1.2 (Name, Role, Value) requires interactive controls to have accessible names; Apple HIG confirms `.accessibilityLabel` is the correct mechanism on iOS.

---

## Component 5 — DocumentView (`Markus_v3/Views/DocumentView.swift`)

### Behavioral constraints

- **Every user-triggered mode transition posts exactly one announcement.** When `mode` transitions from `.rendered` to `.raw` (by any path: toolbar button, `onTap` callback, `switchTo`, `switchToRawFromSwipe`), `UIAccessibility.post(notification: .announcement, argument:)` is called with a non-empty localizable string describing raw/edit mode. When `mode` transitions from `.raw` to `.rendered` (toolbar button, `switchToRenderedFromSwipe`), an announcement for rendered/preview mode is posted.
- **The initial mode assignment on `onAppear` does not post an announcement.** The `didInitMode` guard already in the codebase gates the DC-4 initial mode selection. The `.onChange(of: mode)` observer must only post when `didInitMode` is already `true`. Because `onAppear` writes `mode` before setting `didInitMode = true`, the batched SwiftUI `@State` update means the initial `onChange` fires while `didInitMode` is still `false`, so the guard is effective.
- **Announcements are localizable.** Both strings pass through `String(localized:)` or `NSLocalizedString`. English defaults: "Editing mode" and "Preview mode".
- **Announcement is a no-op when VoiceOver is off.** `UIAccessibility.post(notification: .announcement, ...)` is always unconditional; no guard on `UIAccessibility.isVoiceOverRunning` is needed.
- **One announcement per transition, not per triggering path.** All mode-switch paths write to the same `mode` state property; a single `.onChange(of: mode)` covers all of them. No double announcement is possible.
- **All existing side effects are preserved.** Scroll-anchor seeding, `triggerSave()` calls, and `focusRawOnFirstAppear` are untouched. The announcement is a new, parallel side effect only.

### Change

Add a single `.onChange(of: mode)` modifier to `DocumentView.body`, placed after the existing `.onChange(of: scenePhase)` modifier for readability:

```swift
.onChange(of: mode) { _, newMode in
    guard didInitMode else { return }
    switch newMode {
    case .raw:
        UIAccessibility.post(
            notification: .announcement,
            argument: String(localized: "Editing mode",
                             comment: "VoiceOver announcement when switching to raw edit mode")
        )
    case .rendered:
        UIAccessibility.post(
            notification: .announcement,
            argument: String(localized: "Preview mode",
                             comment: "VoiceOver announcement when switching to rendered preview mode")
        )
    }
}
```

No changes are needed to `switchTo`, `switchToRawFromSwipe`, `switchToRenderedFromSwipe`, or any toolbar action. The single observer covers all paths.

### Contracts

- `mode: DocumentMode` — the existing `@State` property. Unchanged type and mutation sites; `onChange` observes without mutating.
- `didInitMode: Bool` — the existing `@State` property. Read inside the `onChange` closure; never mutated by it.

### Seam relationships

- `DocumentView` already calls `UIAccessibility.post(notification: .announcement, argument:)` in `copyContentsToClipboard()`. No new import is needed; the pattern is already established.

Reuses pattern: **UX checklist** — Nielsen heuristic 1 (Visibility of system status): VoiceOver users must receive feedback that the surface has changed after a mode switch.

---

## Cross-cutting constraints (from requirements)

- CC-1: No `.accessibilityIdentifier` values are removed or renamed across all five changes. All five button identifiers are preserved exactly.
- CC-2: Tests that asserted `simulateLinkTap(_:)` caused a mode switch must be updated to assert no mode switch occurs (AC-1.5). This is a test-correction, not a regression; it must be placed in the same DAG wave as the `RenderedView` change. All other existing tests are unaffected.
- CC-3: No visual rendering changes in any of the five components.
- CC-4: All accessibility improvements are always-on; no setting or user action is required to activate them.

---

## Requirements changes implied by this architecture

No requirements text needs to change.

AC-1.5 correctly identifies the test update obligation that follows from restoring standard link behavior. The architecture flags this as a DAG sequencing constraint — the test update must land in the same wave as the `RenderedView` change — not as a requirements deficiency.

Architecture stable — no requirements changes flagged
