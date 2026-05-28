# Verify — restore-system-create-7

Coverage map from `requirements.md` (AC-*, EC-*) and `design.md` (DC-*) to the spec tests under `features/restore-system-create-7/tests/`.

Task ID column is a placeholder; `/dag` (Stage 5) populates it by tagging each test with the DAG task that must make it pass.

## Test files

| File | Framework | Concern |
|------|-----------|---------|
| `CreateLocationTests.swift` | Swift Testing | DC-1 template-only handoff: template URL lives in temp dir, template file is empty, completes with success import mode, ignores last-opened directory. |
| `InitialModeTests.swift` | Swift Testing | DC-4 content-based initial mode: empty → raw + keyboard, large → raw, otherwise → rendered; pure function of content (provenance-independent). |
| `RemovedComponentsTests.swift` | Swift Testing | AC-5.4 / DC-2 / DC-3: removed source files absent, removed symbols not referenced, no `SceneDelegate.createHandler`, no deferred-write state. Includes a compile-fail checklist (technique 1) and filesystem probes (technique 2). |
| `ResumeRegressionTests.swift` | Swift Testing | DC-5 / DC-6 / DC-7: resume-on-launch, last-opened tracking funnels system-created files through C3 unchanged, no special-case branch. |
| `SystemCreateUITests.swift` | XCUITest | End-to-end: "+" → system rename UI → file persists → editor opens; empty file → raw mode + keyboard; non-empty regression; back-to-browser; next-launch resume. |

## Coverage matrix

### Acceptance criteria → tests

| AC | Test(s) | Task ID |
|----|---------|---------|
| AC-1.1 (new file in browsed folder) | `SystemCreateUITests.test_plusTap_presentsSystemRenameUIInBrowsedFolder`, `SystemCreateUITests.test_confirmRename_persistsFileAndOpensEditor` | _TBD_ |
| AC-1.2 (parent dir not from last-opened) | `CreateLocationTests.templateURLIgnoresLastOpenedDirectory` | _TBD_ |
| AC-1.3 (template-only delegate, no custom resolver/probe) | `CreateLocationTests.templateLandsInTempDir`, `CreateLocationTests.templateIsEmptyOnDisk`, `CreateLocationTests.templateCompletesWithSuccessMode`, `RemovedComponentsTests.noResidualSymbolReferences` | _TBD_ |
| AC-2.1 (system inline rename UI focused) | `SystemCreateUITests.test_plusTap_presentsSystemRenameUIInBrowsedFolder` | _TBD_ |
| AC-2.2 (confirm → file persists, editor opens) | `SystemCreateUITests.test_confirmRename_persistsFileAndOpensEditor` | _TBD_ |
| AC-2.3 (accept system default name) | `SystemCreateUITests.test_acceptSystemDefaultName_opensEditor` | _TBD_ |
| AC-2.4 (no custom Markus naming sheet) | `SystemCreateUITests.test_plusTap_presentsSystemRenameUIInBrowsedFolder` (asserts `MarkusCreateSheet` / `MarkusNameField` absent) | _TBD_ |
| AC-3.1 (file on disk post-create) | `CreateLocationTests.templateIsEmptyOnDisk`, `SystemCreateUITests.test_confirmRename_persistsFileAndOpensEditor` | _TBD_ |
| AC-3.2 (no deferred-write code path) | `RemovedComponentsTests.noDeferredWriteState` | _TBD_ |
| AC-3.3 (no Markus cleanup on rename cancel) | `RemovedComponentsTests.noDeferredWriteState` (no abandon-handler state); EC-3 below | _TBD_ |
| AC-4.1 (empty → raw + keyboard) | `InitialModeTests.emptyContentSelectsRaw`, `InitialModeTests.zeroBytePreexistingSelectsRaw`, `SystemCreateUITests.test_newFileOpensInRawModeWithKeyboard` | _TBD_ |
| AC-4.2 (decision pure function of content) | `InitialModeTests.decisionIgnoresProvenance`, `InitialModeTests.noCreatePathThreadsInitialMode` | _TBD_ |
| AC-4.3 (non-empty → rendered) | `InitialModeTests.midSizeSelectsRendered`, `SystemCreateUITests.test_existingNonEmptyFileOpensRendered` | _TBD_ |
| AC-5.1 (resume-on-launch unchanged) | `ResumeRegressionTests.validBookmarkResumes`, `ResumeRegressionTests.unresolvableBookmarkFallsBack`, `SystemCreateUITests.test_nextLaunchResumesIntoSystemCreatedFile` | _TBD_ |
| AC-5.2 (system-created file recorded by C3) | `ResumeRegressionTests.systemCreatedFileFlowsThroughC3`, `SystemCreateUITests.test_nextLaunchResumesIntoSystemCreatedFile` | _TBD_ |
| AC-5.3 (back-to-browser / edge-swipe) | `SystemCreateUITests.test_backFromSystemCreatedFile_returnsToBrowser` | _TBD_ |
| AC-5.4 (removed types not referenced) | `RemovedComponentsTests.createDocumentHandlerSourceAbsent`, `RemovedComponentsTests.nameProbeSourceAbsent`, `RemovedComponentsTests.createTargetResolverSourceAbsent`, `RemovedComponentsTests.localDocumentsFallbackSourceAbsent`, `RemovedComponentsTests.removedTestFilesAbsent`, `RemovedComponentsTests.noResidualSymbolReferences`, `RemovedComponentsTests.sceneDelegateHasNoCreateHandler` | _TBD_ |
| AC-6.1 (old unit tests removed) | `RemovedComponentsTests.removedTestFilesAbsent` | _TBD_ |
| AC-6.2 (UI tests rewritten or removed) | Replaced by `SystemCreateUITests.*` (observable outcome); old `ResumeAndCreateUITests` create-flow paths covered by `RemovedComponentsTests.noResidualSymbolReferences` for code drift. | _TBD_ |
| AC-6.3 (full suite passes) | Suite-wide; satisfied when every test above passes via `xcodebuild test`. | _TBD_ |

### Edge cases → tests

| EC | Test(s) | Task ID |
|----|---------|---------|
| EC-1 (read-only folder) | Not directly tested in spec suite — by DC-1 / `CreateLocationTests.*` Markus contributes no probe/fallback, so behavior is whatever the system produces. Covered by absence of writability-probe code (`RemovedComponentsTests.noResidualSymbolReferences`). | _TBD_ |
| EC-2 (name collision) | Covered by absence of `NameProbe`-style logic (`RemovedComponentsTests.noResidualSymbolReferences`); system collision behavior is framework-owned. | _TBD_ |
| EC-3 (user cancels rename) | Covered by `RemovedComponentsTests.noDeferredWriteState` (no Markus-owned abandon-handler exists). | _TBD_ |
| EC-4 (last-opened in same folder) | `ResumeRegressionTests.c3NoSpecialCaseForCreates` | _TBD_ |
| EC-5 (create after resume back-out) | `SystemCreateUITests.test_backFromSystemCreatedFile_returnsToBrowser` + `test_plusTap_presentsSystemRenameUIInBrowsedFolder` (browser shows whatever system default folder; Markus does not force). | _TBD_ |
| EC-6 (pre-existing zero-byte file) | `InitialModeTests.zeroBytePreexistingSelectsRaw` | _TBD_ |
| EC-7 (deferred-write tests gone) | `RemovedComponentsTests.removedTestFilesAbsent`, `RemovedComponentsTests.noDeferredWriteState` | _TBD_ |
| EC-8 (legacy Untitled n.md files left alone) | Not tested — declaration explicitly puts migration out of scope, and the absence of any migration code is covered by `RemovedComponentsTests.noResidualSymbolReferences` (no `NameProbe` / `Untitled` references). | _TBD_ |

### Design contracts → tests

| DC | Test(s) | Task ID |
|----|---------|---------|
| DC-1 (template-only system create delegate) | `CreateLocationTests.templateLandsInTempDir`, `templateIsEmptyOnDisk`, `templateCompletesWithSuccessMode`, `templateURLIgnoresLastOpenedDirectory`; `SystemCreateUITests.test_plusTap_presentsSystemRenameUIInBrowsedFolder` | _TBD_ |
| DC-2 (no deferred on-disk persistence) | `RemovedComponentsTests.noDeferredWriteState`, `CreateLocationTests.templateIsEmptyOnDisk` (file is real on disk pre-handoff) | _TBD_ |
| DC-3 (no abandoned-create observer) | `RemovedComponentsTests.noDeferredWriteState`, `RemovedComponentsTests.noResidualSymbolReferences` | _TBD_ |
| DC-4 (content-based initial mode) | All of `InitialModeTests.*` | _TBD_ |
| DC-5 (resume-on-launch preserved) | `ResumeRegressionTests.validBookmarkResumes`, `ResumeRegressionTests.unresolvableBookmarkFallsBack` | _TBD_ |
| DC-6 (system-created files funnel through C3) | `ResumeRegressionTests.systemCreatedFileFlowsThroughC3`, `ResumeRegressionTests.c3NoSpecialCaseForCreates`, `SystemCreateUITests.test_nextLaunchResumesIntoSystemCreatedFile` | _TBD_ |
| DC-7 (back navigation preserved) | `SystemCreateUITests.test_backFromSystemCreatedFile_returnsToBrowser` | _TBD_ |

## Notes on technique

- **Removed-component coverage** uses two complementary techniques, documented in `RemovedComponentsTests.swift`:
  1. **Compile-fail checklist** — commented-out symbol references that would re-break compilation if the removed types were reintroduced. This is the only way to assert "type does not exist" from inside a module that imports the project; uncommenting any line in the checklist is itself the regression signal.
  2. **Filesystem / source-tree probes** — Swift Testing checks that the removed source files are absent at known paths, plus a Swift-source grep for the removed symbol names and the deferred-write state vocabulary. This catches symbols that come back at *new* paths, which technique 1 cannot.
- **Behavioral framing** — every test asserts an observable: a URL parent, a file's existence on disk, a mode enum value, a UI element's presence. No test asserts call signatures, constructor argument lists, or private attributes, per the Stage 4 brief.
- **Reference-only** — these files are not bundled into the Xcode test target. The build implementer mirrors them into `Markus_v3Tests/` and `Markus_v3UITests/` when picking up each DAG task, adjusting accessibility identifiers and helper imports to match the live host.
- **Task IDs deferred** — populated by Stage 5 (`/dag`) once the build dependency graph exists.

## Untestable requirements

None. All AC-* and DC-* lines are testable as written after the F-001 reframing.
