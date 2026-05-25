import Foundation

/// Pure helper that picks a collision-free `Untitled[ n].md` name in the supplied
/// directory.
///
/// Behavioral contract (design DC-6/DC-7/DC-11):
/// - Empty / collision-free directory yields exactly `Untitled.md`.
/// - On collision, returns the lowest available `Untitled n.md` for integer n ≥ 2,
///   gap-filling, never overwriting or mutating an existing entry.
/// - Always `.md` extension; never `.markdown`/`.txt`.
/// - Anchored solely to the supplied directory; files elsewhere never influence the result.
/// - Read-only: never materializes the candidate file on disk.
enum NameProbe {

    static let baseName = "Untitled"
    static let fileExtension = "md"

    /// Returns the lowest-available `Untitled[ n].md` URL in `dir`.
    static func availableName(in dir: URL) -> URL {
        let existing = Set(
            (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        )

        if !existing.contains("\(baseName).\(fileExtension)") {
            return dir.appendingPathComponent("\(baseName).\(fileExtension)")
        }

        var n = 2
        while existing.contains("\(baseName) \(n).\(fileExtension)") {
            n += 1
        }
        return dir.appendingPathComponent("\(baseName) \(n).\(fileExtension)")
    }
}
