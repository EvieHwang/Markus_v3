# DAG — restore-system-create-7

Dependency graph of build tasks for the restore-system-create-7 removal feature. Six tasks across three waves. Tasks within a wave can run in parallel; tasks in a later wave depend on all earlier waves landing first.

Sources: `requirements.md` (AC-*, EC-*), `design.md` (DC-*), `verify.md` (test-to-task mapping), `tests/` (spec tests).

## Conventions

- **Inputs**: spec files and source files the task reads.
- **Outputs**: source files modified or deleted; behavior delivered (AC-/DC- references).
- **Acceptance**: objectively checkable condition for marking the task `complete` in `state.md`. The default is "the tests tagged to this task pass under `xcodebuild test -scheme Markus_v3 -destination 'platform=iOS Simulator,name=iPhone 17'`." Task-specific extras are listed where they apply.

## Wave 1 — independent component deletions

The three sibling helper components (C5/C6/C7) live in their own files and have their own unit-test files. Each can be deleted in isolation — they have no inter-dependencies, and the load-bearing call site (the body of `CreateDocumentHandler`) is rewritten in Wave 2, so deletions here cause a temporary compile break inside `CreateDocumentHandler.swift` only. That breakage is healed when Wave 2 (T-004) replaces `CreateDocumentHandler`'s invocation with the template-only delegate body. Pair each source deletion with its matching unit-test file deletion in the same task to keep the per-task delta self-contained, per design.md "Build-time considerations."

### T-001 — Delete C5 NameProbe

- **Description:** Remove `NameProbe` (the `Untitled[ n].md` collision-avoidance helper) and its unit tests.
- **Inputs:** `design.md` "Components being removed → C5"; `requirements.md` AC-5.4, AC-6.1.
- **Outputs:**
  - Deleted: `Markus_v3/Create/NameProbe.swift`, `Markus_v3Tests/NameProbeTests.swift`.
  - Behavior delivered: AC-5.4 (partial — `NameProbe` symbol gone), AC-6.1 (partial — `NameProbeTests` gone).
- **Dependencies:** none.
- **Wave:** 1.
- **Acceptance:** `RemovedComponentsTests.nameProbeSourceAbsent` passes (source file absent at known path; symbol grep clean for `NameProbe` in `Markus_v3/`).

### T-002 — Delete C6 CreateTargetResolver

- **Description:** Remove `CreateTargetResolver` (last-directory-vs-fallback chooser + writability probe) and its unit tests.
- **Inputs:** `design.md` "Components being removed → C6"; `requirements.md` AC-5.4, AC-6.1.
- **Outputs:**
  - Deleted: `Markus_v3/Create/CreateTargetResolver.swift`, `Markus_v3Tests/CreateTargetResolverTests.swift`.
  - Behavior delivered: AC-5.4 (partial), AC-6.1 (partial), EC-1 (read-only folder behavior follows from absence of probe code).
- **Dependencies:** none.
- **Wave:** 1.
- **Acceptance:** `RemovedComponentsTests.createTargetResolverSourceAbsent` passes; no `CreateTargetResolver` references remain under `Markus_v3/` (verified by source grep).

### T-003 — Delete C7 LocalDocumentsFallback

- **Description:** Remove `LocalDocumentsFallback` (app-container Documents fallback target) and its unit tests.
- **Inputs:** `design.md` "Components being removed → C7"; `requirements.md` AC-5.4, AC-6.1.
- **Outputs:**
  - Deleted: `Markus_v3/Create/LocalDocumentsFallback.swift`, `Markus_v3Tests/LocalDocumentsFallbackTests.swift`.
  - Behavior delivered: AC-5.4 (partial), AC-6.1 (partial).
- **Dependencies:** none.
- **Wave:** 1.
- **Acceptance:** `RemovedComponentsTests.localDocumentsFallbackSourceAbsent` passes.

## Wave 2 — load-bearing rewrites

Wave 2 depends on Wave 1: T-004 rewrites the delegate body that previously called into C5/C6/C7, so it needs those types' deletions visible to assert "no residual call site." T-004 and T-005 touch different files and can run in parallel within the wave; both must land before Wave 3's final sweep.

### T-004 — Reduce C4 to template-only delegate; strip deferred-write

- **Description:** Replace `CreateDocumentHandler`'s directory/naming/deferred-write logic with a minimal template-only implementation of `documentBrowser(_:didRequestDocumentCreationWithHandler:)` living directly on `BrowserHostController`. The new body creates an empty `.md` template file in `NSTemporaryDirectory()`, invokes the system completion handler with `(templateURL, .copy)`, and returns. Removes `CreateDocumentHandler.swift`, the `SceneDelegate.createHandler` property and its scene-connect construction, the deferred-write branches in `BrowserHostController` (the "for deferred-write create, becoming real on disk for the first time…" branch), and any deferred-write paths in `MarkdownDocumentSaveBridge`. Deletes the corresponding deferred-write tests in `Markus_v3Tests/MarkdownDocumentSaveBridgeTests.swift`.
- **Inputs:** `design.md` DC-1, DC-2, DC-3 and "Components being removed → C4 / Deferred-write behavior"; `requirements.md` AC-1.1, AC-1.2, AC-1.3, AC-2.*, AC-3.1, AC-3.2, AC-3.3, AC-5.4, EC-3.
- **Outputs:**
  - Deleted: `Markus_v3/Create/CreateDocumentHandler.swift`.
  - Modified: `Markus_v3/Host/BrowserHostController.swift` (template-only delegate body; deferred-write branch removed), `Markus_v3/Host/SceneDelegate.swift` (`createHandler` property and construction removed), `Markus_v3/Host/MarkdownDocumentSaveBridge.swift` (deferred-write path removed), `Markus_v3Tests/MarkdownDocumentSaveBridgeTests.swift` (deferred-write assertions removed).
  - Behavior delivered: DC-1 (template-only), DC-2 (no deferred persistence), DC-3 (no abandoned-create observer), AC-1.1, AC-1.2, AC-1.3, AC-2.1, AC-2.2, AC-2.3, AC-2.4, AC-3.1, AC-3.2, AC-3.3.
- **Dependencies:** T-001, T-002, T-003 (those deletions must land first so the rewritten delegate body has no symbols to reference).
- **Wave:** 2.
- **Acceptance:** `CreateLocationTests.templateLandsInTempDir`, `templateIsEmptyOnDisk`, `templateCompletesWithSuccessMode`, `templateURLIgnoresLastOpenedDirectory`, `RemovedComponentsTests.createDocumentHandlerSourceAbsent`, `RemovedComponentsTests.sceneDelegateHasNoCreateHandler`, and `RemovedComponentsTests.noDeferredWriteState` all pass.

### T-005 — Content-based initial mode in DocumentView

- **Description:** Widen the existing `.onAppear` initial-mode decision in `Markus_v3/Views/DocumentView.swift` to also return `.raw` (with the raw editor's text input becoming first responder and the software keyboard presented) when document content is empty. Large-content `.raw` selection and otherwise-`.rendered` selection are preserved. Removes any create-path-threaded `initialMode` value supplied from `BrowserHostController` (the parameter itself may remain on `DocumentView.init` for unrelated callers per the non-normative design note, but no call site passes a non-nil value driven by "this came from a create").
- **Inputs:** `design.md` DC-4 and "Seam relationships → DC-4"; `requirements.md` AC-4.1, AC-4.2, AC-4.3, EC-6.
- **Outputs:**
  - Modified: `Markus_v3/Views/DocumentView.swift` (initial-mode rule widened), `Markus_v3/Host/BrowserHostController.swift` (no `initialMode` value supplied for new files).
  - Behavior delivered: DC-4, AC-4.1, AC-4.2, AC-4.3, EC-6, plus the regression guards in AC-5.1/AC-5.2/AC-5.3 confirming the open path still funnels system-created files through C3 (DC-5, DC-6, DC-7).
- **Dependencies:** T-001, T-002, T-003 (so the content-rule edit lands on top of a tree with no `Create/` residue); independent of T-004's delegate rewrite at the file level, but Wave 3's full-suite gate requires both.
- **Wave:** 2.
- **Acceptance:** `InitialModeTests.emptyContentSelectsRaw`, `zeroBytePreexistingSelectsRaw`, `midSizeSelectsRendered`, `decisionIgnoresProvenance`, `noCreatePathThreadsInitialMode`, plus `ResumeRegressionTests.validBookmarkResumes`, `unresolvableBookmarkFallsBack`, `systemCreatedFileFlowsThroughC3`, `c3NoSpecialCaseForCreates` all pass.

## Wave 3 — final sweep

### T-006 — Final sweep: directory cleanup, residual-reference check, full suite green

- **Description:** Confirm `Markus_v3/Create/` is empty and remove the directory along with its Xcode group reference. Mirror the spec UI tests into `Markus_v3UITests/SystemCreateUITests.swift` and remove the now-obsolete create-flow assertions from `Markus_v3UITests/ResumeAndCreateUITests.swift` (the deferred-write / custom-handler routing assertions; resume-only assertions stay). Run a project-wide grep for the removed symbol names (`CreateDocumentHandler`, `NameProbe`, `CreateTargetResolver`, `LocalDocumentsFallback`, `createHandler`, deferred-write vocabulary) and confirm zero hits in `Markus_v3/` source. Run the full Xcode test suite and confirm green.
- **Inputs:** `design.md` "Build-time considerations"; `requirements.md` AC-5.4, AC-6.1, AC-6.2, AC-6.3; `verify.md` test-to-task mapping.
- **Outputs:**
  - Deleted: `Markus_v3/Create/` directory and Xcode group reference; create-flow assertions inside `Markus_v3UITests/ResumeAndCreateUITests.swift`.
  - Added: `Markus_v3UITests/SystemCreateUITests.swift` (mirrored from spec tests).
  - Behavior delivered: AC-5.4 (no residual references), AC-6.1, AC-6.2, AC-6.3 (full suite passes).
- **Dependencies:** T-001, T-002, T-003, T-004, T-005.
- **Wave:** 3.
- **Acceptance:** `RemovedComponentsTests.removedTestFilesAbsent` and `RemovedComponentsTests.noResidualSymbolReferences` pass; `SystemCreateUITests.test_plusTap_presentsSystemRenameUIInBrowsedFolder`, `test_confirmRename_persistsFileAndOpensEditor`, `test_acceptSystemDefaultName_opensEditor`, `test_newFileOpensInRawModeWithKeyboard`, `test_existingNonEmptyFileOpensRendered`, `test_backFromSystemCreatedFile_returnsToBrowser`, `test_nextLaunchResumesIntoSystemCreatedFile` pass; `xcodebuild test -scheme Markus_v3 -destination 'platform=iOS Simulator,name=iPhone 17'` exits 0.

## Wave summary

| Wave | Tasks | Parallelism |
|------|-------|-------------|
| 1 | T-001, T-002, T-003 | full — three independent file deletions |
| 2 | T-004, T-005 | full — disjoint files (Host/ vs. Views/), each waiting only on Wave 1 |
| 3 | T-006 | n/a — single closing task |

## Task → behavior trace (at-a-glance)

| Task | Primary AC/DC | Primary tests |
|------|---------------|---------------|
| T-001 | AC-5.4, AC-6.1 | `RemovedComponentsTests.nameProbeSourceAbsent` |
| T-002 | AC-5.4, AC-6.1, EC-1 | `RemovedComponentsTests.createTargetResolverSourceAbsent` |
| T-003 | AC-5.4, AC-6.1 | `RemovedComponentsTests.localDocumentsFallbackSourceAbsent` |
| T-004 | DC-1, DC-2, DC-3, AC-1.*, AC-2.*, AC-3.* | `CreateLocationTests.*`, `RemovedComponentsTests.createDocumentHandlerSourceAbsent` / `sceneDelegateHasNoCreateHandler` / `noDeferredWriteState` |
| T-005 | DC-4, AC-4.*, DC-5/6/7 regression | `InitialModeTests.*`, `ResumeRegressionTests.*` |
| T-006 | AC-5.4, AC-6.1, AC-6.2, AC-6.3 | `RemovedComponentsTests.removedTestFilesAbsent` / `noResidualSymbolReferences`, `SystemCreateUITests.*` |
