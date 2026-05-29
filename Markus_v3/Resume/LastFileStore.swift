import Foundation

/// Persists a single security-scoped bookmark (and the recorded URL's path) for
/// the most recently opened file, and resolves it back to an access-scoped URL
/// on demand.
///
/// Behavioral contract (design DC-1/DC-5/DC-15):
/// - Exactly one durable reference exists; `recordLastOpened(_:)` replaces any prior one.
/// - The reference survives full app termination (verified by sharing a `UserDefaults` suite).
/// - `resolveLastOpened()` returns `nil` for stale/corrupt/unreachable bookmarks and
///   **does not clear** the stored reference (RETAIN-on-failure, DC-5).
/// - Reads are non-destructive (DC-15) — back navigation never touches the store, and
///   even repeated resolution attempts leave the reference intact.
///
/// Why we store the path string alongside the bookmark: a security-scoped bookmark
/// tracks the file by identity, so a file that has been moved or renamed in place
/// (or temporarily replaced by a sync placeholder that's been swapped out) would
/// still resolve through the bookmark even though it is no longer reachable at the
/// path the user opened. The path-existence check anchors "reachable" to the
/// path the user actually opened — matching the requirement's notion of unreachable
/// (BR-5/BR-20 / DC-4/DC-5).
nonisolated final class LastFileStore {

    static let defaultBookmarkKey = "Markus_v3.LastFileStore.bookmarkData"
    static let defaultPathKey = "Markus_v3.LastFileStore.path"

    private let defaults: UserDefaults
    private let bookmarkKey: String
    private let pathKey: String

    init(defaults: UserDefaults = .standard,
         bookmarkKey: String = LastFileStore.defaultBookmarkKey,
         pathKey: String = LastFileStore.defaultPathKey) {
        self.defaults = defaults
        self.bookmarkKey = bookmarkKey
        self.pathKey = pathKey
    }

    /// True when a bookmark record currently exists. Independent of whether
    /// the bookmark resolves — used to verify RETAIN-on-failure (DC-5).
    var hasRecord: Bool {
        defaults.data(forKey: bookmarkKey) != nil
    }

    /// Records the given URL as the last-opened file, replacing any prior reference.
    /// On bookmark-creation failure, the reference is left unchanged.
    func recordLastOpened(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(data, forKey: bookmarkKey)
            defaults.set(url.path, forKey: pathKey)
        } catch {
            // Bookmark creation failed; preserve any existing reference.
        }
    }

    /// Resolves the stored bookmark to a reachable URL, or returns `nil` on any failure.
    /// Never clears the stored reference (RETAIN-on-failure, DC-5/DC-6).
    ///
    /// resume-and-detector-hardening-11 DC-1/DC-3: the bookmark is the identity of
    /// the last-opened file; the recorded path is a reachability hint. When the
    /// recorded path is missing on disk, probe the bookmark-resolved URL under
    /// security scope and resume there if reachable. The recorded path is never
    /// rewritten from inside the resolver (DC-4) — `recordLastOpened(_:)` remains
    /// the sole persistence funnel.
    func resolveLastOpened() -> URL? {
        guard let data = defaults.data(forKey: bookmarkKey) else { return nil }

        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            return nil
        }

        let recordedPath = defaults.string(forKey: pathKey)

        // Bookmark-fallback (DC-3): the recorded path moved/vanished since
        // record-time. Don't abandon the bookmark — probe the bookmark-resolved
        // URL under security scope and resume there if reachable. On probe
        // failure, return nil but retain the stored reference (DC-6) so a
        // later launch can recover (e.g. iCloud placeholder finishes
        // downloading, permission re-granted).
        if let recordedPath, !FileManager.default.fileExists(atPath: recordedPath) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url
        }

        // Fallback: if no recorded path is present (older record), at least
        // verify the bookmark-resolved URL is reachable.
        if recordedPath == nil {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        }

        return url
    }
}
