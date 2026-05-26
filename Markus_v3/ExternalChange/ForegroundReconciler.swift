import Foundation

/// DC-23 (adversarial F-003) — reconcile a latched-but-surface-less outcome on
/// foreground/return.
///
/// A non-user dismissal (backgrounding, memory-pressure teardown) leaves a
/// classified `collision`/`deleted` outcome latched with no surface presented and
/// save-back suspended. On return, the outcome is re-validated against the current
/// settled disk content and the live buffer (reusing the DC-21 equality gate and
/// DC-4/DC-16 presence ordering) and exactly one of two things happens — there is
/// no third "do nothing" branch, so the {latched, surface-less, suspended} state is
/// unreachable:
///
/// - **re-present** — the outcome still holds (collision still materially differs,
///   or the file is still genuinely absent): show the surface again;
/// - **lift** — the outcome no longer holds (buffer now content-identical to disk,
///   or the file reappeared as a move): clear the latch and resume normal operation.
enum ForegroundReconciler {
    enum Decision: Equatable, Sendable {
        case rePresent
        case lift
    }

    nonisolated static func reconcile(
        latchedOutcome: ExternalChangeOutcome,
        settledDiskContent: String?,
        liveBuffer: String,
        lastKnownDisk: String,
        fileReappearedAt: URL?
    ) -> Decision {
        switch latchedOutcome {
        case .deleted:
            // Reappeared at a new location → a move; lift and retarget.
            if fileReappearedAt != nil { return .lift }
            // Still genuinely absent → re-present the deletion banner.
            if settledDiskContent == nil { return .rePresent }
            // Present again at the followed location → nothing to decide; lift.
            return .lift
        case .collision:
            guard let disk = settledDiskContent else { return .rePresent }
            // Still holds iff the live buffer still materially differs from disk.
            return ContentEqualityGate.equal(liveBuffer, disk) ? .lift : .rePresent
        case .absorb, .moved:
            return .lift
        }
    }
}
