# DAG: accessibility-8

Five surgical accessibility fixes across four components. All changes are additive
to the accessibility tree or replace a blocking override with platform-default
behavior.

---

## Size check

5 tasks across 3 waves. Fits one screen. No split required.

---

## Tasks

### T-001 — Remove OpenURLAction override from RenderedView + update simulateLinkTap + correct existing tests

**Wave:** 1

**Description:**
Remove the `.environment(\.openURL, OpenURLAction { _ in ... })` modifier block from
`RenderedView` so that link taps are dispatched to the system default handler rather
than redirected to `onTap(nil)`. Update `simulateLinkTap(_:)` to an empty body (or
remove it) since its former behavior no longer represents link activation. Update
the existing tests in `RenderedViewTests.swift` that asserted the old link-tap-calls-
`onTap` behavior (`testLinkTapFiresCallback`, `testLinkTapReportsNilFractional`) to
reflect the corrected semantics (link taps do not call `onTap`). These test corrections
must land in the same wave as the production change (CC-2, AC-1.5, design CC-3 DAG note).

**Files touched:**
- `Markus_v3/Views/RenderedView.swift`
- `Markus_v3Tests/RenderedViewTests.swift` (test corrections for AC-1.5)

**Inputs:**
- `features/accessibility-8/design.md` §Component 1
- `features/accessibility-8/requirements.md` §Concern 1 (AC-1.1–1.5, EC-1.1–1.4)

**Outputs:**
- `RenderedView` with `OpenURLAction` override removed; `simulateLinkTap` emptied or removed
- Updated `RenderedViewTests.swift` reflecting corrected link-tap semantics

**Dependencies:** none

**Acceptance condition:**
`xcodebuild test` passes with no failures in `RenderedViewTests.swift`. The test
`testLinkTapFiresCallback` (or its successor) asserts that link taps do NOT call
`onTap`. The `openURL` environment in `RenderedView.body` is the default system
handler (no `.environment(\.openURL, ...)` modifier present). Non-link taps still
call `onTap` — verified by existing `testNonLinkTapCallsOnTap` or equivalent.

---

### T-002 — Add .isHeader accessibility traits to H1–H6 in MarkdownThemeFactory

**Wave:** 2

**Description:**
In each of the six heading closures (`heading1` through `heading6`) in
`MarkdownThemeFactory.makeTheme()`, append `.accessibilityAddTraits(.isHeader)` to
`configuration.label`. If the trait does not propagate through MarkdownUI's container
to the leaf element VoiceOver focuses (verifiable via `AccessibilityHeadingRotorUITests`),
wrap `configuration.label` in an `.accessibilityElement(children: .combine)` container
that carries the trait, as described in the design's Component 2 fallback.

**Files touched:**
- `Markus_v3/Views/MarkdownThemeFactory.swift`

**Inputs:**
- `features/accessibility-8/design.md` §Component 2
- `features/accessibility-8/requirements.md` §Concern 2 (AC-2.1–2.5, EC-2.1–2.4)

**Outputs:**
- `MarkdownThemeFactory.makeTheme()` with `.isHeader` trait on all six heading levels
- Visual output (font size, weight, margins) unchanged

**Dependencies:** T-001 (none strictly; placed in Wave 2 to allow CI to validate T-001 first)

**Acceptance condition:**
`xcodebuild test` passes with no failures in `MarkdownThemeFactoryAccessibilityTests`
and `AccessibilityHeadingRotorUITests`. Specifically, `testRenderedViewExposesAtLeastOneHeadingElement`
passes (trait is present on at least one element in the live accessibility tree),
and `headingFontIsProportionalToBody` passes (typography unchanged).

---

### T-003 — Add UIContentSizeCategory observer to MarkdownEditorTextView with 1pt floor

**Wave:** 2

**Description:**
Add a stored `NSObjectProtocol?` token (`dynamicTypeObserver`) to
`MarkdownEditorTextView`. Register a `UIContentSizeCategory.didChangeNotification`
observer in `init` (after existing `configureTraits()` and `configureAppearance()`
calls) that calls `self?.configureAppearance()` on the main queue with `[weak self]`.
Remove the observer token in `deinit`. Update `configureAppearance()` to clamp the
computed size to a minimum of 1pt using `max(1, rawSize)`.

**Files touched:**
- `Markus_v3/Editor/MarkdownEditorTextView.swift`

**Inputs:**
- `features/accessibility-8/design.md` §Component 3
- `features/accessibility-8/requirements.md` §Concern 3 (AC-3.1–3.6, EC-3.1–3.3)

**Outputs:**
- `MarkdownEditorTextView` with live Dynamic Type observer and 1pt font-size floor
- Observer lifecycle tied to view lifecycle (no retain cycle, no dangling observer)

**Dependencies:** T-001 (none strictly; placed in Wave 2 to allow CI to validate T-001 first)

**Acceptance condition:**
`xcodebuild test` passes with no failures in `MarkdownEditorDynamicTypeTests`.
Specifically, `observerIsRemovedOnDealloc` passes (no retain cycle), `fontSizeHasFloorOfOnePt`
passes, and `fontAndTypingAttributesBothUpdate` passes. `deinit` is present in source
and removes the stored token.

---

### T-004 — Add accessibility labels/hints to DetectorSurfaces buttons + post .layoutChanged after banner dismissal

**Wave:** 2

**Description:**
In `DetectorSurfaces.swift`, add `.accessibilityLabel(...)` modifiers to all five
buttons (`ConflictKeepMine`, `ConflictKeepTheirs`, `ConflictDiscardMine`,
`DeletionBannerSaveAs`, `DeletionBannerDismiss`) and `.accessibilityHint(...)` to
`ConflictDiscardMine`. All strings must pass through `String(localized:)`. The "Dismiss"
banner button label must be context-specific (not the bare word "Dismiss"). After
`detector.dismissDeletionBanner()` in the "Dismiss" button action, post
`UIAccessibility.post(notification: .layoutChanged, argument: nil)`. In the
`fileExporter` completion handler, after `detector.completeSaveAs(to: url)` in the
`.success` branch, post the same notification. All five `.accessibilityIdentifier`
values must remain unchanged.

**Files touched:**
- `Markus_v3/Views/DetectorSurfaces.swift`

**Inputs:**
- `features/accessibility-8/design.md` §Component 4
- `features/accessibility-8/requirements.md` §Concern 4 (AC-4.1–4.9, EC-4.1–4.3)

**Outputs:**
- `DetectorSurfaces` with accessibility labels, hint, and post-dismissal `.layoutChanged` notifications
- All five `.accessibilityIdentifier` values unchanged

**Dependencies:** T-001 (none strictly; placed in Wave 2 to allow CI to validate T-001 first)

**Acceptance condition:**
`xcodebuild test` passes with no failures in `AccessibilityLabelsUITests`. Specifically:
`testConflictSheetButtonIdentifiersArePreserved` and `testDeletionBannerButtonIdentifiersArePreserved`
pass (identifiers intact); `testKeepMineHasNonEmptyAccessibilityLabel`,
`testKeepTheirsHasNonEmptyAccessibilityLabel`, `testDiscardMineHasNonEmptyAccessibilityLabel`,
`testDeletionBannerSaveAsHasNonEmptyLabel` pass; `testDismissBannerButtonHasContextSpecificLabel`
passes (label is not the bare word "Dismiss").

---

### T-005 — Post VoiceOver mode-switch announcements at triggering call sites in DocumentView

**Wave:** 3

**Description:**
In `DocumentView.swift`, add `UIAccessibility.post(notification: .announcement, argument:)`
calls at each of the four user-triggered mode-transition call sites:
(1) `switchTo(_:target:)` — switch on `target` to post the raw-mode or rendered-mode
announcement; (2) the toolbar "Show rendered" `Button { ... }` handler; (3)
`switchToRenderedFromSwipe()`. `switchToRawFromSwipe()` delegates to `switchTo` and
requires no separate post. The `onAppear` initial mode assignment is not a triggering
call site and must not post an announcement. All strings must pass through
`String(localized:)`. No `.onChange(of: mode)` observer is added for announcements.

**Files touched:**
- `Markus_v3/Views/DocumentView.swift`

**Inputs:**
- `features/accessibility-8/design.md` §Component 5
- `features/accessibility-8/requirements.md` §Concern 5 (AC-5.1–5.6, EC-5.1–5.4)

**Outputs:**
- `DocumentView` with `UIAccessibility.post(.announcement, ...)` at the four triggering paths
- All existing side effects (save, scroll anchor, focus) preserved

**Dependencies:** T-002, T-003, T-004 (must land after Wave 2 tasks so full suite is green before T-005 is integrated)

**Acceptance condition:**
`xcodebuild test` passes with no failures in `DocumentViewModeAnnouncementTests`.
Specifically, `onAppearDoesNotPostAnnouncement` passes (no spurious launch announcement),
`eachSwitchPostsExactlyOneAnnouncement` passes, `switchToRenderedStillTriggersSave`
passes (existing side effect preserved). Source inspection confirms no `.onChange(of: mode)`
announcement observer is present.

---

## Wave summary

| Wave | Tasks | Rationale |
|------|-------|-----------|
| 1 | T-001 | RenderedView change + test corrections must land together (AC-1.5 / CC-2); no dependencies |
| 2 | T-002, T-003, T-004 | Independent component changes; all depend only on Wave 1 passing CI |
| 3 | T-005 | DocumentView integrates after Wave 2 is green; the full suite must be clean before mode-switch announcements land |
