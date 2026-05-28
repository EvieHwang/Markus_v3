# Verify — save-bridge-hardening-9

Human-readable coverage summary for the spec tests under `tests/`. Maps every requirement (BR / edge / NR) and every design constraint (DC) to the test suite(s) that verify it. Task ID labels (T-…) are added by `/dag` after the DAG is committed.

Tests live in `tests/unit/SaveBridgeHardeningTests.swift` (Swift Testing). They are per-feature reference specs, not part of the Xcode test target (per constitution.md).

## Test suites

| Suite | DCs covered | Cases |
|-------|-------------|-------|
| `WriteOutcomeBus` | DC-1, DC-2, DC-3 | 7 |
| `SaveBackGatePrecedence` | DC-4 | 3 |
| `CoordinatedWriteSeam` | DC-5, DC-6, DC-7 | 5 |
| `ScopedResourceDiscipline` | DC-8 | 3 |
| `SaveFailedAlertRouter` | DC-10, DC-11, DC-12, DC-13, DC-14, DC-15 | 10 |
| `LiftRefresh` | DC-16, DC-17, DC-18, DC-19, DC-20 | 8 |

Total: 6 suites, 37 test cases. DC-9 (no new user-visible delay on the steady-state path) is an observational property exercised by the `WriteOutcomeBus` success path and the existing external-change-5 steady-state regression — no dedicated case; it is covered by the absence of added latency in the success-path tests.

## Requirements coverage

### BR-1 — Write errors surface to the user

| Sub-ID | Verified by |
|--------|-------------|
| BR-1.1 | `WriteOutcomeBus` ("thrown write resolves as .failure") + `SaveFailedAlertRouter` ("A failure surfaces the existing saveFailed alert") |
| BR-1.2 | `SaveFailedAlertRouter` ("alert message carries the underlying error's localized description") |
| BR-1.3 | `SaveFailedAlertRouter` ("Dismiss closes the alert; no retry, no queue, no clearing of dirty") |
| BR-1.4 | `WriteOutcomeBus` ("After failure the buffer remains dirty against lastKnownDiskContent") |
| BR-1.5 | `WriteOutcomeBus` ("On failure, lastKnownDiskContent is not updated" + "settle window is not opened") |
| BR-1.6 | `WriteOutcomeBus` ("A successful write after a failure clears dirty state via the normal success path") + `SaveFailedAlertRouter` ("A success after a dismissed failure does not re-present the prior alert") |

### BR-2 — Writes are coordinated

| Sub-ID | Verified by |
|--------|-------------|
| BR-2.1 | `CoordinatedWriteSeam` ("Every write attempt enters the coordinator" + "Immediate-flush attempts are coordinated too") |
| BR-2.2 | `CoordinatedWriteSeam` ("Two writes through the same coordinator do not interleave") |
| BR-2.3 | `CoordinatedWriteSeam` ("Coordinator acquisition failure is .failure; no uncoordinated fallback") |
| BR-2.4 | `ScopedResourceDiscipline` (all three cases) |
| BR-2.5 | Observational — covered by `WriteOutcomeBus` success-path cadence and existing external-change-5 steady-state regression (see DC-9 note) |

### BR-3 — Reconciliation lift refreshes the reference

| Sub-ID | Verified by |
|--------|-------------|
| BR-3.1 | `LiftRefresh` ("Lift on content-identity refreshes lastKnownDiskContent to the settled bytes") |
| BR-3.2 | `LiftRefresh` ("After lift on identity, the next save is a no-op") |
| BR-3.3 | `LiftRefresh` ("The refresh adopts settled bytes, not a stale snapshot") |
| BR-3.4 | `LiftRefresh` ("The lift refresh never mutates the buffer") |
| BR-3.5 | `LiftRefresh` ("Lift on a moved successor refreshes lastKnownDiskContent against the new location") |
| BR-3.6 | `LiftRefresh` ("The re-present branch does NOT refresh lastKnownDiskContent") |

### Edge cases and failure modes

| ID | Verified by |
|----|-------------|
| BR-4 — backgrounded failure latch | `SaveFailedAlertRouter` ("A failure while no view is alive is latched" + "Background latch reflects the most recent failure") |
| BR-5 — rapid failures coalesce | `SaveFailedAlertRouter` ("Multiple rapid failures present at most one alert; the latest error wins") |
| BR-6 — failure then success | `SaveFailedAlertRouter` ("A success after a dismissed failure does not re-present") |
| BR-7 — coordinator timeout/contention | `CoordinatedWriteSeam` ("Coordinator acquisition failure is .failure; no uncoordinated fallback") |
| BR-8 — atomic write throws inside block | `CoordinatedWriteSeam` ("Atomic write throwing inside the coordinated block is a clean failure") |
| BR-9 — lift while typing | `LiftRefresh` ("A character typed between sample and lift is preserved") |
| BR-10 — coordinated read returns nil | `LiftRefresh` ("If the coordinated read returns nil, no lift fires and no refresh occurs") |
| BR-11 — failure during conflict sheet | `SaveFailedAlertRouter` ("Save-failed alert does not pre-empt a presented conflict sheet" + "After the conflict surface clears, a still-pending save-failed alert may surface") |
| BR-12 — saveSynchronously held to same contracts | `CoordinatedWriteSeam` ("Immediate-flush (saveSynchronously) attempts are coordinated too") + `SaveFailedAlertRouter` (background latch cases for BR-4) |

### Non-regression

| ID | Verified by |
|----|-------------|
| NR-1 — steady-state save path | `WriteOutcomeBus` ("A successful write resolves as .success" + "lastKnownDiskContent is updated and the settle window opens once") |
| NR-2 — silent absorb (clean & content-identical) | `LiftRefresh` ("Lift on content-identity refreshes…" + "lift never mutates the buffer") — exercises the absorb-shaped lift path |
| NR-3 — three-option sheet under collision | `SaveFailedAlertRouter` ("Save-failed alert does not pre-empt a presented conflict sheet") — verifies the precedence invariant that protects the sheet |
| NR-4 — DC-22 save-back gate preserved | `SaveBackGatePrecedence` (all three cases) |
| NR-5 — Keep Mine / Save As inherit BR-1 + BR-2 | `CoordinatedWriteSeam` + `SaveFailedAlertRouter` (write-path tests apply equally; routed via the same bridge entry) |
| NR-6 — re-present branch unaffected | `LiftRefresh` ("The re-present branch does NOT refresh lastKnownDiskContent") |
| NR-7 — bridge router and `SaveStatusObserver` don't double-fire | `SaveFailedAlertRouter` ("Bridge router and SaveStatusObserver do not double-fire on the same failure") |

## Design seam coverage

Every DC traces to at least one suite — see the suite table at the top. DC-9 is the one observational property without a dedicated case; it is satisfied by the success-path tests in `WriteOutcomeBus` not introducing a contention dependency.

## Task → test mapping

*To be populated by `/dag` after the DAG is committed. Each task in `dag.md` will be listed here with the suite(s)/case(s) whose acceptance condition it satisfies. Every task must map to at least one test.*
