# Design — Save-Bridge Hardening

*Architecture for `save-bridge-hardening-9`. Source of truth for intent: `features/save-bridge-hardening-9/declaration.md`; behavior: `features/save-bridge-hardening-9/requirements.md`. Every constraint below (DC-n) is phrased as an observable property of the running system — what the user or the system can detect — not as a call signature, attribute name, or library API detail. Where a name appears, it is a public interface this project exposes to its own callers (the host, the editor, the bridge) and is marked as such.*

**Deferred-question resolution:** None. Requirements declared themselves stable with no architecture-flagged questions; this design pins mechanism only and leaves `requirements.md` untouched.

---

## Ground-truth check (resolved before drafting)

- **Seams consulted (read before drafting):** `MarkdownDocumentSaveBridge` (Wave 3, swallow-on-failure return path; `allowsSaveBack` gate; `onDidWrite` notification; security-scoped resource discipline), `ChangeDetector` (settle gate, `reconcileOnForeground()` DC-23 lift path, `noteSaveCompleted`, `coordinatedRead*` read pattern), `MarkdownDocument` (`lastKnownDiskContent`, DC-9), `ActiveAlert.saveFailed` + `DocumentView.activeAlert` alert presentation, `SaveStatusObserver` (DC-3 narrow job), `BrowserHostController` (bridge/detector wiring).
- **Inherited patterns:** `external-change-5/design.md` defines the apply-edge integrity model, the latched-outcome lifecycle (DC-22/DC-23), the settle-window contract (DC-6/DC-9), the coordinated-read shape, and the single-alert `ActiveAlert` UI surface. This feature *extends* those seams; it does not introduce a parallel mechanism.
- **Concurrency:** Swift 6 strict concurrency. The bridge, detector, document model, and alert state all live `@MainActor`. The new coordinator-wrapped write either runs synchronously on the main actor (matching today's atomic write) or hops the error back to the main actor before touching the alert state or `lastKnownDiskContent`. No off-main mutation of buffer or surface state.
- **Pattern reuse from constitution.md:** constitution.md registers Python/React patterns only; nothing here is marked `Reuses pattern: [constitution name]`. In-repo seams reused from prior features are marked `Reuses seam:` / `Extends seam:`.

---

## High-level shape

No new owned component. Three behavior changes graft onto two existing seams.

- **File access layer (primary).** The save bridge gains two new behaviors: (a) it propagates write failure as a classified outcome instead of returning silently, and (b) every write attempt — debounced and immediate-flush — runs inside a write-coordinated block, mirroring the coordinated-read discipline the detector already uses. The detector's foreground-reconciliation lift path gains one additional behavior: when it lifts on content-identity (or on a moved-successor whose contents now agree), it refreshes the document's last-known-disk reference to the settled bytes that justified the lift.
- **Conflict & lifecycle UI.** The existing `ActiveAlert.saveFailed` surface gains a second producer: write failures originating in the bridge. `DocumentView`'s single-alert presentation rule is preserved (one alert at a time per document; the new producer does not double-fire when `SaveStatusObserver` also reports a save error for the same event).

The three Shape responsibilities map to four component-level extensions:

- **Save bridge — failure-as-outcome (File access layer).** *Extends seam: `MarkdownDocumentSaveBridge`.*
- **Save bridge — write coordination (File access layer).** *Extends seam: `MarkdownDocumentSaveBridge`; reuses pattern from `ChangeDetector.coordinatedRead*`.*
- **Reconciliation lift refresh (File access layer).** *Extends seam: `ChangeDetector.reconcileOnForeground()` (DC-23 lift branch).*
- **Save-failed alert routing (Conflict & lifecycle UI).** *Extends seam: `ActiveAlert.saveFailed` + `DocumentView` alert presentation (DC-3 narrow-observer convention).*

---

## Components

### 1. Save bridge — failure as a classified outcome (File access layer) — *primary*

Today the bridge's write path returns silently on any thrown error from the atomic write (recorded as a Wave-3 deferral in `resume-and-create-2/build-deviations.md`). This component reclassifies a failed write as an outcome the system surfaces to the user, while preserving the dirty buffer so the user's edits are not stranded.

**Public interface this project exposes:** the bridge gains one outbound notification (paired with the existing successful-write notification `onDidWrite`) that the host binds to the editor's alert surface. The host wires this notification at the same construction site that wires `onDidWrite` and `allowsSaveBack`, so error routing and success routing are co-located. The host is the caller that must bind to it; the contract is "every terminal write attempt resolves to exactly one of {success, failure}, and both are observable to the host."

**DC-1 — Every write attempt resolves to exactly one observable outcome.** A write attempt (debounced or immediate-flush) terminates as either *success* or *failure*, and the host observes which. No write attempt completes in a third "silently returned" state that the host cannot distinguish from success. The property the user sees: after any write attempt, the system has either advanced (clean against new disk content) or surfaced an error; it never appears advanced when it actually failed (BR-1.1, BR-1.4). *Extends seam: `MarkdownDocumentSaveBridge`; companion to existing `onDidWrite`.*

**DC-2 — Success-only side effects do not fire on failure.** The two side effects that fire today on a successful write — updating `MarkdownDocument.lastKnownDiskContent` to the just-written content, and opening the detector's settle window via the save-completed trigger — fire **only** on the success outcome. On failure neither fires (BR-1.5). The property: a failed write never makes the document falsely appear clean, and never opens a settle window that would suppress a real subsequent collision signal. *Extends seam: `ChangeDetector.noteSaveCompleted` + `MarkdownDocument.lastKnownDiskContent` (DC-9 of external-change-5).*

**DC-3 — Failure preserves the dirty buffer; success after failure clears it.** After a failed write attempt, the buffer remains dirty against `lastKnownDiskContent` (since DC-2 did not refresh it). A subsequent successful write — manual flush at backgrounding, or a later debounced write triggered by further typing — clears the dirty state via the normal success path (`onDidWrite` → settle window + `lastKnownDiskContent` refresh) exactly as the steady-state save path does today (BR-1.4, BR-1.6, NR-1.2/1.3). The property: failure is recoverable by the next successful save; no manual user action is required beyond their normal edit/idle pattern (or backgrounding).

**DC-4 — The save-back gate precedes the coordinated block.** The existing DC-22 gate (`allowsSaveBack`) is checked *before* entering the coordinator, not inside it (NR-4). The property: a classified collision/deletion suspends save-back without paying the cost of acquiring file coordination, and a gated-out attempt is neither a success nor a failure — it is simply not a write attempt and does not surface an alert. This preserves the existing DC-22 invariant that wrapping the write in a coordinator does not bypass the suspension latch.

### 2. Save bridge — write coordination (File access layer)

The bridge wraps each terminal write in `NSFileCoordinator.coordinate(writingItemAt:)`, matching the read-side convention the detector already uses. The coordinator becomes the serialization point between Markus's write and any other coordinated presenter (Markus's own detector, iCloud, other apps that have registered for the same URL).

**Reuses pattern:** the coordinated-read shape established by `ChangeDetector.coordinatedReadData(_:)` — instantiate an `NSFileCoordinator(filePresenter: nil)`, perform the file I/O inside the coordinator's closure, honor the security-scoped resource lifecycle around the inner URL the coordinator hands to the closure, and treat the coordinator's out-parameter error as terminal for the operation.

**DC-5 — Writes are serialized with the rest of the coordinated file world.** Every write attempt performed by the bridge runs inside `NSFileCoordinator.coordinate(writingItemAt:)`. The behavioral property: an external coordinated write injected concurrently with a Markus save does not produce a torn on-disk file — after both writes settle, the on-disk bytes are exactly one of the two writes' bytes, never a partial interleave (BR-2.1, BR-2.2). Coordination applies equally to debounced writes and to the immediate-flush write performed at backgrounding/teardown (BR-2.1, BR-12).

**DC-6 — Coordinated-or-fail; no uncoordinated fallback.** If the coordinator reports an acquisition error (timeout, contention, or any error surfaced via the coordinator's out-parameter), the bridge does **not** fall back to an uncoordinated atomic write as "best effort." The attempt resolves as failure per DC-1 and surfaces via DC-9 below (BR-2.3, BR-7). The property: a write either lands under coordination or does not land — there is no third "best-effort uncoordinated" path that would defeat the no-torn-file guarantee.

**DC-7 — Atomic-write failure inside the coordinated block is a clean failure.** If the underlying atomic write inside the coordinated block throws, the file on disk is either pre-write or post-write — never partial (the atomic-write contract). The bridge treats this as failure per DC-1; `lastKnownDiskContent` is not updated and the settle window does not open (DC-2), so the buffer stays dirty and the next save will retry the still-unsaved content (BR-8).

**DC-8 — Security-scoped resource discipline is preserved on both paths.** The `startAccessingSecurityScopedResource` / `stopAccessingSecurityScopedResource` pair is balanced across both the success and failure paths of the coordinated write (BR-2.4). The property: a repeated sequence of failing writes does not leak security-scoped accesses, and the existing scoped-resource lifetime guarantees that allow the file to be read/written at all are not weakened by the new coordinator wrapping. *Reuses seam: the coordinated-read scoped-resource pattern in `ChangeDetector.coordinatedReadData(_:)`.*

**DC-9 — No new user-visible delay on the steady-state path.** A save that does not race with any other coordinated work behaves indistinguishably to the user from the pre-hardening atomic write — typing → 500ms idle → write → clean state, with no perceptible coordination latency added (BR-2.5, NR-1.1–NR-1.4). The property is observational: the steady-state cadence of "typing settles, write happens, document is clean" is preserved; coordination's cost is only paid when there is actual contention with another presenter.

### 3. Save-failed alert routing (Conflict & lifecycle UI)

The host wires the bridge's failure notification (DC-1) into the existing `ActiveAlert.saveFailed` surface. No new alert type, banner, toast, or status surface is invented (OOS-4). The existing single-alert model in `DocumentView` continues to apply.

*Extends seam: `ActiveAlert.saveFailed`, `DocumentView.activeAlert`.*

**DC-10 — A write failure surfaces "Couldn't save" via the existing alert path.** When the bridge resolves a write attempt as failure (DC-1), the editor presents the existing "Couldn't save" alert with a message derived from the underlying error's localized description, and the existing dismiss action (BR-1.1, BR-1.2, BR-1.3). Dismissal closes the alert and performs no retry, no queueing, and no clearing of the dirty state (BR-1.3, DC-3). The property: the user is informed promptly and given an actionable surface; the document remains in a state from which a subsequent successful save can recover it.

**DC-11 — At most one save-failed alert per document at a time; the latest failure wins.** Multiple rapid write failures (e.g., permission revoked across three keystroke-driven debounces) coalesce into at most one presented alert at a time, consistent with the existing `ActiveAlert` single-alert model. If a new failure arrives while a save-failed alert is already presented, the alert reflects the most recent error (BR-5). The property: the user does not see a stack of identical alerts, and the latest error description is the one shown.

**DC-12 — A success after failure clears the failure surface; the prior alert does not re-surface.** Once a write succeeds (clearing dirty state via DC-3), the failure surface is treated as outcome-resolved: a previously dismissed alert is not re-presented on the next failure-free state change, and the system reflects the *latest* save outcome (BR-1.6, BR-6). The property: the alert tracks the live save state, not an accumulated history.

**DC-13 — Failure observed while no view is alive is latched and presented on next foreground.** When `saveSynchronously()` fires at backgrounding or scene-resign and the write fails, no view is alive to display the alert at the moment of failure. The failure is latched on the bridge (or on a host-owned channel the editor reads) and the alert is presented the next time `DocumentView` is foregrounded for that document (BR-4). Persistence across a cold launch is not required (BR-4). The buffer remains dirty across the backgrounding (DC-3). The property: backgrounded failures are not lost to the void; they are deferred to the next foreground appearance of the editor.

**DC-14 — Save-failed alert does not pre-empt a presented conflict sheet or deletion banner.** If a residual write attempt fires and fails despite the DC-22 suspension (e.g., a race in which classification lands a tick after the write enters the coordinator), surfacing the failure does not dismiss or pre-empt a presented conflict sheet or deletion banner — the conflict UI remains the primary surface; the save-failed alert may queue behind it or coalesce per DC-11, but the user's pending three-option choice is not lost (BR-11). The property: the conflict resolution surface has higher precedence than a save-failed alert; the user's pending deliberate choice is never wiped by a background failure notification.

**DC-15 — The bridge's failure surface and `SaveStatusObserver` do not double-fire.** `SaveStatusObserver` continues its narrow job — surfacing `UIDocument`-level save errors and download state (DC-3 of external-change-5). The new bridge-side error routing is *additional*, targeted at write failures originating in the bridge's coordinated atomic write, which are not reported by `SaveStatusObserver` today. The single-alert `ActiveAlert` model in `DocumentView` enforces the no-double-fire property: a single underlying save failure produces at most one presented "Couldn't save" alert at a time, regardless of which producer (bridge or observer) routed it (BR-5, NR-7, OOS-10).

### 4. Reconciliation lift refresh (File access layer)

`ChangeDetector.reconcileOnForeground()` (DC-23 of external-change-5) recovers a latched-but-surface-less outcome on foreground return by either re-presenting the surface or lifting suspension. Today the lift branch clears the latch and re-arms the detector, and *also* updates `lastKnownDiskContent` to the settled disk bytes when the file is present — but only on the same-location collision-was-cleared path. This component generalizes that refresh so the property holds across both lift sub-paths and so it is stated as a behavioral invariant, not a side effect.

*Extends seam: `ChangeDetector.reconcileOnForeground()` (DC-23 of external-change-5).*

**DC-16 — A lift on content-identity refreshes the last-known-disk reference to the settled bytes that justified the lift.** When `reconcileOnForeground()` takes the lift branch because the live buffer is content-identical to settled disk under the existing equality gate (DC-11 of external-change-5), `MarkdownDocument.lastKnownDiskContent` is set to those settled disk bytes before suspension is lifted (BR-3.1, BR-3.3). The property: immediately after such a lift, the document is clean against disk, and the next debounced or explicit save attempt is a no-op against disk because the buffer equals `lastKnownDiskContent` (BR-3.2). A subsequent save cannot clobber a fresher-but-equal disk state the user never observed.

**DC-17 — A lift on a moved-successor where contents now agree refreshes against the settled bytes at the new location.** When the lift branch is taken because the file has reappeared as a move successor whose settled bytes agree with the live buffer (BR-3.5), the same refresh property holds at the retargeted location: `lastKnownDiskContent` matches the settled bytes at the new location after the lift, and a subsequent save does not clobber it. *Reuses seam: `ChangeDetector` retarget path (DC-19 of external-change-5).*

**DC-18 — The lift refresh never mutates the buffer.** Only `lastKnownDiskContent` is updated. The visible text, cursor, and scroll position are preserved (BR-3.4), consistent with DC-12 (absorb) of external-change-5. The property: if the user happens to type one more character between the content-identity sample and the lift completion, the lift does not overwrite that character — the resulting state is "buffer dirty against fresh `lastKnownDiskContent`", and the next save will write the typed delta, which is correct and not a regression (BR-9).

**DC-19 — The re-present branch is unaffected; lift-refresh is the lift branch's contract only.** When `reconcileOnForeground()` takes the re-present branch because the outcome still holds (collision still materially differs, or file still genuinely absent), `lastKnownDiskContent` is **not** silently refreshed — a refresh there would defeat the surfaced choice (BR-3.6, NR-6). The property: the re-present path remains exactly as DC-23 of external-change-5 specifies; only the lift sub-paths gain the refresh contract.

**DC-20 — Disk-read failure during reconciliation does not synthesize a lift.** If the coordinated read inside `reconcileOnForeground()` returns nil (read failed, file inaccessible), the lift's content-identity branch does not run against a stale reference (BR-10). The existing reconciler logic remains the authority on whether a lift is taken; this component only constrains what happens *when* the lift fires. The property: this design does not introduce a new lift path, only a refresh obligation on existing lift paths.

---

## Seam relationships (data flow)

```
host presents document
        │
        ├── creates ──► save bridge
        │                  │ write attempt (debounced or saveSynchronously):
        │                  │   1. check allowsSaveBack gate          (DC-4)
        │                  │   2. enter NSFileCoordinator(writingItemAt:)  (DC-5)
        │                  │   3. atomic write inside coordinated block    (DC-7)
        │                  │   4. balance scoped-resource access           (DC-8)
        │                  └─► outcome resolves to success OR failure      (DC-1)
        │                         │                     │
        │                         ▼                     ▼
        │                     onDidWrite           onDidFailWrite
        │                  (lastKnownDisk +     (route to ActiveAlert.saveFailed
        │                   settle window)       via host; latch if backgrounded)
        │                       (DC-2, NR-1)      (DC-10, DC-11, DC-13)
        │
        └── creates ──► change detector
                            │
                            │ reconcileOnForeground() on scene→active:
                            │   ┌─ re-present  → activeSurface, NO refresh    (DC-19)
                            │   └─ lift        → refresh lastKnownDiskContent (DC-16/17),
                            │                     preserve buffer/cursor       (DC-18),
                            │                     re-arm detector
                            ▼
                  editor (DocumentView) presents:
                  - "Couldn't save" alert         (DC-10, DC-14 precedence)
                  - conflict sheet / deletion banner (unchanged from external-change-5)
```

The bridge and the detector share two pieces of state owned by `MarkdownDocument`: `lastKnownDiskContent` (DC-9 of external-change-5) and the followed location. This feature does not change *who* writes those values; it strengthens *when* the bridge writes `lastKnownDiskContent` (only on success — DC-2) and extends *when* the detector writes it (on every lift, not just incidentally — DC-16/17). The DC-22 save-back suspension latch continues to be the single mutual-exclusion mechanism between the bridge and the detector; coordination is orthogonal to it (DC-4).

---

## Prescription-feedback resolution

*The declaration and requirements name three implementation specifics that orient the build agent but should not be tested as call shapes: `NSFileCoordinator.coordinate(writingItemAt:)`, `MarkdownDocumentSaveBridge.writeNow()`, and the four-state `ActiveAlert.saveFailed` case. These names remain in the design as orientation; the **properties they protect** are the behavioral surface tests assert.*

- **`NSFileCoordinator.coordinate(writingItemAt:)` → "writes are serialized with the rest of the coordinated file world; no torn writes."** The API name is the declaration's chosen mechanism, but the test surface is the observable end-state: under injected concurrent external coordinated writes, the on-disk bytes are always exactly one writer's bytes, never a partial interleave (DC-5, BR-2.2). Tests need not name the coordinator type.
- **`MarkdownDocumentSaveBridge.writeNow()` → "every write attempt resolves to exactly one observable outcome."** The bridge's internal write path is named in the requirements because that is where the swallow lives today; the contract it protects is DC-1 — failure is observable to the host, never a silent return. Tests assert the outcome reaches the editor's alert surface (or the latch, when backgrounded), not the function's name.
- **`ActiveAlert.saveFailed` → "save failures present on the existing single-alert surface; at most one at a time per document."** The case name pins the reuse target (no new banner/toast/status surface invented). Tests assert single-alert behavior, latest-error-wins coalescing, no double-fire with `SaveStatusObserver`, and that the conflict sheet/banner outranks it (DC-10, DC-11, DC-14, DC-15).

## Behavioral test anchors (for `/tests`)

These restate the now-pinned properties so spec tests can assert concretely:

- **DC-1/DC-10:** force a write to throw (revoked permission, simulated I/O failure) → the "Couldn't save" alert appears on the existing alert surface, the buffer remains dirty against `lastKnownDiskContent`, and `lastKnownDiskContent` is unchanged from before the failed attempt (BR-1.1, BR-1.4, BR-1.5).
- **DC-3:** after a failed write, allow the next debounced write to succeed → the document becomes clean, the alert does not re-surface, and the settle window opens exactly as steady-state (BR-1.6, NR-1.2/1.3).
- **DC-5/DC-7:** inject a concurrent external coordinated write during a Markus save → final on-disk bytes are exactly one of the two writes' bytes, never a partial mix (BR-2.2).
- **DC-6:** force the coordinator to fail acquisition → outcome is failure (not a silent uncoordinated fallback) and the alert surfaces (BR-2.3, BR-7).
- **DC-8:** repeat a failing write many times in a row → no leak of security-scoped resource accesses (BR-2.4); subsequent successful writes still work.
- **DC-11:** drive multiple rapid failed writes → at most one alert presented, message reflects the latest error (BR-5).
- **DC-13:** background the app with a pending write that fails during `saveSynchronously()` → on next foreground of the document, the alert appears; buffer was preserved across the backgrounding (BR-4, BR-12).
- **DC-14:** with a conflict sheet presented, drive a residual save attempt that fails → sheet remains the primary surface; user's three-option choice is not pre-empted (BR-11).
- **DC-15:** verify that a single underlying save failure produces at most one alert across the bridge and `SaveStatusObserver` paths combined (NR-7).
- **DC-16/DC-18:** background with a clean buffer pending content-identity reconciliation, foreground → lift fires, `lastKnownDiskContent` matches settled disk, the next save is a no-op (BR-3.1, BR-3.2). Type one character between sample and lift → the typed character is preserved; only `lastKnownDiskContent` is refreshed; the next save writes the delta (BR-3.4, BR-9).
- **DC-17:** lift on a moved successor whose contents now agree → at the new location, `lastKnownDiskContent` matches the settled bytes; subsequent save is a no-op against the new location (BR-3.5).
- **DC-19:** verify the re-present branch does **not** refresh `lastKnownDiskContent` — re-presenting must not pre-empt the user's pending choice by silently agreeing with disk (BR-3.6, NR-6).
- **NR-1–NR-7:** steady-state save still coalesces typing on 500ms idle into a single coordinated write per gap; external-change silent absorb still occurs without spurious save-failed alerts; the three-option sheet still appears under true collision; DC-22 gate still suppresses writes from classification; Keep Mine / Save As inherit coordinated + error-surfaced semantics; `reconcileOnForeground()` re-present branch unchanged; `SaveStatusObserver` keeps its narrow job.

---

Architecture stable — no requirements changes flagged
