# Adversarial Review — Resume and Detector Hardening

requirements.md @ c519a79 · design.md @ c519a79 · mode: FRESH REVIEW

*Scope check first, then integrity / coverage / security / standards / failure-modes / scope-drift. Subject of every candidate finding traced to declaration or requirements before filing.*

**Overall:** This is a deliberately small, surgical feature touching two specific surfaces of existing components. The design closes both audit gaps with a synchronous-ordering choice (CD/DC-7 option a) and an inverted bookmark-vs-path identity policy (DC-1/DC-3) that are well-anchored to BR text and to the existing code shape. Both DCs include observable properties and explicit rationale for the path *not* taken. No HIGH findings; no MEDIUM findings; one LOW finding recorded for tracking but non-blocking.

---

## Findings

### F-001 — Bookmark-fallback probe is `fileExists`, not a coordinated read
- **Severity:** LOW
- **Lens:** failure modes (subject traces to BR-4 "reachable and readable", design DC-3)
- **Finding:** DC-3 specifies the bookmark-fallback reachability probe as `FileManager.fileExists(atPath:)` inside a security-scope bracket, deliberately not a coordinated read. The design's stated rationale (resume-time cost, downstream open path owns content-level errors) is sound. The residual gap is narrow: a bookmark-resolved URL can exist on disk per `fileExists` but be unreadable at open time (permission revoked between probe and open, undownloaded iCloud placeholder that `fileExists` reports as present, file vanished in the millisecond between probe and open). In that case the launch resumes into the editor and the open path raises whatever error it already raises today — there is no new failure mode introduced, only one previously prevented by the path-veto.
- **Concrete failure mode:** A user whose bookmark probe passes but whose open fails sees the open-path-hardening surfaces (file size / permission / encoding errors) instead of the document browser. That is the open-path-hardening contract, not this feature's, but it is a small behavior change worth recording.
- **Recommended action:** none (LOW, non-blocking). The behavior is consistent with the declaration's "fall back to bookmark" intent and with open-path-hardening-10's stance that load failures surface in the editor frame. Recording so it isn't a surprise during build/QA.
- **Status:** open (LOW)

---

## Prescription feedback

*None.* The design states behavioral properties throughout; the single deliberate call-shape contract (DC-9 — `displayURL` is init-only before `start()`) is named, justified, and tied to the BR-17 precondition. No findings to record here.

---

## Verification notes

- **Coverage lens:** every BR-1..BR-19 traces to at least one DC; conversely every DC carries an observable that maps to a BR. Spot-checked: BR-2 → DC-1/DC-3; BR-9 → DC-7 (vacuous-gap argument) + DC-11 (steady-state passthrough); BR-13 → DC-8; BR-19 → DC-7 (main-actor program order).
- **Security lens:** no new persistence, no new IPC, no new privilege boundary. Security-scoped resource bracketing is reused identically from the existing "no recorded path" branch in `LastFileStore.resolveLastOpened`. No finding.
- **Standards lens (constitution.md):** Swift Testing + XCUITest framework already named; no new dependency; HIG-aligned silent resume (DC-1/DC-3 inherit from resume-and-create-2). No finding.
- **Scope-drift lens:** every DC traces to a declaration item. DC-4 explicitly honors declaration Out-of-scope §1 (no additional resume metadata). No finding.
