import Foundation

/// Observable surface the create-target resolver consults to find the
/// last-opened file's containing directory. C1 (`LastFileStore`) is the
/// production conformer; tests provide a stub conformer.
protocol LastDirectoryProviding {
    func resolveLastDirectory() -> URL?
}

/// Chooses the directory in which a newly created file should live.
///
/// Behavioral contract (design DC-12 / requirements BR-10, BR-11, BR-21,
/// BR-22, BR-23):
/// - Returns the last-opened file's directory **only** if (a) the directory
///   is currently reachable and (b) a side-effect-free-on-success writability
///   probe succeeds.
/// - Otherwise, falls back to `LocalDocumentsFallback.documentsDirectory()`.
/// - The probe creates a uniquely-named, zero-byte temporary entry and
///   removes it on success; on failure (or if removal fails for any reason)
///   no residual file is left in the directory.
final class CreateTargetResolver {

    private let lastDirectoryProvider: LastDirectoryProviding

    init(lastDirectoryProvider: LastDirectoryProviding) {
        self.lastDirectoryProvider = lastDirectoryProvider
    }

    /// Resolves the directory in which a new `Untitled[ n].md` should be created.
    /// Throws only if `LocalDocumentsFallback.documentsDirectory()` itself fails,
    /// which would indicate a broken app container — not the routine
    /// last-directory-unreachable case (that path falls back silently).
    func resolveTargetDirectory() throws -> URL {
        if let last = lastDirectoryProvider.resolveLastDirectory(),
           directoryIsReachableAndWritable(last) {
            return last
        }
        return try LocalDocumentsFallback.documentsDirectory()
    }

    /// Side-effect-free-on-success writability probe: try to create and remove
    /// a uniquely-named zero-byte entry. Returns true only if both the
    /// existence/directory check and the create+remove cycle succeed cleanly.
    private func directoryIsReachableAndWritable(_ dir: URL) -> Bool {
        let fm = FileManager.default

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }

        let probe = dir.appendingPathComponent(".markus_v3_writability_probe_\(UUID().uuidString)")
        do {
            try Data().write(to: probe)
        } catch {
            return false
        }

        // Probe created — remove it so the directory is observably unchanged.
        // If removal fails we still return false to avoid leaving residue
        // unaccounted for, but in practice if the write succeeded the remove
        // should too.
        do {
            try fm.removeItem(at: probe)
        } catch {
            try? fm.removeItem(at: probe)
            return false
        }

        return true
    }
}
