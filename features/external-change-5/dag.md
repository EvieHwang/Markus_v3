# DAG: external-change-5

External-change handling: a single owned change detector beside the save bridge,
last-known-disk state on the document model, and the conflict-sheet / deletion-banner
UI driven by detector outcomes, plus the three apply-edge concurrency guarantees
(DC-21/22/23). Ten tasks, four waves.

Generated: 2026-05-25

Drives `/build`. Wave N starts only after Wave N-1 completes. Tasks within a wave run in parallel.

The architectural through-line: the pure decision primitives that are a function of
disk + buffer state come first with no host dependency (Wave 1: the equality gate, the
last-known-disk authority, the four-outcome classifier, the resolution end-states). Wave 2
composes those primitives into the stateful detector pieces that need the Wave-1
primitives — the settle gate, the apply-edge re-validation, the save-suspension latch, and
the foreground reconciler. Wave 3 lands the owned change detector itself (the single
authority of BR-10) and wires last-known-disk onto `MarkdownDocument`, reconciled with the
existing `SaveStatusObserver`. Wave 4 attaches the user-visible surfaces — the conflict
sheet and the deletion banner / Save As + follow-on-move — onto `DocumentView` and the host.

---

## Wave 1 — Pure decision primitives (parallel, no host / no detector dependency)

### T-001 — `ContentEqualityGate` (DC-11) — byte-or-newline-normalized equality
**Description:** Add the content-equality gate: two contents are equal iff byte-identical OR equal after newline normalization (CRLF/CR → LF). This single gate is the authority behind absorb-vs-collision (detector) and clean-vs-dirty (document model). Its negation is "materially differs": any difference beyond newline encoding is material; empty↔non-empty is always material; trailing-whitespace differences are material (the gate is newline-only, not whitespace-insensitive). Pure value-level function, no I/O, no scene.
**Inputs:** design.md DC-11; requirements BR-2, BR-11.
**Outputs:** `Markus_v3/ExternalChange/ContentEqualityGate.swift` (new).
**Dependencies:** none.
**Wave:** 1.
**Acceptance:** `ContentEqualityGateTests` suite passes (all 7): `byteIdenticalEqual`, `crlfNormalizedEqual`, `bareCrNormalizedEqual`, `emptyVsNonEmptyMaterial`, `realTextChangeMaterial`, `trailingWhitespaceIsMaterial`, `emptyEqualsEmpty`.

### T-002 — `LastKnownDiskState` (DC-9, DC-10) — clean/dirty authority on the document model
**Description:** Give `MarkdownDocument` a last-known-disk-content value — the bytes Markus last wrote to or read from disk — and derive clean/dirty from it via the equality gate (T-001): clean when buffer equals last-known-disk (newline-normalized), dirty otherwise. This replaces "dirty = undo manager registered an edit" as the conflict-decision authority, so a buffer typed-then-reverted-to-disk content is clean. Provide a reset hook so an absorb or a successful save resets last-known-disk to the new disk content. Pure value/state logic; the wiring into the live `MarkdownDocument` writer/detector is done in Wave 3 (T-007).
**Inputs:** design.md DC-9, DC-10, DC-11; requirements BR-1.3 (clean after absorb), definitions of clean/dirty buffer. Uses T-001's equality gate.
**Outputs:** `Markus_v3/ExternalChange/LastKnownDiskState.swift` (new).
**Dependencies:** T-001.
**Wave:** 1.
**Acceptance:** `LastKnownDiskStateTests` suite passes: `equalIsClean`, `divergedIsDirty`, `revertedToDiskIsClean`, `newlineOnlyIsClean`, `resetMakesClean`.

### T-003 — `ConflictResolution` (DC-13) — Keep Mine / Keep Theirs / Discard Mine end-states
**Description:** Add the resolution primitive that maps each of the three conflict options to its end-state: **Keep Mine** writes the buffer to disk and leaves the buffer clean (buffer unchanged); **Keep Theirs** and **Discard Mine** are behaviorally identical — adopt the on-disk content into the buffer, drop local edits, buffer becomes clean, and no clobbering write to disk. Exactly three options exist (`keepMine`, `keepTheirs`, `discardMine`); there is no merge option. Pure decision over (option, buffer, on-disk) → (new buffer, content-written-to-disk?, clean-after); the surface that drives it is wired in Wave 4 (T-008).
**Inputs:** design.md DC-13; requirements BR-4.2, BR-5, BR-6, BR-7, OOS-2.
**Outputs:** `Markus_v3/ExternalChange/ConflictResolution.swift` (new).
**Dependencies:** none.
**Wave:** 1.
**Acceptance:** `ConflictResolutionTests` suite passes (all): `keepMineWritesBuffer`, `keepTheirsAdoptsDisk`, `discardMineAdoptsDisk`, `keepTheirsEqualsDiscardMine`, `exactlyThreeOptions`.

---

## Wave 2 — Stateful classification & concurrency primitives (parallel, depend on Wave 1)

### T-004 — `ChangeClassifier` (DC-4) — four exclusive outcomes, presence-first
**Description:** Add the pure classifier that, for any settled situation (presence + on-disk content + buffer + last-known-disk), emits exactly one of `absorb` / `collision` / `moved` / `deleted`. Presence is resolved first (DC-4/DC-16): a resolvable file at the same location → absorb (clean buffer, or dirty-but-content-identical via T-001's gate) or collision (dirty AND material); a file resolvable at a new location → moved, unless it also carries a material change against a dirty buffer (then collision at the new location, DC-20); a genuinely absent file → deleted. A resolvable (moved) file is never deleted. Pure decision, no timers/scene.
**Inputs:** design.md DC-4, DC-16 (presence ordering), DC-20; requirements BR-1.1, BR-2, BR-4.1, BR-8.1, BR-8.4, BR-9.1, BR-11, BR-16. Uses T-001 (equality gate), T-002 (clean/dirty).
**Outputs:** `Markus_v3/ExternalChange/ChangeClassifier.swift` (new).
**Dependencies:** T-001, T-002.
**Wave:** 2.
**Acceptance:** `ChangeClassifierTests` suite passes (all): `cleanBufferAbsorbs`, `contentIdenticalDirtyAbsorbs`, `newlineIdenticalDirtyAbsorbs`, `dirtyMaterialIsCollision`, `emptiedDiskIsCollision`, `emptiedDiskWithDirtyBufferIsCollision`, `relocatedMatchingIsMoved`, `absentIsDeleted`, `movedIsNeverDeleted`, `movePlusMaterialChangeIsCollision`, `exactlyOneOutcome`.

### T-005 — `SettleGate` (DC-6, DC-7, DC-8) — 2s window + in-flight suppression, delay-not-discard
**Description:** Add the settle gate: a fixed 2-second grace window opened (reset) by each of three triggers — open, first-persist (create), save-complete. While the window is open, change and deletion signals are suppressed. Independently of the timer, an in-flight sync (the busy signal) suppresses classification regardless of elapsed time, so a slow sync outlasting 2s is still suppressed until it settles. Suppression delays, never discards: once the window closes and sync settles, a still-present signal is classifiable again (the gate does not consume the pending signal — it only gates timing). Pure timing logic with an injectable clock/`now` parameter.
**Inputs:** design.md DC-6, DC-7, DC-8; requirements BR-3 (all), BR-17 (settle covers create).
**Outputs:** `Markus_v3/ExternalChange/SettleGate.swift` (new).
**Dependencies:** none (uses no Wave-1 output; it is a self-contained timing primitive).
**Wave:** 2.
**Acceptance:** `SettleGateTests` suite passes (all): `suppressedWithinWindowAfterSave`, `suppressedWithinWindowAfterCreate`, `suppressedWithinWindowAfterOpen`, `notSuppressedAfterWindow`, `inFlightSyncSuppressesPastWindow`, `inFlightSyncSuppressesAlone`, `triggerResetsWindow`, `suppressionDelaysNotDiscards`.

### T-006 — `ApplyEdgeRevalidation` (DC-21) + `SaveSuspensionLatch` (DC-22) — apply-edge integrity
**Description:** Two coupled apply-edge guarantees that together close adversarial F-001/F-002; both are small, both gate the same classify→act flow, and both must agree on what counts as a latched outcome — bundled into one coherent session.
- **`ApplyEdgeRevalidation` (DC-21, F-001):** before any buffer mutation, re-derive the outcome against the *live* buffer (not the read-time snapshot) using the equality gate (T-001): a clean-at-read buffer that turned dirty does not run the silent absorb — it re-derives to absorb only if content-identical, else collision; an unchanged buffer still absorbs silently (no spurious sheet). No character typed after the read is ever silently lost.
- **`SaveSuspensionLatch` (DC-22, F-002):** suspend save-back from the instant a collision/deletion is *classified* (not from surface presentation), so a queued/debounced save in the classify→present gap is refused. A second collision signal while latched does not stack. Suspension lifts on an explicit user resolution; a non-user (system) dismissal does NOT lift (it stays latched-unresolved — recovery is DC-23/T-010).
**Inputs:** design.md DC-21, DC-22; requirements BR-19, BR-20, BR-4.3, BR-4.4, BR-9.3, BR-12. Uses T-001 (equality gate).
**Outputs:** `Markus_v3/ExternalChange/ApplyEdgeRevalidation.swift` (new), `Markus_v3/ExternalChange/SaveSuspensionLatch.swift` (new).
**Dependencies:** T-001.
**Wave:** 2.
**Acceptance:** `ApplyEdgeRevalidationTests` suite passes (all 4): `unchangedBufferAbsorbsSilently`, `typedDuringReadMaterialBecomesCollision`, `typedDuringReadContentIdenticalAbsorbs`, `typedCharactersNeverSilentlyLost`. `SaveSuspensionLatchTests` suite passes (all 6): `collisionClassificationSuspends`, `deletionClassificationSuspends`, `queuedSaveRefusedInGap`, `explicitResolutionLifts`, `systemDismissalDoesNotLift`, `secondSignalDoesNotStack`.

---

## Wave 3 — Owned detector + document-model wiring (parallel, depend on Wave 1/2)

### T-007 — Change detector (DC-1, DC-2, DC-3, DC-5) — single coordinated-read authority reconciled with `SaveStatusObserver`
**Description:** Add the owned change detector in the File access layer: created by `BrowserHostController.presentDocument(at:)` beside the save bridge, given the same followed URL and `MarkdownDocument`, torn down on dismiss; exactly one live at a time, observing only the open document (BR-18, OOS-3). It performs coordinated, never-torn reads (NSFileVersion/NSFileCoordinator) so a half-written file is never classified as a material difference, feeds settled disk state through the settle gate (T-005), classifies via the classifier (T-004), and emits a single classified outcome stream (`absorb`/`collision`/`moved`/`deleted`) to its caller. It consumes `SaveStatusObserver`'s busy signal as an input to the settle gate (DC-7) but is never consulted-by / delegates-to it for the collision decision — `SaveStatusObserver` keeps its narrow download/save-error job (DC-3), so a single change yields at most one user-visible response. While an outcome is latched it stays quiescent (no second competing outcome, DC-5). Also wires `LastKnownDiskState` (T-002) into the live `MarkdownDocument` and the save bridge so a save resets last-known-disk and the detector reads the shared reference (DC-9). This task delivers detection + the absorb path (silent adoption preserving the editing mode, DC-12); the collision sheet, deletion banner, and follow-on-move surfaces attach in Wave 4.
**Inputs:** design.md C1 (detector), DC-1, DC-2, DC-3, DC-4, DC-5, DC-7, DC-9, DC-12, §Two observers, §Seam relationships; requirements BR-1, BR-2, BR-3.3, BR-10, BR-18; existing `BrowserHostController`, `MarkdownDocumentSaveBridge`, `MarkdownDocument`, `SaveStatusObserver`. Composes T-001…T-006.
**Outputs:** `Markus_v3/ExternalChange/ChangeDetector.swift` (new), last-known-disk wiring in `Markus_v3/Models/MarkdownDocument.swift` + the save bridge, detector construction in `BrowserHostController`.
**Dependencies:** T-001, T-002, T-004, T-005, T-006.
**Wave:** 3.
**Acceptance:** App compiles and launches; the walking-skeleton open→render→edit→save loop is unregressed. UI: `testCleanBufferExternalChangeIsSilent`, `testCleanAbsorbAdoptsNewContent`, `testCleanAbsorbPreservesRawMode`, `testContentIdenticalChangeIsSilentAndNonDisruptive`, `testNormalCreateTypeSaveProducesNoConflictSurfaces`, `testEditSaveLoopProducesNoConflictSheets`, `testChangeToNonOpenFileProducesNoUI` pass. `testInFlightSyncSuppressesSheet` remains an executable `XCTSkip` (busy-state fixture). The build agent confirms detection is grounded in coordinated reads, not `documentState` bits (BR-10/DC-1), and that a single change produces at most one user-visible response (DC-3).

---

## Wave 4 — User-visible surfaces & lifecycle (parallel, attach to the detector)

### T-008 — Conflict sheet (DC-14, DC-15) — three-option modal driven by `collision`
**Description:** Extend `DocumentView` to present a modal three-option conflict sheet (Keep Mine / Keep Theirs / Discard Mine, no merge) if and only if the detector (T-007) emits `collision`, driving each option through `ConflictResolution` (T-003). The sheet is gated to at most one at a time (DC-5/BR-4.4); save-back is already suspended from classification by the latch (T-006), so nothing overwrites disk while the choice is pending. A non-user (system) dismissal — backgrounding, memory-pressure teardown — never counts as a resolution (DC-15); the latched outcome survives (recovery on foreground is T-010). On resolution the sheet dismisses and editing resumes in the same mode. Accessibility identifiers `ConflictKeepMine` / `ConflictKeepTheirs` / `ConflictDiscardMine`; no `ConflictMerge`.
**Inputs:** design.md DC-14, DC-15; requirements BR-4, BR-5.3, BR-6.3, BR-7.3, BR-12; T-003, T-006, T-007; existing `DocumentView`.
**Outputs:** conflict-sheet UI in `Markus_v3/Views/DocumentView.swift` (and a small sheet view if extracted), bound to the detector's `collision` outcome.
**Dependencies:** T-003, T-006, T-007.
**Wave:** 4.
**Acceptance:** UI tests pass: `testTrueCollisionShowsThreeOptionSheet`, `testSecondCollisionDoesNotStackSheet`, `testKeepMineDismissesAndResumesRawMode`, `testKeepTheirsAdoptsExternalContent`, `testDiscardMineDismissesSheet`. `testKeepMineWritesBufferToDisk` remains an executable `XCTSkip` (on-disk read-back; logic-level `ConflictResolutionTests.keepMineWritesBuffer`).

### T-009 — Deletion banner + Save As + follow-on-move (DC-16, DC-17, DC-18, DC-19, DC-20)
**Description:** Extend the editor/host for the `deleted` and `moved` outcomes:
- **Deletion banner (DC-16/17/18):** when the detector classifies `deleted` (only after the 2s presence-disambiguation interval has passed with the file still absent — a reappearance within 2s is a `moved`, not a deletion), show a non-modal banner offering Save As. The banner does not discard the buffer; save-back to the vanished path stays suspended from classification (T-006); Save As writes the buffer to a user-chosen new location, retargets the followed location + save bridge + detector + resume reference, resets last-known-disk, and dismisses; dismissing without Save As preserves the buffer. A never-persisted deferred-write create is exempt from deletion. Identifiers `DeletionBannerSaveAs` / `DeletionBannerDismiss`.
- **Follow-on-move (DC-19/20):** when the detector classifies `moved`, retarget the followed location (subsequent saves write there, not the old path), update the displayed title (rename → `fileURL.lastPathComponent`), and update the resume reference via `LastFileStore.recordLastOpened`. A move alone shows neither sheet nor banner; a move carrying a material change against a dirty buffer is gated as a collision (handled by the classifier T-004, surfaced via T-008).
**Inputs:** design.md DC-16, DC-17, DC-18, DC-19, DC-20; requirements BR-8, BR-9, BR-16, BR-17; T-006, T-007; existing `DocumentView`, `BrowserHostController`, `LastFileStore`.
**Outputs:** deletion-banner + Save As UI in `Markus_v3/Views/DocumentView.swift`, move-retarget wiring in `BrowserHostController` / the detector + `MarkdownDocument` followed location.
**Dependencies:** T-006, T-007.
**Wave:** 4.
**Acceptance:** UI tests pass: `testRenameAloneShowsNoSheetOrBanner`, `testRenamePropagatesToTitle`, `testDeletionShowsBannerAndKeepsBuffer`, `testDeleteThenReappearWithinWindowIsMoveNoBanner`, `testDismissingBannerPreservesBuffer`. `testMoveRetargetsSaveAndResume` and `testSaveAsContinuesSessionAtNewLocation` remain executable `XCTSkip` stubs (on-disk path inspection / picker + read-back); the build agent verifies the on-disk behavior per verify.md's untestable section.

### T-010 — `ForegroundReconciler` (DC-23) + lifecycle wiring + failure-path reuse
**Description:** Close the apply-edge lifecycle guarantees and the alert-path reuse:
- **`ForegroundReconciler` (DC-23, F-003):** on app/document return to the foreground with an outcome latched (T-006) but no surface presented, reconcile against current settled disk + live buffer (reusing the equality gate T-001 / presence ordering): re-present the surface if the outcome still holds (collision still materially differs, or file still absent), or recoverably lift (collision now content-identical, or file reappeared as a move → retarget) so suspension never outlives the surface. Reconciliation is total — no third "do nothing" branch. Wire this into `DocumentView`/host scene-foreground so the conflict sheet (T-008) and deletion banner (T-009) are re-presented or lifted, and the buffer is preserved across the dismissal.
- **Failure-path reuse (BR-13/BR-14):** invalid-UTF-8 external content reuses the existing `invalidEncoding` alert (not a conflict sheet, no silent overwrite); a save-back write failure during a resolution reuses the existing `saveFailed` alert and does not falsely mark the conflict resolved.
**Inputs:** design.md DC-23, DC-15 (tightened), DC-22 bullet 4; requirements BR-13, BR-14, BR-15, BR-21; existing `ActiveAlert` (`invalidEncoding`, `saveFailed`); T-006, T-007, T-008, T-009.
**Outputs:** `Markus_v3/ExternalChange/ForegroundReconciler.swift` (new), scene-foreground reconciliation wiring + failure-path reuse in `DocumentView` / the detector.
**Dependencies:** T-006, T-007, T-008, T-009.
**Wave:** 4.
**Acceptance:** `ForegroundReconcilerTests` suite passes (all 5): `stillDivergentRePresents`, `nowIdenticalLifts`, `reappearedDeletionLifts`, `stillAbsentRePresents`, `reconciliationIsTotal`. UI tests pass: `testBackgroundingDoesNotAutoResolveSheet`, `testBufferPreservedAcrossBackgroundWithPendingSheet`, `testInvalidUtf8UsesAlertNotConflictSheet`. `testReconcileLiftsWhenDiskNowAgrees` and `testSaveFailureDuringKeepMineReusesAlert` remain executable `XCTSkip` stubs (disk-agreement-during-background / forced-failure fixtures); the build agent verifies per verify.md's untestable section.

---

## Wave summary

| Wave | Tasks | Can parallelize? |
|------|-------|-----------------|
| 1 | T-001, T-002, T-003 | Yes — T-002 uses T-001 within the wave but is a pure local compose; T-003 independent. (T-002 is sequenced after T-001 in the graph below; both land before Wave 2.) |
| 2 | T-004, T-005, T-006 | Yes — all attach to Wave-1 primitives via independent surfaces |
| 3 | T-007 | Single task (the owned detector + document-model wiring) |
| 4 | T-008, T-009, T-010 | Yes — all attach to T-007's outcome stream; T-010 reconciles the surfaces T-008/T-009 present |

**Total tasks:** 10
**Total waves:** 4

**Sizing note.** 10 tasks across 4 waves, within the 3–4 wave target and fitting one
screen. No new framework, dependency, or deploy path: `NSFileCoordinator`/`NSFileVersion`
are already in the SDK and the detector sits beside the existing save bridge under the
existing UIKit host (`resume-and-create-2`). This is a coherent depth slice (detection →
classification → concurrency integrity → surfaces), not a walking skeleton, so the task
count reflects the three apply-edge HIGH guarantees (DC-21/22/23) being first-class seams
rather than gold-plating. Not too small (well above 1–2 tasks); not too large (no split
warranted).

**Why T-006 bundles `ApplyEdgeRevalidation` and `SaveSuspensionLatch`.** Both are small
apply-edge primitives gating the *same* classify→act flow and must agree on what a latched
outcome is; the suspension latch's "system dismissal does not lift" contract is the precondition
T-010's reconciler recovers from. Splitting them would force two touches of the same flow in
the same wave for no isolation benefit.

**Why T-010 bundles the reconciler and the failure-path reuse.** Both are foreground/alert
lifecycle wiring on the same `DocumentView`/detector boundary, both are small, and the
reconciler depends on both surfaces (T-008/T-009) already existing; co-locating them keeps
the lifecycle edge a single coherent, testable session.

---

## Dependency graph

```
T-001   T-003                         ← Wave 1
  | \
  |  T-002                            ← Wave 1 (T-002 ← T-001)
  |    \
  |     \        T-005                ← Wave 2 (T-005 independent)
  |      \      /
T-004   T-006                         ← Wave 2 (T-004 ← T-001,T-002; T-006 ← T-001)
   \      |     /
    \     |    /
      T-007                           ← Wave 3 (T-007 ← T-001,T-002,T-004,T-005,T-006)
     /   |   \
    /    |    \
T-008  T-009  (T-010 ← T-008,T-009)   ← Wave 4
    \    |    /
     \   |   /
      T-010                           ← Wave 4 (reconciles T-008/T-009 surfaces)
```

More precisely:

- T-002 ← T-001
- T-004 ← T-001, T-002
- T-005 ← (none)
- T-006 ← T-001
- T-007 ← T-001, T-002, T-004, T-005, T-006
- T-008 ← T-003, T-006, T-007
- T-009 ← T-006, T-007
- T-010 ← T-006, T-007, T-008, T-009

---

## Next step

After this DAG is committed, `verify.md`'s task → test mapping is filled in (this stage),
then `/build` orchestrates the build wave-by-wave.
