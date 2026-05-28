# Design: accessibility-8

## Changelog

**Revision 1 (adversarial round 1):**
- Component 5 rewritten: `.onChange(of: mode)` announcement observer removed. Announcements now posted directly inside each triggering path (`switchTo`, toolbar "Show rendered" handler, `switchToRawFromSwipe`, `switchToRenderedFromSwipe`). The `didInitMode` guard dependency is eliminated entirely. *Addresses adversarial F-001.*
- Component 4 updated: after `detector.dismissDeletionBanner()` and after the `fileExporter` completion handler calls `detector.completeSaveAs(to:)`, post `UIAccessibility.post(notification: .layoutChanged, argument: nil)` so VoiceOver focus moves away from the now-invisible banner controls. *Addresses adversarial F-003.*
- Component 4 updated: "Dismiss" deletion banner label corrected to a context-specific string ("Dismiss file deleted notice") per AC-4.6 revision.
- Prescription feedback items from adversarial-review.md restated as behavioral constraints throughout. No new implementation prescriptions added.

---

## Overview

Five surgical accessibility fixes across four components. All changes are purely additive to the accessibility tree or replace a blocking override with platform-default behavior. No visual rendering changes. No new components created.

---

## Component 1 — RenderedView (`Markus_v3/Views/RenderedView.swift`)

### Behavioral constraints

- **Link activation opens the URL.** When a user (sighted or VoiceOver) activates any link element inside the rendered Markdown, the system's default URL handler opens the URL. The document mode does not change as a result of link activation.
- **Non-link taps enter raw mode.** A tap on any area of the rendered view that is not a link element triggers `onTap(fractionalY)`, which transitions the document to `.raw` mode. This path is unchanged.
- **VoiceOver "Edit" action enters raw mode.** The `.accessibilityAction(named: "Edit")` closure, which calls `onTap(nil)`, is unchanged. VoiceOver users retain a dedicated, clearly-labeled path to edit mode.
- **`simulateLinkTap` is a no-op.** After removing the `OpenURLAction` override, `simulateLinkTap(_:)` no longer has a meaningful behavior to simulate — the URL is dispatched to the system environment, not to this view's closure. The method body becomes empty or the method is removed entirely. Tests that previously used it to assert a mode switch must be updated to reflect that link taps do not switch modes.
- **Unregistered URL schemes produce no crash and no mode switch.** `mailto:`, custom-scheme, and unregistered scheme URLs are passed to the SwiftUI environment's `openURL` action; the OS handles or silently ignores them. (Note: SwiftUI's `openURL` environment action routes through the SwiftUI environment delegation chain before reaching the UIKit layer — the behavioral outcome is that the OS handles the URL, not that `UIApplication.shared.open` is called directly.)

### Change

Remove the `.environment(\.openURL, OpenURLAction { _ in ... })` modifier block (lines 64–67 of current source). The SwiftUI `openURL` environment reverts to the default system handler. The `.onTapGesture` modifier, the `.accessibilityAction`, and the swipe gesture are untouched.

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
- **If trait does not propagate through MarkdownUI's container to the leaf element VoiceOver focuses**, wrap `configuration.label` in an `.accessibilityElement(children: .combine)` container with the `.isHeader` trait. This is the fallback if applying the trait directly to `configuration.label` does not cause VoiceOver's heading rotor to find the element (verifiable via AC-2.2 and AC-2.5's XCUITest).

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
- **Computed font size has a minimum floor of 1pt.** The formula `UIFont.preferredFont(forTextStyle: .body).pointSize - 2` is clamped so the result is never less than 1pt. If the formula yields a value less than 1pt, the font is set to 1pt. This makes WCAG 1.4.4 compliance unconditional for any current or future Dynamic Type category.
- **Cursor position is preserved.** Setting `font` and `typingAttributes[.font]` on a `UITextView` does not reset the selection range; the cursor remains at its pre-update position by construction. This is an observable invariant: if a future change to `configureAppearance()` replaces `attributedText` or sets `text = ...`, cursor preservation must be re-examined.
- **Observer lifecycle matches view lifecycle.** The notification observer is registered during `init` and removed in `deinit`. No dangling observer; no retain cycle. The capture list uses `[weak self]`.
- **Observer fires on main queue.** The observer is added with `queue: .main` so `configureAppearance()` and any UIKit mutations run on the main thread without an additional dispatch wrapper.
- **Raw editor is not visible during the change — still correct on return.** If the view is off-screen (rendered mode is active), the notification fires and `configureAppearance()` runs. When raw mode is subsequently shown, the font is already correct. No additional trigger in `MarkdownTextViewBridge` is needed.
- **Rapid successive changes converge to the final state.** Each notification invocation calls `configureAppearance()` independently. Intermediate states do not cause visible glitches or crashes.
- **`typingAttributes[.font]` assignment after `self.font =` is present for explicitness only.** Setting `self.font` on a `UITextView` causes UIKit to reset `typingAttributes` to a dictionary derived from the new font; the subsequent `typingAttributes[.font]` write is therefore redundant in practice. Both writes must remain — removing the second write is acceptable during implementation if the implementer confirms UIKit's behavior, but the behavioral requirement is that both `font` and `typingAttributes[.font]` reflect the updated size after every `configureAppearance()` call (per AC-3.2).

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

`configureAppearance()` is updated to clamp the computed size to a minimum of 1pt:

```swift
private func configureAppearance() {
    let rawSize = UIFont.preferredFont(forTextStyle: .body).pointSize - 2
    let size = max(1, rawSize)
    let monoFont = UIFont(name: "SFMono-Regular", size: size)
        ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    font = monoFont
    typingAttributes[.font] = monoFont
}
```

### Contracts

- `configureAppearance()` — already `private`; it is now called from two sites: `init` and the notification handler.
- `deinit` — new addition; removes the stored observer token.

### Seam relationships

- `MarkdownTextViewBridge.Representable.makeUIView` creates a `MarkdownEditorTextView`. Lifecycle is UIKit-standard; `deinit` fires when `UIViewRepresentable` tears down the view. No change to `MarkdownTextViewBridge`.
- No change to `DocumentView` or `RawEditorView`.

---

## Component 4 — DetectorSurfaces (`Markus_v3/Views/DetectorSurfaces.swift`)

### Behavioral constraints

- **VoiceOver announces a meaningful label for each button.** Each of the five buttons has an `.accessibilityLabel` that communicates the action to a VoiceOver user in plain language. The visible button title (used for sighted users) is unchanged.
- **"Discard Mine" has an accessibility hint.** VoiceOver reads a hint on the "Discard Mine" button that explains the action is irreversible and that local edits will be permanently lost. No other button requires a hint.
- **"Dismiss" banner button has a context-specific label.** The "Dismiss" deletion banner button label names what is being dismissed — not the bare word "Dismiss" alone — so VoiceOver users can distinguish it from other dismiss controls (WCAG 2.4.6). The label is "Dismiss file deleted notice" or equivalent context-specific phrasing. *Addresses adversarial F-004 (incorporated from requirements AC-4.6 revision).*
- **All `.accessibilityIdentifier` values are preserved.** The identifiers `ConflictKeepMine`, `ConflictKeepTheirs`, `ConflictDiscardMine`, `DeletionBannerSaveAs`, and `DeletionBannerDismiss` remain on their respective buttons, unchanged. UI tests that query by identifier continue to pass.
- **`.accessibilityLabel` and `.accessibilityIdentifier` co-exist on the same button.** They serve different purposes — test hook vs. announced name — and do not conflict. Both modifiers must be present.
- **When VoiceOver is off, no observable change.** Labels and hints are present in the accessibility tree but have no effect on sighted users.
- **VoiceOver focus moves to a defined document element after banner dismissal.** After the deletion banner is removed from the view hierarchy — whether by the "Dismiss" button action, by a "Save As" resolution via the `fileExporter` completion handler, or by any other programmatic path — `UIAccessibility.post(notification: .layoutChanged, argument: nil)` is posted. This causes VoiceOver to move focus away from the now-invisible banner controls to an appropriate element in the document. VoiceOver must not be in a stuck-focus or focus-on-invisible-element state after banner dismissal. *Addresses adversarial F-003.*

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

In `deletionBanner`, the "Dismiss" button action must post the `.layoutChanged` notification after dismissal:

```swift
Button("Save As") { showSaveAs = true }
    .accessibilityIdentifier("DeletionBannerSaveAs")
    .accessibilityLabel(String(localized: "Save to New Location",
                               comment: "VoiceOver label for deletion banner Save As button"))

Button("Dismiss") {
    detector.dismissDeletionBanner()
    UIAccessibility.post(notification: .layoutChanged, argument: nil)
}
.accessibilityIdentifier("DeletionBannerDismiss")
.accessibilityLabel(String(localized: "Dismiss file deleted notice",
                           comment: "VoiceOver label for deletion banner Dismiss button"))
```

The `fileExporter` completion handler must also post the notification after `completeSaveAs`:

```swift
.fileExporter(
    isPresented: $showSaveAs,
    document: document,
    contentType: .plainText,
    defaultFilename: detector.displayURL.deletingPathExtension().lastPathComponent
) { result in
    if case let .success(url) = result {
        detector.completeSaveAs(to: url)
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }
}
```

### Contracts

- No change to button action closures or `ChangeDetector` API beyond the notification posts above.
- No change to `DocumentView`'s overlay that instantiates `DetectorSurfaces`.

### Seam relationships

- `DetectorSurfaces` is a self-contained overlay inserted in `DocumentView`. The relationship is unchanged.

Reuses pattern: **UX checklist** — WCAG 4.1.2 (Name, Role, Value) requires interactive controls to have accessible names; Apple HIG confirms `.accessibilityLabel` is the correct mechanism on iOS. Nielsen heuristic 1 (Visibility of system status): VoiceOver users must receive feedback when the surface changes.

---

## Component 5 — DocumentView (`Markus_v3/Views/DocumentView.swift`)

### Behavioral constraints

- **Every user-triggered mode transition posts exactly one announcement.** When a user action causes the mode to transition from `.rendered` to `.raw`, `UIAccessibility.post(notification: .announcement, argument:)` is called with a non-empty localizable string describing raw/edit mode. When a user action causes the mode to transition from `.raw` to `.rendered`, an announcement for rendered/preview mode is posted.
- **Announcements fire at the call site of each triggering path, not in a reactive observer.** The announcement is posted directly inside the code path that writes `mode`, not inside a `.onChange(of: mode)` observer. This eliminates any dependency on SwiftUI's state-batching semantics and ensures announcements cannot fire spuriously during initial mode setup. *Addresses adversarial F-001.*
- **The initial mode assignment on `onAppear` does not post an announcement.** Because announcements are posted only inside explicit user-triggered call sites (listed below), and `onAppear`'s `mode = resolved` write is not one of those call sites, no announcement fires on initial load regardless of whether `didInitMode` is true or false. The `didInitMode` guard is no longer involved in announcement suppression and may be retained for its original purpose (preventing re-initialization on subsequent `onAppear` calls) without any impact on announcement behavior.
- **Triggering paths that post announcements are:**
  - `switchTo(_:target:)` — called by the `onTap` closure in the `.rendered` case (tap-to-edit) and by `switchToRawFromSwipe()`. Posts the appropriate announcement for the `target` mode immediately before or after writing `mode = target`.
  - The toolbar "Show rendered" button handler — directly in the `Button { ... }` body. Posts the rendered-mode announcement.
  - `switchToRenderedFromSwipe()` — posts the rendered-mode announcement.
  - `switchToRawFromSwipe()` delegates to `switchTo`, which posts the raw-mode announcement. No separate post is needed in `switchToRawFromSwipe()`.
- **No `.onChange(of: mode)` observer for announcements.** The observer described in the original design is removed. No `.onChange(of: mode)` modifier is added to `DocumentView.body` for this purpose.
- **Announcements are localizable.** Both strings pass through `String(localized:)` or `NSLocalizedString`. English defaults: "Editing mode" and "Preview mode".
- **Announcement is a no-op when VoiceOver is off.** `UIAccessibility.post(notification: .announcement, ...)` is always unconditional; no guard on `UIAccessibility.isVoiceOverRunning` is needed.
- **All existing side effects are preserved.** Scroll-anchor seeding, `triggerSave()` calls, and `focusRawOnFirstAppear` are untouched. The announcement is a new, parallel side effect only.

### Change

**Remove:** Do not add a `.onChange(of: mode)` modifier for announcements. The original design's proposed observer is not implemented.

**Add to `switchTo(_:target:)`:** Post the announcement for `target` mode:

```swift
private func switchTo(_ from: DocumentMode, target: DocumentMode) {
    if from == .raw && target == .rendered {
        triggerSave()
    }
    mode = target
    switch target {
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

**Add to the toolbar "Show rendered" button handler** (currently the `Button { ... }` body that writes `mode = .rendered`):

```swift
Button {
    pendingRenderedAnchor = ScrollAnchor(fractionalY: rawScrollState.currentFractionalY)
    triggerSave()
    mode = .rendered
    UIAccessibility.post(
        notification: .announcement,
        argument: String(localized: "Preview mode",
                         comment: "VoiceOver announcement when switching to rendered preview mode")
    )
} label: {
    Image(systemName: "eye")
}
.accessibilityLabel("Show rendered")
```

**Add to `switchToRenderedFromSwipe()`:**

```swift
private func switchToRenderedFromSwipe() {
    pendingRenderedAnchor = ScrollAnchor(fractionalY: rawScrollState.currentFractionalY)
    triggerSave()
    mode = .rendered
    UIAccessibility.post(
        notification: .announcement,
        argument: String(localized: "Preview mode",
                         comment: "VoiceOver announcement when switching to rendered preview mode")
    )
}
```

`switchToRawFromSwipe()` already delegates to `switchTo(.rendered, target: .raw)`, which now posts the raw-mode announcement. No change needed to `switchToRawFromSwipe()` itself.

### Contracts

- `mode: DocumentMode` — the existing `@State` property. Unchanged type and mutation sites.
- `didInitMode: Bool` — the existing `@State` property. Not involved in announcement logic.
- `switchTo(_:target:)` — updated to include announcement posting. Call sites are unchanged.

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
