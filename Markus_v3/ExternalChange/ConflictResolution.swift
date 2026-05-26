import Foundation

/// DC-13 — the three conflict-sheet options and their end-states.
///
/// Three options exist (no "merge"): **Keep Mine** writes the buffer to disk and
/// leaves the buffer clean; **Keep Theirs** and **Discard Mine** are behaviorally
/// identical — adopt the on-disk content into the buffer, drop local edits, buffer
/// becomes clean, with no clobbering write to disk. Two labels, one outcome.
enum ConflictResolution {
    enum Option: CaseIterable, Equatable {
        case keepMine
        case keepTheirs
        case discardMine
    }

    /// The observable end-state of a resolution.
    struct Result: Equatable {
        /// The buffer content after the resolution.
        let newBufferContent: String
        /// What, if anything, was written to disk. `nil` means no write was
        /// performed (Keep Theirs / Discard Mine never clobber the external content).
        let contentWrittenToDisk: String?
        /// Whether the buffer is clean against disk after the resolution.
        let bufferIsCleanAfter: Bool
    }

    nonisolated static func apply(_ option: Option, buffer: String, onDisk: String) -> Result {
        switch option {
        case .keepMine:
            // Buffer wins: written to disk, buffer unchanged, now clean against disk.
            return Result(newBufferContent: buffer,
                          contentWrittenToDisk: buffer,
                          bufferIsCleanAfter: true)
        case .keepTheirs, .discardMine:
            // Disk wins: adopt on-disk content, drop local edits, no clobbering write.
            return Result(newBufferContent: onDisk,
                          contentWrittenToDisk: nil,
                          bufferIsCleanAfter: true)
        }
    }
}
