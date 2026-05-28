# Requirements: save-bridge-hardening-9

Behavioral requirements for the three write-path hardening changes named in `features/save-bridge-hardening-9/declaration.md`: surfacing write errors, coordinating writes through `NSFileCoordinator`, and refreshing the in-memory buffer when foreground reconciliation lifts on equality. Requirements are stated as observable behavior; the declaration fixes `NSFileCoordinator.coordinate(writingItemAt:)` as the coordination mechanism, and `ChangeDetector.reconcileOnForeground()` as the lift site, so those names appear in the relevant requirements as design constraints (not as test obligations for call shape).

## Definitions

These terms are used with fixed meaning throughout; reused from `external-change-5/requirements.md` where applicable.

- **Save bridge** — `MarkdownDocumentSaveBridge`, the per-document component that writes the in-memory buffer to disk on a 500ms idle debounce and on explicit `saveSynchronously()` (background/teardown).
- **Write attempt** — one execution of the bridge's `writeNow()` path (debounced or immediate-flush).
- **Save-status surface** — the existing user-facing alert path used today for `ActiveAlert.saveFailed` ("Couldn't save"), driven through `DocumentView`'s alert presentation. Reusing this surface satisfies the declaration's "via the existing save-status surface."
- **Buffer**, **clean buffer**, **dirty buffer**, **on-disk content**, **content-identical**, **materially differs**, **settled / settle window**, **last-known-disk content** — per `external-change-5/requirements.md`.
- **Coordinated write** — a write performed inside `NSFileCoordinator.coordinate(writingItemAt:)`, so a concurrent coordinated reader/writer (Markus itself, iCloud, another presenter) does not interleave with the write.
- **Reconciliation lift on equality** — the `lift` branch of `ChangeDetector.reconcileOnForeground()` (DC-23 of external-change-5) taken when the live buffer is content-identical to settled disk: the latched outcome is cleared, suspension lifts, and the detector re-arms.

---

## User stories and acceptance criteria

### BR-1 — Write errors surface to the user, not the void

**As a** user whose save just failed (revoked permission, disk full, file unreachable, etc.),
**when** the bridge's `writeNow()` returns an error,
**so that** I am not left editing under the false belief my file is saved,
**I want** the failure shown on the existing save-status surface and my buffer kept dirty until a save actually lands.

Acceptance criteria:

- BR-1.1 Given a write attempt that throws (any `Error` from the underlying `Data.write(to:options:)` or the coordinator), the save-status surface presents a "Couldn't save" alert routed through the existing `ActiveAlert.saveFailed` path. No write failure is silently swallowed.
- BR-1.2 The alert message includes enough of the underlying `Error` for the user to act on it (e.g. a localized description string from the underlying error). No diagnostic detail beyond what the underlying `Error` carries is required (per declaration out-of-scope).
- BR-1.3 The alert is dismissable (the existing alert path's OK action is sufficient). Dismissing the alert does not retry, queue, or clear the dirty state.
- BR-1.4 After a failed write attempt the buffer remains dirty against `lastKnownDiskContent`: the document is not falsely marked clean, and a subsequent successful save (manual or debounced) writes the still-unsaved content.
- BR-1.5 After a failed write attempt, `lastKnownDiskContent` is NOT updated and the settle window is NOT opened (the success-only side effects of DC-9/DC-6 do not fire on failure).
- BR-1.6 A successful write that follows a failed one clears the dirty state (updates `lastKnownDiskContent`, opens the settle window) exactly as the steady-state save path does today; the prior failure alert does not re-surface.

### BR-2 — Writes are coordinated with the rest of the file system

**As a** user whose file is also being written by iCloud (or another coordinated presenter) at roughly the same moment Markus saves,
**when** an external write lands during Markus's save,
**so that** my file is not torn and a fresher external write is not silently clobbered,
**I want** Markus's write serialized with the rest of the coordinated file world.

Acceptance criteria:

- BR-2.1 Every write attempt the bridge performs (debounced and `saveSynchronously()`) is wrapped in `NSFileCoordinator.coordinate(writingItemAt:)`, matching how reads are already coordinated in `ChangeDetector.coordinatedRead*` (declaration constraint).
- BR-2.2 An external coordinated write injected concurrently with a Markus save does not produce a torn on-disk file: after both writes settle, the on-disk bytes are exactly the bytes of one of the two writes (Markus's full buffer or the external content) — never a partial interleave.
- BR-2.3 If the coordinator itself reports an error (`NSError` via the `coordinate` out-parameter, or an underlying `Data.write` failure inside the coordinated block), that error is propagated to the save-status surface per BR-1 — coordinator errors are not silently swallowed any more than direct write errors are.
- BR-2.4 The coordinated write must release any security-scoped resource it started (i.e. the existing `startAccessingSecurityScopedResource` / `stopAccessingSecurityScopedResource` discipline is preserved across both the success and failure paths).
- BR-2.5 Coordination does not introduce a new user-visible delay on the steady-state save path: a save that does not race with any other coordinated work behaves indistinguishably (to the user) from the pre-hardening atomic write.

### BR-3 — Reconciliation lift refreshes the buffer-vs-disk reference

**As a** user whose foreground reconciliation just lifted suspension because the live buffer is content-identical to settled disk,
**when** the lift fires,
**so that** my next save cannot clobber a fresher-but-equal disk state I never observed,
**I want** the in-memory buffer reference (`lastKnownDiskContent`) refreshed to the settled disk bytes that justified the lift, so a subsequent save is a no-op rather than a write.

Acceptance criteria:

- BR-3.1 When `ChangeDetector.reconcileOnForeground()` takes the `lift` branch via content-identity (the live buffer equals settled disk under the DC-11 equality gate), `lastKnownDiskContent` is set to the settled disk bytes that justified the lift, before suspension is lifted to autosave.
- BR-3.2 Immediately after such a lift, the document is clean against disk (BR-2 from external-change-5 semantics) — the bridge's next debounced or explicit save attempt is a no-op against disk (no write fires) because the buffer matches `lastKnownDiskContent`.
- BR-3.3 The lift refresh adopts the *settled* bytes (the bytes read through the coordinated read in `reconcileOnForeground()`), not a stale snapshot the detector held from before backgrounding.
- BR-3.4 The lift refresh never overwrites or mutates the user's buffer — only `lastKnownDiskContent` is updated. The visible text, cursor, and scroll position are preserved (consistent with DC-12 absorb behavior).
- BR-3.5 If the lift branch is taken via the file-reappeared-as-move path (not content-identity), the same property holds at the retargeted location: after the lift, `lastKnownDiskContent` matches the settled bytes at the new location, so a subsequent save does not clobber it.
- BR-3.6 The "re-present" branch of `reconcileOnForeground()` is unaffected: if the outcome still holds (collision or deletion still material), `lastKnownDiskContent` is NOT silently refreshed (a refresh there would defeat the surfaced choice).

---

## Edge cases and failure modes

- BR-4 **Error surface while backgrounded.** A write attempt that fires from `saveSynchronously()` during backgrounding (the host's teardown / scene-resign flush) and fails: the failure is latched so the save-status surface appears on next foreground, rather than being lost because no view was alive to display the alert. The buffer remains dirty across the backgrounding (BR-1.4). At minimum, the alert is presented the next time `DocumentView` is foregrounded for that document; no additional persistence across cold launch is required.
- BR-5 **Multiple rapid failures.** If several debounced write attempts fail in quick succession (e.g. permission is revoked and three keystroke-driven debounces all throw), the user does not see a stack of alerts: at most one save-failed alert is presented at a time per document, consistent with the existing `ActiveAlert` single-alert model. The most recent error is the one surfaced; the dirty state remains until a save actually lands.
- BR-6 **Failure then success.** After a save-failed alert is shown and dismissed, a subsequent successful write must not re-present the failed alert. The save-status surface tracks the *latest* outcome; success clears the failed state.
- BR-7 **Coordinator timeout / contention.** If `NSFileCoordinator.coordinate(writingItemAt:)` fails to acquire coordination (timeout, error reported via the out-parameter), the buffer is preserved (no partial write performed) and the failure is surfaced per BR-1/BR-2.3. The bridge does not fall back to an uncoordinated `Data.write` as a "best effort" — coordinated-or-fail is the contract.
- BR-8 **Coordinator block throws after a partial write.** If the underlying `Data.write(to:options:.atomic)` throws inside the coordinated block (atomic write semantics mean disk is either pre-write or post-write, never partial), the failure is surfaced per BR-1; `lastKnownDiskContent` is not updated; the buffer stays dirty.
- BR-9 **Reconciliation lift while editing.** If the user is actively typing at the instant `reconcileOnForeground()` runs its content-identity check (the buffer happens to equal disk at sample, then the user types one more character before the lift completes), the lift's `lastKnownDiskContent` refresh must not overwrite the just-typed buffer: the refresh updates only `lastKnownDiskContent`, never the buffer (BR-3.4). The resulting state is "buffer dirty against fresh `lastKnownDiskContent`" — the next save will write the typed delta, which is correct and not a regression.
- BR-10 **Reconciliation lift on content-identity where disk read fails.** If `reconcileOnForeground()`'s coordinated read returns `nil` (read failed, file inaccessible), the lift's content-identity branch does not run with a stale `lastKnownDiskContent` reference; the existing reconciler logic is the authority on whether `lift` is taken at all. This requirement does not introduce a new lift path — it only constrains what happens *when* the lift fires (BR-3.1).
- BR-11 **Error surface during a presented conflict sheet or deletion banner.** A write that fails while a collision/deletion is classified should not occur in the first place (DC-22 suspends save-back from classification). If, despite suspension, a residual write attempt fires and fails, surfacing the failure must not dismiss or pre-empt the conflict sheet / deletion banner — the conflict UI remains the primary surface; the save-failed alert may queue behind it or coalesce, but the user's pending three-option choice is not lost.
- BR-12 **Save during teardown / `saveSynchronously()`.** The immediate-flush path used at backgrounding and host teardown is held to the same BR-1 and BR-2 contracts: errors there surface (per BR-4 latching), and the write is coordinated (BR-2.1).

---

## Out of scope (restating the declaration + clarifications)

- OOS-1 **No retry queue or transient-failure backoff.** A failed write surfaces the error and stops; the user decides what to do (per declaration).
- OOS-2 **No sidecar / recovery file on write failure.** The buffer in memory is the recovery path; no on-disk crash-recovery artifact is created.
- OOS-3 **No migration of `MarkdownDocumentSaveBridge` to `UIDocument`.** The bridge stays as-is structurally; only the write path is hardened.
- OOS-4 **No new save-status surface invented.** Reuse the existing `ActiveAlert.saveFailed` / `DocumentView` alert path. No new banner, toast, status bar, or settings entry is introduced.
- OOS-5 **No diagnostic detail beyond the underlying `Error`.** The alert text need not include stack traces, file paths beyond what the `Error` already carries, or telemetry hooks.
- OOS-6 **Open-side hardening (UTF-8 fallback, load error surface, large-file ceiling) is not in this feature** — see `open-path-hardening-10`.
- OOS-7 **Resume bookmark fallback and detector-start race are not in this feature** — see `resume-and-detector-hardening-11`.
- OOS-8 **No change to the 500ms debounce value or the `saveSynchronously()` API contract.** This feature hardens the write *implementation*, not the cadence or the public seam shape.
- OOS-9 **No new conflict-detection logic.** Coordination of writes prevents *torn* writes but is not a new collision-detection mechanism; the detector remains the single authority on collisions (per DC-1 of external-change-5).
- OOS-10 **No change to `SaveStatusObserver`'s narrow job.** It continues to surface `UIDocument`-level save errors and download state where applicable; the new write-error surfacing route from the bridge is *additional*, not a replacement.

---

## Non-regression requirements

These exist explicitly so the hardening cannot silently break properties earned by prior features. Each is a "still works the same" assertion that the spec tests must hold.

- NR-1 **Steady-state save path.** Typing → idle 500ms → write → `onDidWrite` → `lastKnownDiskContent` updated → settle window opened. After this feature: the same observable end-state holds for a normal successful save (now performed inside a coordinator), including:
  - NR-1.1 Continuous typing coalesces into at most one write per 500ms idle gap (no per-keystroke writes).
  - NR-1.2 A successful debounced write updates `lastKnownDiskContent` exactly once per write.
  - NR-1.3 A successful debounced write opens the settle window (DC-6) so the immediate echo from sync is suppressed and does not produce a spurious conflict sheet (BR-3 of external-change-5).
  - NR-1.4 `saveSynchronously()` at backgrounding flushes any pending debounced save and writes the current buffer, with the same coordinated-and-error-surfaced contract.
- NR-2 **External-change reconciliation under non-collision (silent absorb).** Both clean-buffer absorb (BR-1 of external-change-5) and content-identical dirty-buffer absorb (BR-2 of external-change-5) continue to occur silently — no save-failure alert appears as collateral, and the buffer/cursor/scroll preservation properties hold (BR-1.5, BR-2.3 of external-change-5).
- NR-3 **Three-option sheet under true collision.** BR-4 of external-change-5 holds unchanged: the conflict sheet appears iff dirty buffer AND materially differs AND settled, with exactly Keep Mine / Keep Theirs / Discard Mine. The new coordinated-write path does not affect *whether* a collision is classified, only that Markus's own writes don't tear; the apply-edge invariants of DC-21/DC-22/DC-23 are unaffected.
- NR-4 **DC-22 save-back gate is preserved.** `allowsSaveBack()` still gates the bridge's `writeNow()` (and `saveSynchronously()`); a classified collision/deletion still suppresses writes from classification onward. Wrapping in a coordinator does not bypass this gate (the gate check precedes the coordinated block).
- NR-5 **Conflict resolution writes (Keep Mine, Save As).** Keep Mine and Save As, which today go through the bridge's write path (directly or via `requestImmediateWrite?()`), inherit BR-1 (error surfacing) and BR-2 (coordinated) for free; on success they continue to behave as DC-13 / DC-17 of external-change-5 specify.
- NR-6 **Reconciliation re-present branch.** `reconcileOnForeground()`'s `rePresent` branch (DC-23) still re-presents the conflict sheet or deletion banner when the outcome still holds, and `lastKnownDiskContent` is not silently refreshed on that branch (BR-3.6).
- NR-7 **`SaveStatusObserver` continues its narrow job** (DC-3 of external-change-5). It still surfaces `UIDocument`-state save errors and download state; the new bridge-side error surfacing does not double-fire the alert (a single write failure produces at most one save-failed alert at a time, per BR-5).

---

Requirements stable — no architectural feedback to incorporate
