# DAG: save-bridge-hardening-9

Save-bridge hardening: failure-as-outcome on the write path, NSFileCoordinator
wrapping (with scoped-resource and save-back-gate discipline), single-alert
routing of save failures (with background latch and conflict-sheet precedence),
and a reconciliation-lift refresh of `lastKnownDiskContent`. Four tasks,
three waves.

Generated: 2026-05-28

Drives `/build`. Wave N starts only after Wave N-1 completes. Tasks within a
wave run in parallel.

The architectural through-line: the pure outcome contract comes first
(Wave 1), with no dependency on the host alert surface or the live bridge —
"a terminal write attempt resolves to exactly one of {success, failure, gated-out},
and the two success-only side effects fire only on success." The
reconciliation-lift refresh (Wave 1) is independent of the bridge work and
extends `ChangeDetector.reconcileOnForeground()` on its own seam. Wave 2 lands
the coordinated-write wrapping inside the live `MarkdownDocumentSaveBridge`,
composing the Wave-1 outcome contract with `NSFileCoordinator`, the
security-scoped-resource discipline, and the DC-22 save-back gate (gate
precedes coordinator acquisition). Wave 3 attaches the host-side alert
router — the single-alert lifecycle, background latch, conflict-sheet
precedence, and no-double-fire with `SaveStatusObserver`.

---

## Wave 1 — Pure contracts (parallel, no host / no live-bridge dependency)

### T-001 — `WriteOutcomeBus` + success-only side-effect gating (DC-1, DC-2, DC-3)
**Description:** Add the write-outcome contract: every terminal write attempt
(debounced or immediate-flush) resolves to exactly one observable outcome —
`success`, `failure(message:)`, or the non-attempt `gatedOut` — paired with the
existing `onDidWrite` notification on the bridge. On `success`, the two
side effects fire: `MarkdownDocument.lastKnownDiskContent` advances to the
just-written bytes, and the detector's settle window opens via
`noteSaveCompleted`. On `failure`, neither side effect fires; the buffer
therefore remains dirty against `lastKnownDiskContent`, and a subsequent
successful write clears the dirty state via the normal success path. The
`gatedOut` value is a not-attempted state surfaced separately so callers can
distinguish "we never tried" from "we tried and failed" (NR-4 / DC-4). This
task delivers the bus type and the success/failure routing of the two side
effects; the actual coordinator wrapping is T-002 and the alert routing is
T-003. Pure value-level contract — no `NSFileCoordinator`, no live bridge,
no view.
**Inputs:** design.md DC-1, DC-2, DC-3; requirements BR-1.1, BR-1.4, BR-1.5,
BR-1.6, NR-1.2, NR-1.3; existing `MarkdownDocument.lastKnownDiskContent`
(read/write seam from external-change-5 T-002/T-007), existing
`ChangeDetector.noteSaveCompleted` (settle-window opener from external-change-5
T-005/T-007).
**Outputs:** new write-outcome bus type beside `MarkdownDocumentSaveBridge`
(public seam in `Markus_v3/Models/` or `Markus_v3/ExternalChange/`), with the
two side-effect hooks wired through the bus's `success` branch only. No
behavioral change to the live bridge yet (the bus is exposed; the bridge
adopts it in T-002).
**Dependencies:** none.
**Wave:** 1.
**Acceptance:** `WriteOutcomeBus` suite passes (all 7 cases):
`successResolves`, `failureResolvesWithMessage`,
`failureDoesNotRefreshLastKnownDisk`, `failureDoesNotOpenSettleWindow`,
`successFiresBothSideEffectsOnce`, `failurePreservesDirty`,
`successAfterFailureClearsDirty`.

### T-002 — `ReconciliationLiftRefresh` (DC-16, DC-17, DC-18, DC-19, DC-20)
**Description:** Extend `ChangeDetector.reconcileOnForeground()`'s lift branch
with the refresh contract: when the lift fires because the live buffer is
content-identical to settled disk under the existing equality gate (DC-11 of
external-change-5), set `MarkdownDocument.lastKnownDiskContent` to those
settled bytes before suspension is lifted — so the next save is a no-op
against disk, not a clobber of a fresher-but-equal disk state. The same
refresh property holds when the lift is taken via the moved-successor path:
`lastKnownDiskContent` matches the settled bytes at the new location. The
refresh **never** mutates the buffer (visible text, cursor, scroll preserved);
if the user types a character between sample and lift, the typed delta is
preserved and the next save writes it. The re-present branch is unaffected:
no silent refresh there, because a refresh would defeat the surfaced choice.
A nil coordinated read inside `reconcileOnForeground()` does not synthesize a
lift; the existing reconciler logic remains the authority on whether the lift
fires. Pure decision over (latched outcome, settled disk, live buffer,
last-known-disk, reappeared-at) → (branch, new last-known-disk, new buffer,
followed location). Independent of the bridge work (T-001/T-002/T-003 in
this DAG); attaches only to the existing detector seam.
**Inputs:** design.md DC-16, DC-17, DC-18, DC-19, DC-20; requirements
BR-3.1–3.6, BR-9, BR-10, NR-6; existing `ChangeDetector.reconcileOnForeground()`
(external-change-5 DC-23 lift branch), existing equality gate
(`ContentEqualityGate`, external-change-5 T-001), existing
`MarkdownDocument.lastKnownDiskContent` (external-change-5 T-002).
**Outputs:** lift-refresh logic in `Markus_v3/ExternalChange/ChangeDetector.swift`
(or a small extracted helper if natural), extending the existing
`reconcileOnForeground()` lift branch to refresh `lastKnownDiskContent` per
DC-16/17 and preserve the buffer per DC-18. No new lift path; no change to
the re-present branch.
**Dependencies:** none.
**Wave:** 1.
**Acceptance:** `LiftRefresh` suite passes (all 8 cases):
`liftOnIdentityRefreshes`, `liftMakesNextSaveNoop`,
`refreshIsSettledNotStale`, `liftNeverMutatesBuffer`,
`liftPreservesTypedDelta`, `liftOnMovedSuccessor`,
`rePresentDoesNotRefresh`, `diskReadFailureNoLift`.

---

## Wave 2 — Coordinated write wrapping on the live bridge (depends on T-001)

### T-003 — Coordinated write + save-back gate + scoped-resource discipline (DC-4, DC-5, DC-6, DC-7, DC-8, DC-9)
**Description:** Replace the live bridge's atomic-write path with a
coordinated-write block, composed with the Wave-1 outcome bus (T-001). The
DC-22 (external-change-5) `allowsSaveBack` gate is checked **before** entering
the coordinator: a gated-out attempt acquires no coordinator and records
`gatedOut` on the bus — it is neither a write attempt nor an alert source
(NR-4). When the gate allows, every write attempt — debounced and
`saveSynchronously()` — runs inside `NSFileCoordinator.coordinate(writingItemAt:)`,
mirroring the coordinated-read pattern in `ChangeDetector.coordinatedRead*`.
If the coordinator reports an acquisition error (timeout, contention), the
attempt resolves as `failure` on the bus — there is **no** uncoordinated
best-effort fallback (coordinated-or-fail is the contract). If the underlying
atomic write throws inside the coordinated block, that is a clean failure
on the bus (atomic semantics mean disk is pre-write or post-write, never
partial). The `startAccessingSecurityScopedResource` /
`stopAccessingSecurityScopedResource` pair is balanced across **both** the
success and failure paths (no leaked scoped accesses across repeated
failures). The steady-state cadence is preserved: a save that does not race
with any other coordinated work behaves indistinguishably from the
pre-hardening atomic write (no new user-visible delay).
**Inputs:** design.md DC-4, DC-5, DC-6, DC-7, DC-8, DC-9; requirements
BR-2.1–2.5, BR-7, BR-8, BR-12, NR-1.1, NR-1.4, NR-4, NR-5; existing
`MarkdownDocumentSaveBridge.writeNow()` and `saveSynchronously()`, existing
`ChangeDetector.coordinatedReadData(_:)` (pattern source), existing
`allowsSaveBack` gate from external-change-5 T-006 (`SaveSuspensionLatch`).
Composes T-001's outcome bus for `success` / `failure` / `gatedOut` routing.
**Outputs:** coordinated-write block in
`Markus_v3/Models/MarkdownDocumentSaveBridge.swift` (or wherever the bridge
lives), with the `allowsSaveBack` gate ahead of the coordinator and
balanced scoped-resource bracketing across both paths. Both `writeNow()`
and `saveSynchronously()` use the same coordinated path.
**Dependencies:** T-001.
**Wave:** 2.
**Acceptance:** `SaveBackGatePrecedence` suite passes (all 3):
`gatedOutSkipsCoordinatorAndOutcome`, `coordinatorDoesNotBypassGate`,
`gatedAttemptsResumeOnceAllowed`. `CoordinatedWriteSeam` suite passes (all 5):
`everyAttemptCoordinated`, `immediateFlushIsCoordinated`,
`coordinatorAcquisitionFailureIsClean`,
`atomicThrowInsideCoordinatedIsCleanFailure`, `twoWritesSerialize`.
`ScopedResourceDiscipline` suite passes (all 3): `successBalances`,
`failureBalances`, `repeatedFailuresDoNotLeak`. Build agent confirms
DC-9 observationally: the steady-state save cadence (typing → 500ms idle →
write → clean) is preserved with no perceptible coordination latency added
when there is no contention (covered by the success-path tests in
`WriteOutcomeBus` and the existing external-change-5 steady-state regression).

---

## Wave 3 — Host alert routing (depends on T-001 and T-003)

### T-004 — `SaveFailedAlertRouter` — single-alert lifecycle, background latch, conflict precedence, no double-fire (DC-10, DC-11, DC-12, DC-13, DC-14, DC-15)
**Description:** Wire the bridge's failure outcomes (T-001 bus, surfaced
by T-003's coordinated write) into the existing `ActiveAlert.saveFailed`
surface on `DocumentView`. A `failure` outcome presents the existing
"Couldn't save" alert with a message derived from the underlying error's
localized description; the existing dismiss action closes the alert and
performs no retry, no queue, no clearing of dirty (DC-10, BR-1.3). Multiple
rapid failures coalesce into at most one presented alert at a time; the
latest error message wins (DC-11, BR-5). A `success` outcome clears the
failure surface — a previously dismissed alert is not re-presented (DC-12,
BR-6). A failure observed while no view is alive (e.g. `saveSynchronously()`
during backgrounding) is latched on the router and presented the next time
`DocumentView` is foregrounded for the document — persistence across cold
launch is not required (DC-13, BR-4, BR-12). A presented conflict sheet or
deletion banner outranks the save-failed alert: a residual write failure
while a conflict surface is presented does **not** pre-empt the user's
pending three-option choice; the save-failed alert queues behind it and may
surface once the conflict UI clears (DC-14, BR-11). A single underlying
failure does **not** double-fire across the bridge route and the
`SaveStatusObserver` route — the single-alert `ActiveAlert` model absorbs
the duplicate, and `SaveStatusObserver` keeps its narrow `UIDocument`-state
job (DC-15, NR-7, OOS-10).
**Inputs:** design.md DC-10, DC-11, DC-12, DC-13, DC-14, DC-15; requirements
BR-1.1, BR-1.2, BR-1.3, BR-1.6, BR-4, BR-5, BR-6, BR-11, BR-12, NR-7,
OOS-4, OOS-10; existing `ActiveAlert.saveFailed` case and
`DocumentView.activeAlert` presentation (from `resume-and-create-2` /
external-change-5), existing `SaveStatusObserver` (external-change-5 DC-3 /
T-007). Composes T-001's outcome bus; consumes the failure outcomes routed
by T-003's coordinated bridge.
**Outputs:** host-side router wiring the bus's `failure` outcomes into
`ActiveAlert.saveFailed`, plus background-latch state, conflict-precedence
state, and the duplicate-absorption coordination with `SaveStatusObserver`.
Wired at the same construction site in `BrowserHostController` where
`onDidWrite` and `allowsSaveBack` are already bound. `DocumentView` exposes
the foreground-appeared hook the router consumes for DC-13.
**Dependencies:** T-001, T-003.
**Wave:** 3.
**Acceptance:** `SaveFailedAlertRouter` suite passes (all 10):
`failureSurfacesAlert`, `alertCarriesLocalizedDescription`,
`dismissDoesNothingElse`, `multipleFailuresCoalesce`,
`successClearsAlert`, `backgroundFailureIsLatched`,
`backgroundLatchLatestWins`, `conflictSheetOutranksSaveFailed`,
`saveFailedSurfacesAfterConflictResolves`,
`noDoubleFireWithSaveStatusObserver`.

---

## Wave summary

| Wave | Tasks | Can parallelize? |
|------|-------|------------------|
| 1 | T-001, T-002 | Yes — both are pure contracts; T-001 is the write-outcome bus + side-effect gating; T-002 is the reconciliation-lift refresh on a different seam. They share no surface. |
| 2 | T-003 | Single task — coordinated-write wrapping on the live bridge, composing T-001. |
| 3 | T-004 | Single task — host alert routing, composing T-001 and consuming T-003. |

**Total tasks:** 4
**Total waves:** 3

**Sizing note.** 4 tasks across 3 waves, fitting one screen, no new
framework or deploy path: `NSFileCoordinator` is already in the SDK and
already used by the existing coordinated-read pattern in
`ChangeDetector.coordinatedReadData(_:)`; the alert surface
(`ActiveAlert.saveFailed`) is reused, not invented (OOS-4). This is a
hardening of three existing seams (`MarkdownDocumentSaveBridge`,
`ChangeDetector.reconcileOnForeground()`, `ActiveAlert.saveFailed` routing),
which is exactly the depth-slice the declaration calls for — not a walking
skeleton, not a re-architecture. Above the 1–2 task "too small" threshold;
well below the 3–4 wave "too large" threshold.

**Why T-003 bundles the coordinator wrapping with the save-back gate and
scoped-resource discipline.** All three live on the same write path inside
the live bridge and must agree on the order of operations: gate first
(DC-4), then coordinator acquisition (DC-5), then balanced scoped-resource
bracketing across the atomic write (DC-8). Splitting them would force two
touches of the same `writeNow()` / `saveSynchronously()` flow with no
isolation benefit, and the bundled task is still atomic for a single
session.

**Why T-004 is separate from T-003.** The coordinated-write wrapping
(T-003) is a file-access-layer change; the alert routing (T-004) is a
conflict-and-lifecycle-UI change on `DocumentView` / `BrowserHostController`
that depends on the bus contract delivered by T-001 **and** the live
failure outcomes routed by T-003. Co-locating them would mix two shape
layers in one session and obscure the seam boundary.

---

## Dependency graph

```
T-001     T-002              ← Wave 1 (both independent)
   \
    \
     T-003                   ← Wave 2 (T-003 ← T-001)
        \
         \
          T-004              ← Wave 3 (T-004 ← T-001, T-003)
```

More precisely:

- T-001 ← (none)
- T-002 ← (none)
- T-003 ← T-001
- T-004 ← T-001, T-003

T-002 is independent of T-001/T-003/T-004 — it could in principle land in
any wave. It is placed in Wave 1 so the reconciliation-lift refresh is
available when the build agent picks up the wave-3 alert routing (which
sometimes interacts with reconciliation on foreground, even though no
T-004 test directly invokes the lift path).

---

## Next step

After this DAG is committed, `verify.md`'s task → test mapping is filled
in (this stage), then `/build` orchestrates the build wave-by-wave.
