Corrective feature — reverts the custom new-file creation flow introduced in `resume-and-create-2` and restores the system `UIDocumentBrowserViewController` create affordance.

## Feature declaration

[`features/restore-system-create-7/declaration.md`](features/restore-system-create-7/declaration.md)

Remove Markus's custom new-file creation flow and let the system's `UIDocumentBrowserViewController` create affordance handle new files the way iOS does it everywhere else: "+" tap creates an empty file in the **currently-browsed folder**, with the system's **inline rename UI** in the browser, before opening the file in the editor. Eliminates `CreateDocumentHandler`, `NameProbe`, `CreateTargetResolver`, `LocalDocumentsFallback`, and the deferred-write behavior. Reduces surface area and restores Files-app intuition.

## Requirements

[`features/restore-system-create-7/requirements.md`](features/restore-system-create-7/requirements.md)

Six user stories, all behavioral. Highlights:

- **US-1 / AC-1.\*** — new files land in the folder the user is currently browsing, not in any app-resolved directory.
- **US-2 / AC-2.\*** — naming uses the system's inline rename UI; no custom Markus naming sheet.
- **US-3 / AC-3.\*** — new files exist on disk from creation (no deferred-write state).
- **US-4 / AC-4.\*** — content-based initial mode: empty → raw + keyboard, large → raw, otherwise → rendered.
- **US-5 / AC-5.\*** — resume-on-launch, last-opened tracking (C1/C3), and back-to-browser (C8) unchanged.
- **US-6 / AC-6.\*** — test suite reflects the removal.

## Design

[`features/restore-system-create-7/design.md`](features/restore-system-create-7/design.md)

Three architectural moves:

1. **Remove the directory-choosing / naming / deferred-write logic** layered on top of the create delegate (C4–C7 + the deferred-write behavior).
2. **Reduce the system create delegate to a template-only handoff** (DC-1) — `documentBrowser(_:didRequestDocumentCreationWithHandler:)` provides an empty `.md` template URL in `NSTemporaryDirectory()` and immediately completes the system handler. The system then runs its default create + inline-rename flow, copying the template into the user-browsed folder.
3. **Add one behavioral seam** (DC-4) — content-based initial-mode selection inside `DocumentView`'s existing `.onAppear` decision. No new component is introduced.

The components kept unchanged are C0 (BrowserHost), C1 (LastFileStore), C2 (LaunchResumeBranch), C3 (DocumentOpenObserver), C8 (BackToBrowser).

## Adversarial review

[`features/restore-system-create-7/adversarial-review.md`](features/restore-system-create-7/adversarial-review.md)

One finding, **F-001 (HIGH, integrity/feasibility)** — *"Don't override the create delegate" may disable the "+" affordance entirely.* The original framing of AC-1.3 / DC-1 (delegate fully un-implemented) would have actually disabled the system "+" affordance — `UIDocumentBrowserViewController` requires the delegate to be implemented and to supply a template URL. Both requirements.md (AC-1.3) and design.md (DC-1) were reframed to "delegate is template-only" — retaining the framework-required method, supplying a template in `NSTemporaryDirectory()`, and invoking the system completion handler with a success import mode. **Status: resolved.** No acknowledged or deferred findings.

## Build summary

DAG: 6 tasks across 3 waves.

| Wave | Task | SHA | What landed |
|------|------|-----|-------------|
| 1 | T-001 | `f214bae` | Delete C5 `NameProbe` (source + unit tests) |
| 1 | T-002 | `31c0867` | Delete C6 `CreateTargetResolver` (source + unit tests, incl. writability probe) |
| 1 | T-003 | `a877a15` | Delete C7 `LocalDocumentsFallback` (source + unit tests) |
| 2 | T-004 | `b4a71dd` | Reduce C4 to template-only delegate on `BrowserHostController`; strip deferred-write from `BrowserHostController` and `MarkdownDocumentSaveBridge`; remove `SceneDelegate.createHandler` |
| 2 | T-005 | `b4a71dd` | Content-based initial-mode rule in `DocumentView.onAppear` (empty → raw + keyboard); strip create-path `initialMode` threading |
| 3 | T-006 | `26155ac` | Final sweep: prune obsolete `ResumeAndCreateUITests` Story B; mirror `SystemCreateUITests`; rewrite `ExternalChangeUITests.testNormalCreateTypeSaveProducesNoConflictSurfaces`; verify clean grep |

**Build deviations** are recorded in [`features/restore-system-create-7/build-deviations.md`](features/restore-system-create-7/build-deviations.md): D-1 (LaunchResumeBranch inlining), D-2 (spec-test API adaptation incl. adding static `DocumentView.initialMode` helpers + `LastFileStore.hasRecord`), D-3 (SystemCreateUITests XCTSkip rationale), D-4 (Create/ dir auto-cleanup), D-5 (residual-symbol-grep wave timing), D-6 (Story B wholesale removal), D-7 (testNormalCreateTypeSaveProducesNoConflictSurfaces rewrite).

**Final test status:**

- **Unit suite (Markus_v3Tests):** 243/243 pass.
- **restore-system-create-7 spec mirrors:** 22/22 pass (CreateLocation, InitialMode, ResumeRegression, RemovedComponents — all under Swift Testing).
- **UI suite (Markus_v3UITests):** SystemCreateUITests = 2 live pass + 5 XCTSkip with documented rationale (D-3); rewritten BR-3.5 passes; remaining ExternalChangeUITests pass in isolation. The 3 background-scenephase tests (`testBackgroundingDoesNotAutoResolveSheet`, `testBufferPreservedAcrossBackgroundWithPendingSheet`, `testDeleteThenReappearWithinWindowIsMoveNoBanner`) flake in full-suite runs on this host due to XCUITest `DebuggerLLDB.DebuggerVersionStore` / `Application failed preflight checks` infrastructure errors; they pass when run isolated. Unrelated to this feature.

## Risk

- **System "+" affordance label on iOS 26.** The system browser's "+" affordance is not exposed under any of the candidate accessibility labels XCUITest can match (`Create Document`, `New Document`, `Create`). End-to-end UI coverage of the create flow is therefore unit-level only (`RestoreSystemCreate7_CreateLocationTests`). A future device-level smoke test should manually verify the "+" → system rename → editor flow.
- **Pre-existing UI-test flake.** The host hits intermittent XCUITest infrastructure errors that affect the entire UI suite, not just this feature. Worth investigating separately (likely needs a fresh Xcode/CoreSimulator state). All tests pass in isolation.
- **Migration of `Untitled n.md` files.** Files left in user directories by the old custom create flow stay where they are (per declaration Out of scope, EC-8). Users own those files now.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
