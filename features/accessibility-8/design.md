# Design: accessibility-8

## Overview

Five targeted accessibility changes across four files. All changes are additive
to the accessibility tree; no visible rendering changes. No new files are
created; no existing interfaces are broken.

---

## Component 1 — RenderedView (link behavior)

**File:** `Markus_v3/Views/RenderedView.swift`

### Behavioral constraints

- BC-1.1: When a user activates a link element in the rendered view — by tap or
  by VoiceOver double-tap — the system `openURL` environment action is invoked
  with the link's URL. The document mode remains `.rendered`. No mode switch
  occurs.
- BC-1.2: When a user taps any area of the rendered view that is not a link,
  `onTap(fractionalY)` fires and the document transitions to `.raw` mode, exactly
  as before.
- BC-1.3: The VoiceOver "Edit" custom accessibility action (`.accessibilityAction(named: "Edit")`)
  continues to call `onTap(nil)`, transitioning the document to `.raw` mode.
- BC-1.4: SwiftUI's default `openURL` environment propagation is in effect for
  the `Markdown(...)` content. `UIApplication.shared.open` handles http/https,
  mailto, and custom-scheme URLs. An unregistered scheme is silently ignored by
  the OS; no crash, no mode switch.
- BC-1.5: `simulateLinkTap(_:)` no longer calls `onTap`. It is a no-op (or is
  removed). Tests that previously asserted a mode switch on link tap must be
  updated to assert no mode switch (the URL is passed to `openURL` instead).

### Change

Remove the `.environment(\.openURL, OpenURLAction { _ in ... })` modifier block
(lines 64–67 of current source). This unblocks SwiftUI's default URL-opening
path. The `.onTapGesture` block remains untouched.

Update or remove `simulateLinkTap(_:)`: after removal of the override, calling
`onTap(nil)` from that helper is semantically wrong. The helper either becomes a
no-op or is deleted and any callers are updated accordingly.

### Seam

`RenderedView` receives `onTap` from `DocumentView`. The `onTap` callback is
unchanged in signature; only the path that previously triggered it (link
activation) is removed. `DocumentView` needs no change for this concern.

### Contracts preserved

- `.accessibilityAction(named: "Edit")` remains the VoiceOver path to edit mode.
- `.accessibilityIdentifier("RenderedView")` is unchanged.
- `simulateTap()` is unchanged.

---

## Component 2 — MarkdownThemeFactory (heading traits)

**File:** `Markus_v3/Views/MarkdownThemeFactory.swift`

### Behavioral constraints

- BC-2.1: Each heading view (H1 through H6) carries the UIAccessibility trait
  `.isHeader`. VoiceOver's headings rotor finds and navigates between all six
  heading levels in document order.
- BC-2.2: Body paragraphs, list items, and code blocks carry no `.isHeader`
  trait.
- BC-2.3: Visual output is identical — font size, weight, and margins are
  unchanged. The trait is metadata only.
- BC-2.4: The `.isHeader` trait persists across Dynamic Type size changes. Because
  `RenderedView` rebuilds its body on `dynamicTypeSize` changes (triggering
  `makeTheme()` again), the rebuilt view builders include the trait by construction.

### Change

In each of the six heading builder closures (`heading1` … `heading6`), append
`.accessibilityAddTraits(.isHeader)` to `configuration.label` — the same object
on which `.markdownMargin` and `.markdownTextStyle` are already called. The
trait must be applied to the label view directly, not to a wrapper, so that
MarkdownUI's layout hierarchy presents the trait on the heading element itself.

Example pattern for each heading level:

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

### Seam

`MarkdownThemeFactory` is stateless and has no callers to update. `RenderedView`
calls `makeTheme()` at body-build time. No contract change.

---

## Component 3 — MarkdownEditorTextView (Dynamic Type live update)

**File:** `Markus_v3/Editor/MarkdownEditorTextView.swift`

### Behavioral constraints

- BC-3.1: When `UIContentSizeCategory.didChangeNotification` fires while the
  view is allocated, `configureAppearance()` runs on the main queue. After it
  runs, `font` and `typingAttributes[.font]` reflect the new
  `UIFont.preferredFont(forTextStyle: .body).pointSize - 2` at the current
  category.
- BC-3.2: The cursor's position in the document text is preserved across the
  font update. No text content is lost.
- BC-3.3: The notification observer is registered exactly once (in `init`) and
  is removed in `deinit`. No retain cycle exists between the observer token and
  `self`. No dangling observer fires after deallocation.
- BC-3.4: Rapid successive notifications result in the view converging to the
  final category's size. Intermediate updates do not crash or corrupt the text
  storage.
- BC-3.5: When the view is not in the window at the time of the notification
  (rendered mode is active), `configureAppearance()` still runs. When raw mode
  becomes active again, the text view already shows the correct font — no
  additional trigger is needed.

### Change

Add a stored notification observer token:

```swift
private var dynamicTypeObserver: NSObjectProtocol?
```

In the shared initialization path (called from both `init` variants), register
the observer after `configureAppearance()`:

```swift
dynamicTypeObserver = NotificationCenter.default.addObserver(
    forName: UIContentSizeCategory.didChangeNotification,
    object: nil,
    queue: .main
) { [weak self] _ in
    self?.configureAppearance()
}
```

Using `[weak self]` prevents a retain cycle. The `queue: .main` parameter
delivers on the main queue without an extra `DispatchQueue.main.async` wrapper.

In `deinit`, remove the observer:

```swift
deinit {
    if let token = dynamicTypeObserver {
        NotificationCenter.default.removeObserver(token)
    }
}
```

`configureAppearance()` already rebuilds `font` and `typingAttributes[.font]`
from the current system font query, so no changes to that method are required.
The cursor is preserved because `configureAppearance()` sets `font` and
`typingAttributes` directly — it does not replace `attributedText` or call
`text = ...`, which would reset the selection range.

### Seam

`MarkdownEditorTextView` is a `UITextView` subclass. Its bridge,
`MarkdownTextViewBridge.Representable`, creates the instance in `makeUIView` and
holds no direct reference after creation. Lifecycle is UIKit-standard. No
changes to `MarkdownTextViewBridge` are needed for this concern.

---

## Component 4 — DetectorSurfaces (accessibility labels and hints)

**File:** `Markus_v3/Views/DetectorSurfaces.swift`

### Behavioral constraints

- BC-4.1: "Keep Mine" button: VoiceOver announces a label describing keeping the
  user's local version. Visible button title is unchanged.
- BC-4.2: "Keep Theirs" button: VoiceOver announces a label describing keeping
  the incoming (remote) version. Visible button title is unchanged.
- BC-4.3: "Discard Mine" button: VoiceOver announces a label describing
  discarding local changes, plus a hint that the action is irreversible and
  local edits cannot be recovered.
- BC-4.4: "Save As" deletion-banner button: VoiceOver announces a label
  describing saving the document to a new location.
- BC-4.5: "Dismiss" deletion-banner button: VoiceOver announces a meaningful
  label for dismissing the file-deleted notice.
- BC-4.6: All five `.accessibilityIdentifier` values —
  `ConflictKeepMine`, `ConflictKeepTheirs`, `ConflictDiscardMine`,
  `DeletionBannerSaveAs`, `DeletionBannerDismiss` — are preserved exactly. They
  must not be removed, renamed, or reordered.
- BC-4.7: When VoiceOver is off, the labels and hints are present in the
  accessibility tree but produce no observable effect on sighted users.

### Change

Add `.accessibilityLabel` and (for "Discard Mine") `.accessibilityHint` after
each existing `.accessibilityIdentifier`, keeping the identifier modifier first
so the ordering is easy to audit.

Conflict sheet buttons:

```swift
Button("Keep Mine") { detector.resolveConflict(.keepMine) }
    .accessibilityIdentifier("ConflictKeepMine")
    .accessibilityLabel("Keep My Version")

Button("Keep Theirs") { detector.resolveConflict(.keepTheirs) }
    .accessibilityIdentifier("ConflictKeepTheirs")
    .accessibilityLabel("Keep Their Version")

Button("Discard Mine", role: .destructive) { detector.resolveConflict(.discardMine) }
    .accessibilityIdentifier("ConflictDiscardMine")
    .accessibilityLabel("Discard My Changes")
    .accessibilityHint("Your local edits cannot be recovered after this action.")
```

Deletion banner buttons:

```swift
Button("Save As") { showSaveAs = true }
    .accessibilityIdentifier("DeletionBannerSaveAs")
    .accessibilityLabel("Save to New Location")

Button("Dismiss") { detector.dismissDeletionBanner() }
    .accessibilityIdentifier("DeletionBannerDismiss")
    .accessibilityLabel("Dismiss")
```

The label strings are plain Swift string literals here; they must be wrapped in
`String(localized:)` or `NSLocalizedString(_:comment:)` in the actual
implementation so they are localizable. (The pattern already exists in
`DocumentView.copyContentsToClipboard()`.)

### Seam

`DetectorSurfaces` is a self-contained overlay; it receives `detector` and
`document` by injection from `DocumentView`. No changes to `DocumentView` are
needed for this concern.

---

## Component 5 — DocumentView (mode-switch announcements)

**File:** `Markus_v3/Views/DocumentView.swift`

### Behavioral constraints

- BC-5.1: Every transition of the `mode` state from `.rendered` to `.raw` —
  regardless of the triggering path (toolbar button, `onTap` callback,
  `switchTo`, `switchToRawFromSwipe`) — posts exactly one
  `UIAccessibility.post(notification: .announcement, argument: ...)` call with
  a non-empty, localizable string describing raw/edit mode (e.g., "Editing mode").
- BC-5.2: Every transition of the `mode` state from `.raw` to `.rendered` posts
  exactly one announcement with a non-empty, localizable string describing
  rendered/preview mode (e.g., "Preview mode").
- BC-5.3: The initial `onAppear` assignment of `mode` (DC-4 rule) does NOT fire
  an announcement. The guard is that the `didInitMode` flag is `false` at the
  time of the first `mode` write; the `.onChange(of: mode)` observer therefore
  must only post when `didInitMode` is already `true`.
- BC-5.4: When VoiceOver is off, `UIAccessibility.post(notification: .announcement, ...)`
  is a no-op. No error, no crash.
- BC-5.5: Announcement strings pass through `NSLocalizedString` or
  `String(localized:)` so they appear in `.strings` / `.xcstrings` files for
  future localization. The English default values are "Editing mode" and
  "Preview mode".
- BC-5.6: All existing mode-switch side effects are undisturbed: scroll-anchor
  seeding, `triggerSave()` calls, `focusRawOnFirstAppear`, and
  `pendingRenderedAnchor` seeding happen in the same code paths as today.

### Change

Add a single `.onChange(of: mode)` modifier to `DocumentView.body`. The
modifier fires once per mode value change and posts the appropriate announcement,
guarded by `didInitMode`:

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

Placement: attach after the existing `.onChange(of: scenePhase)` modifier so
the ordering of side-effect modifiers is consistent and easy to read.

The guard `guard didInitMode else { return }` is safe because:

1. `onAppear` sets `mode` and then immediately sets `didInitMode = true` in the
   same synchronous block. SwiftUI batches `@State` mutations; `.onChange`
   observers fire after the render cycle, by which time `didInitMode` is `true`.
   However, the `onAppear` block writes `mode` first and `didInitMode` second
   in source order; to be certain the guard works, the ordering in `onAppear`
   must be preserved (mode set → didInitMode set = true), which is already the
   case in the current source.
2. All subsequent mode changes (toolbar, tap, swipe) occur after `onAppear`
   completes, so `didInitMode` is `true` and the announcement fires.

No changes are needed to `switchTo`, `switchToRawFromSwipe`, or
`switchToRenderedFromSwipe`. The single `.onChange(of: mode)` observer covers
all paths, satisfying AC-5.3 ("fires once per mode transition, not once per
triggering path").

### Seam

`DocumentView` already uses `UIAccessibility.post` in
`copyContentsToClipboard()`, establishing the pattern. No new import is needed.

---

## Cross-cutting constraints (all components)

- All changes are additive; no `.accessibilityIdentifier` value is removed or
  renamed (CC-1).
- All existing unit and UI tests continue to pass. Where `simulateLinkTap`
  previously asserted a mode switch, those tests must be updated to assert no
  mode switch — this is a test-correction, not a regression (CC-2, AC-1.5).
- Visual rendering is unchanged across all five changes (CC-3).
- No new user-visible settings or opt-in mechanism; all improvements are always-on
  (CC-4).

---

## Patterns reused from constitution.md

Reuses pattern: **Commits — conventional commits, one per logical unit of work.**
Each of the five concerns is implemented and committed independently:
`fix(accessibility): ...` per concern.

Reuses pattern: **UX checklist — Apple HIG as the authoritative reference for
platform decisions.** The `.isHeader` trait, `UIAccessibility.post` announcement,
and `openURL` restoration all follow Apple HIG accessibility guidance directly.

---

## Requirements changes implied by this architecture

One requirement warrants a note — not a change, but an implementation order
dependency:

**AC-1.5 / test update:** The requirement states that tests relying on the old
`simulateLinkTap` → mode-switch behavior "must be updated to reflect the
corrected semantics." This is a test file change, not a requirements change.
The architecture flags it here so the DAG places the test update in the same
wave as the `RenderedView` change, not after it.

No requirements changes are otherwise needed.

---

Architecture stable — no requirements changes flagged
