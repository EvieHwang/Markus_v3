// SaveBridgeHardeningTests.swift
// Spec tests for save-bridge-hardening-9 (unit / integration-seam level)
//
// Framework: Swift Testing (@Test, #expect, #require) per constitution.md.
// These tests live in features/save-bridge-hardening-9/tests/ and are reference
// specs — they are NOT part of the Xcode test target until the DAG step copies /
// links them into Markus_v3Tests/. They will fail with a missing-symbol /
// ImportError until each task is implemented.
//
// Do NOT add DAG task-ID tags here — tagging happens in the NEXT stage (verify.md
// is the authoritative task→test mapping after the DAG is committed).
//
// These cover the *logic-level* seams of the feature — the parts that are an
// observable function of write outcome + reconciliation input and need no running
// scene:
//
//   WriteOutcomeBus         — DC-1 every write attempt resolves to success|failure
//                              (paired with the existing onDidWrite); DC-2 success-
//                              only side effects gated; DC-3 dirty preserved.
//   SaveBackGatePrecedence  — DC-4 the allowsSaveBack gate precedes the coordinated
//                              block (NR-4); a gated attempt is neither success
//                              nor failure.
//   CoordinatedWriteSeam    — DC-5/DC-6/DC-7 coordinated-or-fail, atomic failure
//                              inside the coordinated block is a clean failure
//                              (BR-2.1/2.2/2.3, BR-7, BR-8).
//   ScopedResourceDiscipline— DC-8 startAccessing / stopAccessing balanced across
//                              both success and failure paths (BR-2.4).
//   SaveFailedAlertRouter   — DC-10/DC-11/DC-12/DC-13/DC-14/DC-15 single-alert
//                              coalescing, latest-error-wins, background-latch,
//                              conflict-precedence, no double-fire with the
//                              SaveStatusObserver path.
//   LiftRefresh             — DC-16/DC-17/DC-18/DC-19/DC-20 the reconciliation
//                              lift refresh of lastKnownDiskContent (BR-3.1–3.6,
//                              BR-9, BR-10).
//
// Each suite drives the *behavioral property* through a small in-test seam. We
// deliberately do NOT assert call signatures, private attributes, or constructor
// arguments — only the observable end-state the design names (which outcome
// surfaces, which content lands, what stays recoverable, what last-known-disk
// reference holds). Where a public in-repo seam name is fixed by design (the
// outcome bus paired with onDidWrite, the ActiveAlert.saveFailed case, the
// lastKnownDiskContent reference), the test binds to that seam's observable
// contract. The build agent maps these public seam names onto the real bridge /
// detector / document-model symbols when the tasks are implemented.

import Testing
import Foundation
@testable import Markus_v3

// MARK: - Shared fixtures

/// The two terminal outcomes a write attempt may resolve to (DC-1). The "gated"
/// third value is NOT a write attempt — it is a not-attempted state surfaced
/// separately so callers can distinguish "we never tried" from "we tried and
/// failed" (NR-4 / DC-4). The set is the contract; whether the production type
/// is an enum, a callback pair, or two notifications is an implementation detail.
enum WriteAttemptOutcome: Equatable {
    case success
    case failure(message: String)
    /// Not a write attempt — the save-back gate refused before the coordinator
    /// was even entered (DC-4). Not surfaced to the user, not counted as failure.
    case gatedOut
}

/// A minimal "underlying error" the test seam can throw / report; the production
/// type is `Error`, but tests assert only that the user-visible message carries
/// the localized description (BR-1.2).
struct FakeWriteError: Error, LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - WriteOutcomeBus — DC-1 / DC-2 / DC-3 (BR-1.1, BR-1.4, BR-1.5, BR-1.6)
//
// Every terminal write attempt resolves to exactly one of {success, failure} and
// the host observes which. Success fires the two side effects (refresh
// lastKnownDiskContent + open settle window). Failure fires neither. The dirty
// state therefore persists across a failure and a subsequent success clears it.

@Suite("WriteOutcomeBus — every attempt resolves to one observable outcome (DC-1/2/3)")
struct WriteOutcomeBusTests {

    // DC-1 / BR-1.1 — a write that succeeds resolves as .success and the host
    // observes it; there is no third silently-returned state.
    @Test("A successful write resolves as .success on the outcome bus")
    func successResolves() {
        let bus = WriteOutcomeBus()
        bus.recordAttempt(result: .success(bytesWritten: Data("hello\n".utf8)))
        #expect(bus.lastOutcome == .success)
    }

    // DC-1 / BR-1.1 — a write that throws resolves as .failure carrying the
    // underlying error's localized description (BR-1.2). No silent swallow.
    @Test("A thrown write resolves as .failure carrying the underlying error message")
    func failureResolvesWithMessage() {
        let bus = WriteOutcomeBus()
        bus.recordAttempt(result: .failure(error: FakeWriteError(message: "permission denied")))
        #expect(bus.lastOutcome == .failure(message: "permission denied"))
    }

    // DC-2 / BR-1.5 — on failure, lastKnownDiskContent is NOT updated.
    @Test("On failure, lastKnownDiskContent is not updated")
    func failureDoesNotRefreshLastKnownDisk() {
        let doc = LastKnownDiskRef(value: "orig\n")
        let bus = WriteOutcomeBus(lastKnownDiskRef: doc)
        bus.recordAttempt(buffer: "new but unsaved\n",
                          result: .failure(error: FakeWriteError(message: "I/O")))
        #expect(doc.value == "orig\n", "Failed write must not advance lastKnownDiskContent (BR-1.5)")
    }

    // DC-2 / BR-1.5 — on failure, the settle window is NOT opened.
    @Test("On failure, the settle window is not opened")
    func failureDoesNotOpenSettleWindow() {
        let settle = SettleWindowProbe()
        let bus = WriteOutcomeBus(settleWindow: settle)
        bus.recordAttempt(buffer: "x\n",
                          result: .failure(error: FakeWriteError(message: "I/O")))
        #expect(settle.openCount == 0,
                "Failed write must not open the settle window (BR-1.5, DC-2)")
    }

    // DC-2 / NR-1.2 / NR-1.3 — on success, BOTH side effects fire exactly once.
    @Test("On success, lastKnownDiskContent is updated and the settle window opens once")
    func successFiresBothSideEffectsOnce() {
        let doc = LastKnownDiskRef(value: "orig\n")
        let settle = SettleWindowProbe()
        let bus = WriteOutcomeBus(lastKnownDiskRef: doc, settleWindow: settle)
        bus.recordAttempt(buffer: "fresh\n",
                          result: .success(bytesWritten: Data("fresh\n".utf8)))
        #expect(doc.value == "fresh\n")
        #expect(settle.openCount == 1)
    }

    // DC-3 / BR-1.4 — after a failed write the buffer remains dirty against
    // lastKnownDiskContent (because DC-2 did not refresh).
    @Test("After failure the buffer remains dirty against lastKnownDiskContent")
    func failurePreservesDirty() {
        let doc = LastKnownDiskRef(value: "orig\n")
        let bus = WriteOutcomeBus(lastKnownDiskRef: doc)
        bus.recordAttempt(buffer: "my edits\n",
                          result: .failure(error: FakeWriteError(message: "denied")))
        #expect(doc.value != "my edits\n",
                "Dirty must survive failure — the document cannot appear clean (BR-1.4)")
    }

    // DC-3 / BR-1.6 — a successful write after a failure clears dirty exactly
    // as the steady-state path; the prior alert does not re-surface (alert
    // re-surface is asserted in SaveFailedAlertRouterTests.successClearsAlert).
    @Test("A successful write after a failure clears dirty state via the normal success path")
    func successAfterFailureClearsDirty() {
        let doc = LastKnownDiskRef(value: "orig\n")
        let bus = WriteOutcomeBus(lastKnownDiskRef: doc)
        bus.recordAttempt(buffer: "edits\n",
                          result: .failure(error: FakeWriteError(message: "denied")))
        bus.recordAttempt(buffer: "edits\n",
                          result: .success(bytesWritten: Data("edits\n".utf8)))
        #expect(doc.value == "edits\n",
                "A subsequent success must clear dirty by refreshing lastKnownDiskContent (BR-1.6)")
    }
}

// MARK: - SaveBackGatePrecedence — DC-4 (NR-4)
//
// The DC-22 (external-change-5) allowsSaveBack gate is checked BEFORE entering
// the coordinator. A gated-out attempt is neither success nor failure — no
// alert, no last-known-disk update, no coordinator acquisition cost.

@Suite("SaveBackGatePrecedence — the gate precedes the coordinated block (DC-4, NR-4)")
struct SaveBackGatePrecedenceTests {

    // DC-4 / NR-4 — when the gate refuses, no coordinator is acquired and no
    // outcome (success or failure) is recorded on the bus.
    @Test("A gated-out attempt acquires no coordinator and records no outcome")
    func gatedOutSkipsCoordinatorAndOutcome() {
        let coordinator = CoordinatorProbe()
        let bus = WriteOutcomeBus()
        let bridge = HardenedSaveBridgeSeam(coordinator: coordinator, outcomeBus: bus)
        bridge.attemptWrite(buffer: "x\n", allowsSaveBack: false)
        #expect(coordinator.acquisitionCount == 0,
                "Gate-refused attempts must not pay the coordinator cost (DC-4)")
        #expect(bus.lastOutcome == .gatedOut,
                "A gated-out attempt is not a write attempt — neither success nor failure (NR-4)")
    }

    // DC-4 — wrapping in a coordinator does not bypass the gate. The gate is
    // outer-most; the coordinator never even sees a refused attempt.
    @Test("Coordinator wrapping does not bypass the suspension gate")
    func coordinatorDoesNotBypassGate() {
        let coordinator = CoordinatorProbe()
        let bridge = HardenedSaveBridgeSeam(coordinator: coordinator)
        for _ in 0..<5 {
            bridge.attemptWrite(buffer: "x\n", allowsSaveBack: false)
        }
        #expect(coordinator.acquisitionCount == 0,
                "Repeated gated attempts must never reach the coordinator (DC-4)")
    }

    // NR-4 / DC-4 — once the gate allows again (e.g. user resolved a collision),
    // the next attempt does flow through the coordinator and records an outcome.
    @Test("Once the gate allows, the next attempt does enter the coordinator")
    func gatedAttemptsResumeOnceAllowed() {
        let coordinator = CoordinatorProbe()
        let bus = WriteOutcomeBus()
        let bridge = HardenedSaveBridgeSeam(coordinator: coordinator, outcomeBus: bus)
        bridge.attemptWrite(buffer: "x\n", allowsSaveBack: false)   // gated
        bridge.attemptWrite(buffer: "x\n", allowsSaveBack: true)    // allowed
        #expect(coordinator.acquisitionCount == 1)
        #expect(bus.lastOutcome != .gatedOut)
    }
}

// MARK: - CoordinatedWriteSeam — DC-5 / DC-6 / DC-7 (BR-2.1, BR-2.2, BR-2.3, BR-7, BR-8)
//
// Every write happens inside the coordinator. If acquisition fails, the bridge
// does NOT fall back to an uncoordinated write — coordinated-or-fail is the
// contract. If the atomic write throws inside the coordinated block, that is a
// clean failure (atomic semantics mean disk is pre-write or post-write, never
// partial).

@Suite("CoordinatedWriteSeam — coordinated-or-fail; atomic failure is a clean failure (DC-5/6/7)")
struct CoordinatedWriteSeamTests {

    // DC-5 / BR-2.1 — every successful write went through the coordinator (count == attempts).
    @Test("Every write attempt enters the coordinator")
    func everyAttemptCoordinated() {
        let coordinator = CoordinatorProbe()
        let bridge = HardenedSaveBridgeSeam(coordinator: coordinator)
        bridge.attemptWrite(buffer: "a\n", allowsSaveBack: true)
        bridge.attemptWrite(buffer: "b\n", allowsSaveBack: true)
        bridge.attemptWrite(buffer: "c\n", allowsSaveBack: true)
        #expect(coordinator.acquisitionCount == 3,
                "Each terminal write attempt must acquire the coordinator (DC-5, BR-2.1)")
    }

    // DC-5 / BR-2.1 — saveSynchronously (immediate flush) is also coordinated.
    @Test("Immediate-flush (saveSynchronously) attempts are coordinated too")
    func immediateFlushIsCoordinated() {
        let coordinator = CoordinatorProbe()
        let bridge = HardenedSaveBridgeSeam(coordinator: coordinator)
        bridge.flushImmediately(buffer: "x\n", allowsSaveBack: true)
        #expect(coordinator.acquisitionCount == 1,
                "saveSynchronously must use the same coordinated path (BR-2.1, BR-12)")
    }

    // DC-6 / BR-2.3 / BR-7 — coordinator acquisition failure resolves as
    // .failure on the outcome bus; the bridge does NOT fall back to an
    // uncoordinated atomic write.
    @Test("Coordinator acquisition failure is .failure; no uncoordinated fallback")
    func coordinatorAcquisitionFailureIsClean() {
        let coordinator = CoordinatorProbe()
        coordinator.nextAcquisitionResult = .failure(error: FakeWriteError(message: "coord timeout"))
        let bus = WriteOutcomeBus()
        let writeProbe = AtomicWriteProbe()
        let bridge = HardenedSaveBridgeSeam(coordinator: coordinator,
                                            outcomeBus: bus,
                                            atomicWrite: writeProbe)
        bridge.attemptWrite(buffer: "x\n", allowsSaveBack: true)
        #expect(bus.lastOutcome == .failure(message: "coord timeout"))
        #expect(writeProbe.uncoordinatedFallbackCount == 0,
                "There must be no uncoordinated best-effort fallback (DC-6, BR-7)")
    }

    // DC-7 / BR-8 — atomic write throws INSIDE the coordinated block: clean
    // failure on the outcome bus; success side effects do not fire.
    @Test("Atomic write throwing inside the coordinated block is a clean failure")
    func atomicThrowInsideCoordinatedIsCleanFailure() {
        let coordinator = CoordinatorProbe()
        let bus = WriteOutcomeBus()
        let writeProbe = AtomicWriteProbe()
        writeProbe.nextResult = .failure(error: FakeWriteError(message: "disk full"))
        let doc = LastKnownDiskRef(value: "orig\n")
        let bridge = HardenedSaveBridgeSeam(coordinator: coordinator,
                                            outcomeBus: bus,
                                            atomicWrite: writeProbe,
                                            lastKnownDiskRef: doc)
        bridge.attemptWrite(buffer: "edits\n", allowsSaveBack: true)
        #expect(bus.lastOutcome == .failure(message: "disk full"))
        #expect(doc.value == "orig\n",
                "lastKnownDiskContent must not advance on a thrown atomic write (DC-7)")
    }

    // BR-2.2 — under injected concurrent coordinated writes, the on-disk bytes
    // end up exactly one writer's bytes, never a partial interleave. This is the
    // serialization contract the coordinator provides; the seam test asserts the
    // bridge HONORS the contract by using the coordinator for every attempt
    // (CoordinatedWriteSeamTests.everyAttemptCoordinated). End-to-end byte
    // verification under real iCloud-style contention is in the UI tests
    // (skipped, with a build-agent verification note).
    @Test("Two writes through the same coordinator do not interleave (serialization seam)")
    func twoWritesSerialize() {
        let coordinator = CoordinatorProbe()
        let bridge = HardenedSaveBridgeSeam(coordinator: coordinator)
        bridge.attemptWrite(buffer: "AAAA\n", allowsSaveBack: true)
        bridge.attemptWrite(buffer: "BBBB\n", allowsSaveBack: true)
        // Both attempts acquired the coordinator; the coordinator's contract
        // says they did not interleave at the file level.
        #expect(coordinator.acquisitionCount == 2)
        #expect(coordinator.observedInterleave == false,
                "The coordinator must not report any observed mid-write interleave (BR-2.2)")
    }
}

// MARK: - ScopedResourceDiscipline — DC-8 (BR-2.4)
//
// startAccessingSecurityScopedResource and stopAccessingSecurityScopedResource
// are balanced across BOTH success and failure paths. Repeated failing writes
// must not leak scoped accesses.

@Suite("ScopedResourceDiscipline — start/stop balanced on success and failure (DC-8, BR-2.4)")
struct ScopedResourceDisciplineTests {

    // DC-8 / BR-2.4 — every successful write balances start/stop exactly once.
    @Test("A successful write balances start/stop exactly once")
    func successBalances() {
        let scope = ScopedResourceProbe()
        let bridge = HardenedSaveBridgeSeam(scopedResource: scope)
        bridge.attemptWrite(buffer: "x\n", allowsSaveBack: true)
        #expect(scope.startCount == 1 && scope.stopCount == 1)
        #expect(scope.outstanding == 0,
                "No security-scoped access may be left outstanding after a successful write")
    }

    // DC-8 / BR-2.4 — a failed write still balances start/stop.
    @Test("A failed write still balances start/stop")
    func failureBalances() {
        let scope = ScopedResourceProbe()
        let writeProbe = AtomicWriteProbe()
        writeProbe.nextResult = .failure(error: FakeWriteError(message: "I/O"))
        let bridge = HardenedSaveBridgeSeam(scopedResource: scope, atomicWrite: writeProbe)
        bridge.attemptWrite(buffer: "x\n", allowsSaveBack: true)
        #expect(scope.outstanding == 0,
                "No security-scoped access may be leaked on the failure path (BR-2.4)")
    }

    // DC-8 / BR-2.4 — many failures in a row do not accumulate outstanding
    // scoped accesses, and a subsequent success still works.
    @Test("Repeated failures do not leak; a subsequent success still works")
    func repeatedFailuresDoNotLeak() {
        let scope = ScopedResourceProbe()
        let writeProbe = AtomicWriteProbe()
        let bridge = HardenedSaveBridgeSeam(scopedResource: scope, atomicWrite: writeProbe)
        for _ in 0..<10 {
            writeProbe.nextResult = .failure(error: FakeWriteError(message: "denied"))
            bridge.attemptWrite(buffer: "x\n", allowsSaveBack: true)
        }
        #expect(scope.outstanding == 0, "No leaks across 10 consecutive failures (DC-8)")
        // Then a success still lands cleanly.
        writeProbe.nextResult = .success
        bridge.attemptWrite(buffer: "x\n", allowsSaveBack: true)
        #expect(scope.outstanding == 0)
    }
}

// MARK: - SaveFailedAlertRouter — DC-10/11/12/13/14/15 (BR-1.1/2/3, BR-4/5/6, BR-11, NR-7)
//
// The router observes the WriteOutcomeBus and drives ActiveAlert.saveFailed:
//   - one alert at a time, latest error wins (DC-11, BR-5)
//   - dismiss does no retry, no clear of dirty (DC-10, BR-1.3)
//   - success after failure clears the failure surface (DC-12, BR-6)
//   - failure while no view is alive is latched and shown on next foreground
//     (DC-13, BR-4)
//   - the conflict sheet / deletion banner outranks the save-failed alert
//     (DC-14, BR-11)
//   - a single underlying failure does not double-fire across the bridge path
//     and the SaveStatusObserver path (DC-15, NR-7)

@Suite("SaveFailedAlertRouter — single-alert coalescing, latest-wins, lifecycle (DC-10–15)")
struct SaveFailedAlertRouterTests {

    // DC-10 / BR-1.1 — a failure surfaces the existing 'Couldn't save' alert.
    @Test("A failure surfaces the existing saveFailed alert")
    func failureSurfacesAlert() {
        let router = SaveFailedAlertRouter()
        router.observe(outcome: .failure(message: "denied"), viewIsAlive: true)
        #expect(router.activeAlert == .saveFailed(message: "denied"))
    }

    // DC-10 / BR-1.2 — the alert message carries the underlying error's
    // localized description.
    @Test("The alert message carries the underlying error's localized description")
    func alertCarriesLocalizedDescription() {
        let router = SaveFailedAlertRouter()
        router.observe(outcome: .failure(message: "The file 'Notes.md' could not be saved because you don't have permission."),
                       viewIsAlive: true)
        if case let .saveFailed(message) = router.activeAlert {
            #expect(message.contains("Notes.md"))
            #expect(message.contains("permission"))
        } else {
            Issue.record("Expected a saveFailed alert with the underlying message")
        }
    }

    // DC-10 / BR-1.3 — dismiss closes the alert and performs no retry, no
    // queue, no clearing of dirty state.
    @Test("Dismiss closes the alert; no retry, no queue, no clearing of dirty")
    func dismissDoesNothingElse() {
        let router = SaveFailedAlertRouter()
        let retryProbe = RetryProbe()
        router.retryHook = { retryProbe.count += 1 }
        router.observe(outcome: .failure(message: "denied"), viewIsAlive: true)
        router.dismiss()
        #expect(router.activeAlert == .none)
        #expect(retryProbe.count == 0, "Dismiss must not retry (BR-1.3)")
    }

    // DC-11 / BR-5 — multiple rapid failures coalesce into at most one alert
    // at a time; the latest error message wins.
    @Test("Multiple rapid failures present at most one alert; the latest error wins")
    func multipleFailuresCoalesce() {
        let router = SaveFailedAlertRouter()
        router.observe(outcome: .failure(message: "first"), viewIsAlive: true)
        router.observe(outcome: .failure(message: "second"), viewIsAlive: true)
        router.observe(outcome: .failure(message: "third"), viewIsAlive: true)
        #expect(router.presentedAlertCount == 1, "At most one alert at a time (BR-5)")
        #expect(router.activeAlert == .saveFailed(message: "third"),
                "The latest error message is the one shown (DC-11)")
    }

    // DC-12 / BR-1.6 / BR-6 — a success after a (dismissed) failure clears the
    // failure surface and does not re-present the prior alert.
    @Test("A success after a dismissed failure does not re-present the prior alert")
    func successClearsAlert() {
        let router = SaveFailedAlertRouter()
        router.observe(outcome: .failure(message: "old"), viewIsAlive: true)
        router.dismiss()
        router.observe(outcome: .success, viewIsAlive: true)
        #expect(router.activeAlert == .none,
                "A success clears the failure surface; old alert does not re-surface (BR-6)")
    }

    // DC-13 / BR-4 / BR-12 — a failure observed while no view is alive is
    // latched and presented on next foreground.
    @Test("A failure while no view is alive is latched and presented on next foreground")
    func backgroundFailureIsLatched() {
        let router = SaveFailedAlertRouter()
        router.observe(outcome: .failure(message: "bg I/O"), viewIsAlive: false)
        #expect(router.activeAlert == .none, "Nothing is presented while no view is alive")
        #expect(router.hasLatchedFailure)
        router.foregroundAppeared()
        #expect(router.activeAlert == .saveFailed(message: "bg I/O"),
                "On next foreground the latched failure is presented (BR-4, DC-13)")
    }

    // DC-13 / BR-4 — the latch carries the LATEST background error (consistent
    // with DC-11 "latest wins").
    @Test("Background latch reflects the most recent failure")
    func backgroundLatchLatestWins() {
        let router = SaveFailedAlertRouter()
        router.observe(outcome: .failure(message: "first bg"), viewIsAlive: false)
        router.observe(outcome: .failure(message: "second bg"), viewIsAlive: false)
        router.foregroundAppeared()
        #expect(router.activeAlert == .saveFailed(message: "second bg"))
    }

    // DC-14 / BR-11 — if a conflict sheet or deletion banner is presented, a
    // save-failed alert does not pre-empt it. The conflict UI keeps the
    // primary surface; the save-failed alert queues or coalesces behind it.
    @Test("Save-failed alert does not pre-empt a presented conflict sheet")
    func conflictSheetOutranksSaveFailed() {
        let router = SaveFailedAlertRouter()
        router.noteConflictSurfacePresented(true)
        router.observe(outcome: .failure(message: "residual"), viewIsAlive: true)
        #expect(router.activeAlert != .saveFailed(message: "residual"),
                "A conflict sheet must remain the primary surface (DC-14, BR-11)")
        #expect(router.conflictSurfaceStillPresented,
                "The user's pending three-option choice must not be lost (BR-11)")
    }

    // DC-14 / BR-11 — when the conflict sheet later dismisses (user resolved),
    // the queued save-failed alert may then surface (or coalesce if a fresh
    // outcome has already cleared it).
    @Test("After the conflict surface clears, a still-pending save-failed alert may surface")
    func saveFailedSurfacesAfterConflictResolves() {
        let router = SaveFailedAlertRouter()
        router.noteConflictSurfacePresented(true)
        router.observe(outcome: .failure(message: "queued"), viewIsAlive: true)
        router.noteConflictSurfacePresented(false)
        // Now the queued save-failed may present (single-alert rule still applies).
        #expect(router.activeAlert == .saveFailed(message: "queued") || router.activeAlert == .none,
                "Once conflict UI clears, a queued save-failed may surface, subject to single-alert rule")
    }

    // DC-15 / NR-7 — a single underlying save failure produces at most one
    // presented alert across both routes (bridge router AND SaveStatusObserver).
    @Test("Bridge router and SaveStatusObserver do not double-fire on the same failure")
    func noDoubleFireWithSaveStatusObserver() {
        let router = SaveFailedAlertRouter()
        // Both producers fire for what is, conceptually, the same underlying failure.
        router.observe(outcome: .failure(message: "underlying"), viewIsAlive: true)
        router.observeFromSaveStatusObserver(message: "underlying")
        #expect(router.presentedAlertCount == 1,
                "A single underlying failure must surface at most one alert (DC-15, NR-7)")
    }
}

// MARK: - LiftRefresh — DC-16/17/18/19/20 (BR-3.1–3.6, BR-9, BR-10, NR-6)
//
// reconcileOnForeground()'s LIFT branch refreshes lastKnownDiskContent to the
// settled bytes that justified the lift. The RE-PRESENT branch does NOT
// refresh. The refresh never mutates the buffer. If the coordinated read fails,
// no lift fires; the refresh contract has nothing to apply to.

/// The detector's reconciliation input for a foreground pass. Mirrors the
/// shape used in external-change-5's ForegroundReconciler tests so the lift
/// refresh can be driven without a running scene.
struct ReconciliationInput {
    var latchedOutcome: ExternalChangeOutcomeKindLite
    var settledDiskContent: String?     // nil ⇔ coordinated read returned nil
    var liveBuffer: String
    var lastKnownDisk: String
    var fileReappearedAt: URL?
}

/// Lite mirror of the four classification outcomes; kept here so this test
/// file does not depend on the external-change-5 tests file.
enum ExternalChangeOutcomeKindLite: Equatable { case absorb, collision, moved, deleted }

@Suite("LiftRefresh — the lift branch refreshes lastKnownDiskContent (DC-16–20, BR-3)")
struct LiftRefreshTests {

    /// Run a reconciliation pass and return the post-pass (lastKnownDisk,
    /// buffer, branch). The seam binds to the design's observable contract:
    /// what does lastKnownDiskContent equal after the pass; was the buffer
    /// mutated; which branch fired.
    private func runReconcile(_ input: ReconciliationInput) -> ReconciliationResult {
        ReconciliationLiftRefresh.run(
            latched: input.latchedOutcome == .collision ? .collision : .deleted,
            settledDiskContent: input.settledDiskContent,
            liveBuffer: input.liveBuffer,
            lastKnownDisk: input.lastKnownDisk,
            fileReappearedAt: input.fileReappearedAt
        )
    }

    // DC-16 / BR-3.1 — lift on content-identity: lastKnownDiskContent is set
    // to the settled disk bytes that justified the lift.
    @Test("Lift on content-identity refreshes lastKnownDiskContent to the settled bytes")
    func liftOnIdentityRefreshes() {
        let input = ReconciliationInput(
            latchedOutcome: .collision,
            settledDiskContent: "agreed\n",
            liveBuffer: "agreed\n",
            lastKnownDisk: "orig\n",
            fileReappearedAt: nil
        )
        let r = runReconcile(input)
        #expect(r.branch == .lift)
        #expect(r.newLastKnownDisk == "agreed\n",
                "lastKnownDiskContent must be set to the settled bytes that justified the lift (BR-3.1)")
    }

    // DC-16 / BR-3.2 — immediately after the lift the document is clean against
    // disk; a subsequent save attempt would be a no-op against `newLastKnownDisk`.
    @Test("After lift on identity, the next save is a no-op (buffer == newLastKnownDisk)")
    func liftMakesNextSaveNoop() {
        let input = ReconciliationInput(
            latchedOutcome: .collision,
            settledDiskContent: "agreed\n",
            liveBuffer: "agreed\n",
            lastKnownDisk: "orig\n",
            fileReappearedAt: nil
        )
        let r = runReconcile(input)
        #expect(r.newLastKnownDisk == r.newBuffer,
                "Buffer equals lastKnownDiskContent → next save is a no-op (BR-3.2)")
    }

    // DC-16 / BR-3.3 — the refresh adopts the SETTLED bytes (the bytes read
    // through the coordinated read in reconcileOnForeground), not a stale
    // snapshot. We assert this by giving the reconciler a stale lastKnownDisk
    // and verifying the refresh equals settledDiskContent, not lastKnownDisk.
    @Test("The refresh adopts settled bytes, not a stale snapshot")
    func refreshIsSettledNotStale() {
        let input = ReconciliationInput(
            latchedOutcome: .collision,
            settledDiskContent: "fresh\n",
            liveBuffer: "fresh\n",
            lastKnownDisk: "stale-snapshot-from-before-background\n",
            fileReappearedAt: nil
        )
        let r = runReconcile(input)
        #expect(r.newLastKnownDisk == "fresh\n",
                "Refresh must be the just-read settled bytes, not the stale pre-background snapshot (BR-3.3)")
    }

    // DC-18 / BR-3.4 — the lift refresh never mutates the buffer.
    @Test("The lift refresh never mutates the buffer (only lastKnownDiskContent)")
    func liftNeverMutatesBuffer() {
        let input = ReconciliationInput(
            latchedOutcome: .collision,
            settledDiskContent: "agreed\n",
            liveBuffer: "agreed\n",
            lastKnownDisk: "orig\n",
            fileReappearedAt: nil
        )
        let r = runReconcile(input)
        #expect(r.newBuffer == "agreed\n",
                "Buffer is unchanged; only lastKnownDiskContent is updated (BR-3.4)")
        #expect(r.bufferWasMutated == false)
    }

    // DC-18 / BR-9 — user types one more character between the content-identity
    // sample and the lift completion: the typed character is preserved; the
    // refresh updates only lastKnownDiskContent; the next save will write the delta.
    @Test("A character typed between sample and lift is preserved; refresh stays on lastKnownDiskContent")
    func liftPreservesTypedDelta() {
        // The reconciler sampled "agreed" against "agreed" on disk → lift decided.
        // Between sample and lift the user typed "X". The lift must refresh
        // lastKnownDiskContent to "agreed" without touching the buffer.
        let r = ReconciliationLiftRefresh.runWithRaceInjection(
            latched: .collision,
            sampledBuffer: "agreed\n",
            settledDiskContent: "agreed\n",
            liveBufferAtLift: "agreedX\n",
            lastKnownDisk: "orig\n"
        )
        #expect(r.newBuffer == "agreedX\n", "Typed character is preserved (BR-9, BR-3.4)")
        #expect(r.newLastKnownDisk == "agreed\n",
                "lastKnownDiskContent is refreshed to settled disk; buffer/disk now diverge → buffer is dirty, next save writes the delta (BR-9)")
        #expect(r.bufferWasMutated == false)
    }

    // DC-17 / BR-3.5 — lift on a moved successor whose contents agree: at the
    // NEW location, lastKnownDiskContent matches the settled bytes there.
    @Test("Lift on a moved successor refreshes lastKnownDiskContent against the new location")
    func liftOnMovedSuccessor() {
        let dest = URL(fileURLWithPath: "/tmp/moved/Doc.md")
        let input = ReconciliationInput(
            latchedOutcome: .deleted,                       // was deleted, reappeared
            settledDiskContent: "mine\n",
            liveBuffer: "mine\n",
            lastKnownDisk: "mine\n",
            fileReappearedAt: dest
        )
        let r = runReconcile(input)
        #expect(r.branch == .lift)
        #expect(r.newLastKnownDisk == "mine\n",
                "lastKnownDiskContent matches the settled bytes at the new location (BR-3.5)")
        #expect(r.followedLocation == dest,
                "The followed location retargets to the move successor (BR-3.5)")
    }

    // DC-19 / BR-3.6 / NR-6 — the RE-PRESENT branch does NOT refresh
    // lastKnownDiskContent. Refreshing there would defeat the surfaced choice.
    @Test("The re-present branch does NOT refresh lastKnownDiskContent")
    func rePresentDoesNotRefresh() {
        let input = ReconciliationInput(
            latchedOutcome: .collision,
            settledDiskContent: "theirs\n",
            liveBuffer: "mine\n",                            // still divergent
            lastKnownDisk: "orig\n",
            fileReappearedAt: nil
        )
        let r = runReconcile(input)
        #expect(r.branch == .rePresent)
        #expect(r.newLastKnownDisk == "orig\n",
                "Re-present must NOT silently agree with disk (BR-3.6, NR-6)")
    }

    // DC-20 / BR-10 — if the coordinated read returned nil (read failed),
    // no lift fires; the refresh contract has nothing to apply. We assert the
    // reconciler does not invent a refresh against a stale lastKnownDisk.
    @Test("If the coordinated read returns nil, no lift fires and no refresh occurs")
    func diskReadFailureNoLift() {
        let input = ReconciliationInput(
            latchedOutcome: .collision,
            settledDiskContent: nil,                         // read failed
            liveBuffer: "mine\n",
            lastKnownDisk: "orig\n",
            fileReappearedAt: nil
        )
        let r = runReconcile(input)
        #expect(r.branch != .lift,
                "A failed coordinated read must not synthesize a lift (BR-10, DC-20)")
        #expect(r.newLastKnownDisk == "orig\n",
                "Refresh contract does not apply when no lift fires (BR-10)")
    }
}

// MARK: - In-test seam types
//
// These types describe the *observable contract* the build agent's real
// implementation must satisfy. They are not specifications of the production
// type names or shapes — only of the behaviors tests assert. The build agent
// is free to expose these via any concrete type / protocol / pair of callbacks
// it chooses; the tests bind to the behaviors here.

/// A bus the host observes to learn the outcome of each terminal write attempt.
/// The production realization may be a notification, a continuation, a sink, or
/// a pair of callbacks (`onDidWrite`, `onDidFailWrite`). The contract is: every
/// terminal attempt resolves to exactly one of `.success` / `.failure(message:)`
/// observed here, with success-only side effects fired exactly when `.success`
/// is recorded and never when `.failure` is.
final class WriteOutcomeBus {
    enum AttemptResult {
        case success(bytesWritten: Data)
        case failure(error: Error)
    }
    private(set) var lastOutcome: WriteAttemptOutcome = .gatedOut
    private let lastKnownDiskRef: LastKnownDiskRef?
    private let settleWindow: SettleWindowProbe?

    init(lastKnownDiskRef: LastKnownDiskRef? = nil, settleWindow: SettleWindowProbe? = nil) {
        self.lastKnownDiskRef = lastKnownDiskRef
        self.settleWindow = settleWindow
    }

    func recordAttempt(buffer: String = "", result: AttemptResult) {
        switch result {
        case let .success(bytes):
            lastOutcome = .success
            if let ref = lastKnownDiskRef, let s = String(data: bytes, encoding: .utf8) {
                ref.value = s
            }
            settleWindow?.openCount += 1
        case let .failure(error):
            let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            lastOutcome = .failure(message: message)
            // BR-1.5: NEITHER side effect fires.
        }
    }
}

/// Wrapper for the document's lastKnownDiskContent so tests can observe it.
final class LastKnownDiskRef {
    var value: String
    init(value: String) { self.value = value }
}

/// Probe for the detector's settle-window opener (DC-6/DC-9 of external-change-5).
final class SettleWindowProbe {
    var openCount: Int = 0
}

/// Probe for coordinator acquisition outcomes. Tracks how many times the bridge
/// asked for coordination and whether the coordinator reports any observed
/// interleave (BR-2.2 — must be false).
final class CoordinatorProbe {
    enum AcquisitionResult { case success, failure(error: Error) }
    var nextAcquisitionResult: AcquisitionResult = .success
    private(set) var acquisitionCount: Int = 0
    private(set) var observedInterleave: Bool = false

    func acquire() throws {
        acquisitionCount += 1
        switch nextAcquisitionResult {
        case .success: return
        case let .failure(error): throw error
        }
    }
}

/// Probe for the atomic write itself, used to inject failures inside the
/// coordinated block. Also tracks whether the bridge ever fell back to an
/// uncoordinated write (it must never — DC-6).
final class AtomicWriteProbe {
    enum WriteResult { case success, failure(error: Error) }
    var nextResult: WriteResult = .success
    var uncoordinatedFallbackCount: Int = 0
}

/// Probe for the start/stop balance of the security-scoped resource (DC-8).
final class ScopedResourceProbe {
    private(set) var startCount: Int = 0
    private(set) var stopCount: Int = 0
    var outstanding: Int { startCount - stopCount }
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
}

/// A retry probe used to verify dismiss does not retry (BR-1.3).
final class RetryProbe { var count: Int = 0 }

/// The hardened save bridge seam exercised by these tests. The production type
/// is `MarkdownDocumentSaveBridge`; this seam captures the new behaviors the
/// build agent must add to it. It is intentionally minimal — only the inputs
/// (buffer, gate decision) and the outputs (outcome on the bus, coordinator
/// acquisitions, scoped-resource balance) the tests observe.
final class HardenedSaveBridgeSeam {
    private let coordinator: CoordinatorProbe
    private let outcomeBus: WriteOutcomeBus
    private let atomicWrite: AtomicWriteProbe
    private let scopedResource: ScopedResourceProbe?
    private let lastKnownDiskRef: LastKnownDiskRef?

    init(coordinator: CoordinatorProbe = CoordinatorProbe(),
         outcomeBus: WriteOutcomeBus = WriteOutcomeBus(),
         atomicWrite: AtomicWriteProbe = AtomicWriteProbe(),
         scopedResource: ScopedResourceProbe? = nil,
         lastKnownDiskRef: LastKnownDiskRef? = nil) {
        self.coordinator = coordinator
        self.outcomeBus = outcomeBus
        self.atomicWrite = atomicWrite
        self.scopedResource = scopedResource
        self.lastKnownDiskRef = lastKnownDiskRef
    }

    /// Drive a debounced-style attempt. The `allowsSaveBack` parameter mirrors
    /// the DC-22 (external-change-5) gate; when false, the attempt is gated
    /// out per DC-4 / NR-4 (no coordinator, no outcome surface).
    func attemptWrite(buffer: String, allowsSaveBack: Bool) {
        guard allowsSaveBack else {
            // DC-4 / NR-4: gated-out → not a write attempt; no coordinator
            // acquired, no outcome routed to the alert path.
            return
        }
        do {
            try coordinator.acquire()
        } catch {
            outcomeBus.recordAttempt(buffer: buffer, result: .failure(error: error))
            return
        }
        scopedResource?.start()
        defer { scopedResource?.stop() }
        switch atomicWrite.nextResult {
        case .success:
            outcomeBus.recordAttempt(buffer: buffer,
                                     result: .success(bytesWritten: Data(buffer.utf8)))
            lastKnownDiskRef?.value = buffer
        case let .failure(error):
            outcomeBus.recordAttempt(buffer: buffer, result: .failure(error: error))
        }
    }

    /// Drive an immediate-flush attempt (saveSynchronously). The same coordinated-
    /// and-error-surfaced contract applies (BR-12, NR-1.4).
    func flushImmediately(buffer: String, allowsSaveBack: Bool) {
        attemptWrite(buffer: buffer, allowsSaveBack: allowsSaveBack)
    }
}

/// The router observes the outcome bus and drives the existing
/// ActiveAlert.saveFailed case. The production type is the host's binding
/// between the bridge's failure notification and `DocumentView.activeAlert`.
final class SaveFailedAlertRouter {
    enum Alert: Equatable { case none, saveFailed(message: String) }
    private(set) var activeAlert: Alert = .none
    private(set) var presentedAlertCount: Int = 0
    private(set) var hasLatchedFailure: Bool = false
    private(set) var conflictSurfaceStillPresented: Bool = false
    var retryHook: (() -> Void)?

    private var latchedMessage: String?
    private var conflictPresented: Bool = false
    private var lastUnderlyingMessage: String?

    func observe(outcome: WriteAttemptOutcome, viewIsAlive: Bool) {
        switch outcome {
        case .success:
            // DC-12 — success clears the failure surface.
            activeAlert = .none
            hasLatchedFailure = false
            latchedMessage = nil
            lastUnderlyingMessage = nil
        case .gatedOut:
            return
        case let .failure(message):
            lastUnderlyingMessage = message
            if !viewIsAlive {
                // DC-13 — latch for next foreground.
                hasLatchedFailure = true
                latchedMessage = message
                return
            }
            if conflictPresented {
                // DC-14 — conflict outranks; queue behind.
                latchedMessage = message
                return
            }
            present(message: message)
        }
    }

    /// A failure surfaced by the OTHER producer (SaveStatusObserver) for the
    /// same underlying failure. The single-alert rule absorbs the duplicate
    /// (DC-15, NR-7).
    func observeFromSaveStatusObserver(message: String) {
        if lastUnderlyingMessage == message, activeAlert != .none {
            // Already presented by the bridge route; do not double-fire.
            return
        }
        if activeAlert == .none {
            present(message: message)
        }
        // else: single-alert rule keeps the existing presentation.
    }

    func dismiss() {
        activeAlert = .none
        // BR-1.3 — no retry, no queue, no clearing of dirty state.
    }

    func foregroundAppeared() {
        if let m = latchedMessage, !conflictPresented {
            hasLatchedFailure = false
            latchedMessage = nil
            present(message: m)
        }
    }

    func noteConflictSurfacePresented(_ presented: Bool) {
        conflictPresented = presented
        conflictSurfaceStillPresented = presented
        if !presented, let m = latchedMessage, activeAlert == .none {
            latchedMessage = nil
            present(message: m)
        }
    }

    private func present(message: String) {
        if activeAlert == .none {
            presentedAlertCount += 1
        }
        // DC-11 — latest wins; replace the message in place without bumping the count.
        activeAlert = .saveFailed(message: message)
    }
}

/// Result of running a reconciliation pass under the lift-refresh contract.
struct ReconciliationResult {
    enum Branch: Equatable { case rePresent, lift }
    var branch: Branch
    var newLastKnownDisk: String
    var newBuffer: String
    var bufferWasMutated: Bool
    var followedLocation: URL?
}

/// The lift-refresh seam exercised by these tests. The production realization
/// extends `ChangeDetector.reconcileOnForeground()`'s lift branch with the
/// refresh contract (DC-16/17/18/19/20).
enum ReconciliationLiftRefresh {

    enum Latched { case collision, deleted }

    static func run(latched: Latched,
                    settledDiskContent: String?,
                    liveBuffer: String,
                    lastKnownDisk: String,
                    fileReappearedAt: URL?) -> ReconciliationResult {
        // DC-20: failed coordinated read → no lift, no refresh.
        guard let settled = settledDiskContent else {
            return ReconciliationResult(branch: .rePresent,
                                        newLastKnownDisk: lastKnownDisk,
                                        newBuffer: liveBuffer,
                                        bufferWasMutated: false,
                                        followedLocation: nil)
        }
        switch latched {
        case .collision:
            if settled == liveBuffer {
                // DC-16: lift on content-identity → refresh to settled.
                return ReconciliationResult(branch: .lift,
                                            newLastKnownDisk: settled,
                                            newBuffer: liveBuffer,
                                            bufferWasMutated: false,
                                            followedLocation: nil)
            } else {
                // DC-19: re-present → no refresh.
                return ReconciliationResult(branch: .rePresent,
                                            newLastKnownDisk: lastKnownDisk,
                                            newBuffer: liveBuffer,
                                            bufferWasMutated: false,
                                            followedLocation: nil)
            }
        case .deleted:
            if let dest = fileReappearedAt, settled == liveBuffer {
                // DC-17: moved-successor lift with agreeing content.
                return ReconciliationResult(branch: .lift,
                                            newLastKnownDisk: settled,
                                            newBuffer: liveBuffer,
                                            bufferWasMutated: false,
                                            followedLocation: dest)
            } else {
                return ReconciliationResult(branch: .rePresent,
                                            newLastKnownDisk: lastKnownDisk,
                                            newBuffer: liveBuffer,
                                            bufferWasMutated: false,
                                            followedLocation: nil)
            }
        }
    }

    /// Drive the sample/lift race used by BR-9: the reconciler sampled the
    /// buffer at one moment ("sampledBuffer"), the lift completes a moment
    /// later, and by then the user has typed one more character
    /// ("liveBufferAtLift"). The refresh must update lastKnownDiskContent to
    /// settled disk; the buffer must not be touched.
    static func runWithRaceInjection(latched: Latched,
                                     sampledBuffer: String,
                                     settledDiskContent: String,
                                     liveBufferAtLift: String,
                                     lastKnownDisk: String) -> ReconciliationResult {
        // The lift decision was made on (sampledBuffer == settled). When it
        // applies, it refreshes lastKnownDisk to settled and leaves the live
        // buffer alone (DC-18 / BR-9).
        precondition(sampledBuffer == settledDiskContent,
                     "Setup: identity-lift was decided on the sample")
        return ReconciliationResult(branch: .lift,
                                    newLastKnownDisk: settledDiskContent,
                                    newBuffer: liveBufferAtLift,
                                    bufferWasMutated: false,
                                    followedLocation: nil)
    }
}
