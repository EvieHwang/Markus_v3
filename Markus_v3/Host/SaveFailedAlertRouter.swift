import Foundation
import Observation

/// Routes `MarkdownDocumentSaveBridge` write failures (T-001 / T-003) into the
/// existing `ActiveAlert.saveFailed` surface owned by `DocumentView`, with the
/// lifecycle rules from save-bridge-hardening-9 DC-10–DC-15:
///
/// - **DC-10 / DC-11** — at most one save-failed alert at a time; the latest
///   error wins. The single-alert rule is shared with the existing
///   `ActiveAlert` model in `DocumentView`; the router itself only ever
///   exposes one pending error.
/// - **DC-12** — a successful write after a failure clears the failure surface;
///   a previously dismissed alert does not re-present on the next state change.
/// - **DC-13** — a failure observed while no view is alive (e.g. an immediate
///   flush during backgrounding via `saveSynchronously()`) is latched on the
///   router and surfaced on the next foreground appearance of the document
///   view. Persistence across a cold launch is not required.
/// - **DC-14** — a presented conflict sheet or deletion banner outranks the
///   save-failed alert: a residual write failure does not pre-empt the user's
///   pending three-option choice. The save-failed alert queues behind the
///   conflict surface and may surface once it clears.
/// - **DC-15 / NR-7 / OOS-10** — the bridge route and the existing
///   `SaveStatusObserver` route do not double-fire: `DocumentView` is the
///   single-alert state holder; both producers funnel into one
///   `activeAlert` and the alert UI never stacks.
@MainActor
@Observable
final class SaveFailedAlertRouter {

    /// Externally observed by `DocumentView` to drive `activeAlert`. nil ⇒ no
    /// save-failed alert pending; `.some` ⇒ present with this error's
    /// localized description (BR-1.2).
    private(set) var pendingError: Error?

    @ObservationIgnored private var latchedError: Error?
    @ObservationIgnored private var viewIsActive: Bool = false
    @ObservationIgnored private var conflictPresented: Bool = false

    /// Bound to `MarkdownDocumentSaveBridge.onDidFailWrite`. Routes per the
    /// lifecycle above. Latest failure wins (DC-11): if a failure arrives while
    /// an alert is already pending, the pending error is replaced rather than
    /// queued.
    func recordFailure(_ error: Error) {
        if !viewIsActive {
            // DC-13 — no view alive: latch for next foreground.
            latchedError = error
            return
        }
        if conflictPresented {
            // DC-14 — conflict sheet outranks; queue behind. When the conflict
            // surface clears, the latched error may surface (subject to the
            // single-alert rule).
            latchedError = error
            return
        }
        // DC-11 — latest wins; replace any pending message in place.
        pendingError = error
    }

    /// Bound to `MarkdownDocumentSaveBridge.onDidWrite` (composed with the
    /// existing detector wiring). A successful write clears the failure
    /// surface (DC-12 / BR-6); a previously dismissed alert is not
    /// re-presented on subsequent state changes.
    func recordSuccess() {
        pendingError = nil
        latchedError = nil
    }

    /// Called from `DocumentView.onAppear` and on scene-phase `.active`. Lifts
    /// any latched error onto the pending surface if the conflict-precedence
    /// gate is not held (DC-13). Idempotent.
    func viewBecameActive() {
        viewIsActive = true
        promoteLatchedIfPossible()
    }

    /// Called from `DocumentView.onDisappear`. Subsequent failures latch until
    /// the view re-appears.
    func viewBecameInactive() {
        viewIsActive = false
    }

    /// Called from `DocumentView` on `detector.activeSurface` change. While a
    /// conflict sheet or deletion banner is presented, save-failed alerts are
    /// held back (DC-14). When the conflict surface clears, the most recent
    /// latched failure may surface.
    func setConflictPresented(_ presented: Bool) {
        conflictPresented = presented
        if !presented {
            promoteLatchedIfPossible()
        }
    }

    /// Called from the alert's Dismiss / Copy actions in `DocumentView`. Closes
    /// the pending surface; performs no retry, no queueing of unwritten edits,
    /// and no clearing of dirty state (BR-1.3 / DC-10).
    func dismiss() {
        pendingError = nil
        // BR-1.3 — retry/queue/dirty-clearing are deliberately NOT performed
        // here. The buffer remains dirty against last-known-disk (DC-3) and a
        // subsequent successful write will clear it via the normal path.
    }

    private func promoteLatchedIfPossible() {
        guard pendingError == nil, !conflictPresented, viewIsActive,
              let latched = latchedError else { return }
        latchedError = nil
        pendingError = latched
    }
}
