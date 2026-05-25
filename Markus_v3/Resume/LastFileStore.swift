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
    /// Never clears the stored reference (RETAIN-on-failure, DC-5).
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

        // RETAIN-on-failure unreachability check: anchor "reachable" to the path
        // the user originally opened. If the file no longer exists at that path
        // (moved aside, deleted, placeholder swapped out), report unreachable —
        // but DO NOT clear the stored bookmark, so a later launch can recover.
        if let recordedPath = defaults.string(forKey: pathKey),
           !FileManager.default.fileExists(atPath: recordedPath) {
            return nil
        }

        // Fallback: if no recorded path is present (older record), at least
        // verify the bookmark-resolved URL is reachable.
        if defaults.string(forKey: pathKey) == nil {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        }

        return url
    }
}
