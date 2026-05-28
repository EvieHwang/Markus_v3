# Design — Resume and Detector Hardening

*Architecture for `resume-and-detector-hardening-11`. Source of truth for intent: `features/resume-and-detector-hardening-11/declaration.md`; behavior: `features/resume-and-detector-hardening-11/requirements.md`. Inherits the architectures of `resume-and-create-2` (LastFileStore / launch resume branch) and `external-change-5` (ChangeDetector / FilePresenterShim / settle gate / apply-edge re-validation). Every constraint below (DC-n) is phrased as an observable property; the single deliberate exception is the `displayURL` seeding rule (DC-9), which the requirements explicitly raise as a call-shape contract.*

**Deferred-question resolution.** This design resolves the three architecture questions left open at the bottom of `requirements.md`:
- (1) Mechanism for "initial read before live callbacks" (BR-8/BR-10/BR-18) → §Start ordering, **DC-6/DC-7/DC-8**.
- (2) Reachability probe after bookmark fallback, and whether to update the recorded path (BR-2/BR-4) → §Bookmark fallback, **DC-3/DC-4**.
- (3) `displayURL` seeding during the start gate (BR-8 vs. `init`) → §Start ordering, **DC-9**.

None of the three resolutions required changing requirement *text*; accordingly the requirements bottom marker is flipped to stable as part of this step.

---

## Ground-truth check (seams consulted before drafting)

- `Markus_v3/Resume/LastFileStore.swift` — the existing resolve path: resolves the bookmark, then checks `FileManager.fileExists(atPath: recordedPath)` and returns `nil` if the recorded path is gone. There is already a "no recorded path" fallback branch that probes the bookmark-resolved URL inside `startAccessingSecurityScopedResource`. RETAIN-on-failure is preserved end-to-end (the store never clears on a failed resolve).
- `Markus_v3/ExternalChange/ChangeDetector.swift` — `start()` today constructs a `FilePresenterShim` bound to `displayURL` and immediately calls `shim.register()`. There is no coordinated read inside `start()`; the detector relies on the host having seeded `document.lastKnownDiskContent` at present-document time. `displayURL` is set once in `init`, mutated only in `retarget(to:)` (which is reachable only via a presenter move callback, i.e. after `start()`).
- `Markus_v3/ExternalChange/FilePresenterShim.swift` — `NSFilePresenter` callbacks arrive on `presentedItemOperationQueue` (off-main); the shim hops to `@MainActor` before invoking `onChange` / `onMove` / `onDelete`. Each handler enters via `Task { @MainActor in ... }`, so even if the system posts a callback synchronously to the operation queue during `register()`, the handler body itself does not run until the main actor turn lands.
- Precedent design `features/external-change-5/design.md` — DC-1/DC-2 (coordinated never-torn reads), DC-9 (last-known-disk content is the single reference), DC-21 (apply-edge re-derivation). These are the invariants that the start-time ordering must extend, not replace.
- Precedent design `features/resume-and-create-2/design.md` — DC-5 (RETAIN-on-failure, REPLACE-on-success). The bookmark-fallback policy here strengthens what counts as "successfully resolved" without weakening retention.

---

## High-level shape

This feature adds **no new components**. It tightens two existing ones:

- **LastFileStore.resolveLastOpened** gains a bookmark-fallback branch: when the recorded path is missing, the resolver probes the bookmark-resolved URL for reachability under security scope and returns it on success.
- **ChangeDetector.start** gains an *ordered start sequence*: an initial coordinated read of `displayURL` is performed and `document.lastKnownDiskContent` is seeded **before** the `NSFilePresenter` shim is registered, so a presenter callback handler body can never run against placeholder initial state.

Both changes are confined to the **File access layer**. No Document model change, no UI change, no save-bridge change.

---

## Components touched

### C1 — LastFileStore (bookmark-fallback resolve)
*Reuses pattern: security-scoped bookmark (from `resume-and-create-2` DC-1/DC-5).*

`LastFileStore` continues to be the sole durable last-opened reference. The resolve path is extended: the *recorded path string is downgraded from gating identity to reachability hint*. When the bookmark resolves but the recorded path no longer exists, the resolver does not give up; it probes the bookmark-resolved URL under security scope and, on success, returns it. RETAIN-on-failure is unchanged — the store never clears on a failed resolve, regardless of which branch failed.

### C2 — ChangeDetector (ordered start)
*Extends seam: `ChangeDetector` from `external-change-5`.*

`ChangeDetector.start()` becomes an ordered two-step: (1) perform an initial coordinated read of `displayURL` and update `document.lastKnownDiskContent` from it; (2) only then construct and register the `FilePresenterShim`. The detector does not introduce a "ready" flag in handlers because step (1) is synchronous on the main actor *and* step (2) is the action that makes callbacks reachable at all — there is no window in which a registered presenter exists before the initial read has been recorded. This is the chosen mechanism for BR-8/BR-10/BR-18 (option (a) of the requirements' choice list); see DC-7 for why option (b)'s "gate handler bodies behind a ready flag" was not chosen.

### FilePresenterShim, MarkdownDocument, SettleGate, save bridge
**Unchanged.** No new fields, no new entry points. The host's existing seeding of `document.lastKnownDiskContent` at present-document time is preserved as the *prior* value the initial read overwrites on success (and falls back to on initial-read failure, DC-8).

---

## Behavioral contracts (design constraints)

### Bookmark fallback

**DC-1 — Bookmark identity, path as hint.** The stored security-scoped bookmark is the identity of the last-opened file; the recorded path string is consulted only as a fast reachability hint for the originally-opened location. When the two disagree about reachability, the bookmark wins. *(BR-1, BR-14)*
*Observable:* Recording file X at path P and moving X to Q (same security scope) yields a resume URL pointing at Q, not P, and not nil.

**DC-2 — No regression in the steady-state branch.** When the recorded path still points at a file, the resolver behaves exactly as today: it returns the bookmark-resolved URL after the `fileExists(atPath:)` check passes, without performing any additional disk work, additional security-scope start/stop pairs, or extra coordinated reads. *(BR-3, BR-15)*
*Observable:* In a same-path resume, the number of `startAccessingSecurityScopedResource` calls and the number of `fileExists` probes inside `resolveLastOpened()` is identical to today's count.

**DC-3 — Bookmark-fallback reachability probe. (Resolves architecture Q2, part 1.)** When the recorded path is present but `FileManager.fileExists(atPath: recordedPath)` is false, the resolver does not return nil immediately. It instead probes the bookmark-resolved URL by calling `FileManager.fileExists(atPath: url.path)` inside a `startAccessingSecurityScopedResource` / `stopAccessingSecurityScopedResource` pair on that URL — the same probe used by the existing "no recorded path" fallback branch. If the probe succeeds, the bookmark-resolved URL is returned; if it fails (file absent, sync placeholder undownloadable, permission denied, security scope refused), the resolver returns nil. *Rationale for this probe and not a coordinated read:* `resolveLastOpened()` runs at launch on the main actor before any document is presented, and its callers only need to know whether the URL is *worth opening*; whole-content coordinated reads are the open path's job (and would couple resume timing to file size). The `fileExists` probe under security scope is the minimum that confirms what BR-4 calls "reachable and readable" at resume-decision time; downstream open-path errors (e.g. permission lost between resume decision and actual open) continue to fall through the open-path-hardening surfaces, not this resolver. *(BR-2, BR-4, BR-7, BR-14, BR-16)*
*Observable:* Move X out of recorded path P into Q (same scope) → resolver returns Q. Delete X entirely → resolver returns nil. Corrupt the bookmark → resolver returns nil (BR-7/BR-16). Stale-but-resolvable bookmark whose URL is reachable → resolver returns that URL (stale handling is unchanged — see DC-5).

**DC-4 — Recorded path is not rewritten on fallback. (Resolves architecture Q2, part 2.)** A successful bookmark-fallback resolve does **not** update the persisted recorded path string. The path string is only ever written by `recordLastOpened(_:)` — i.e., by the host observing an actual open. *Rationale:* the feature declaration's Out-of-scope explicitly forbids "persisting any additional resume metadata," and `recordLastOpened` is the existing canonical funnel for any path/bookmark update (the host calls it via `DocumentOpenObserver` when the resumed document becomes active, so the path is corrected through the normal path on the very next steady-state turn). Rewriting from inside the resolver would introduce a second persistence site, force a write on every cold launch that took the fallback branch (silent disk I/O the user did not trigger), and risk drift if the host's open later fails after the resolver has already mutated the store. Letting the existing record-on-open path correct the discrepancy keeps the store's write set to one well-known site. *(BR-2 Observable note; declaration Out-of-scope §1)*
*Observable:* Take the bookmark-fallback branch on a launch and then terminate the app before any open completes → the persisted recorded path is unchanged from before the launch. A subsequent successful launch that opens the file via the normal flow updates the recorded path through `recordLastOpened` as today.

**DC-5 — Stale bookmark handling unchanged.** When `bookmarkDataIsStale == true`, the resolver does not throw, does not refresh, does not rewrite — it returns the resolved URL if it is reachable per DC-3 and nil otherwise. Refreshing the bookmark is out of scope (declaration Out-of-scope §2). *(BR-7)*
*Observable:* With a stale-but-resolvable bookmark, the resolve still returns the URL; with a stale-and-unresolvable bookmark, nil; in both cases `hasRecord` remains true.

**DC-6 — RETAIN-on-failure end-to-end.** Neither the recorded-path-missing branch (DC-3 failure case) nor the stale-throw branch (DC-5 failure case) clears the stored bookmark or recorded path. `hasRecord` remains true; a later relaunch with the file reachable again resumes via the bookmark path of DC-1/DC-3. *(BR-4, BR-5)*
*Observable:* After any resolve that returned nil, `hasRecord` is still true; recovery on a later successful resolve is automatic and silent (no banner, no toast, DC-6 of resume-and-create-2 applies). Silent resume on fallback is preserved (BR-6) because the resume flow downstream of the resolver does not inspect *which branch* yielded the URL.

### Start ordering (initial read before live callbacks)

**DC-7 — Initial read precedes presenter registration. (Resolves architecture Q1.)** `ChangeDetector.start()` performs a coordinated read of `displayURL` and writes the decoded UTF-8 string into `document.lastKnownDiskContent` **before** constructing or registering the `FilePresenterShim`. The presenter is not added to `NSFileCoordinator` until the initial read step has run to completion. This is option (a) of the requirements' choice — synchronous initial read, then register — and it is preferred over option (b) (register and gate handler bodies behind a `ready` flag) for three reasons. First, there is no live callback window for option (b) to need: a presenter that has not yet been added cannot receive callbacks, so the gate is trivially satisfied by registration order rather than by a per-handler boolean. Second, the detector is `@MainActor`-isolated and so is the initial read; the read runs on the same actor turn that `start()` was invoked on, so the ordering is a happens-before from program order, not a cross-thread memory contract — testable directly without test infrastructure that races presenter callbacks against a flag. Third, option (b) requires either dropping or queuing callbacks that arrive during the gap; option (a)'s gap is empty, so neither drop nor queue is needed and BR-10's "not dropped" is satisfied vacuously. *(BR-8, BR-10, BR-11, BR-17, BR-18, BR-19)*
*Observable:* In a test that observes the sequence — call `start()`, then trigger an external write and let presenter callbacks fire — the very first time any handler body executes, `document.lastKnownDiskContent` already reflects the initial-read result (or the pre-start host-seeded value if the initial read failed per DC-8). No handler ever observes the pre-start placeholder state in a window between "presenter live" and "initial read recorded," because that window does not exist.

**DC-8 — Initial-read failure is non-fatal, falls through to host-seeded prior. (Resolves architecture Q1 interaction with BR-13.)** If the initial coordinated read in DC-7 fails (file unreadable, coordination error, invalid UTF-8 bytes that do not decode to a String), `start()` leaves `document.lastKnownDiskContent` at whatever value the host seeded prior to start (the existing pre-feature behavior), then proceeds to register the presenter. The detector does not raise `activeSurface`, does not call `onInvalidEncoding`, does not throw out of `start()`. The next live callback re-evaluates against the host-seeded prior via the existing `handleDidChange` path, which already handles invalid-UTF-8 routing (the existing `rawBytes` / `onInvalidEncoding` branch in `handleDidChange`) and unreadable-file routing (returns and waits for the next event). *Rationale:* the requirement (BR-13) is "start completes; presenter becomes live; the detector falls back to host-seeded prior." That is exactly the contract above. Raising a surface from `start()` would mean a freshly-opened document can present a conflict sheet before the user has touched anything, which contradicts the silent-resume promise and external-change-5's BR-3 (no spurious surface around open). *(BR-13)*
*Observable:* In a test where the file at `displayURL` is briefly unreadable during start, `start()` returns without throwing, `activeSurface` is nil, and a later successful change callback classifies normally against the host-seeded `lastKnownDiskContent`.

**DC-9 — `displayURL` is seeded only in `init`; not mutated before `start()`. (Resolves architecture Q3.) *Call-shape contract, deliberately.*** Between the `ChangeDetector` constructor returning and `start()` being invoked, `displayURL` is read-only externally and is not mutated by the detector itself. The detector exposes no setter, no "retarget before start" path; the only existing mutation of `displayURL` is inside `retarget(to:)` (precedent `external-change-5` DC-19), which is reachable only via a presenter move callback — and presenter callbacks are not live until inside `start()` (DC-7). This is one of the rare cases where the call shape *is* the contract: the initial read of DC-7 must be unambiguous about *which* URL it is reading, and the way to make that unambiguous to a test, a build agent, and a future maintainer is to forbid intervening writers between `init` and `start`. Naming this constraint here avoids a future edit that adds a "preload" or "rebind" setter and silently reintroduces the window the feature exists to close. *(BR-8 init-interaction note in requirements; BR-17 precondition note)*
*Observable:* Read `displayURL` immediately before calling `start()` and immediately after `start()` begins its initial read; both observations yield the URL passed into `init`. There is no public surface on `ChangeDetector` by which an external caller can change `displayURL` before `start()` runs.

**DC-10 — Idempotency / second-start behavior unchanged.** A second `start()` call without an intervening `stop()` retains today's behavior (no new guarantee added or removed). Tests added by this feature exercise a single `start()` → `stop()` cycle only. *(BR-11)*
*Observable:* The existing call-once usage pattern in `BrowserHostController.presentDocument` (one `start()` per detector instance) continues to satisfy DC-7/DC-8.

**DC-11 — No regression to steady-state detector behavior.** After `start()` returns, every steady-state behavior from `external-change-5` (settle window, in-flight-sync suppression, presence ordering, apply-edge re-validation, save-suspension latch, foreground reconciliation) is unchanged. The added initial-read step does not consume a settle trigger of its own — settle openness on open continues to be driven by `settleGate.noteTrigger(.opened, at:)` in `init` as today, not by the new initial read. *(BR-12)*
*Observable:* The full `external-change-5` test suite continues to pass without modification; no DC from that feature's design.md is contradicted.

---

## Seam relationships

```
launch (LaunchResumeBranch from resume-and-create-2)
        │
        ▼
  LastFileStore.resolveLastOpened()
        │  (DC-1: bookmark is identity)
        ├─ recorded path exists at file ──► return bookmark-resolved URL          (DC-2)
        ├─ recorded path missing ─────────► probe bookmark-resolved URL under
        │                                   security scope (DC-3) ──► return URL
        │                                                          └─► nil if probe fails (DC-3, DC-6)
        └─ bookmark stale / throws ──────► resolve-if-possible per DC-5, else nil (DC-6)
                                            (recorded path never rewritten — DC-4)
                                            (hasRecord retained on every failure — DC-6)
        │
        ▼
  host presents document, seeds document.lastKnownDiskContent (existing)
        │
        ▼
  ChangeDetector.start()
        │ (DC-9: displayURL is the URL passed in init; unchanged since)
        ├─ initial coordinated read of displayURL (DC-7)
        │     │
        │     ├─ success: document.lastKnownDiskContent ← decoded UTF-8
        │     └─ failure: leave host-seeded value untouched (DC-8)
        │
        └─ construct FilePresenterShim, wire onChange/onMove/onDelete, register   (DC-7)
                │
                ▼
        presenter callbacks now live; first handler body sees DC-7-seeded
        (or DC-8-fallback) lastKnownDiskContent, never placeholder.               (BR-8, BR-10, BR-18)
```

The resume seam and the detector start seam do not interact at runtime — they are two independent hardenings of the File access layer that happen to share a feature for cohesion. The only cross-link is conceptual: both make the launch-to-steady-state path tolerate one more kind of low-frequency adversity (a moved file; a callback that almost-races setup) without changing user-visible behavior or persisted state.

---

## HIG alignment

- Silent resume across moves (DC-1/DC-3) preserves the "no onboarding, no alarms about routine recoverable conditions" stance both declarations name. The user is never told their file moved; it just opens.
- The ordered start (DC-7/DC-8) is invisible by design — it closes a latent race rather than adding a surface.
- RETAIN-on-failure (DC-6) inherits the rationale from `resume-and-create-2` DC-5: the dominant failure mode (iCloud placeholder not yet downloaded, file temporarily offline) commonly clears on a later launch.

---

## Behavioral test anchors (for `/tests`)

- **DC-1/DC-3 (bookmark-fallback resolve):** Record file X at path P; move X to Q in the same security scope; relaunch → resolver returns Q (not P, not nil). Delete X entirely → resolver returns nil; `hasRecord` is still true; restore X at any reachable path covered by the bookmark → next resolve returns it.
- **DC-2 (no steady-state regression):** Same-path resume returns the URL with no additional disk work; the existing resume-and-create-2 tests continue to pass.
- **DC-4 (no recorded-path rewrite on fallback):** After a fallback resolve, the persisted path string is bit-identical to its pre-resolve value; only `recordLastOpened` writes the path.
- **DC-5/DC-6 (stale + retain):** Stale-but-resolvable bookmark → resolves; stale-and-unresolvable → nil; in every failure case `hasRecord` remains true.
- **DC-7 (ordered start):** A test that drives `start()` and inspects state at the first presenter-callback handler entry observes `document.lastKnownDiskContent` equal to the initial-read result (post-write content when the test wrote during setup); no observation of placeholder state.
- **DC-8 (initial-read failure non-fatal):** A `displayURL` that is briefly unreadable during start → `start()` returns; `activeSurface` is nil; a later successful change callback classifies against the host-seeded prior.
- **DC-9 (`displayURL` is init-only before start):** A new `ChangeDetector` instance exposes no public mutator for `displayURL` reachable before `start()`; static check on the interface.
- **DC-11 (no steady-state regression):** The complete `external-change-5` test suite passes unmodified.

---

Architecture stable — no requirements changes flagged
