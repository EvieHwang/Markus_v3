# Verify: external-change-5

Human-readable coverage summary mapping each behavioral requirement (BR-*) and
each design seam / constraint (DC-*) to the test(s) that verify it.

**Note:** The requirement/seam → test mapping below is produced by `/tests`. The
authoritative **task → test mapping** (DAG task IDs) is applied by `/dag` and lives
in the final section of this file. Tests intentionally fail (missing-symbol /
ImportError, or `XCTSkip`) until each task is implemented.

Test files:
- `tests/unit/ExternalChangeTests.swift` — Swift Testing (`@Test`/`#expect`/`#require`), logic-level seams (the equality gate, classification, settle gate, apply-edge re-validation, suspension latch, foreground reconciliation, conflict resolution end-states).
- `tests/ui/ExternalChangeUITests.swift` — XCUITest, scene-level / end-to-end seams (the conflict sheet, deletion banner, silence guarantees, mode preservation, lifecycle across backgrounding, alert-path reuse).

Convention follows `resume-and-create-2` and `editor-foundation-4`: logic that is a
function of disk + buffer state is asserted at the unit level through small in-test
seams bound to the design's *observable contract* (which outcome, which content
lands, what stays recoverable) — never call signatures, private attributes, or
constructor arguments. Everything that needs a running scene (surfaces, focus,
lifecycle) is XCUITest. On-disk container read-back and precise frame-timing are
`XCTSkip` stubs with a build-agent verification note (see Untestable section).

---

## Category 1 — Behavioral tests (from requirements.md)

### Content change — silent absorption (BR-1, BR-2)

| BR | Requirement summary | Test(s) |
|----|---------------------|---------|
| BR-1.1 | Clean buffer + external change → no sheet | `ChangeClassifierTests.cleanBufferAbsorbs`; `ExternalChangeUITests.testCleanBufferExternalChangeIsSilent` |
| BR-1.2 | After absorb, buffer reflects new on-disk content | `ExternalChangeUITests.testCleanAbsorbAdoptsNewContent` |
| BR-1.3 | After absorb, buffer is clean against new content | `LastKnownDiskStateTests.resetMakesClean` (absorb resets last-known-disk → clean) |
| BR-1.4 | No toast/alert/banner on absorb | `ExternalChangeUITests.testCleanBufferExternalChangeIsSilent` |
| BR-1.5 | Absorb preserves the current editing mode | `ExternalChangeUITests.testCleanAbsorbPreservesRawMode` |
| BR-2.1 | Dirty buffer, byte-identical disk → no sheet | `ContentEqualityGateTests.byteIdenticalEqual`; `ChangeClassifierTests.contentIdenticalDirtyAbsorbs`; `ExternalChangeUITests.testContentIdenticalChangeIsSilentAndNonDisruptive` |
| BR-2.2 | Dirty buffer, newline-normalized-identical disk → no sheet | `ContentEqualityGateTests.crlfNormalizedEqual`, `bareCrNormalizedEqual`; `ChangeClassifierTests.newlineIdenticalDirtyAbsorbs` |
| BR-2.3 | Buffer/cursor preserved on content-identical absorb | `ExternalChangeUITests.testContentIdenticalChangeIsSilentAndNonDisruptive` |
| BR-2.4 | No toast/alert/banner | `ExternalChangeUITests.testContentIdenticalChangeIsSilentAndNonDisruptive` |

### Settle-window suppression / no false positives (BR-3)

| BR | Requirement summary | Test(s) |
|----|---------------------|---------|
| BR-3.1 | Change within window after create → suppressed | `SettleGateTests.suppressedWithinWindowAfterCreate` |
| BR-3.2 | Change within window after save → suppressed | `SettleGateTests.suppressedWithinWindowAfterSave` |
| BR-3.3 | Change while sync in flight → suppressed | `SettleGateTests.inFlightSyncSuppressesPastWindow`, `inFlightSyncSuppressesAlone`; `ExternalChangeUITests.testInFlightSyncSuppressesSheet` (`XCTSkip` — busy-state fixture) |
| BR-3.4 | Suppression delays, never discards a real collision | `SettleGateTests.suppressionDelaysNotDiscards`, `notSuppressedAfterWindow` |
| BR-3.5 | Normal create→type→save → zero surfaces | `ExternalChangeUITests.testNormalCreateTypeSaveProducesNoConflictSurfaces` |
| BR-3.6 | Ordinary edit/save loop → zero sheets | `ExternalChangeUITests.testEditSaveLoopProducesNoConflictSheets`; `SettleGateTests.triggerResetsWindow` |

### True collision → conflict sheet (BR-4)

| BR | Requirement summary | Test(s) |
|----|---------------------|---------|
| BR-4.1 | Sheet iff dirty AND material AND settled | `ChangeClassifierTests.dirtyMaterialIsCollision`, `emptiedDiskWithDirtyBufferIsCollision`; `ExternalChangeUITests.testTrueCollisionShowsThreeOptionSheet` |
| BR-4.2 | Exactly three options, no merge | `ConflictResolutionTests.exactlyThreeOptions`; `ExternalChangeUITests.testTrueCollisionShowsThreeOptionSheet` |
| BR-4.3 | No silent overwrite while pending (see BR-20 / DC-22) | `SaveSuspensionLatchTests.collisionClassificationSuspends`, `queuedSaveRefusedInGap` |
| BR-4.4 | At most one sheet; later signals do not stack | `SaveSuspensionLatchTests.secondSignalDoesNotStack`; `ExternalChangeUITests.testSecondCollisionDoesNotStackSheet` |

### Resolution — Keep Mine / Keep Theirs / Discard Mine (BR-5, BR-6, BR-7)

| BR | Requirement summary | Test(s) |
|----|---------------------|---------|
| BR-5.1 | Keep Mine writes buffer→disk | `ConflictResolutionTests.keepMineWritesBuffer`; `ExternalChangeUITests.testKeepMineWritesBufferToDisk` (`XCTSkip` — on-disk read-back) |
| BR-5.2 | Buffer unchanged & clean after Keep Mine | `ConflictResolutionTests.keepMineWritesBuffer` |
| BR-5.3 | Sheet dismisses, same mode resumes | `ExternalChangeUITests.testKeepMineDismissesAndResumesRawMode` |
| BR-6.1 | Keep Theirs → buffer equals on-disk content | `ConflictResolutionTests.keepTheirsAdoptsDisk` |
| BR-6.2 | Keep Theirs clean, no clobber write | `ConflictResolutionTests.keepTheirsAdoptsDisk` |
| BR-6.3 | Sheet dismisses, same mode resumes | `ExternalChangeUITests.testKeepTheirsAdoptsExternalContent` |
| BR-7.1 | Discard Mine → buffer equals on-disk content | `ConflictResolutionTests.discardMineAdoptsDisk`, `keepTheirsEqualsDiscardMine` |
| BR-7.2 | No local edits remain, clean | `ConflictResolutionTests.discardMineAdoptsDisk` |
| BR-7.3 | Sheet dismisses, same mode resumes | `ExternalChangeUITests.testDiscardMineDismissesSheet` |

### Follow on move / rename (BR-8)

| BR | Requirement summary | Test(s) |
|----|---------------------|---------|
| BR-8.1 | Move alone → no sheet, no banner | `ChangeClassifierTests.relocatedMatchingIsMoved`, `movedIsNeverDeleted`; `ExternalChangeUITests.testRenameAloneShowsNoSheetOrBanner` |
| BR-8.2 | Subsequent save writes to new location, not old | `ExternalChangeUITests.testMoveRetargetsSaveAndResume` (`XCTSkip` — on-disk path inspection) |
| BR-8.3 | Rename propagates to displayed title | `ExternalChangeUITests.testRenamePropagatesToTitle` |
| BR-8.4 | Move + content change still gated for collision | `ChangeClassifierTests.movePlusMaterialChangeIsCollision` |
| BR-8.5 | Resume reference updated to new location | `ExternalChangeUITests.testMoveRetargetsSaveAndResume` (`XCTSkip` — relaunch fixture) |

### Deletion → recoverable banner (BR-9)

| BR | Requirement summary | Test(s) |
|----|---------------------|---------|
| BR-9.1 | Deletion → Save As banner | `ChangeClassifierTests.absentIsDeleted`; `ExternalChangeUITests.testDeletionShowsBannerAndKeepsBuffer` |
| BR-9.2 | Banner does not discard the buffer | `ExternalChangeUITests.testDeletionShowsBannerAndKeepsBuffer` |
| BR-9.3 | No silent recreate at old path (see BR-20.3 / DC-22) | `SaveSuspensionLatchTests.deletionClassificationSuspends` |
| BR-9.4 | Save As writes to a new location, continues session | `ExternalChangeUITests.testSaveAsContinuesSessionAtNewLocation` (`XCTSkip` — picker + read-back) |
| BR-9.5 | Delete-then-reappear-within-2s → move, no banner | `ChangeClassifierTests.relocatedMatchingIsMoved`; `ForegroundReconcilerTests.reappearedDeletionLifts`; `ExternalChangeUITests.testDeleteThenReappearWithinWindowIsMoveNoBanner` |
| BR-9.6 | Dismiss banner without Save As → buffer preserved | `ExternalChangeUITests.testDismissingBannerPreservesBuffer` |

### Detection basis (BR-10) — design-review constraint

| BR | Requirement summary | Coverage |
|----|---------------------|----------|
| BR-10.1 | Detection grounded in coordinated file access / version observation, not raw `documentState` | Verified by design review (DC-1, DC-3), not a behavioral test — per BR-10's own statement. The observable proxy enforced by tests: a single change yields at most one user-visible response (see DC-3 below) and classification is a function of settled disk + buffer (the `ChangeClassifierTests` suite), never of a transient flag. |

### Edge cases & failure modes (BR-11 … BR-18)

| BR | Requirement summary | Test(s) |
|----|---------------------|---------|
| BR-11 | Empty↔non-empty material; CRLF↔LF content-identical | `ContentEqualityGateTests.emptyVsNonEmptyMaterial`, `crlfNormalizedEqual`; `ChangeClassifierTests.emptiedDiskWithDirtyBufferIsCollision` |
| BR-12 | Rapid successive changes do not stack sheets | `SaveSuspensionLatchTests.secondSignalDoesNotStack`; `ExternalChangeUITests.testSecondCollisionDoesNotStackSheet` |
| BR-13 | Invalid UTF-8 → existing alert, not a conflict sheet, no overwrite | `ExternalChangeUITests.testInvalidUtf8UsesAlertNotConflictSheet` |
| BR-14 | Save failure during resolution → save-failure alert, conflict not falsely resolved | `ExternalChangeUITests.testSaveFailureDuringKeepMineReusesAlert` (`XCTSkip` — forced-failure fixture) |
| BR-15 | Backgrounding mid-conflict does not auto-resolve / lose buffer | `ExternalChangeUITests.testBackgroundingDoesNotAutoResolveSheet`, `testBufferPreservedAcrossBackgroundWithPendingSheet`; `SaveSuspensionLatchTests.systemDismissalDoesNotLift` |
| BR-16 | Move+delete race → presence wins, no double-prompt | `ChangeClassifierTests.movedIsNeverDeleted`, `relocatedMatchingIsMoved`; `ForegroundReconcilerTests.reappearedDeletionLifts` |
| BR-17 | Never-persisted create exempt from deletion | `SettleGateTests.suppressedWithinWindowAfterCreate` (settle covers create, DC-18); UI: covered by `testNormalCreateTypeSaveProducesNoConflictSurfaces` (no banner in the create flow) |
| BR-18 | Handling applies only to the open document | `ExternalChangeUITests.testChangeToNonOpenFileProducesNoUI` |

### Concurrency integrity — apply-edge guarantees (BR-19, BR-20, BR-21)

| BR | Requirement summary | Test(s) |
|----|---------------------|---------|
| BR-19.1 | Clean-at-read, typed-before-apply, material → collision not silent absorb | `ApplyEdgeRevalidationTests.typedDuringReadMaterialBecomesCollision` |
| BR-19.2 | No character typed after the read snapshot is silently lost | `ApplyEdgeRevalidationTests.typedCharactersNeverSilentlyLost` |
| BR-19.3 | Content-identical re-validated at application, not read time | `ApplyEdgeRevalidationTests.typedDuringReadContentIdenticalAbsorbs` |
| BR-19.4 | No spurious sheet on the unchanged-buffer common case | `ApplyEdgeRevalidationTests.unchangedBufferAbsorbsSilently` |
| BR-20.1 | No write from classification until resolution | `SaveSuspensionLatchTests.collisionClassificationSuspends`, `explicitResolutionLifts` |
| BR-20.2 | Queued/debounced save in the classify→present gap does not fire | `SaveSuspensionLatchTests.queuedSaveRefusedInGap` |
| BR-20.3 | Classified deletion: no recreate at vanished path in the gap | `SaveSuspensionLatchTests.deletionClassificationSuspends` |
| BR-20.4 | Suspension lifts only on explicit resolution or DC-23 recoverable lift | `SaveSuspensionLatchTests.explicitResolutionLifts`, `systemDismissalDoesNotLift`; `ForegroundReconcilerTests` (all) |
| BR-21.1 | Non-user dismissal never marks resolved | `SaveSuspensionLatchTests.systemDismissalDoesNotLift` |
| BR-21.2 | Suspension persists after non-user dismissal | `SaveSuspensionLatchTests.systemDismissalDoesNotLift` |
| BR-21.3 | On foreground: re-present (still holds) or lift (no longer holds) | `ForegroundReconcilerTests.stillDivergentRePresents`, `nowIdenticalLifts`, `reappearedDeletionLifts`, `stillAbsentRePresents`; `ExternalChangeUITests.testBackgroundingDoesNotAutoResolveSheet`, `testReconcileLiftsWhenDiskNowAgrees` (`XCTSkip` — disk-agreement-during-background fixture) |
| BR-21.4 | No stuck-suspended/surface-less state | `ForegroundReconcilerTests.reconciliationIsTotal` |
| BR-21.5 | Buffer preserved across non-user dismissal + re-present | `ExternalChangeUITests.testBufferPreservedAcrossBackgroundWithPendingSheet` |

---

## Category 2 — Integration / seam tests (from design.md)

### Change detector — four exclusive outcomes, presence-first (DC-1, DC-2, DC-4, DC-5)

| Seam behavior (DC) | Test(s) |
|--------------------|---------|
| DC-1 — single detection authority grounded in coordinated reads (not state bits) | Enforced as a property by the `ChangeClassifierTests` suite (classification is a function of settled disk + buffer) and DC-3 below; mechanism verified by design review per BR-10 |
| DC-2 — coordinated, never-torn reads (no mid-write material diff) | `SettleGateTests.inFlightSyncSuppressesPastWindow` (no classification while a sync is in flight — the never-torn property at the timing seam) |
| DC-4 — exactly one outcome; presence resolved first | `ChangeClassifierTests.exactlyOneOutcome`, `movedIsNeverDeleted`, `relocatedMatchingIsMoved`, `absentIsDeleted` |
| DC-5 — quiescence while a choice is pending (no second competing surface) | `SaveSuspensionLatchTests.secondSignalDoesNotStack`; `ExternalChangeUITests.testSecondCollisionDoesNotStackSheet` |

### Two observers — detector vs SaveStatusObserver split (DC-3)

| Seam behavior (DC) | Test(s) |
|--------------------|---------|
| DC-3 — `SaveStatusObserver` keeps its narrow job; the detector owns collisions; a single change yields at most one user-visible response | `ExternalChangeUITests.testInFlightSyncSuppressesSheet` (`XCTSkip` — busy fixture: while busy, the loading/busy surface shows and the detector does not also prompt); logic-level: `SettleGateTests.inFlightSyncSuppressesAlone`, `inFlightSyncSuppressesPastWindow` (the detector consumes busy as a settle input, does not delegate the collision decision) |

### Settle gate — 2s window + in-flight suppression boundaries (DC-6, DC-7, DC-8)

| Seam behavior (DC) | Test(s) |
|--------------------|---------|
| DC-6 — 2s window opened by open / first-persist / save | `SettleGateTests.suppressedWithinWindowAfterOpen`, `...AfterCreate`, `...AfterSave`, `notSuppressedAfterWindow`, `triggerResetsWindow` |
| DC-7 — in-flight suppression independent of the timer | `SettleGateTests.inFlightSyncSuppressesPastWindow`, `inFlightSyncSuppressesAlone` |
| DC-8 — suppression delays, never discards | `SettleGateTests.suppressionDelaysNotDiscards` |

### Document model — last-known-disk state + equality gate (DC-9, DC-10, DC-11, DC-12)

| Seam behavior (DC) | Test(s) |
|--------------------|---------|
| DC-9 — last-known-disk content is the shared reference, reset on absorb/save | `LastKnownDiskStateTests.resetMakesClean` |
| DC-10 — clean/dirty is buffer-vs-last-known-disk, not an undo flag | `LastKnownDiskStateTests.equalIsClean`, `divergedIsDirty`, `revertedToDiskIsClean` |
| DC-11 — equality gate: byte-identical OR newline-normalized | `ContentEqualityGateTests` (all 7); `LastKnownDiskStateTests.newlineOnlyIsClean` |
| DC-12 — absorb preserves the editing surface | `ExternalChangeUITests.testCleanAbsorbPreservesRawMode`, `testContentIdenticalChangeIsSilentAndNonDisruptive` |

### Conflict & lifecycle UI (DC-13, DC-14, DC-15, DC-16, DC-17, DC-18, DC-19, DC-20)

| Seam behavior (DC) | Test(s) |
|--------------------|---------|
| DC-13 — Keep Mine vs (Keep Theirs ≡ Discard Mine), two end-states | `ConflictResolutionTests.keepMineWritesBuffer`, `keepTheirsAdoptsDisk`, `discardMineAdoptsDisk`, `keepTheirsEqualsDiscardMine` |
| DC-14 — sheet iff collision; three options; suspended from classification | `ExternalChangeUITests.testTrueCollisionShowsThreeOptionSheet`; `SaveSuspensionLatchTests.collisionClassificationSuspends` |
| DC-15 — sheet survives backgrounding; non-user dismissal never a resolution | `ExternalChangeUITests.testBackgroundingDoesNotAutoResolveSheet`; `SaveSuspensionLatchTests.systemDismissalDoesNotLift` |
| DC-16 — deletion banner only after 2s presence disambiguation | `ExternalChangeUITests.testDeleteThenReappearWithinWindowIsMoveNoBanner`, `testDeletionShowsBannerAndKeepsBuffer`; `ChangeClassifierTests.absentIsDeleted` |
| DC-17 — Save As continues the session at the new location | `ExternalChangeUITests.testSaveAsContinuesSessionAtNewLocation` (`XCTSkip` — picker + read-back) |
| DC-18 — never-persisted creates exempt from deletion | `SettleGateTests.suppressedWithinWindowAfterCreate`; `ExternalChangeUITests.testNormalCreateTypeSaveProducesNoConflictSurfaces` |
| DC-19 — moves followed transparently (location/title/resume track together) | `ChangeClassifierTests.relocatedMatchingIsMoved`; `ExternalChangeUITests.testRenamePropagatesToTitle`, `testRenameAloneShowsNoSheetOrBanner`, `testMoveRetargetsSaveAndResume` (`XCTSkip`) |
| DC-20 — a move carrying a content change is still gated | `ChangeClassifierTests.movePlusMaterialChangeIsCollision` |

### Apply-edge integrity (DC-21, DC-22, DC-23)

| Seam behavior (DC) | Test(s) |
|--------------------|---------|
| DC-21 — re-validate against the live buffer before mutation; absorb never overwrites edits made after the read | `ApplyEdgeRevalidationTests` (all 4): `unchangedBufferAbsorbsSilently`, `typedDuringReadMaterialBecomesCollision`, `typedDuringReadContentIdenticalAbsorbs`, `typedCharactersNeverSilentlyLost` |
| DC-22 — save-back suspended from classification, not presentation; queued/debounced save in the gap does not fire; two-path lift | `SaveSuspensionLatchTests` (all 6) |
| DC-23 — latched-but-surface-less outcome re-presented or recoverably lifted on foreground; no stuck-suspended state | `ForegroundReconcilerTests` (all 5); `ExternalChangeUITests.testBackgroundingDoesNotAutoResolveSheet`, `testReconcileLiftsWhenDiskNowAgrees` (`XCTSkip`) |

---

## Untestable / partially-testable requirements summary

Surfaced so they are not silently dropped. These mirror the precedent set by
`resume-and-create-2` and `editor-foundation-4` (XCUITest cannot observe certain
container / timing / busy-state properties; covered by `XCTSkip` stubs + a
build-agent verification note). Each has at least one *executable* logic-level
test covering the decision the skipped test would observe end-to-end.

| ID | Requirement / seam | Reason not fully automatable | Mitigation |
|----|--------------------|------------------------------|------------|
| BR-3.3 / DC-3 / DC-7 | No prompt while a sync is in flight | Driving the iCloud download/upload busy signal needs a `SaveStatusObserver` busy fixture | `testInFlightSyncSuppressesSheet` (`XCTSkip`); logic-level `SettleGateTests.inFlightSyncSuppressesPastWindow`, `inFlightSyncSuppressesAlone` |
| BR-5.1 / DC-13 | Keep Mine writes the buffer bytes to the followed file | App-container on-disk read-back is not reachable from the UI test target | `testKeepMineWritesBufferToDisk` (`XCTSkip`); logic-level `ConflictResolutionTests.keepMineWritesBuffer` (asserts the write content + clean end-state) |
| BR-8.2 / BR-8.5 / DC-19 | Save lands at the new path (not the old); resume tracks the move | On-disk path inspection + a terminate/relaunch fixture | `testMoveRetargetsSaveAndResume` (`XCTSkip`); logic-level `ChangeClassifierTests` (moved outcome) + the resume-and-create `LastFileStore` record/resolve seam |
| BR-9.4 / DC-17 | Save As writes the buffer to a chosen location and continues there | Drives the system save picker + on-disk read-back | `testSaveAsContinuesSessionAtNewLocation` (`XCTSkip`); build agent drives the picker fixture |
| BR-14 | Save-failure during resolution reuses the save-failure alert | Requires forcing a save-back write failure | `testSaveFailureDuringKeepMineReusesAlert` (`XCTSkip`); build agent wires `-uitest-force-save-failure` |
| BR-21.3 (lift branch) / DC-23 | On return, disk-now-agrees → lift (no re-present), autosave/detector live again | Requires mutating on-disk content while the app is backgrounded | `testReconcileLiftsWhenDiskNowAgrees` (`XCTSkip`); logic-level `ForegroundReconcilerTests.nowIdenticalLifts`, `reappearedDeletionLifts` |

**Coverage check:** Every BR-* requirement (BR-1 … BR-21, including all numbered
acceptance criteria) is mapped to at least one test above — logic-level, UI-level,
or an `XCTSkip` stub paired with an executable logic-level test for the underlying
decision. BR-10 is, by its own statement, a design-review constraint rather than a
behavioral test; the table notes its enforced observable proxy. Every design
constraint DC-1 … DC-23 is mapped. No requirement and no seam was silently omitted.

No requirement was found untestable-as-written: each behavioral BR has at least one
fully-executable assertion of its observable end-state at the logic level (the
`XCTSkip` cases are the *end-to-end* surface of decisions that are also covered by an
executable logic-level test, not gaps in coverage).

---

## Task → test mapping (DAG task IDs)

*Authoritative task → test mapping, applied by `/dag` after `dag.md` was committed.
Each `dag.md` task maps to the test(s) whose acceptance conditions it satisfies. A
task's tests intentionally fail (missing-symbol / `XCTSkip`) until that task is
implemented; the build agent's first action per task is to confirm its tests fail
in the expected way, then implement until they pass. `XCTSkip` stubs stay skipped
(executable) and are paired with a build-agent on-disk/fixture verification note in
the Untestable section above.*

| Task | Component (DC) | Tests verifying its acceptance condition |
|------|----------------|------------------------------------------|
| T-001 | `ContentEqualityGate` (DC-11) | `ContentEqualityGateTests`: `byteIdenticalEqual`, `crlfNormalizedEqual`, `bareCrNormalizedEqual`, `emptyVsNonEmptyMaterial`, `realTextChangeMaterial`, `trailingWhitespaceIsMaterial`, `emptyEqualsEmpty` |
| T-002 | `LastKnownDiskState` (DC-9/DC-10) | `LastKnownDiskStateTests`: `equalIsClean`, `divergedIsDirty`, `revertedToDiskIsClean`, `newlineOnlyIsClean`, `resetMakesClean` |
| T-003 | `ConflictResolution` (DC-13) | `ConflictResolutionTests`: `keepMineWritesBuffer`, `keepTheirsAdoptsDisk`, `discardMineAdoptsDisk`, `keepTheirsEqualsDiscardMine`, `exactlyThreeOptions` |
| T-004 | `ChangeClassifier` (DC-4) | `ChangeClassifierTests`: `cleanBufferAbsorbs`, `contentIdenticalDirtyAbsorbs`, `newlineIdenticalDirtyAbsorbs`, `dirtyMaterialIsCollision`, `emptiedDiskIsCollision`, `emptiedDiskWithDirtyBufferIsCollision`, `relocatedMatchingIsMoved`, `absentIsDeleted`, `movedIsNeverDeleted`, `movePlusMaterialChangeIsCollision`, `exactlyOneOutcome` |
| T-005 | `SettleGate` (DC-6/7/8) | `SettleGateTests`: `suppressedWithinWindowAfterSave`, `suppressedWithinWindowAfterCreate`, `suppressedWithinWindowAfterOpen`, `notSuppressedAfterWindow`, `inFlightSyncSuppressesPastWindow`, `inFlightSyncSuppressesAlone`, `triggerResetsWindow`, `suppressionDelaysNotDiscards` |
| T-006 | `ApplyEdgeRevalidation` (DC-21) + `SaveSuspensionLatch` (DC-22) | `ApplyEdgeRevalidationTests`: `unchangedBufferAbsorbsSilently`, `typedDuringReadMaterialBecomesCollision`, `typedDuringReadContentIdenticalAbsorbs`, `typedCharactersNeverSilentlyLost`; `SaveSuspensionLatchTests`: `collisionClassificationSuspends`, `deletionClassificationSuspends`, `queuedSaveRefusedInGap`, `explicitResolutionLifts`, `systemDismissalDoesNotLift`, `secondSignalDoesNotStack` |
| T-007 | Change detector (DC-1/2/3/5, absorb DC-12) | `ExternalChangeUITests`: `testCleanBufferExternalChangeIsSilent`, `testCleanAbsorbAdoptsNewContent`, `testCleanAbsorbPreservesRawMode`, `testContentIdenticalChangeIsSilentAndNonDisruptive`, `testNormalCreateTypeSaveProducesNoConflictSurfaces`, `testEditSaveLoopProducesNoConflictSheets`, `testChangeToNonOpenFileProducesNoUI`; `testInFlightSyncSuppressesSheet` (`XCTSkip` — DC-3/DC-7 busy fixture). *Detector logic seams are also exercised by the T-004/T-005/T-006 suites it composes; this row lists the scene-level tests that prove the live detector.* |
| T-008 | Conflict sheet (DC-14, DC-15) | `ExternalChangeUITests`: `testTrueCollisionShowsThreeOptionSheet`, `testSecondCollisionDoesNotStackSheet`, `testKeepMineDismissesAndResumesRawMode`, `testKeepTheirsAdoptsExternalContent`, `testDiscardMineDismissesSheet`; `testKeepMineWritesBufferToDisk` (`XCTSkip` — on-disk read-back; logic-level `ConflictResolutionTests.keepMineWritesBuffer` under T-003) |
| T-009 | Deletion banner + Save As + follow-on-move (DC-16/17/18/19/20) | `ExternalChangeUITests`: `testRenameAloneShowsNoSheetOrBanner`, `testRenamePropagatesToTitle`, `testDeletionShowsBannerAndKeepsBuffer`, `testDeleteThenReappearWithinWindowIsMoveNoBanner`, `testDismissingBannerPreservesBuffer`; `testMoveRetargetsSaveAndResume` (`XCTSkip` — path inspection + relaunch), `testSaveAsContinuesSessionAtNewLocation` (`XCTSkip` — picker + read-back) |
| T-010 | `ForegroundReconciler` (DC-23) + lifecycle + failure-path reuse | `ForegroundReconcilerTests`: `stillDivergentRePresents`, `nowIdenticalLifts`, `reappearedDeletionLifts`, `stillAbsentRePresents`, `reconciliationIsTotal`; `ExternalChangeUITests`: `testBackgroundingDoesNotAutoResolveSheet`, `testBufferPreservedAcrossBackgroundWithPendingSheet`, `testInvalidUtf8UsesAlertNotConflictSheet`; `testReconcileLiftsWhenDiskNowAgrees` (`XCTSkip` — disk-agreement-during-background), `testSaveFailureDuringKeepMineReusesAlert` (`XCTSkip` — forced save failure) |

**Coverage check (task → test):** Every task T-001 … T-010 maps to at least one
test. Every executable test in `tests/unit/ExternalChangeTests.swift` and
`tests/ui/ExternalChangeUITests.swift` is assigned to exactly one owning task (the
task whose acceptance condition it verifies); `XCTSkip` stubs are assigned to the
task that delivers the behavior they would observe end-to-end and are paired with an
executable logic-level test under an earlier task where noted. No task is left
without coverage and no test is left unmapped. BR-10 remains a design-review
constraint (no behavioral test of its own) whose observable proxy is enforced by the
T-004 classifier suite and the T-007 single-response UI checks.
