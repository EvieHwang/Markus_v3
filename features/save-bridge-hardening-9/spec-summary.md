# Spec summary — save-bridge-hardening-9

## Feature

Markus is a lens over the user's existing markdown files; the core promise is that no edit is ever silently lost. A post-shipping audit identified three remaining failure modes on the write/reconcile path that can violate that promise: a write that fails silently (the user keeps typing under the false belief the file is saved), an uncoordinated write that clobbers a fresher iCloud version that landed mid-save, and a foreground reconciliation that lifts on equality but leaves the in-memory buffer stale so the next save overwrites a fresher-but-equal disk state. This feature closes all three.

## What it does

- **Save failures become visible.** When a save fails — revoked permission, simulated disk-full, any underlying write error — the user sees a "Couldn't save" alert routed through the same alert surface the app already uses for other lifecycle events. The document stays marked dirty until a save actually lands; the user can keep editing and the next successful save clears the alert state. A dismissed alert does not retry, queue, or pretend the file was saved.
- **Saves stay coordinated with the rest of the file system.** Every write — both the debounced save while editing and the immediate flush when the app backgrounds — runs under the same file coordination Markus already uses for reads. An external app (or iCloud) writing the same file at the same time can no longer produce a torn file; the two writes serialize, and the on-disk bytes are always exactly one writer's bytes.
- **Foreground reconciliation no longer leaves the buffer stale.** When the app returns to the foreground and the on-disk content turns out to equal what's in memory (silent absorb), the in-memory "last known disk" reference is refreshed to those settled bytes. A subsequent save becomes a true no-op instead of overwriting a fresher-but-equal disk state the user never saw.
- **Background failures aren't lost to the void.** A write that fails while the app is backgrounding (no view alive to show the alert) is latched and surfaced the next time the editor foregrounds the same document.
- **The conflict sheet keeps precedence.** If a residual write failure races with a presented conflict sheet or deletion banner, the conflict surface still wins — the user's pending three-option choice is never wiped by a background failure notification.

## Risks carried

No risks acknowledged. The adversarial review produced zero open findings (HIGH, MEDIUM, or LOW) and zero scope-drift concerns.

## Out of scope

- Retry queues or transient-failure backoff — the alert surfaces the error; the user decides.
- Sidecar / recovery files on write failure.
- Migrating the save bridge to `UIDocument`.
- Open-side hardening (UTF-8 fallback, load error surface, large-file ceiling) — that is `open-path-hardening-10`.
- Resume bookmark fallback and detector-start race — that is `resume-and-detector-hardening-11`.
- Diagnostic detail beyond what the underlying error already carries.
- New alert surfaces, banners, toasts, or status indicators — the existing `ActiveAlert.saveFailed` path is reused, not extended.

## Build preview

4 tasks across 3 waves. Wave 1 lands two independent pure-contract pieces in parallel: the write-outcome bus with success-only side-effect gating (T-001) and the reconciliation-lift refresh on `ChangeDetector.reconcileOnForeground()` (T-002). Wave 2 wraps the live bridge's write path in `NSFileCoordinator`, bundling the save-back gate, coordinated-or-fail contract, and balanced security-scoped resource discipline (T-003). Wave 3 attaches the host-side alert router for single-alert coalescing, background latch, conflict precedence, and no double-fire with `SaveStatusObserver` (T-004). Fits one screen; no new framework, dependency, or deploy path; hardens three existing seams without altering product surface — comfortably one build session.

## Next step

Start a new session and run `/build feature-name: save-bridge-hardening-9`.
