import Foundation

/// DC-6 / DC-7 / DC-8 — the settle gate.
///
/// A fixed grace window (2s by design) opened/reset by each of three triggers —
/// open, first-persist (create), save-complete. While the window is open, change
/// and deletion signals are suppressed. Independently of the timer, an in-flight
/// sync suppresses classification regardless of elapsed time, so a slow sync that
/// outlasts the window is still suppressed until it settles. Suppression delays,
/// never discards: the gate only gates timing — it does not consume the pending
/// signal, so a still-present collision is classifiable once the window closes.
struct SettleGate: Sendable {
    enum Trigger: Sendable {
        case opened
        case created
        case saveCompleted
    }

    let windowSeconds: TimeInterval
    private var lastTriggerAt: TimeInterval?

    init(windowSeconds: TimeInterval) {
        self.windowSeconds = windowSeconds
    }

    /// Note a settle trigger at `time`; this opens (or resets) the grace window.
    mutating func noteTrigger(_ trigger: Trigger, at time: TimeInterval) {
        lastTriggerAt = time
    }

    /// True if classification must be suppressed at `now`: while a sync is in
    /// flight (independent of the timer), or while still within the window.
    func isSuppressed(at now: TimeInterval, syncInFlight: Bool) -> Bool {
        if syncInFlight { return true }
        guard let last = lastTriggerAt else { return false }
        return (now - last) < windowSeconds
    }
}
