# Requirements — Resume and Detector Hardening

*Behavioral requirements for the "resume-and-detector-hardening-11" feature. Scope is limited to the two audit findings in `features/resume-and-detector-hardening-11/declaration.md`: (1) bookmark-fallback in `LastFileStore.resolveLastOpened()`, and (2) ordered start of `ChangeDetector.start()` so the initial coordinated read precedes live `NSFilePresenter` callbacks. Existing resume requirements (resume-and-create-2) and existing detector requirements (external-change-5) are inherited and not restated; this document covers only the deltas needed to close the two gaps.*

---

## User stories with acceptance criteria

### Story A — Resume across moves and renames

> As a writer who reorganizes my iCloud folders between writing sessions, I want the app to still resume into my last-opened file when I've moved or renamed it, rather than silently dropping me back at the document browser.

**BR-1 — Bookmark is the authoritative resume target.**
On launch, when a stored last-opened reference exists, the resume target is the URL produced by resolving the stored security-scoped bookmark. The recorded path string is consulted only to confirm reachability of the originally-opened location; it is not the identity of the file.
*Observable:* With a stored bookmark for file X recorded at path P, when X has been moved to a different path Q (still resolvable through its bookmark), launching the app produces a resume target whose URL is Q, not P, and not nil.

**BR-2 — Fall back to bookmark when recorded path is gone.**
When the stored bookmark resolves successfully but the recorded path string no longer points at a file, `resolveLastOpened()` returns the bookmark-resolved URL (provided that URL itself is reachable and readable) instead of returning nil.
*Observable:* Record file X at path P, move X to Q in the same security scope, relaunch → `resolveLastOpened()` returns a URL pointing at Q. The app opens directly into the rendered view of X-at-Q (per BR-2 of resume-and-create-2, which is now satisfied via the bookmark rather than the path).

**BR-3 — No regression when the recorded path still resolves.**
When the recorded path still points at the originally-opened file, `resolveLastOpened()` returns a URL for that same file (current behavior). No additional disk work is performed beyond what the current path-check + bookmark resolution already does.
*Observable:* Record file X at path P, do not move it, relaunch → `resolveLastOpened()` returns a URL whose path is P (or the bookmark-equivalent for P), and the resume flow opens X-at-P as before.

**BR-4 — Bookmark-resolved URL must itself be reachable.**
If the recorded path is missing AND the bookmark-resolved URL is also unreachable or unreadable (file deleted entirely, sync placeholder undownloadable, permission lost, security scope refused), `resolveLastOpened()` returns nil and the launch falls through to the document browser silently — preserving BR-5 of resume-and-create-2.
*Observable:* With a stored bookmark whose resolved URL no longer exists on disk, `resolveLastOpened()` returns nil; the document browser is the first interactive screen; no error UI is shown.

**BR-5 — RETAIN-on-failure is preserved end-to-end.**
A launch on which `resolveLastOpened()` returns nil (BR-4) does not clear the stored bookmark or recorded path. A later launch on which the bookmark can again resolve (e.g. the file reappears, sync downloads the placeholder) successfully resumes via the bookmark path of BR-2.
*Observable:* After a failed resolution, `LastFileStore.hasRecord` is still true; a later relaunch with the file reachable again resumes into it.

**BR-6 — Silent resume on bookmark-fallback.**
The bookmark-fallback resume (BR-2) presents no banner, toast, or alert indicating that the file's path changed. It is indistinguishable from a same-path resume to the user.
*Observable:* Move file X between launches → on relaunch, the rendered view of X-at-new-location is the first interactive screen with no transient "your file moved" UI of any kind.

**BR-7 — Stale-bookmark handling unchanged.**
If the bookmark itself is stale (`bookmarkDataIsStale == true`) or throws on resolution, the failure is treated as in BR-4: return nil, retain the record, fall through silently. Refreshing a stale bookmark is not in scope here (see Out of scope).
*Observable:* With a stale stored bookmark, `resolveLastOpened()` returns nil; `hasRecord` remains true; no crash.

---

### Story B — Detector start without a callback race

> As a user whose iCloud sync writes to my open file the instant the app comes back to the foreground, I want the detector to not miss or mis-classify that write because it happened while the detector was still initializing.

**BR-8 — Initial coordinated read precedes live presenter callbacks.**
`ChangeDetector.start()` completes an initial coordinated read of the displayed URL and seeds the detector's initial-state slot (`document.lastKnownDiskContent` or equivalent) before any `NSFilePresenter` callback (`onChange` / `onMove` / `onDelete`) is allowed to run its handler body.
*Observable:* In a test that registers a presenter, schedules an external write to land between presenter registration and the moment `start()` returns, and observes the sequence — the initial coordinated read is recorded before any change-callback handler observes its first event. There is no point in time at which a callback handler can read `lastKnownDiskContent` while it is still in its pre-start placeholder state.

**BR-9 — External change landing during start is not lost.**
An external write delivered while `ChangeDetector.start()` is executing is either:
  (a) absorbed cleanly into the initial read (the presenter's first callback then observes the post-write content as the current state with no surface raised), or
  (b) processed as a normal post-start change against the initial read (the callback fires after start completes and is classified against a non-placeholder `lastKnownDiskContent`).
In neither case is the event silently dropped, and in neither case is `lastKnownDiskContent` left torn (partially-written, mismatched against what the classifier sees).
*Observable:* In a test that injects an external write during start, the resulting detector state at quiescence is either (a) absorbed silently with `lastKnownDiskContent` equal to the post-write content and no `activeSurface`, or (b) a correctly-classified outcome (absorb / collision) consistent with the buffer at the time the callback fired. The test never observes a final state where `lastKnownDiskContent` differs from the content actually on disk at quiescence with no callback pending.

**BR-10 — No callback handler runs against placeholder initial state.**
No code path inside `handleDidChange`, `handleDidMove`, or `handleDidDelete` executes its classification logic before the initial read of BR-8 has been recorded. Callbacks that arrive earlier are queued, deferred, or otherwise serialized after the initial read; they are not dropped.
*Observable:* In a test that forces a callback to be enqueued before the initial read finishes, the classification step is observed to run only after the initial-read seed has been written. Inserting an assertion at the top of each handler body that "initial state is seeded" never fires false.

**BR-11 — `start()` is idempotent and safe to call once per detector lifetime.**
Calling `start()` exactly once per `ChangeDetector` instance is the supported pattern (matching current usage). Behavior on a second `start()` call without an intervening `stop()` is unchanged from today (no new guarantees added or removed by this feature).
*Observable:* A single `start()` → `stop()` cycle in a test produces the BR-8/BR-9/BR-10 guarantees; calling `start()` twice without `stop()` is not exercised by new tests.

**BR-12 — No regression to steady-state detector behavior.**
After `start()` returns, the detector behaves identically to its pre-hardening self for all subsequent events: settle window, in-flight-sync suppression, apply-edge re-validation, collision/absorb/move/delete classification, save-suspension latch, foreground reconciliation. The change is confined to the start sequence.
*Observable:* The existing external-change-5 test suite continues to pass without modification. No external-change-5 BR is contradicted or weakened.

**BR-13 — Initial read failure is non-fatal.**
If the initial coordinated read in BR-8 fails (file unreadable, coordination error, invalid UTF-8), `start()` still completes and the presenter still becomes live; the detector treats the failure equivalently to "no initial seed change from the value the host passed in" and the next live callback re-evaluates from there. The app does not crash and no surface is raised solely because the initial read failed.
*Observable:* In a test where the file at `displayURL` is briefly unreadable during start, `start()` returns without throwing; `activeSurface` is nil; a subsequent successful change callback classifies normally against whatever `lastKnownDiskContent` the host seeded prior to start.

---

## Edge cases and failure modes

**BR-14 — Bookmark resolves to a different security scope than the recorded path.**
If the recorded path points at a location the app no longer has access to, but the bookmark resolves to a reachable URL in a still-valid security scope, BR-2 applies: the bookmark-resolved URL is returned. The recorded path is not used to gate access.
*Observable:* Move the file across containers such that the original path is no longer accessible but the bookmark's security scope still grants access at the new URL → `resolveLastOpened()` returns the new URL.

**BR-15 — Both path and bookmark target the same file.**
When the recorded path exists AND the bookmark resolves to the same file at the same path (the steady-state case), `resolveLastOpened()` returns that URL once. No double-resolution, no extra access-start/stop pair beyond what the current implementation does.
*Observable:* Steady-state resume → exactly one URL returned; no observable difference from today's behavior at the call site.

**BR-16 — Path exists but bookmark resolution throws.**
If the recorded path still points at a file but the bookmark itself fails to resolve (throws), the result is nil (current behavior). The recorded path alone is not a sufficient resume target without a working bookmark — security-scoped access requires the bookmark.
*Observable:* With a corrupt bookmark and an existing file at the recorded path, `resolveLastOpened()` returns nil; `hasRecord` remains true (BR-5).

**BR-17 — Presenter callback arrives before `start()` is called.**
Callbacks cannot arrive before `start()` is called, because the presenter is not registered until inside `start()`. This BR is recorded only to make the precondition explicit: BR-8/BR-10's "before live callbacks" window begins at presenter registration and ends when the initial read seed is recorded.
*Observable:* No test for "callback before start" is required; the surface area does not exist.

**BR-18 — Presenter callback arrives during initial read.**
If a `NSFilePresenter` callback is dispatched by the system between presenter registration and the completion of the initial coordinated read, BR-10's deferral applies. The detector does not process two reads concurrently in a way that leaves `lastKnownDiskContent` torn between them.
*Observable:* In a test that injects a presenter callback while the initial read is in progress, the final `lastKnownDiskContent` is consistent with the content the classifier saw when it ran (no half-applied initial read).

**BR-19 — Synchronous vs. asynchronous start.**
The synchronous-vs-asynchronous nature of `start()` is an implementation choice (see Architectural resolution needed). BR-8/BR-10 are stated as a happens-before relation, not a calling-thread guarantee. Callers must not assume that `start()` returning means subsequent reads of `lastKnownDiskContent` from arbitrary threads are immediately consistent — they must continue to observe the existing main-actor isolation.
*Observable:* Tests run on the main actor (as the detector already requires) and observe BR-8 ordering there.

---

## Out of scope

*Carried from the feature declaration plus relevant project/precedent exclusions.*

- **Persisting additional resume metadata.** Only the existing bookmark + path are read/written. No new defaults keys, no last-seen-directory, no file identifier cache.
- **Refreshing stale bookmarks.** When `bookmarkDataIsStale == true`, the bookmark may still be resolved-and-returned (current behavior); rewriting a refreshed bookmark back into `UserDefaults` is not part of this feature.
- **Surface UI for "your last file moved."** No banner, toast, alert, or analytics event. Silent successful resume only.
- **Reworking `NSFilePresenter` registration model.** Only the ordering of initial read vs. presenter live-ness changes. Registration topology, presenter lifetime, and re-registration on rename (`retarget`) are unchanged.
- **Save-side hardening** — `save-bridge-hardening-9`.
- **Open-side hardening** — `open-path-hardening-10`.
- **Cross-device handoff / multi-scene restoration.** Inherited from resume-and-create-2.
- **Settings or user-configurable resume behavior.** Inherited from the project declaration.
- **Changes to classification logic, settle window, latch behavior, or apply-edge re-validation.** Out of scope; this feature is purely about start-time ordering and bookmark-vs-path policy.

---

## Architectural resolution needed

1. **Mechanism for "initial read before live callbacks" (BR-8/BR-10/BR-18).** The requirement is a happens-before relation, not a specific implementation. Design must choose between: (a) perform the coordinated read synchronously inside `start()` and register the presenter only after it returns; (b) register the presenter but gate all handler bodies behind a "ready" flag set once the initial read completes; (c) some hybrid. Each choice has different implications for callbacks that arrive during the gap. Design must specify the chosen mechanism, the queueing/deferral policy for BR-10, and how BR-13 (initial-read failure) interacts with the chosen gate.

2. **Reachability check after bookmark fallback (BR-2/BR-4).** When the recorded path is missing and the bookmark resolves, design must specify the reachability probe applied to the bookmark-resolved URL: `FileManager.fileExists(atPath:)` inside a `startAccessingSecurityScopedResource` block (mirroring the current "no recorded path" fallback branch) is the obvious choice but should be confirmed. Design should also specify whether the recorded path string is updated to the bookmark-resolved path on a successful fallback, or left untouched until the next `recordLastOpened` — the declaration's "Out of scope: persisting any additional resume metadata" leans toward the latter, but this is a design call.

3. **Behavior of `displayURL` during the start gate (BR-8 interaction with `init`).** `displayURL` is set in `init` and is the URL the initial coordinated read uses. Design should confirm that no path other than the constructor seeds `displayURL` before `start()` runs, so the initial read is unambiguous about which URL it reads.
