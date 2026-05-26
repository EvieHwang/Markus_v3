import Foundation

/// DC-22 (adversarial F-002) — save-back suspension keyed to *classification*, not
/// surface presentation.
///
/// The moment the detector classifies `collision` or `deleted`, save-back is
/// suspended — closing the classify→present latency gap, so a queued/debounced save
/// cannot fire and clobber the disagreeing disk content before the surface appears.
/// A second collision signal while latched does not stack. Suspension lifts on an
/// explicit user resolution; a non-user (system) dismissal does NOT lift — the
/// outcome stays latched-unresolved and recovery is owned by DC-23 (ForegroundReconciler).
struct SaveSuspensionLatch: Sendable {
    private(set) var allowsSaveBack = true
    private(set) var surfacePresented = false
    private(set) var latchedCount = 0
    private var latchedOutcome: ExternalChangeOutcome?

    init() {}

    /// Whether an outcome is latched and still unresolved (suspension in force).
    var isLatchedUnresolved: Bool {
        latchedOutcome != nil && !allowsSaveBack
    }

    /// Latch a classified outcome. Only `collision` / `deleted` suspend; a repeat
    /// signal while latched updates the outcome but does not stack a second latch.
    mutating func classify(_ outcome: ExternalChangeOutcome) {
        guard outcome == .collision || outcome == .deleted else { return }
        if latchedOutcome == nil {
            latchedCount = 1
        }
        latchedOutcome = outcome
        allowsSaveBack = false
    }

    /// Mark the surface (sheet/banner) as now on screen.
    mutating func presentSurface() {
        surfacePresented = true
    }

    /// A save-back attempt; refused (returns false) while suspended.
    func attemptSaveBack() -> Bool {
        allowsSaveBack
    }

    /// Explicit user resolution — the only path (besides DC-23 lift) that clears
    /// the latch and resumes save-back.
    mutating func resolveByUser() {
        latchedOutcome = nil
        surfacePresented = false
        latchedCount = 0
        allowsSaveBack = true
    }

    /// A non-user dismissal (backgrounding / memory-pressure teardown): the surface
    /// is gone but the outcome stays latched and suspension stays in force.
    mutating func dismissBySystem() {
        surfacePresented = false
    }
}
