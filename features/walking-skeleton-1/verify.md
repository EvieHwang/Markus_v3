# Test coverage: walking-skeleton-1

*Spec tests are written before implementation per CLAUDE.md's build-flow note. Each test is tagged with the DAG task IDs whose acceptance condition it verifies. Tests will fail with import-error / "type does not exist" until the corresponding task is built — that's the expected initial state.*

**Framework:** Swift Testing (unit) + XCUITest (UI) — populated this run into `constitution.md` `## Testing`.

**Run:** `xcodebuild test -scheme Markus_v3 -destination 'platform=iOS Simulator,name=iPhone 15'` or `⌘U` in Xcode.

---

## Coverage matrix

Every DAG task has at least one test. Every behavioral requirement maps to at least one test.

| DAG task | Tests |
|---|---|
| T-001 (Xcode project + dep + manifest) | `BootstrapTests.swift` (project builds, MarkdownUI resolves, Privacy Manifest validates, UTType declared) |
| T-002 (DocumentMode, DocumentError, ActiveAlert) | `SmallTypesTests.swift` |
| T-003 (MarkdownDocument) | `MarkdownDocumentTests.swift` |
| T-004 (AutosaveCoordinator) | `AutosaveCoordinatorTests.swift` |
| T-005 (SaveStatusObserver) | `SaveStatusObserverTests.swift` |
| T-006 (ToastModifier) | `ToastModifierTests.swift` |
| T-007 (RenderedView) | `RenderedViewTests.swift` (unit) + `WalkingSkeletonFlowUITests.swift` (E2E) |
| T-008 (RawEditorView) | `RawEditorViewTests.swift` (unit) + `WalkingSkeletonFlowUITests.swift` (E2E) |
| T-009 (DocumentLoadingView) | `DocumentLoadingViewTests.swift` |
| T-010 (DocumentView + Markus_v3App) | `DocumentViewTests.swift` + `WalkingSkeletonFlowUITests.swift` (E2E) |

---

## Behavioral coverage (requirements → tests)

| Requirement | Test(s) |
|---|---|
| AC-1.1 (first launch → document browser, no splash/onboarding) | `WalkingSkeletonFlowUITests.testFirstLaunchShowsDocumentBrowser` |
| AC-1.2 (no splash/onboarding/library) | `WalkingSkeletonFlowUITests.testFirstLaunchShowsDocumentBrowser` (asserts absence) |
| AC-1.3 (UTType filter to .md/.markdown) | `BootstrapTests.testInfoPlistDeclaresMarkdownUTTypes` |
| AC-2.1 (open file → renders as GFM) | `WalkingSkeletonFlowUITests.testOpenFileRendersGFM` |
| AC-2.2 (rendered is default mode) | `DocumentViewTests.testInitialModeIsRenderedForSmallFile` |
| AC-2.3 (nav bar = filename without extension) | `WalkingSkeletonFlowUITests.testNavBarShowsFilenameWithoutExtension` |
| AC-2.4 (read via security-scoped access, no copy) | `WalkingSkeletonFlowUITests.testNoCopyInAppContainer` |
| AC-2.5 (empty file opens, blank rendered view) | `MarkdownDocumentTests.testEmptyFileRoundTrip`, `RenderedViewTests.testEmptySourceProducesEmptyView` |
| AC-3.1 (tap rendered → raw) | `WalkingSkeletonFlowUITests.testTapToEdit`, `RenderedViewTests.testTapGestureSwitchesMode` |
| AC-3.2 (raw shows eye-icon toolbar item) | `WalkingSkeletonFlowUITests.testRawModeShowsEyeIcon` |
| AC-3.3 (link tap in rendered → raw, no follow) | `RenderedViewTests.testLinkTapSwitchesMode` |
| AC-3.4 (tap-to-edit + second tap places cursor) | `WalkingSkeletonFlowUITests.testTapToEditRequiresSecondTapForCursor` |
| AC-4.1 (raw editor is monospace TextEditor) | `RawEditorViewTests.testUsesMonospaceFont` |
| AC-4.2 (edits dirty the document) | `RawEditorViewTests.testTextChangeDirtiesDocument` |
| AC-4.3 (save goes to original location, no copy) | `WalkingSkeletonFlowUITests.testEditsPersistAtOriginalLocation` |
| AC-4.4 (save triggers: mode switch, leaving doc, background, 500 ms idle) | `AutosaveCoordinatorTests.testDebouncedSaveAfter500ms`, `DocumentViewTests.testModeSwitchTriggersSave`, `DocumentViewTests.testBackgroundingTriggersSave` |
| AC-4.5 (post-save, dirty flag clears) | `MarkdownDocumentTests.testSaveClearsDirtyState` |
| AC-4.6 (default UITextView behavior) | `RawEditorViewTests.testUsesDefaultTextEditorBehavior` (no smart-quote/autocorrect override) |
| AC-5.1 (eye icon → rendered) | `WalkingSkeletonFlowUITests.testEyeIconReturnsToRendered` |
| AC-5.2 (return-to-rendered triggers save) | `DocumentViewTests.testModeSwitchTriggersSave` |
| AC-5.3 (rendered view shows latest source) | `WalkingSkeletonFlowUITests.testEditedContentVisibleInRendered` |
| AC-5.4 (mode is not persisted across opens) | `DocumentViewTests.testInitialModeIsRenderedForSmallFile` (each open starts in rendered) |
| AC-6.1 (close + reopen shows edits) | `WalkingSkeletonFlowUITests.testEditsVisibleAfterCloseReopen` |
| AC-6.2 (file on disk contains edits) | `WalkingSkeletonFlowUITests.testEditsPersistAtOriginalLocation` |
| AC-6.3 (no app-container copy) | `WalkingSkeletonFlowUITests.testNoCopyInAppContainer` |
| EC-1 (empty file) | `MarkdownDocumentTests.testEmptyFileRoundTrip` |
| EC-2 (≥ 500 KB → raw mode by default) | `DocumentViewTests.testLargeFileOpensInRawMode`, `DocumentViewTests.testSmallFileOpensInRendered` |
| EC-3 (GFM features render visibly) | `RenderedViewTests.testGFMFeaturesRender` |
| EC-4 (invalid UTF-8) | `MarkdownDocumentTests.testInvalidUTF8ThrowsInvalidEncoding` |
| EC-5 (.markdown extension treated identically) | `MarkdownDocumentTests.testMarkdownAndMdExtensionsBothReadable` |
| EC-6 (background → save before suspend; long backgrounding resets mode to rendered) | `DocumentViewTests.testBackgroundingTriggersSave`, `DocumentViewTests.testSceneTeardownResetsToRendered` |
| EC-7 (app killed mid-edit → unsaved edits may be lost) | `AutosaveCoordinatorTests.testNoSaveBefore500msIdle` (documents the bound) |
| EC-8 (rapid mode switching does not crash) | `WalkingSkeletonFlowUITests.testRapidModeSwitching` |
| EC-9/10/12 (save failures → non-fatal alert; in-memory text preserved) | `SaveStatusObserverTests.testSavingErrorStateFiresLastSaveError`, `DocumentViewTests.testSaveFailureShowsAlert` |
| EC-11 (external mod last-write-wins) | *not tested in skeleton — Roadmap #3* (explicitly out-of-scope) |
| EC-13 (iCloud download pending → loading indicator) | `SaveStatusObserverTests.testEditingDisabledStateFiresIsDownloading`, `DocumentLoadingViewTests.testRendersSpinnerAndLabel` |
| EC-14 (cancel file picker) | `WalkingSkeletonFlowUITests.testCancelFilePicker` |
| EC-15 (non-markdown file rejected) | `BootstrapTests.testInfoPlistDeclaresMarkdownUTTypes` (browser filter is the primary defense) |
| AC-RECOVER-1 (save-failure alert offers Copy + Dismiss) | `DocumentViewTests.testSaveFailureAlertHasCopyAndDismiss` |
| AC-RECOVER-2 (toast appears after Copy) | `ToastModifierTests.testToastAppearsAndClears`, `DocumentViewTests.testCopyTriggersToast` |
| AC-A11Y-1 (eye-icon VoiceOver label) | `WalkingSkeletonFlowUITests.testEyeIconAccessibilityLabel` |
| AC-A11Y-2 (Edit accessibility action on rendered) | `WalkingSkeletonFlowUITests.testRenderedViewHasEditAccessibilityAction` |
| AC-A11Y-3 (Copy posts VoiceOver announcement, independent of toast) | `DocumentViewTests.testCopyPostsAccessibilityAnnouncement` |

---

## Structural coverage (design → tests)

| Design element | Test(s) |
|---|---|
| `DocumentGroup` is the only entry point (component #1) | `WalkingSkeletonFlowUITests.testFirstLaunchShowsDocumentBrowser` |
| `ReferenceFileDocument` (component #2) | `MarkdownDocumentTests.testRoundTripReadWrite` |
| `initialByteSize` captured (component #2) | `MarkdownDocumentTests.testInitialByteSizeMatchesInput` |
| `MarkdownUI` pin via SwiftPM (component #5, Dependencies) | `BootstrapTests.testMarkdownUIResolvesAtPinnedMinor` |
| `OpenURLAction` intercept (component #5, AC-3.3) | `RenderedViewTests.testLinkTapSwitchesMode` |
| Save debounce = 500 ms (component #7) | `AutosaveCoordinatorTests.testDebouncedSaveAfter500ms` |
| Global `UIDocument.stateChangedNotification` subscription (component #11) | `SaveStatusObserverTests.testGlobalNotificationSubscriptionWorksWithoutDocumentReference` |
| Privacy Manifest enumeration (component #10, F-006) | `BootstrapTests.testPrivacyManifestEnumeratesRequiredCategories` |
| MarkdownUI version constraint = `.upToNextMinor` (Dependencies, F-005) | `BootstrapTests.testMarkdownUIPinUsesUpToNextMinor` |
| `UIAccessibility.post` on Copy (component #8, F-008) | `DocumentViewTests.testCopyPostsAccessibilityAnnouncement` |
| Toast `.accessibilityHidden(true)` (component #8) | `ToastModifierTests.testToastTextIsAccessibilityHidden` |

---

## Notes for the build agent

- Tests live in two Xcode targets: `Markus_v3Tests` (Swift Testing) and `Markus_v3UITests` (XCUITest).
- The reference test specs in `features/walking-skeleton-1/tests/` mirror the Xcode test files 1:1; they exist as a human-readable companion to verify.md. When you build a task, port the corresponding spec test into the matching Xcode target file, then run.
- Per CLAUDE.md's build-flow note: a test that passes BEFORE its task has been implemented is a signal that the test or its tagging is wrong. Fail-on-import is the expected initial state.
- The E2E `WalkingSkeletonFlowUITests` requires a sample `.md` file bundled with the UI-test target — drop a small `sample.md` into the UI-test resources at T-001 time so later tests can open it.
