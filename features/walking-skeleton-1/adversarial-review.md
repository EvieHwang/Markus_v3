# Adversarial review: walking-skeleton-1

Reviewed against `requirements.md` + `design.md` at commit **c9d7bd1** (prior review header was at **8d9e787**). Third pass; re-attacks F-003, F-007, F-008 fixes from the 3rd-pass `/t3-requirements` + `/t3-architecture` runs.

No pattern-reuse markers in `design.md`, so all lenses applied at full scrutiny — no surfaces scoped down.

## Open findings

*(none)*

All 8 findings have been addressed across three loop iterations and verified through re-attack. No new HIGH findings were introduced by the third-pass changes. Two minor implementation-discovery notes (below) are out-of-scope for adversarial review and explicitly delegated to the build agent per the user's direction to close the loop.

## Resolved findings

### F-001 — RESOLVED (originally MEDIUM, Integrity)
EC-6 silently broke after scene tear-down. Fix: requirements.md EC-6 tightened to acknowledge scene tear-down resets mode to rendered as acceptable; SceneStorage-backed restoration deferred. Survived re-attack at 8d9e787.

### F-002 — RESOLVED (originally MEDIUM, Failure modes)
Save fails with no recovery action; user loses unsaved edits on close. Fix: AC-RECOVER-1/2 add "Copy contents to clipboard" + confirmation toast. Survived re-attack at 8d9e787.

### F-003 — RESOLVED (originally MEDIUM, Failure modes)
`AutosaveCoordinator` didn't observe save failures; iCloud-offline save errors fired silently. Fix lineage:
- 2nd pass: `SaveStatusObserver` (component #11) introduced — but specified `init(document: UIDocument)`, which SwiftUI's `DocumentGroup` doesn't expose.
- 3rd pass: mechanism clarified — global `UIDocument.stateChangedNotification` subscription with `object: nil`, justified by single-document-at-a-time architecture. Build agent has unambiguous implementation path.
**Re-attack verdict:** the mechanism is now correct, complete, and implementable from inside a SwiftUI `DocumentGroup` app. No adjacent gap surfaced.

### F-004 — RESOLVED (originally MEDIUM, Coverage)
Large files block the main thread; "no deadlock" wording allowed a frozen UI. Fix: EC-2 — files ≥ 500 KB open in raw mode by default. Survived re-attack at 8d9e787.

### F-005 — RESOLVED (originally LOW, Security)
MarkdownUI version pin too loose. Fix: `.upToNextMinor(from: "2.4.0")`. Survived re-attack at 8d9e787.

### F-006 — RESOLVED (originally LOW, Security / Standards compliance)
Privacy Manifest required-reason API categories not enumerated. Fix: design.md component #10 enumerates `FileTimestamp` C617.1, `UserDefaults` CA92.1, `DiskSpace` E174.1, with build-agent instruction to drop unused categories during implementation. Survived re-attack at 8d9e787.

### F-007 — RESOLVED (originally LOW, Coverage)
iCloud download-pending file presentation undefined. Fix lineage:
- 2nd pass: `SaveStatusObserver.isDownloadingFromiCloud` + `DocumentLoadingView` (components #11, #12) introduced — but inherited F-003's mechanism issue.
- 3rd pass: mechanism shared with F-003 resolution; `DocumentLoadingView` explicitly documented as a safety net with build-agent verification instruction (keep if needed, delete if `DocumentGroup` handles it natively).
**Re-attack verdict:** user-visible behavior is guaranteed by either path (system spinner OR `DocumentLoadingView`); design no longer leaves the build agent guessing.

### F-008 — RESOLVED (originally LOW, Standards compliance)
AC-RECOVER-2's transient toast not announced by VoiceOver; blind users got no audible confirmation after Copy. Fix:
- requirements.md AC-A11Y-3 (3rd-pass `/t3-requirements`) — independent VoiceOver announcement requirement.
- design.md component #8 (3rd-pass `/t3-architecture`) — Copy action calls `UIAccessibility.post(notification: .announcement)` before the toast; toast text is `.accessibilityHidden(true)` to avoid double-announce.
**Re-attack verdict:** announcement fires regardless of toast visibility/timing; `.accessibilityHidden` prevents duplicate announce; localization wrapper present. No adjacent gap surfaced.

---

## Implementation-discovery notes (delegated to build agent)

These are NOT findings — they are real-but-tractable things the build agent may encounter that don't rise to "would block the build." Per user direction (close the adversarial loop, build agent handles inline):

1. **iOS 26 `UIDocument.stateChangedNotification` userInfo shape.** Design component #11 already includes a build-agent note: if iOS 26 surfaces the source document via userInfo, prefer that path over the implicit single-document assumption. Build agent verifies on real device.
2. **`DocumentLoadingView` reachability.** Design component #12 already includes a build-agent verification instruction: test against a not-yet-downloaded iCloud file; delete the component if the system path handles it; keep it otherwise. Either outcome is acceptable.
3. **Privacy Manifest category trim.** Design component #10 already includes the over-declare-then-trim instruction. Build agent verifies which required-reason APIs `UIDocument`/`DocumentGroup` actually call on iOS 26 and removes unused entries.

---

## Severity summary

After 3 loop iterations:

- HIGH: 0
- MEDIUM: 0
- LOW: 0
- **All 8 findings resolved.**

**DAG generation is not blocked. Loop has converged.**

## Re-run guard

The next `/t3-adversarial` run will compare against commit **c9d7bd1**. If `requirements.md` and `design.md` are unchanged since this commit, the lenses will not be re-applied; the report will state "no changes since adversarial review at c9d7bd1 — open findings remain as previously documented."
