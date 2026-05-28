# Verify: accessibility-8

Human-readable coverage summary mapping each acceptance criterion to the test(s) that verify it.
Task → test mapping is added by Stage 5 (DAG). Do not add task IDs here.

---

## Component 1 — RenderedView: Restore standard link behavior

| AC | Description | Test file | Test name(s) |
|----|-------------|-----------|--------------|
| AC-1.1 | Link tap does not switch to raw mode; `openURL` handles the URL | `LinkBehaviorUITests.swift` | `testLinkTapDoesNotSwitchToRawMode` |
| AC-1.2 | VoiceOver double-tap on link does not switch to raw mode | `LinkBehaviorUITests.swift` | `testLinkTapDoesNotSwitchToRawMode` (covers sighted + VoiceOver path at the OS level; VoiceOver gesture cannot be automated — see limitation note in file) |
| AC-1.3 | Non-link tap transitions to `.raw` | `LinkBehaviorUITests.swift` | `testNonLinkTapSwitchesToRawMode`, `testDocumentWithNoLinksEntersRawModeOnTap` |
| AC-1.4 | VoiceOver "Edit" action still transitions to raw mode | `LinkBehaviorUITests.swift` | `testVoiceOverEditActionSwitchesToRawMode` |
| AC-1.5 | `simulateLinkTap` no longer triggers `onTap` | Covered by the behavioral intent of `testLinkTapDoesNotSwitchToRawMode` (link taps leave the rendered view, not the raw editor). Updated test semantics are documented in `RenderedViewTests.swift` (existing tests that relied on old behavior must be updated per CC-2). |

### Edge cases

| EC | Test |
|----|------|
| EC-1.4 (no links — all taps enter raw mode) | `LinkBehaviorUITests.swift` → `testDocumentWithNoLinksEntersRawModeOnTap` |

---

## Component 2 — MarkdownThemeFactory: Heading accessibility traits

| AC | Description | Test file | Test name(s) |
|----|-------------|-----------|--------------|
| AC-2.1 | Each heading view's accessibility traits include `.isHeader` (unit-level proxy via `headingFont(level:)`) | `MarkdownThemeFactoryAccessibilityTests.swift` | `h1LargerThanBody`, `h2LargerThanBody`, `h3AtLeastBody`, `h4EqualsBody`, `h5SmallerThanBody`, `h6SmallerThanH5`, `headingLevelsDescend`, `makeThemeDoesNotCrash` |
| AC-2.1 | `.isHeader` trait propagates to element VoiceOver focuses (end-to-end) | `AccessibilityHeadingRotorUITests.swift` | `testRenderedViewExposesAtLeastOneHeadingElement`, `testHeadingCountMatchesSeedFileStructure` |
| AC-2.2 | VoiceOver heading rotor navigates sequentially in document order | `AccessibilityHeadingRotorUITests.swift` | `testHeadingElementsAreInDocumentOrder`, `testRenderedViewExposesAtLeastOneHeadingElement` |
| AC-2.3 | Body text does not carry `.isHeader` trait | `MarkdownThemeFactoryAccessibilityTests.swift` → `bodyFontIsNotHeadingScale`; `AccessibilityHeadingRotorUITests.swift` → `testBodyTextDoesNotHaveHeaderTrait` |
| AC-2.4 | Heading trait does not alter visual font metrics | `MarkdownThemeFactoryAccessibilityTests.swift` → `headingFontIsProportionalToBody` |
| AC-2.5 | End-to-end behavioral verification (trait reaches element, not just modifier applied) | `AccessibilityHeadingRotorUITests.swift` → `testRenderedViewExposesAtLeastOneHeadingElement`, `testHeadingElementsAreInDocumentOrder`, `testHeadingCountMatchesSeedFileStructure` |

### Limitation note (AC-2.2 / AC-2.5)
VoiceOver rotor gesture automation is not supported in iOS simulators via XCUITest. The `testVoiceOverRotorGestureIsNotAutomatable` test documents this as an explicit `XCTSkip` with manual verification instructions. The trait-presence tests provide the available end-to-end behavioral signal per AC-2.5.

---

## Component 3 — MarkdownEditorTextView: Dynamic Type live update

| AC | Description | Test file | Test name(s) |
|----|-------------|-----------|--------------|
| AC-3.1 | Font updates to `body - 2` after `UIContentSizeCategory.didChangeNotification` | `MarkdownEditorDynamicTypeTests.swift` | `fontUpdatesOnNotification` |
| AC-3.2 | Both `font` and `typingAttributes[.font]` update after notification | `MarkdownEditorDynamicTypeTests.swift` | `fontAndTypingAttributesBothUpdate` |
| AC-3.3 | Cursor position preserved after resize | `MarkdownEditorDynamicTypeTests.swift` | `fontAssignmentDoesNotResetSelection` |
| AC-3.4 | Off-screen update: font correct when raw mode shown after change | Covered structurally by `fontUpdatesOnNotification` (notification fires regardless of window hierarchy for a UIView; the view does not need to be in a window to receive it). |
| AC-3.5 | Observer removed on dealloc; no retain cycle | `MarkdownEditorDynamicTypeTests.swift` | `observerIsRemovedOnDealloc` |
| AC-3.6 | Font size floor of 1pt (adversarial F-005) | `MarkdownEditorDynamicTypeTests.swift` | `fontSizeHasFloorOfOnePt`, `initFontSizeSatisfiesFloor` |

### Edge cases

| EC | Test |
|----|------|
| EC-3.1 (rapid successive changes converge) | `MarkdownEditorDynamicTypeTests.swift` → `rapidNotificationsConverge` |

---

## Component 4 — DetectorSurfaces: Accessibility labels and hints

| AC | Description | Test file | Test name(s) |
|----|-------------|-----------|--------------|
| AC-4.1 | "Keep Mine" has non-empty `.accessibilityLabel` | `AccessibilityLabelsUITests.swift` | `testKeepMineHasNonEmptyAccessibilityLabel` |
| AC-4.2 | "Keep Theirs" has non-empty `.accessibilityLabel` | `AccessibilityLabelsUITests.swift` | `testKeepTheirsHasNonEmptyAccessibilityLabel` |
| AC-4.3 | "Discard Mine" has non-empty `.accessibilityLabel` | `AccessibilityLabelsUITests.swift` | `testDiscardMineHasNonEmptyAccessibilityLabel` |
| AC-4.4 | "Discard Mine" has non-empty `.accessibilityHint` (irreversible) | `AccessibilityLabelsUITests.swift` | `testDiscardMineHasAccessibilityHint` (XCTSkip — XCUITest cannot read `.accessibilityHint` as a separate property; documented limitation) |
| AC-4.5 | "Save As" banner button has non-empty `.accessibilityLabel` | `AccessibilityLabelsUITests.swift` | `testDeletionBannerSaveAsHasNonEmptyLabel` |
| AC-4.6 | "Dismiss" banner button label is context-specific (not bare "Dismiss") | `AccessibilityLabelsUITests.swift` | `testDismissBannerButtonHasContextSpecificLabel` |
| AC-4.7 | All five `.accessibilityIdentifier` values preserved | `AccessibilityLabelsUITests.swift` | `testConflictSheetButtonIdentifiersArePreserved`, `testDeletionBannerButtonIdentifiersArePreserved` |
| AC-4.8 | Conflict sheet title text is accessible and unchanged | `AccessibilityLabelsUITests.swift` | `testConflictSheetTitleIsPresent` |
| AC-4.9 | `.layoutChanged` posted after banner dismissal; VoiceOver focus not stuck | `AccessibilityLabelsUITests.swift` | `testDeletionBannerDismissHidesBannerAndAppRemainsUsable` (best-effort: banner disappears and app remains usable; direct notification interception is not possible in XCUITest) |

### Limitation note (AC-4.4)
`XCUIElement.accessibilityHint` is not a readable property in XCUITest; hints are VoiceOver-spoken only. The test is a documented `XCTSkip` with manual verification instructions. The hint's presence is verified at the source level (`.accessibilityHint(...)` modifier on `ConflictDiscardMine` in `DetectorSurfaces.swift`).

### Limitation note (AC-4.9)
`UIAccessibility.post(notification: .layoutChanged, ...)` cannot be intercepted in XCUITest. The end-to-end behavioral signal (banner disappears, app usable) is the available automation proxy. VoiceOver focus destination requires on-device manual testing.

---

## Component 5 — DocumentView: VoiceOver announcements on mode switches

| AC | Description | Test file | Test name(s) |
|----|-------------|-----------|--------------|
| AC-5.1 | `switchTo(.rendered, target: .raw)` posts a non-empty announcement | `DocumentViewModeAnnouncementTests.swift` | `switchToRawPostsAnnouncement`, `switchToRawAnnouncementText`, `swipeToRawPostsAnnouncement` |
| AC-5.2 | `switchTo(.raw, target: .rendered)` / toolbar / swipe post announcements | `DocumentViewModeAnnouncementTests.swift` | `switchToRenderedPostsAnnouncement`, `toolbarShowRenderedPostsAnnouncement`, `swipeToRenderedPostsAnnouncement`, `renderedModeAnnouncementText` |
| AC-5.3 | Each transition posts exactly one announcement | `DocumentViewModeAnnouncementTests.swift` | `eachSwitchPostsExactlyOneAnnouncement`, `renderedPathsEachPostOneAnnouncement` |
| AC-5.4 | Announcement strings are localizable | `DocumentViewModeAnnouncementTests.swift` | `announcementStringsAreLocalizable` |
| AC-5.5 | `onAppear` initial mode assignment does NOT post an announcement | `DocumentViewModeAnnouncementTests.swift` | `onAppearDoesNotPostAnnouncement`, `onAppearRawForEmptyFilePostsNoAnnouncement` |
| AC-5.6 | Existing side effects preserved (save, scroll anchor, focus) | `DocumentViewModeAnnouncementTests.swift` | `switchToRenderedStillTriggersSave`, `switchToRawDoesNotTriggerSave`, `toolbarShowRenderedTriggersSave` |

### Approach note (AC-5.1–5.3)
`UIAccessibility.post()` is a global side-effect with no testable return value and cannot be intercepted without swizzling, which produces flaky shared-state tests. The tests use `DocumentViewAnnouncementProbe` — a value-type mirror of `DocumentView`'s triggering logic with the `UIAccessibility.post` call replaced by a capturable string. This gives structural coverage of the four call sites (`switchTo`, toolbar handler, `switchToRenderedFromSwipe`, `switchToRawFromSwipe`-via-delegation). Real-device VoiceOver verification is the complementary manual step.

---

## Cross-cutting constraints

| CC | Coverage |
|----|---------|
| CC-1 (no identifiers removed) | `AccessibilityLabelsUITests.swift` → `testConflictSheetButtonIdentifiersArePreserved`, `testDeletionBannerButtonIdentifiersArePreserved` |
| CC-2 (existing tests updated for link semantics) | `RenderedViewTests.swift` — the existing `testLinkTapFiresCallback` and `testLinkTapReportsNilFractional` tests reflect the OLD behavior and must be updated as part of the Component 1 implementation wave to reflect AC-1.5 (link taps do not call `onTap`). This is a test-correction obligation, not a regression. |
| CC-3 (no visual rendering changes) | `MarkdownThemeFactoryAccessibilityTests.swift` → `headingFontIsProportionalToBody` (font metrics unchanged) |
| CC-4 (all improvements always-on) | No test required; verified by the absence of any settings/toggle mechanism in the implementation. |

---

## Untestable / manual-only

| Item | Reason | Manual verification |
|------|--------|---------------------|
| AC-1.2 (VoiceOver link activation on device) | VoiceOver gesture automation not supported in iOS simulators | Enable VoiceOver on a physical device, open a document with a link, swipe to the link element, double-tap — confirm Safari opens and DocumentView stays in rendered mode. |
| AC-2.2 (VoiceOver rotor swipe gesture) | VoiceOver rotor cannot be driven in XCUITest | Enable VoiceOver, open a heading-bearing document, rotate rotor to "Headings", swipe down — confirm sequential heading navigation. |
| AC-3.4 (off-screen update correctness) | Cannot programmatically change system Dynamic Type in tests | Use Settings → Accessibility → Larger Text while the app is open in rendered mode; switch to raw and confirm font is updated. |
| AC-4.4 (hint is spoken by VoiceOver) | `XCUIElement.accessibilityHint` not readable in XCUITest | Enable VoiceOver, trigger conflict sheet, navigate to "Discard Mine", pause — confirm hint is announced. |
| AC-4.9 (VoiceOver focus destination after banner dismissal) | `UIAccessibility.post` notification not interceptable in XCUITest | Enable VoiceOver, trigger deletion banner, navigate focus to banner buttons, tap "Dismiss" — confirm focus moves to document content, not stuck on invisible banner. |
| AC-5.1–5.2 (real UIAccessibility.post fires) | Global side-effect; no test-observable return value without swizzling | Enable VoiceOver, trigger mode switches via each path — confirm announcement is heard. |
