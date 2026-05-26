import Foundation

/// DC-9 / DC-10 — the last-known-disk authority for clean/dirty.
///
/// Carries the bytes Markus last *wrote to* or last *read from* disk for the open
/// document. A buffer is *clean* when it equals this value under the content
/// equality gate (DC-11), *dirty* otherwise. This replaces "dirty = the undo
/// manager registered an edit": a buffer typed-then-reverted-to-disk content is
/// clean, because content divergence — not edit history — is the authority.
struct LastKnownDiskState: Equatable {
    private(set) var lastKnownDisk: String

    nonisolated init(lastKnownDisk: String) {
        self.lastKnownDisk = lastKnownDisk
    }

    /// Clean iff the buffer equals last-known-disk under the newline-normalized gate.
    nonisolated func isClean(buffer: String) -> Bool {
        ContentEqualityGate.equal(buffer, lastKnownDisk)
    }

    /// Reset after an absorb or a successful save: the new on-disk content becomes
    /// the reference against which clean/dirty is computed.
    mutating func reset(toDiskContent content: String) {
        lastKnownDisk = content
    }
}
