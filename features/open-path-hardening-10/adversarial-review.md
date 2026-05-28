# Adversarial review — open-path-hardening-10

Header: requirements.md @ 2f5549e90ea1829da0271f34814ca28ec1713afe · design.md @ 695f7b36bf4abc7f17565d1f0c24c2a4a022d955 · mode: verification pass

---

## Findings

*No open findings.*

---

## Resolved

### F-001 — Save-side byte change from BOM stripping crosses the feature's own scope boundary
- **Severity:** MEDIUM
- **Lens:** scope drift
- **Subject trace (original):** Feature `declaration.md` §"Shape touched" — "Does not touch: File access layer save side". Also OOS-4 in `requirements.md` — "No changes to the save path."
- **Finding (original):** DC-3 had committed to stripping the BOM on load, producing a one-time silent byte change on a no-edit save round-trip of a BOM-prefixed file — exactly the silent destructive round-trip declaration §Why is trying to close, and crossing OOS-4.
- **Resolution:** BR-1.3 and `requirements.md` Definitions both pin BOM **retention** in the in-memory buffer with render-time suppression. DC-3 implements accordingly: "(i) the rendered surface does not display the BOM as a visible character...; (ii) a save of an unmodified BOM-prefixed file produces a file whose bytes are byte-for-byte identical to the original (the BOM survives the round trip)." DC-3 also addresses the adjacent question of how this interacts with `external-change-5`'s content-equality gate ("operates on the full in-memory buffer including the BOM; this is consistent with prior behavior because, today, a file that decoded successfully did not strip its BOM either"). The save path is not touched; OOS-4 holds. **Verification pass attack with the scope-drift lens found no adjacent gap.**
- **Status:** resolved

### F-002 — Alert host coverage when no document is presented is not pinned
- **Severity:** MEDIUM
- **Lens:** coverage / failure modes
- **Subject trace (original):** BR-3.1, BR-3.5, DC-1; the Ground-truth check named `DocumentView`'s `activeAlert` channel as the existing surface, but the open-path alerts can fire on a cold launch when no `DocumentView` is on screen.
- **Finding (original):** Design did not pin where the alert is hosted when there is no presented document, leaving a reachable failure mode (cold launch → pick a problem file → `ActiveAlert` set but no view rendering it → silent no-op recreated).
- **Resolution:** DC-6a is added and pins the alert host explicitly: the `.alert(item: $activeAlert)` modifier for open-path surfaces is bound to `BrowserHostController`'s root host view, which is on screen for the entire browser-idle lifetime (including before any document has ever been presented in the session). The `ActiveAlert` state for open-path failures is owned by `BrowserHostController`; `DocumentView` retains its own alert host for running-document surfaces, unchanged. The behavioral test anchor explicitly stages cold-launch → trigger each of the four surfaces → assert alert presented. **Verification pass attack with the coverage/failure-modes lens:** considered (a) lifecycle gap between host-view appearance and first failure write — DC-6a names the host as on-screen for the entire browser-idle lifetime, ruling this out; (b) collision between the two `.alert(item:)` modifiers — DC-6a separates ownership (open-path `ActiveAlert` owned by `BrowserHostController`, running-document `ActiveAlert` owned by `DocumentView`), so no two modifiers bind the same state. No adjacent gap.
- **Status:** resolved

### F-003 — Resume bookmark-fallback race with this feature's alerts is left ambiguous
- **Severity:** LOW
- **Lens:** failure modes / cross-feature boundary
- **Subject trace (original):** BR-16 and DC-11 deferred the ordering question between this feature's moved/removed alert and `resume-and-detector-hardening-11`'s bookmark fallback, leaving room for two surfaces to fire or for an alert to be visually displaced.
- **Finding (original):** Design did not specify whether bookmark fallback runs before or after this feature's open pipeline.
- **Resolution:** DC-11 now contains an explicit ordering contract: "The resume path resolves its URL — including any bookmark-fallback recovery owned by `resume-and-detector-hardening-11` — *before* handing the URL to this feature's open pipeline; consequently this feature never observes a vanished-then-recovered URL, and the moved/removed alert (DC-8) never fires for a URL that the bookmark fallback would have rescued." The contract also specifies the upstream-violation fallback ("the worst case is a moved/removed alert that is then visually displaced by a successful open; the safety net for that is `resume-and-detector-hardening-11`'s responsibility, not this feature's"). **Verification pass attack with the cross-feature-boundary lens:** the contract is named, the failure mode under contract violation is bounded and routed to the owning feature. No adjacent gap.
- **Status:** resolved

---

## Prescription feedback

None this pass. The verification pass did not surface any prescription drift in the revisions; DC-6a names the alert host as an in-repo seam (`BrowserHostController`'s root view, the `.alert(item:)` modifier) without dictating method signatures, and DC-11's ordering contract is phrased as an observable contract between features rather than a call-site sequence.

---

## Summary

Verification pass against requirements.md @ 2f5549e9 and design.md @ 695f7b36. All three previously-addressed findings are resolved: F-001 (BOM retention, MEDIUM, scope drift) fixed by BR-1.3 + DC-3 retaining the BOM in-buffer and suppressing at render; F-002 (MEDIUM, alert host coverage) fixed by new DC-6a pinning `BrowserHostController`'s root view as the open-path alert host; F-003 (LOW, resume ordering) fixed by the ordering contract added to DC-11. Adjacent-gap attacks with the original lenses (scope drift, coverage/failure modes, cross-feature boundary) found nothing new. No open findings. Spec is ready for the next stage.
