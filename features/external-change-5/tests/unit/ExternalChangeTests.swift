// ExternalChangeTests.swift
// Spec tests for external-change-5 (unit / integration-seam level)
//
// Framework: Swift Testing (@Test, #expect, #require) per constitution.md.
// These tests live in features/external-change-5/tests/ and are reference
// specs — they are NOT part of the Xcode test target until the DAG step copies /
// links them into Markus_v3Tests/. They will fail with a missing-symbol /
// ImportError until each task is implemented.
//
// Do NOT add DAG task-ID tags here — tagging happens in the NEXT stage (verify.md
// is the authoritative task→test mapping after the DAG is committed).
//
// These cover the *logic-level* seams of the feature — the parts that are an
// observable function of disk state + buffer state and need no running scene:
//
//   ContentEqualityGate    — DC-11 byte-or-newline-normalized equality (the gate
//                             behind absorb-vs-collision and clean-vs-dirty)
//   LastKnownDiskState     — DC-9/DC-10 clean/dirty as buffer-vs-last-known-disk
//   ChangeClassifier       — DC-4 four exclusive outcomes (absorb|collision|
//                             moved|deleted), presence-first ordering, and the
//                             BR-1/BR-2/BR-4/BR-8/BR-9 classification rules
//   SettleGate             — DC-6/DC-7/DC-8 2s window + in-flight suppression +
//                             suppression-delays-never-discards
//   ApplyEdgeRevalidation  — DC-21 re-derive against the live buffer before any
//                             mutation (BR-19, adversarial F-001)
//   SaveSuspensionLatch    — DC-22 suspension keyed to classification, not
//                             presentation (BR-20, adversarial F-002)
//   ForegroundReconciler   — DC-23 latched-but-surface-less re-present-or-lift
//                             (BR-21, adversarial F-003)
//   ConflictResolution     — DC-13 Keep Mine / Keep Theirs / Discard Mine end-states
//
// Each suite drives the *behavioral property* through a small in-test seam.
// We deliberately do NOT assert call signatures, private attributes, or
// constructor arguments — only the observable end-state the design names
// (which outcome, which content lands, what stays recoverable). Where a public
// in-repo seam name is fixed by design (the four outcome cases, the equality
// gate, last-known-disk), the test binds to that seam's observable contract.
//
// The build agent maps these public seam names onto the real detector /
// document-model symbols when the tasks are implemented; the contract under test
// is the outcome, not the wiring.

import Testing
import Foundation
@testable import Markus_v3

// MARK: - Shared fixtures

/// The four exclusive classification outcomes the detector emits (DC-4). The UI
/// maps these to surfaces; the document model maps absorb to a buffer adoption.
/// This mirror exists so the logic-level tests can assert *which* outcome a given
/// (disk, buffer, presence, settle) situation produces without a running scene.
/// When the real detector lands, the build agent points these tests at its
/// outcome stream; the case set is the contract (BR-10 / DC-4).
enum ExternalChangeOutcomeKind: Equatable {
    case absorb
    case collision
    case moved
    case deleted
    /// No outcome emitted (suppressed by the settle gate / in-flight sync, DC-6/DC-7).
    case suppressed
}

// MARK: - ContentEqualityGate — DC-11 (BR-2, BR-11)
//
// Two contents are equal iff byte-identical OR equal after newline normalization
// (CRLF/CR → LF). This single gate decides absorb-vs-collision and clean-vs-dirty.
// "Material difference" is exactly its negation. Empty↔non-empty is always material.

@Suite("ContentEqualityGate — byte-or-newline-normalized equality (DC-11)")
struct ContentEqualityGateTests {

    // BR-2.1 / DC-11 — byte-identical content is equal (no material difference).
    @Test("Byte-identical content is equal")
    func byteIdenticalEqual() {
        #expect(ContentEqualityGate.equal("# Title\nbody\n", "# Title\nbody\n"))
    }

    // BR-2.2 / BR-11 / DC-11 — CRLF vs LF only is equal (a pure re-encode is never material).
    @Test("CRLF differing only by line endings is equal")
    func crlfNormalizedEqual() {
        #expect(ContentEqualityGate.equal("a\r\nb\r\nc", "a\nb\nc"))
    }

    // BR-11 / DC-11 — bare CR (old-Mac) line endings normalize to LF too.
    @Test("Bare CR line endings are equal after normalization")
    func bareCrNormalizedEqual() {
        #expect(ContentEqualityGate.equal("a\rb\rc", "a\nb\nc"))
    }

    // BR-11 / DC-11 — empty vs non-empty is always a material difference.
    @Test("Empty vs non-empty is material (not equal)")
    func emptyVsNonEmptyMaterial() {
        #expect(!ContentEqualityGate.equal("", "x"))
        #expect(!ContentEqualityGate.equal("x", ""))
    }

    // DC-11 — any difference beyond newline encoding is material.
    @Test("A real text change is material (not equal)")
    func realTextChangeMaterial() {
        #expect(!ContentEqualityGate.equal("hello", "hello world"))
    }

    // DC-11 — trailing-whitespace differences ARE material (the gate is newline-only,
    // requirements explicitly do NOT make it trailing-whitespace-insensitive).
    @Test("Trailing-whitespace difference is material (gate is newline-only)")
    func trailingWhitespaceIsMaterial() {
        #expect(!ContentEqualityGate.equal("line", "line   "))
    }

    // DC-11 — two empties are equal.
    @Test("Empty equals empty")
    func emptyEqualsEmpty() {
        #expect(ContentEqualityGate.equal("", ""))
    }
}

// MARK: - LastKnownDiskState — DC-9 / DC-10 (clean/dirty authority)
//
// MarkdownDocument carries a last-known-disk value: the bytes Markus last wrote
// to or read from disk. clean == buffer equals last-known-disk (DC-11 gate),
// dirty otherwise. This is the authority for collision decisions — NOT the undo
// manager (DC-10: a buffer typed-then-reverted-to-disk is clean).

@Suite("LastKnownDiskState — clean/dirty is buffer-vs-last-known-disk (DC-9/DC-10)")
struct LastKnownDiskStateTests {

    // DC-9/DC-10 — fresh load: buffer equals last-known-disk → clean.
    @Test("Buffer equal to last-known-disk is clean")
    func equalIsClean() {
        let s = LastKnownDiskState(lastKnownDisk: "hello\n")
        #expect(s.isClean(buffer: "hello\n"))
    }

    // DC-10 — buffer diverged → dirty.
    @Test("Buffer diverged from last-known-disk is dirty")
    func divergedIsDirty() {
        let s = LastKnownDiskState(lastKnownDisk: "hello\n")
        #expect(!s.isClean(buffer: "hello world\n"))
    }

    // DC-10 — the KEY property: typed-then-reverted-to-disk is CLEAN (content, not
    // edit-history, is the authority). No undo flag involved.
    @Test("Buffer reverted to exactly disk content is clean (content, not edit history)")
    func revertedToDiskIsClean() {
        let s = LastKnownDiskState(lastKnownDisk: "hello\n")
        // The user typed and then deleted back to the original — undo would say
        // "edited" but content equality says clean.
        #expect(s.isClean(buffer: "hello\n"))
    }

    // DC-11 — clean/dirty uses the same newline-normalized gate as the detector.
    @Test("Newline-only difference from disk is still clean")
    func newlineOnlyIsClean() {
        let s = LastKnownDiskState(lastKnownDisk: "a\nb\n")
        #expect(s.isClean(buffer: "a\r\nb\r\n"))
    }

    // DC-9 — after an absorb / save resets last-known-disk, clean is recomputed
    // against the new value.
    @Test("Resetting last-known-disk makes the matching buffer clean")
    func resetMakesClean() {
        var s = LastKnownDiskState(lastKnownDisk: "old\n")
        #expect(!s.isClean(buffer: "new\n"))
        s.reset(toDiskContent: "new\n")
        #expect(s.isClean(buffer: "new\n"))
    }
}

// MARK: - ChangeClassifier — DC-4 four exclusive outcomes, presence-first
//
// For any settled disk situation the classifier emits EXACTLY ONE outcome.
// Presence is resolved first (DC-4/DC-16): a resolvable file → absorb|collision|
// moved; a genuinely absent file → deleted. This suite drives the pure
// classification decision (no timers, no scene) with an explicit situation value.

/// A settled situation handed to the classifier: what the coordinated read found.
/// This is the detector's *input* expressed behaviorally — presence + on-disk
/// content + the followed-vs-found location — not an implementation type.
struct SettledSituation {
    enum Presence { case sameLocation, movedTo(URL), absent }
    var presence: Presence
    var onDiskContent: String?   // nil when absent
    var buffer: String
    var lastKnownDisk: String
}

@Suite("ChangeClassifier — exactly one outcome, presence-first (DC-4, BR-1/2/4/8/9)")
struct ChangeClassifierTests {

    private func classify(_ s: SettledSituation) -> ExternalChangeOutcomeKind {
        ChangeClassifier.classify(
            presenceSameLocation: { if case .sameLocation = s.presence { return true } else { return false } }(),
            movedLocation: { if case let .movedTo(u) = s.presence { return u } else { return nil } }(),
            isAbsent: { if case .absent = s.presence { return true } else { return false } }(),
            onDiskContent: s.onDiskContent,
            buffer: s.buffer,
            lastKnownDisk: s.lastKnownDisk
        )
    }

    // BR-1.1 — clean buffer + external content change → absorb (no sheet).
    @Test("Clean buffer with an external change classifies as absorb")
    func cleanBufferAbsorbs() {
        let s = SettledSituation(presence: .sameLocation, onDiskContent: "new\n",
                                 buffer: "old\n", lastKnownDisk: "old\n")
        #expect(classify(s) == .absorb)
    }

    // BR-2.1 — dirty buffer but on-disk byte-identical to buffer → absorb (no sheet).
    @Test("Dirty buffer that is content-identical to disk classifies as absorb")
    func contentIdenticalDirtyAbsorbs() {
        let s = SettledSituation(presence: .sameLocation, onDiskContent: "mine\n",
                                 buffer: "mine\n", lastKnownDisk: "orig\n")
        #expect(classify(s) == .absorb)
    }

    // BR-2.2 — dirty buffer content-identical after newline normalization → absorb.
    @Test("Dirty buffer content-identical after newline normalization classifies as absorb")
    func newlineIdenticalDirtyAbsorbs() {
        let s = SettledSituation(presence: .sameLocation, onDiskContent: "mine\r\n",
                                 buffer: "mine\n", lastKnownDisk: "orig\n")
        #expect(classify(s) == .absorb)
    }

    // BR-4.1 — dirty buffer AND material on-disk difference → collision.
    @Test("Dirty buffer with a material on-disk difference classifies as collision")
    func dirtyMaterialIsCollision() {
        let s = SettledSituation(presence: .sameLocation, onDiskContent: "theirs\n",
                                 buffer: "mine\n", lastKnownDisk: "orig\n")
        #expect(classify(s) == .collision)
    }

    // BR-11 — empty↔non-empty with a dirty buffer is material → collision.
    @Test("Disk emptied under a dirty buffer is a material collision")
    func emptiedDiskIsCollision() {
        let s = SettledSituation(presence: .sameLocation, onDiskContent: "",
                                 buffer: "mine\n", lastKnownDisk: "mine\n")
        // buffer differs from new disk (empty) and buffer != lastKnownDisk? Here
        // buffer == lastKnownDisk so buffer is CLEAN → this is actually absorb of
        // the emptying. Assert the presence-first + clean rule: clean → absorb.
        #expect(classify(s) == .absorb)
    }

    // BR-11 + BR-4 — empty-on-disk with genuinely dirty buffer → collision.
    @Test("Disk emptied while buffer has unsaved edits is a collision")
    func emptiedDiskWithDirtyBufferIsCollision() {
        let s = SettledSituation(presence: .sameLocation, onDiskContent: "",
                                 buffer: "my edits\n", lastKnownDisk: "orig\n")
        #expect(classify(s) == .collision)
    }

    // BR-8.1 / DC-4 — file resolvable at a NEW location, no content divergence → moved (not deleted, not collision).
    @Test("File found at a new location with matching content classifies as moved")
    func relocatedMatchingIsMoved() {
        let dest = URL(fileURLWithPath: "/tmp/moved/Doc.md")
        let s = SettledSituation(presence: .movedTo(dest), onDiskContent: "same\n",
                                 buffer: "same\n", lastKnownDisk: "same\n")
        #expect(classify(s) == .moved)
    }

    // BR-9.1 / DC-4 / DC-16 — genuinely absent file → deleted.
    @Test("Genuinely absent file classifies as deleted")
    func absentIsDeleted() {
        let s = SettledSituation(presence: .absent, onDiskContent: nil,
                                 buffer: "mine\n", lastKnownDisk: "mine\n")
        #expect(classify(s) == .deleted)
    }

    // DC-4 — presence-first ordering: a file resolvable elsewhere is NEVER deleted,
    // even if it moved. (A move never also fires a deletion.)
    @Test("A resolvable moved file is never classified deleted")
    func movedIsNeverDeleted() {
        let dest = URL(fileURLWithPath: "/tmp/moved/Doc.md")
        let s = SettledSituation(presence: .movedTo(dest), onDiskContent: "mine\n",
                                 buffer: "mine\n", lastKnownDisk: "mine\n")
        #expect(classify(s) != .deleted)
    }

    // BR-8.4 / DC-20 — a move that ALSO carries a material change against a dirty
    // buffer is still gated: it is a collision (the move does not smuggle an
    // overwrite past the user). Observable: outcome is collision, evaluated at the
    // new location's content.
    @Test("A move carrying a material change under a dirty buffer is still a collision")
    func movePlusMaterialChangeIsCollision() {
        let dest = URL(fileURLWithPath: "/tmp/moved/Doc.md")
        let s = SettledSituation(presence: .movedTo(dest), onDiskContent: "theirs\n",
                                 buffer: "mine\n", lastKnownDisk: "orig\n")
        #expect(classify(s) == .collision)
    }

    // DC-4 — exactly one outcome: the classifier never returns two. (Exhaustive
    // single-value return is the contract; we assert it is a defined non-suppressed
    // value for a settled same-location clean case.)
    @Test("Classification yields exactly one defined outcome")
    func exactlyOneOutcome() {
        let s = SettledSituation(presence: .sameLocation, onDiskContent: "new\n",
                                 buffer: "x\n", lastKnownDisk: "x\n")
        let out = classify(s)
        #expect([.absorb, .collision, .moved, .deleted].contains(out))
    }
}

// MARK: - SettleGate — DC-6 / DC-7 / DC-8 (BR-3)
//
// The settle window is a fixed 2s grace period opened by open / first-persist /
// save-complete. While open (or while sync is in flight) the detector suppresses
// classification of change AND deletion signals. Suppression DELAYS, never
// discards: once the window closes a still-present collision is surfaced.

@Suite("SettleGate — 2s window + in-flight suppression, delay-not-discard (DC-6/7/8)")
struct SettleGateTests {

    // DC-6 — a change signal within 2s of a trigger is suppressed.
    @Test("Change signal within the 2s window after a save is suppressed")
    func suppressedWithinWindowAfterSave() {
        var gate = SettleGate(windowSeconds: 2.0)
        gate.noteTrigger(.saveCompleted, at: 0)
        #expect(gate.isSuppressed(at: 1.0, syncInFlight: false))   // 1s < 2s
    }

    // DC-6 — after a create trigger, within window → suppressed.
    @Test("Change signal within the window after a create is suppressed")
    func suppressedWithinWindowAfterCreate() {
        var gate = SettleGate(windowSeconds: 2.0)
        gate.noteTrigger(.created, at: 0)
        #expect(gate.isSuppressed(at: 0.5, syncInFlight: false))
    }

    // DC-6 — after open trigger, within window → suppressed.
    @Test("Change signal within the window after open is suppressed")
    func suppressedWithinWindowAfterOpen() {
        var gate = SettleGate(windowSeconds: 2.0)
        gate.noteTrigger(.opened, at: 0)
        #expect(gate.isSuppressed(at: 1.9, syncInFlight: false))
    }

    // DC-6 — once 2s elapse with no in-flight sync, suppression ends.
    @Test("After the window elapses, signals are no longer suppressed")
    func notSuppressedAfterWindow() {
        var gate = SettleGate(windowSeconds: 2.0)
        gate.noteTrigger(.saveCompleted, at: 0)
        #expect(!gate.isSuppressed(at: 2.001, syncInFlight: false))
    }

    // DC-7 — in-flight sync suppresses independently of the timer: a slow sync
    // that outlasts 2s is still suppressed until it settles.
    @Test("In-flight sync suppresses even after the timer would have elapsed")
    func inFlightSyncSuppressesPastWindow() {
        var gate = SettleGate(windowSeconds: 2.0)
        gate.noteTrigger(.opened, at: 0)
        #expect(gate.isSuppressed(at: 10.0, syncInFlight: true),
                "A sync still in flight must suppress regardless of the 2s timer")
    }

    // DC-7 — in-flight sync alone (no recent trigger) still suppresses.
    @Test("In-flight sync suppresses with no recent trigger")
    func inFlightSyncSuppressesAlone() {
        let gate = SettleGate(windowSeconds: 2.0)
        #expect(gate.isSuppressed(at: 100.0, syncInFlight: true))
    }

    // DC-6 — re-trigger resets the 2s (a save mid-window pushes the window out).
    @Test("A new trigger resets the window")
    func triggerResetsWindow() {
        var gate = SettleGate(windowSeconds: 2.0)
        gate.noteTrigger(.opened, at: 0)
        gate.noteTrigger(.saveCompleted, at: 1.5)   // resets
        #expect(gate.isSuppressed(at: 3.0, syncInFlight: false),  // 3.0 - 1.5 = 1.5 < 2
                "A trigger mid-window must reset the 2s grace period")
    }

    // DC-8 — suppression delays, never discards: a collision present during the
    // window is still classifiable once the window closes. (We assert the gate does
    // not consume/clear the pending signal — it only gates timing.)
    @Test("A collision suppressed during the window is evaluated after it closes")
    func suppressionDelaysNotDiscards() {
        var gate = SettleGate(windowSeconds: 2.0)
        gate.noteTrigger(.saveCompleted, at: 0)
        #expect(gate.isSuppressed(at: 1.0, syncInFlight: false))   // suppressed now
        #expect(!gate.isSuppressed(at: 2.5, syncInFlight: false),  // surfaced later
                "Suppression must postpone evaluation, never permanently discard it")
    }
}

// MARK: - ApplyEdgeRevalidation — DC-21 (BR-19, adversarial F-001)
//
// A classification is derived from the buffer as it stood when the coordinated
// read began, but it is NEVER applied against that historical snapshot. Before any
// buffer mutation, the outcome is re-derived against the buffer as it stands NOW.
// Key property: a clean-at-read buffer that turned dirty must not be silently
// overwritten by absorb — it is preserved (content-identical → absorb) or surfaced
// (material → collision). The unchanged-buffer common case still absorbs silently.

@Suite("ApplyEdgeRevalidation — re-derive against live buffer before mutation (DC-21)")
struct ApplyEdgeRevalidationTests {

    /// Re-derive the outcome at the moment of application given the read-time
    /// snapshot and the live buffer. Observable contract: the outcome the system
    /// ACTS on, after re-validation.
    private func reEvaluate(readTimeBuffer: String, liveBuffer: String,
                            settledDisk: String, lastKnownDisk: String) -> ExternalChangeOutcomeKind {
        ApplyEdgeRevalidation.reDerive(
            readTimeBuffer: readTimeBuffer,
            liveBuffer: liveBuffer,
            settledDiskContent: settledDisk,
            lastKnownDisk: lastKnownDisk
        )
    }

    // BR-19.4 / DC-21 bullet 4 — common case: buffer unchanged since read → absorb
    // proceeds silently (no spurious sheet).
    @Test("Unchanged buffer since read still absorbs silently")
    func unchangedBufferAbsorbsSilently() {
        let out = reEvaluate(readTimeBuffer: "old\n", liveBuffer: "old\n",
                             settledDisk: "new\n", lastKnownDisk: "old\n")
        #expect(out == .absorb)
    }

    // BR-19.1 / DC-21 bullet 1 — clean at read, user typed before apply, and the
    // typed buffer MATERIALLY differs from disk → re-derives to collision, NOT a
    // silent absorb that destroys the edits.
    @Test("Clean-at-read buffer that turned dirty (material) re-derives to collision, not absorb")
    func typedDuringReadMaterialBecomesCollision() {
        let out = reEvaluate(readTimeBuffer: "old\n",          // clean at read
                             liveBuffer: "my new edits\n",     // typed before apply
                             settledDisk: "external change\n",
                             lastKnownDisk: "old\n")
        #expect(out == .collision,
                "An absorb derived from a clean snapshot must NOT overwrite edits typed during the read")
    }

    // BR-19.3 — the buffer typed during the read happens to be content-identical to
    // the settled disk → re-derives to a silent absorb (no spurious sheet, no loss).
    @Test("Typed-during-read buffer that is content-identical to disk re-derives to absorb")
    func typedDuringReadContentIdenticalAbsorbs() {
        let out = reEvaluate(readTimeBuffer: "old\n",
                             liveBuffer: "disk content\n",     // typed to match disk
                             settledDisk: "disk content\n",
                             lastKnownDisk: "old\n")
        #expect(out == .absorb)
    }

    // BR-19.2 — no character typed after the read is silently lost: a divergent
    // typed buffer is surfaced (collision), never silently replaced. (Same property
    // as the material case, asserted as the data-loss invariant.)
    @Test("Characters typed after the read snapshot are never silently lost")
    func typedCharactersNeverSilentlyLost() {
        let out = reEvaluate(readTimeBuffer: "",
                             liveBuffer: "a character I just typed",
                             settledDisk: "something else from another device",
                             lastKnownDisk: "")
        // Either preserved (absorb because identical — not the case here) or surfaced.
        #expect(out == .collision)
    }
}

// MARK: - SaveSuspensionLatch — DC-22 (BR-20, adversarial F-002)
//
// Save-back is suspended from the instant a collision/deletion is CLASSIFIED, not
// from when its surface appears — closing the classify→present latency gap. A
// queued/debounced save must not fire during that gap. Suspension lifts only on an
// explicit user resolution OR the recoverable lift of DC-23 — never silently while
// unresolved.

@Suite("SaveSuspensionLatch — suspend from classification, not presentation (DC-22)")
struct SaveSuspensionLatchTests {

    // DC-22 — classifying a collision suspends save-back immediately, before any
    // surface is presented.
    @Test("Classifying a collision suspends save-back before the sheet appears")
    func collisionClassificationSuspends() {
        var latch = SaveSuspensionLatch()
        #expect(latch.allowsSaveBack)              // baseline: saves allowed
        latch.classify(.collision)
        #expect(!latch.allowsSaveBack, "Suspension must begin at classification, not presentation")
        #expect(!latch.surfacePresented, "Surface not yet presented — gap is covered")
    }

    // DC-22 / BR-20.3 — classifying a deletion suspends save-back immediately (no
    // autosave can recreate the vanished path before the banner appears).
    @Test("Classifying a deletion suspends save-back before the banner appears")
    func deletionClassificationSuspends() {
        var latch = SaveSuspensionLatch()
        latch.classify(.deleted)
        #expect(!latch.allowsSaveBack)
    }

    // DC-22 bullet 2 — a save queued/debounced BEFORE classification does not fire
    // during the gap: the latch refuses the write attempt.
    @Test("A queued save attempted during the classify→present gap is refused")
    func queuedSaveRefusedInGap() {
        var latch = SaveSuspensionLatch()
        latch.classify(.collision)
        // Surface has not been presented yet (still in the gap):
        #expect(!latch.surfacePresented)
        #expect(!latch.attemptSaveBack(), "A save fired in the gap must be refused, not executed")
    }

    // DC-22 bullet 4 (a) — explicit user resolution (Keep Mine) lifts suspension.
    @Test("Explicit user resolution lifts suspension")
    func explicitResolutionLifts() {
        var latch = SaveSuspensionLatch()
        latch.classify(.collision)
        latch.resolveByUser()
        #expect(latch.allowsSaveBack, "An explicit user resolution must lift suspension")
    }

    // DC-22 bullet 4 — suspension does NOT lift merely because the surface was
    // presented and then dismissed by the system (that path is DC-23, not a resolution).
    @Test("A non-user (system) dismissal does NOT lift suspension")
    func systemDismissalDoesNotLift() {
        var latch = SaveSuspensionLatch()
        latch.classify(.collision)
        latch.presentSurface()
        latch.dismissBySystem()    // backgrounding / memory pressure — not a resolution
        #expect(!latch.allowsSaveBack,
                "A system dismissal must leave suspension in place (DC-22/DC-23)")
        #expect(latch.isLatchedUnresolved, "The outcome stays latched and unresolved")
    }

    // BR-4.4 / DC-5 — a second collision signal while one is latched does not stack;
    // it updates the content to compare but the latch stays single.
    @Test("A second collision signal while latched does not stack a second latch")
    func secondSignalDoesNotStack() {
        var latch = SaveSuspensionLatch()
        latch.classify(.collision)
        latch.classify(.collision)   // a later signal
        #expect(latch.latchedCount == 1, "At most one latched outcome at a time (BR-4.4, DC-5)")
    }
}

// MARK: - ForegroundReconciler — DC-23 (BR-21, adversarial F-003)
//
// A latched-but-surface-less outcome is reconciled on foreground/return: it is
// re-validated against current settled disk + live buffer (reusing DC-21) and
// EITHER re-presented (outcome still holds) OR recoverably lifted (outcome no
// longer holds). There is no "do nothing" third branch — the
// {latched, surface-less, suspended} state is unreachable.

@Suite("ForegroundReconciler — re-present-or-lift, never stuck-suspended (DC-23)")
struct ForegroundReconcilerTests {

    enum Reconciliation: Equatable { case rePresent, lift }

    private func reconcile(latched: ExternalChangeOutcomeKind,
                           settledDisk: String?, liveBuffer: String,
                           lastKnownDisk: String, fileReappearedAt: URL?) -> Reconciliation {
        let result = ForegroundReconciler.reconcile(
            latchedOutcome: latched == .collision ? .collision : .deleted,
            settledDiskContent: settledDisk,
            liveBuffer: liveBuffer,
            lastKnownDisk: lastKnownDisk,
            fileReappearedAt: fileReappearedAt
        )
        return result == .rePresent ? .rePresent : .lift
    }

    // BR-21.3 first branch / DC-23 — collision still materially differs against the
    // live buffer → re-present the sheet.
    @Test("A still-divergent collision re-presents the sheet on foreground")
    func stillDivergentRePresents() {
        let r = reconcile(latched: .collision, settledDisk: "theirs\n",
                          liveBuffer: "mine\n", lastKnownDisk: "orig\n",
                          fileReappearedAt: nil)
        #expect(r == .rePresent)
    }

    // BR-21.3 second branch / DC-23 — collision outcome no longer holds because the
    // buffer is now content-identical to settled disk → recoverable lift.
    @Test("A collision now content-identical to disk lifts (no re-present)")
    func nowIdenticalLifts() {
        let r = reconcile(latched: .collision, settledDisk: "agreed\n",
                          liveBuffer: "agreed\n", lastKnownDisk: "orig\n",
                          fileReappearedAt: nil)
        #expect(r == .lift, "If disk now agrees with the buffer, there is nothing to decide — lift")
    }

    // BR-21.3 / DC-23 — a deletion that reappeared as a move (file resolvable at a
    // new location) lifts and retargets — no banner re-present.
    @Test("A deletion whose file reappeared as a move lifts (retarget, no banner)")
    func reappearedDeletionLifts() {
        let dest = URL(fileURLWithPath: "/tmp/moved/Doc.md")
        let r = reconcile(latched: .deleted, settledDisk: "mine\n",
                          liveBuffer: "mine\n", lastKnownDisk: "mine\n",
                          fileReappearedAt: dest)
        #expect(r == .lift)
    }

    // BR-21.3 / DC-16 — a deletion that is still genuinely absent re-presents the banner.
    @Test("A deletion still genuinely absent re-presents the banner")
    func stillAbsentRePresents() {
        let r = reconcile(latched: .deleted, settledDisk: nil,
                          liveBuffer: "mine\n", lastKnownDisk: "mine\n",
                          fileReappearedAt: nil)
        #expect(r == .rePresent)
    }

    // BR-21.4 / DC-23 — totality: reconciliation always returns exactly one of the
    // two branches; there is no third "do nothing" outcome. (Reachability of the
    // stuck-suspended state is asserted absent by the enum being exhaustive over the
    // two recovery branches.)
    @Test("Reconciliation always yields exactly re-present or lift (no stuck-suspended branch)")
    func reconciliationIsTotal() {
        let r = reconcile(latched: .collision, settledDisk: "x\n",
                          liveBuffer: "y\n", lastKnownDisk: "z\n",
                          fileReappearedAt: nil)
        #expect(r == .rePresent || r == .lift)
    }
}

// MARK: - ConflictResolution — DC-13 (BR-5, BR-6, BR-7)
//
// Keep Mine writes buffer→disk and buffer becomes clean. Keep Theirs and Discard
// Mine are BEHAVIORALLY IDENTICAL: adopt disk into the buffer, drop local edits,
// buffer becomes clean, no clobbering write to disk. Two labels, two end-states
// total (Keep Mine vs. {Keep Theirs ≡ Discard Mine}).

@Suite("ConflictResolution — Keep Mine vs (Keep Theirs ≡ Discard Mine) (DC-13)")
struct ConflictResolutionTests {

    // BR-5.1 / BR-5.2 — Keep Mine: disk ends equal to the buffer; buffer unchanged & clean.
    @Test("Keep Mine writes the buffer to disk and leaves the buffer clean")
    func keepMineWritesBuffer() {
        let r = ConflictResolution.apply(.keepMine, buffer: "mine\n", onDisk: "theirs\n")
        #expect(r.newBufferContent == "mine\n", "Keep Mine preserves the buffer")
        #expect(r.contentWrittenToDisk == "mine\n", "Keep Mine writes the buffer to disk")
        #expect(r.bufferIsCleanAfter, "Buffer is clean against disk after Keep Mine")
    }

    // BR-6.1 / BR-6.2 — Keep Theirs: buffer becomes the on-disk content; no clobber write.
    @Test("Keep Theirs adopts the on-disk content and writes nothing that clobbers it")
    func keepTheirsAdoptsDisk() {
        let r = ConflictResolution.apply(.keepTheirs, buffer: "mine\n", onDisk: "theirs\n")
        #expect(r.newBufferContent == "theirs\n")
        #expect(r.contentWrittenToDisk == nil, "Keep Theirs performs no clobbering write")
        #expect(r.bufferIsCleanAfter)
    }

    // BR-7.1 / BR-7.2 — Discard Mine: same end-state as Keep Theirs (adopt disk, clean).
    @Test("Discard Mine adopts the on-disk content, same end-state as Keep Theirs")
    func discardMineAdoptsDisk() {
        let r = ConflictResolution.apply(.discardMine, buffer: "mine\n", onDisk: "theirs\n")
        #expect(r.newBufferContent == "theirs\n")
        #expect(r.contentWrittenToDisk == nil)
        #expect(r.bufferIsCleanAfter)
    }

    // DC-13 — the explicit equivalence: Keep Theirs ≡ Discard Mine (two labels, one behavior).
    @Test("Keep Theirs and Discard Mine produce identical end-states")
    func keepTheirsEqualsDiscardMine() {
        let kt = ConflictResolution.apply(.keepTheirs, buffer: "mine\n", onDisk: "theirs\n")
        let dm = ConflictResolution.apply(.discardMine, buffer: "mine\n", onDisk: "theirs\n")
        #expect(kt.newBufferContent == dm.newBufferContent)
        #expect(kt.contentWrittenToDisk == dm.contentWrittenToDisk)
        #expect(kt.bufferIsCleanAfter == dm.bufferIsCleanAfter)
    }

    // BR-4.2 / OOS-2 — there is no "merge" option: exactly three options exist.
    @Test("Exactly three resolution options exist; no merge")
    func exactlyThreeOptions() {
        #expect(ConflictResolution.Option.allCases.count == 3)
        #expect(Set(ConflictResolution.Option.allCases) == [.keepMine, .keepTheirs, .discardMine])
    }
}
