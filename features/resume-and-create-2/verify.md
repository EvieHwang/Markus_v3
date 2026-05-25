# Verify: resume-and-create-2

Human-readable coverage summary mapping each behavioral requirement (BR-*) and design seam (DC-* / component) to the test(s) that verify it.

**Note:** Task → test mapping (DAG task IDs) is added in the NEXT stage after the DAG is committed. This file currently maps requirement/seam → test name only. Tests intentionally fail (missing-symbol / ImportError, or `XCTSkip`) until each task is implemented.

Test files:
- `tests/unit/ResumeAndCreateTests.swift` — Swift Testing (`@Test`/`#expect`/`#require`), logic-level seams.
- `tests/ui/ResumeAndCreateUITests.swift` — XCUITest, scene-level / end-to-end seams.

---

## Category 1 — Behavioral tests (from requirements.md)

### Story A — Resume on launch

| BR | Requirement summary | Test file | Test name |
|----|---------------------|-----------|-----------|
| BR-1 | Persist last-opened file (durable across termination) | `ResumeAndCreateTests.swift` | `LastFileStoreTests` → `recordAndResolve`, `referenceIsDurable` |
| BR-2 | Resume opens the file directly into the rendered view | `ResumeAndCreateUITests.swift` | `testResumeLaunchOpensRenderedView`, `testResumeLaunchDoesNotLandOnBrowser` |
| BR-3 | No document-browser flash on resume | `ResumeAndCreateUITests.swift` | `testNoBrowserFlashOnResume` (`XCTSkip` — device-only timing; design build-escalation trigger) |
| BR-4 | First-ever launch falls through to the browser | `ResumeAndCreateUITests.swift` | `testFirstLaunchShowsDocumentBrowser` |
| BR-5 | Unreachable last file falls through silently (no error UI) | `ResumeAndCreateUITests.swift` → `testStaleReferenceFallsThroughSilently`; `ResumeAndCreateTests.swift` → `LastFileStoreTests` → `deletedFileResolvesNil` |
| BR-6 | Resumed file behaves identically to a browser-opened file | `ResumeAndCreateUITests.swift` | `testResumedFileIsEditable` |

### Story B — New file creation

| BR | Requirement summary | Test file | Test name |
|----|---------------------|-----------|-----------|
| BR-7 | Create-Document produces an `.md` file | `ResumeAndCreateTests.swift` → `NameProbeTests` → `probedNameHasMdExtension`; `ResumeAndCreateUITests.swift` → `testCreateDocumentOpensUntitledMd` |
| BR-8 | Default name `Untitled.md` | `ResumeAndCreateTests.swift` → `NameProbeTests` → `emptyDirectoryYieldsUntitled`; `ResumeAndCreateUITests.swift` → `testCreateDocumentOpensUntitledMd` |
| BR-9 | Deterministic collision auto-increment (gap-filling, no overwrite) | `ResumeAndCreateTests.swift` | `NameProbeTests` → `firstCollisionYieldsTwo`, `secondCollisionYieldsThree`, `gapIsFilled`, `existingFilesUntouched`, `unrelatedFilesIgnored` |
| BR-10 | Target directory is the last-opened file's directory (when writable) | `ResumeAndCreateTests.swift` | `CreateTargetResolverTests` → `writableLastDirectoryChosen` |
| BR-11 | Fallback to local Documents | `ResumeAndCreateTests.swift` | `CreateTargetResolverTests` → `noLastReferenceFallsBack`, `unreachableLastDirectoryFallsBack`; `LocalDocumentsFallbackTests` → `vendsDocumentsDirectory`, `directoryExistsAndWritable` |
| BR-12 | New file opens in the raw editor with the keyboard active | `ResumeAndCreateUITests.swift` | `testNewFileOpensInRawEditor`, `testNewFileEditorHasKeyboardFocus` |
| BR-13 | Empty file is not persisted (no trace, name not consumed) | `ResumeAndCreateUITests.swift` | `testUntypedNewFileDoesNotConsumeName` |
| BR-14 | File persists once content is entered | `ResumeAndCreateUITests.swift` | `testTypedNewFilePersists` (`XCTSkip` — needs on-disk container inspection) |
| BR-15 | A persisted new file becomes the last-opened file | `ResumeAndCreateUITests.swift` → `testTypedNewFileBecomesLastOpened` (`XCTSkip`); `ResumeAndCreateTests.swift` → `LastFileStoreTests` → `recordAndResolve` (logic-level: a persisted file recorded resolves back) |

### Story C — Back navigation

| BR | Requirement summary | Test file | Test name |
|----|---------------------|-----------|-----------|
| BR-16 | Back chevron returns to the document browser (both modes) | `ResumeAndCreateUITests.swift` | `testBackChevronFromRenderedReturnsToBrowser`, `testBackChevronFromRawEditorReturnsToBrowser` |
| BR-17 | Edge-swipe-back returns to the document browser | `ResumeAndCreateUITests.swift` | `testEdgeSwipeBackReturnsToBrowser` |
| BR-18 | Back navigation does not clear the last-opened reference | `ResumeAndCreateUITests.swift` → `testBackThenRelaunchStillResumes`; `ResumeAndCreateTests.swift` → `LastFileStoreTests` → `readsAreNonDestructive` |

### Edge cases and failure modes

| BR | Requirement summary | Test file | Test name |
|----|---------------------|-----------|-----------|
| BR-19 | Stale/invalid bookmark → browser, no crash | `ResumeAndCreateTests.swift` → `LastFileStoreTests` → `corruptReferenceResolvesNil`, `deletedFileResolvesNil`; `ResumeAndCreateUITests.swift` → `testStaleReferenceFallsThroughSilently` |
| BR-20 | Failed resolution does not require clearing the reference (RETAIN-on-failure) | `ResumeAndCreateTests.swift` | `LastFileStoreTests` → `retainOnFailure` |
| BR-21 | Non-writable last directory at create → fall back to local Documents | `ResumeAndCreateTests.swift` | `CreateTargetResolverTests` → `readOnlyLastDirectoryFallsBack` |
| BR-22 | Collision probing happens in the resolved target directory | `ResumeAndCreateTests.swift` | `NameProbeTests` → `anchoredToSuppliedDirectory`; `CreateTargetResolverTests` → `nameProbeAnchoredToResolvedDirectory` |
| BR-23 | First-ever launch then create → file in local Documents, raw editor | `ResumeAndCreateUITests.swift` → `testFirstLaunchThenCreate`; `ResumeAndCreateTests.swift` → `CreateTargetResolverTests` → `noLastReferenceFallsBack` |
| BR-24 | Empty-file-not-persisted survives interruption | `ResumeAndCreateUITests.swift` | `testUntypedNewFileDoesNotConsumeName` |
| BR-25 | Back from an untyped new file leaves no file | `ResumeAndCreateUITests.swift` | `testBackFromUntypedNewFileLeavesNoFile`, `testUntypedNewFileDoesNotConsumeName` |
| BR-26 | Resolved name remains collision-free at write time (overwrites nothing) | `ResumeAndCreateTests.swift` | `NameProbeTests` → `existingFilesUntouched`, `gapIsFilled` |

---

## Category 2 — Integration / seam tests (from design seams)

### C0 — BrowserHost / C4 creation-delegate path controls materialization + target directory

| Seam behavior (DC) | Test file | Test name |
|--------------------|-----------|-----------|
| C4 ↔ creation-delegate: new file opens in raw editor, keyboard up (DC-8) | `ResumeAndCreateUITests.swift` | `testNewFileOpensInRawEditor`, `testNewFileEditorHasKeyboardFocus` |
| C4 ↔ creation-delegate: write withheld until first keystroke; abandon leaves no trace, name not consumed (DC-9) | `ResumeAndCreateUITests.swift` | `testUntypedNewFileDoesNotConsumeName`, `testBackFromUntypedNewFileLeavesNoFile` |
| C4 → C6: target directory is the app-computed directory, not browser-default (DC-12) | `ResumeAndCreateTests.swift` | `CreateTargetResolverTests` → `writableLastDirectoryChosen`, `noLastReferenceFallsBack` |

### C2 — LaunchResumeBranch decides in the scene-activation path

| Seam behavior (DC) | Test file | Test name |
|--------------------|-----------|-----------|
| Resolvable reference → editor is first content, browser not the landing screen (DC-2) | `ResumeAndCreateUITests.swift` | `testResumeLaunchOpensRenderedView`, `testResumeLaunchDoesNotLandOnBrowser` |
| Browser never the visible top screen on resume (DC-3) | `ResumeAndCreateUITests.swift` | `testNoBrowserFlashOnResume` (`XCTSkip` — device verification; build-escalation trigger) |
| No / failed reference → browser is the natural landing, silently (DC-4) | `ResumeAndCreateUITests.swift` → `testFirstLaunchShowsDocumentBrowser`, `testStaleReferenceFallsThroughSilently` |

### C6 — CreateTargetResolver: writability probe + name-probe anchored to resolved directory

| Seam behavior (DC) | Test file | Test name |
|--------------------|-----------|-----------|
| Last directory only when a pre-write probe succeeds, else local Documents (DC-12) | `ResumeAndCreateTests.swift` | `CreateTargetResolverTests` → `writableLastDirectoryChosen`, `unreachableLastDirectoryFallsBack`, `readOnlyLastDirectoryFallsBack`, `noLastReferenceFallsBack` |
| Probe is side-effect-free on success (no stray file) (DC-12) | `ResumeAndCreateTests.swift` | `CreateTargetResolverTests` → `probeLeavesNoResidue` |
| Collision probe anchored to the resolved directory only (DC-11) | `ResumeAndCreateTests.swift` | `NameProbeTests` → `anchoredToSuppliedDirectory`; `CreateTargetResolverTests` → `nameProbeAnchoredToResolvedDirectory` |

### C1 — LastFileStore: durable reference, RETAIN-on-failure

| Seam behavior (DC) | Test file | Test name |
|--------------------|-----------|-----------|
| Exactly one durable reference; opening a new file replaces it (DC-1) | `ResumeAndCreateTests.swift` | `LastFileStoreTests` → `recordAndResolve`, `referenceIsDurable`, `recordReplaces` |
| Failed resolution fails closed (nil) without crashing (DC-4) | `ResumeAndCreateTests.swift` | `LastFileStoreTests` → `deletedFileResolvesNil`, `corruptReferenceResolvesNil` |
| RETAIN-on-failure: a transient miss does not erase the reference (DC-5) | `ResumeAndCreateTests.swift` | `LastFileStoreTests` → `retainOnFailure` |

### C7 — LocalDocumentsFallback: always-available create target

| Seam behavior | Test file | Test name |
|---------------|-----------|-----------|
| Vends the app's local Documents directory, guaranteed writable | `ResumeAndCreateTests.swift` | `LocalDocumentsFallbackTests` → `vendsDocumentsDirectory`, `directoryExistsAndWritable` |

### C8 — BackToBrowser: leading affordance + edge-swipe, reference untouched

| Seam behavior (DC) | Test file | Test name |
|--------------------|-----------|-----------|
| Both modes expose a leading back chevron to the browser (DC-13) | `ResumeAndCreateUITests.swift` | `testBackChevronFromRenderedReturnsToBrowser`, `testBackChevronFromRawEditorReturnsToBrowser` |
| Standard edge-swipe-back returns to the browser (DC-14) | `ResumeAndCreateUITests.swift` | `testEdgeSwipeBackReturnsToBrowser` |
| Leaving the file does not erase the stored reference (DC-15) | `ResumeAndCreateUITests.swift` → `testBackThenRelaunchStillResumes`; `ResumeAndCreateTests.swift` → `LastFileStoreTests` → `readsAreNonDestructive` |

---

## Untestable / partially-testable requirements summary

Surfaced so they are not silently dropped. These mirror the precedent set by `editor-foundation-4/verify.md` (XCUITest cannot observe certain timing/opacity/container properties; covered by `XCTSkip` stubs + manual or build-agent verification).

| ID | Requirement | Reason not fully automatable | Mitigation |
|----|-------------|------------------------------|------------|
| BR-3 / DC-3 | Zero browser flash on resume | XCUITest cannot reliably sample frame-zero presentation order on the simulator; DC-3 is the design's named build-escalation trigger | `testNoBrowserFlashOnResume` (`XCTSkip`); manual device verification by the build agent; if the host cannot present the editor at frame zero, escalate to the requirements↔architecture loop per design.md |
| BR-13 / BR-24 / DC-9 | No on-disk trace from an abandoned create | The app container is not enumerable from the test target without entitlements | Observable proxy `testUntypedNewFileDoesNotConsumeName` (second Create still yields `Untitled`); the build agent additionally inspects the on-disk container to confirm no file remains |
| BR-14 / DC-10 | Typed file persists at the resolved name with typed content | On-disk container inspection unavailable from the test target | `testTypedNewFilePersists` (`XCTSkip`); build agent reads the persisted file at the resolved OS path and asserts content |
| BR-15 | A persisted new file becomes the last-opened file | Depends on BR-14 persistence + terminate/relaunch fixture | `testTypedNewFileBecomesLastOpened` (`XCTSkip`); logic-level `LastFileStoreTests.recordAndResolve` covers the record→resolve half; build agent wires the end-to-end relaunch |

All requirements that could not be fully covered by automated tests are listed above. No requirement was silently omitted. BR-1…BR-26 are each mapped to at least one test (logic-level, UI-level, or an `XCTSkip` stub with a build-agent verification note).

---

## Task → test mapping (DAG task IDs)

*Authoritative mapping, filled in after `dag.md` was committed (Stage 5). Each task is mapped to the test(s) whose acceptance condition it satisfies. Every task has at least one test; `XCTSkip` stubs are executable and named as the test for the requirement they stand in for, with a build-agent verification note (see Untestable section). Test names are the methods/suites in `tests/unit/ResumeAndCreateTests.swift` (Swift Testing) and `tests/ui/ResumeAndCreateUITests.swift` (XCUITest).*

| Task | Component (design) | Description | Tests |
|------|--------------------|-------------|-------|
| T-001 | C1 LastFileStore | Durable last-opened reference, RETAIN-on-failure, read-only resolution | `LastFileStoreTests` → `recordAndResolve`, `referenceIsDurable`, `recordReplaces`, `deletedFileResolvesNil`, `corruptReferenceResolvesNil`, `retainOnFailure`, `readsAreNonDestructive` |
| T-002 | C5 NameProbe | Collision-free `Untitled[ n].md`, `.md` extension, gap-filling, non-destructive, directory-anchored | `NameProbeTests` → `emptyDirectoryYieldsUntitled`, `probedNameHasMdExtension`, `firstCollisionYieldsTwo`, `secondCollisionYieldsThree`, `gapIsFilled`, `existingFilesUntouched`, `unrelatedFilesIgnored`, `anchoredToSuppliedDirectory` |
| T-003 | C7 LocalDocumentsFallback | Vends guaranteed-writable local Documents directory | `LocalDocumentsFallbackTests` → `vendsDocumentsDirectory`, `directoryExistsAndWritable` |
| T-004 | C6 CreateTargetResolver (+ `LastDirectoryProviding`) | Last directory only when reachable + writability probe succeeds, else local Documents; probe side-effect-free; name anchored to resolved dir | `CreateTargetResolverTests` → `writableLastDirectoryChosen`, `noLastReferenceFallsBack`, `unreachableLastDirectoryFallsBack`, `readOnlyLastDirectoryFallsBack`, `probeLeavesNoResidue`, `nameProbeAnchoredToResolvedDirectory` |
| T-005 | C0 BrowserHost | UIKit `UIDocumentBrowserViewController` host replaces `DocumentGroup`; browser-open path preserved; default landing is the browser | `testFirstLaunchShowsDocumentBrowser` (host default landing); plus walking-skeleton / editor-foundation browser-open + tap→raw→edit→save UI tests continue to pass (BR-6 hard-seam regression gate; build-agent confirmed) |
| T-006 | C2 LaunchResumeBranch | Resume-vs-browser at scene activation; resolvable ref → rendered view first; failure → browser silently; zero-flash trigger | `testResumeLaunchOpensRenderedView`, `testResumeLaunchDoesNotLandOnBrowser`, `testStaleReferenceFallsThroughSilently`, `testResumedFileIsEditable`, `testFirstLaunchShowsDocumentBrowser`; `testNoBrowserFlashOnResume` (`XCTSkip` — device-only, build-escalation trigger per design DC-3) |
| T-007 | C4 CreateDocumentHandler | Create → `Untitled.md` in resolved dir, opens raw editor keyboard-up, deferred write, name not consumed on abandon, persists + becomes last-opened | `testCreateDocumentOpensUntitledMd`, `testNewFileOpensInRawEditor`, `testNewFileEditorHasKeyboardFocus`, `testUntypedNewFileDoesNotConsumeName`, `testFirstLaunchThenCreate`, `testBackFromUntypedNewFileLeavesNoFile`; `testTypedNewFilePersists`, `testTypedNewFileBecomesLastOpened` (`XCTSkip` — on-disk container inspection; build-agent verifies) |
| T-008 | C3 DocumentOpenObserver + C8 BackToBrowser | Record-on-open funnel for all entry paths; leading back chevron both modes + edge-swipe; dismiss does not clear the reference | `testBackChevronFromRenderedReturnsToBrowser`, `testBackChevronFromRawEditorReturnsToBrowser`, `testEdgeSwipeBackReturnsToBrowser`, `testBackThenRelaunchStillResumes`; `LastFileStoreTests` → `readsAreNonDestructive` (non-clearing dismiss contract, DC-15) |

**Coverage check:** all 8 tasks (T-001…T-008) map to at least one test. No task is unmapped. The two fully-skipped UI tests under the "Untestable" section (`testNoBrowserFlashOnResume`, `testTypedNewFilePersists`, `testTypedNewFileBecomesLastOpened`) are each attached to the task whose behavior they specify and carry a build-agent verification mitigation; they are not the *sole* test for any task except where noted as the design's named build-escalation trigger (DC-3 / T-006), which additionally has executable resume tests covering DC-2/DC-4.
