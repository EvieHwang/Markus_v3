import Foundation

/// DC-21 (adversarial F-001) — re-derive the outcome against the *live* buffer
/// before any mutation.
///
/// A classification is derived from the buffer as it stood when the coordinated
/// read began, but it is never applied against that historical snapshot. Before any
/// buffer mutation, the outcome is re-derived against the buffer as it stands now: a
/// clean-at-read buffer that turned dirty does not run the silent absorb — it
/// re-derives to `absorb` only if content-identical to settled disk, else
/// `collision`. An unchanged buffer still absorbs silently (no spurious sheet). No
/// character typed after the read is ever silently lost.
enum ApplyEdgeRevalidation {
    nonisolated static func reDerive(
        readTimeBuffer: String,
        liveBuffer: String,
        settledDiskContent: String,
        lastKnownDisk: String
    ) -> ExternalChangeOutcome {
        // The read-time snapshot is deliberately ignored: re-validation is against
        // the live buffer only.
        let dirty = !ContentEqualityGate.equal(liveBuffer, lastKnownDisk)
        if !dirty { return .absorb }
        if ContentEqualityGate.equal(settledDiskContent, liveBuffer) { return .absorb }
        return .collision
    }
}
