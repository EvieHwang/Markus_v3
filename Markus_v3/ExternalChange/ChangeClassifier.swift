import Foundation

/// DC-4 — the four exclusive outcomes the detector emits for a settled disk state.
/// The UI maps these to surfaces; the document model maps `absorb` to a buffer
/// adoption. Presence is resolved first (DC-4/DC-16).
enum ExternalChangeOutcome: Equatable, Sendable {
    case absorb
    case collision
    case moved
    case deleted
}

/// DC-4 — the pure classifier. For any settled situation (presence + on-disk
/// content + buffer + last-known-disk) it emits exactly one outcome, presence-first:
/// a file resolvable at a new location is `moved` (unless it also carries a material
/// change against a dirty buffer → `collision`, DC-20); a file at the same location
/// is `absorb` (clean buffer, or dirty-but-content-identical) or `collision` (dirty
/// AND material); a genuinely absent file is `deleted`. A resolvable file is never
/// `deleted`.
enum ChangeClassifier {
    nonisolated static func classify(
        presenceSameLocation: Bool,
        movedLocation: URL?,
        isAbsent: Bool,
        onDiskContent: String?,
        buffer: String,
        lastKnownDisk: String
    ) -> ExternalChangeOutcome {
        // Presence first: a resolvable successor location is a move.
        if movedLocation != nil {
            let disk = onDiskContent ?? ""
            let dirty = !ContentEqualityGate.equal(buffer, lastKnownDisk)
            let material = !ContentEqualityGate.equal(disk, buffer)
            // A move carrying a material change against unsaved edits is still gated.
            return (dirty && material) ? .collision : .moved
        }

        if presenceSameLocation {
            let disk = onDiskContent ?? ""
            let dirty = !ContentEqualityGate.equal(buffer, lastKnownDisk)
            // Clean buffer: adopt the new disk content silently.
            if !dirty { return .absorb }
            // Dirty but content-identical to disk: silent absorb (echo / coincidence).
            if ContentEqualityGate.equal(disk, buffer) { return .absorb }
            // Dirty and materially different: a true collision.
            return .collision
        }

        // Genuinely absent (and not resolvable elsewhere).
        return .deleted
    }
}
