import Foundation

/// Test-only introspection on per-URL security-scoped resource acquisitions
/// (DC-9, BR-15). The open-path integration goes through these helpers rather
/// than calling URL's `startAccessingSecurityScopedResource` directly so the
/// audit can pair acquires with releases and tests can assert no leak across
/// repeated failed taps.
///
/// In production this is a trivial pass-through with one dictionary lookup
/// per acquire/release; cost is negligible compared to the file read.
enum OpenPathScopeAudit {
    private static var counts: [URL: Int] = [:]
    private static let lock = NSLock()

    /// Number of unbalanced `startAccessing`/`stopAccessing` pairs for `url`.
    /// A clean failure path returns this to baseline (DC-9).
    static func acquiredCount(for url: URL) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[url] ?? 0
    }

    /// Acquire the security-scoped resource and bump the audit counter on
    /// success. Returns the boolean result of the underlying call so the
    /// caller can decide whether to pair a `stopAccessing`.
    @discardableResult
    static func startAccessing(_ url: URL) -> Bool {
        let ok = url.startAccessingSecurityScopedResource()
        if ok {
            lock.lock()
            counts[url, default: 0] += 1
            lock.unlock()
        }
        return ok
    }

    /// Release the security-scoped resource and decrement the audit counter
    /// when `didAcquire` is true. A no-op when `didAcquire` is false.
    static func stopAccessing(_ url: URL, didAcquire: Bool) {
        guard didAcquire else { return }
        url.stopAccessingSecurityScopedResource()
        lock.lock()
        counts[url, default: 0] -= 1
        lock.unlock()
    }
}
