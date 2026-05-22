# Adversarial review: walking-skeleton-1

Reviewed against `requirements.md` + `design.md` at commit **8d9e787** (prior review was at **cdefd5a**). Re-attack pass for the 7 previously-addressed findings; new findings added with new IDs.

No pattern-reuse markers in `design.md` (this is the first iOS surface in the repo), so all lenses applied at full scrutiny — no surfaces scoped down.

## Open findings

### F-003 — MEDIUM — Failure modes (follow-on)
**Lens:** Failure modes
**Finding (original):** `AutosaveCoordinator` doesn't observe save failures; iCloud-offline save errors fire silently.
**Fix claimed:** design.md component #11 (`SaveStatusObserver`) — `init(document: UIDocument)` subscribes to `UIDocument.stateChangedNotification` and exposes `lastSaveError`.
**Re-attack:** The fix's mechanism is correct in spirit but the **`init(document: UIDocument)` signature is not reachable from a SwiftUI `DocumentGroup` + `ReferenceFileDocument` app**: SwiftUI does not expose the underlying `UIDocument` instance to user code. The published API surfaces a `FileDocumentConfiguration<MarkdownDocument>` binding, the document's `UndoManager`, and the file URL — but not the `UIDocument`. A build agent following the design literally will hit this wall.

The fix is still implementable, but via a different mechanism: subscribe to `UIDocument.stateChangedNotification` with `object: nil` (global observation) and treat any state change as relevant because Markus is single-document-at-a-time (one open doc per scene). The design should specify this mechanism explicitly rather than imply per-document subscription.

Concrete failure mode if not clarified: the build agent writes the design literally, can't get a `UIDocument`, can't subscribe, save failures stay silent — the original F-003 returns.

**Recommended action:** `t3-architecture` — clarify the subscription mechanism: either spell out "subscribe with `object: nil` (acceptable because the app is single-document-at-a-time)" OR redesign to use `NSFilePresenter` conformance on `MarkdownDocument` (which exposes some, but not all, of the save-error surface).
**Status:** open (with follow-on note)

### F-007 — LOW — Coverage (follow-on)
**Lens:** Coverage
**Finding (original):** iCloud-download-pending file presentation undefined; user sees a blank rendered view.
**Fix claimed:** design.md component #11 `SaveStatusObserver.isDownloadingFromiCloud` + component #12 `DocumentLoadingView`.
**Re-attack:** Two concerns:
1. **Same mechanism issue as F-003** — `SaveStatusObserver` depends on access to the `UIDocument`, which SwiftUI's `DocumentGroup` does not expose. Same fix applies (global notification observation).
2. **The design may be unnecessary** — `DocumentGroup` itself likely shows a download indicator BEFORE handing the document to `MarkdownDocument.init`; if so, `DocumentLoadingView` never gets a chance to render and `isDownloadingFromiCloud` is never `true`. The user-visible result is still "a loading spinner appears," but via `DocumentGroup`'s built-in path rather than our custom component. The fix is harmless but possibly redundant.

If concern #1 is fixed, concern #2 is just an implementation discovery — the design's component #12 can be retained for safety, or dropped if the system path is verified to handle it.

**Recommended action:** `t3-architecture` — clarify the subscription mechanism (same as F-003); optionally note that `DocumentLoadingView` is a safety net in case `DocumentGroup`'s system-provided download indicator is insufficient.
**Status:** open (with follow-on note)

### F-008 — LOW — Standards compliance (new)
**Lens:** Standards compliance (WCAG / Apple HIG accessibility)
**Finding:** AC-RECOVER-2 specifies a 2-second transient toast ("Copied") after the user taps "Copy contents to clipboard." Design component #8 implements this as `ToastModifier` — a SwiftUI `View` modifier with a `@State` timer. **VoiceOver does not reliably announce transient text that appears and disappears without focus change.** A blind user invoking the Copy action will see the alert dismiss with no audible feedback about whether the copy actually succeeded — they may paste into another app uncertain that there's anything on the clipboard, or repeat the operation.

This intersects with the AC-A11Y additions already absorbed into the feature: those two adds established that minimum accessibility surface lives here, not Roadmap #7. The toast is one of those surfaces.
**Located:** design.md component #8 (`ToastModifier`); requirements.md AC-RECOVER-2.
**Recommended action:** `t3-architecture` — pair the visual toast with `UIAccessibility.post(notification: .announcement, argument: "Copied")` so VoiceOver speaks the confirmation. Add an AC-A11Y-3 in requirements (small enough that `t3-requirements` may want to absorb it too).
**Status:** addressed (requirements side) by requirements.md AC-A11Y-3; architecture side (the `UIAccessibility.post` call itself) still open and will be picked up by `/t3-architecture`

## Resolved findings

### F-001 — RESOLVED (originally MEDIUM, Integrity)
Original: EC-6 silently broke after scene tear-down (`@State` mode reset). Fix: requirements.md EC-6 was tightened to acknowledge scene tear-down resets mode to rendered as an acceptable consequence; SceneStorage-backed restoration deferred. Re-attack: contract now matches OS reality. The only adjacent question (does `scenePhase = .background` guarantee a flushed save before suspend?) is a long-standing iOS reality the design handles as well as any UIDocument-backed app can — UIDocument auto-save is best-effort against suspend, and EC-7 already acknowledges that. Fix survives re-attack.

### F-002 — RESOLVED (originally MEDIUM, Failure modes)
Original: save fails with no recovery action; user closes app and loses unsaved edits. Fix: AC-RECOVER-1/2 add a "Copy contents to clipboard" action + confirmation toast. Re-attack: clipboard write via `UIPasteboard.general.string` does not silently fail in any user-visible way; the alert body text ("Your edits are still in memory and can be copied") gives the user enough context that dismissing is an informed choice. Re-presentation cadence is acceptable (SaveStatusObserver fires on state transitions, not per-attempt, so an offline period produces one alert, not many). Visual confirmation of Copy is covered by toast; **audible confirmation is the new F-008** — that's an adjacent finding, not a F-002 regression. Fix survives re-attack.

### F-004 — RESOLVED (originally MEDIUM, Coverage)
Original: large files block the main thread; "no deadlock" wording allowed a frozen UI. Fix: EC-2 — files ≥ 500 KB open in raw mode by default; eye icon renders on demand. Re-attack: the threshold avoids the freeze for the dominant failure mode (large files from Obsidian-style vaults). Tail-of-distribution concern (small file with a single huge table) is a real edge case but not a blocker for a skeleton — it's a render-perf concern that belongs in a later perf pass, not this feature. Fix survives re-attack.

### F-005 — RESOLVED (originally LOW, Security)
Original: MarkdownUI version pin too loose (`>= 2.4.0`). Fix: design.md Dependencies pinned to `.upToNextMinor(from: "2.4.0")`. Re-attack: stricter than `.upToNextMajor`; 2.5+ requires intentional manual bump. Fix survives re-attack.

### F-006 — RESOLVED (originally LOW, Security / Standards compliance)
Original: Privacy Manifest required-reason API categories not enumerated. Fix: design.md component #10 enumerates `FileTimestamp` C617.1, `UserDefaults` CA92.1, `DiskSpace` E174.1, with a build-agent note to drop unused entries during implementation. Re-attack: covers the categories `UIDocument`/`DocumentGroup` actually touch on iOS 26; over-declaring is acceptable per Apple's docs (under-declaring is the submission reject). The "drop unused during implementation" instruction is sensible — the design declares the maximum plausible set so the build doesn't get stuck guessing. Fix survives re-attack.

---

## Severity summary

After re-attack:

- HIGH: 0 — DAG generation not blocked.
- MEDIUM: 1 — **F-003 still open** (mechanism clarification needed).
- LOW: 2 — F-007 (same mechanism issue + likely redundant), F-008 (new — VoiceOver announce on Copy).

Resolved: 5 findings (F-001, F-002, F-004, F-005, F-006).

## Re-run guard

The next `/t3-adversarial` run will compare against commit **8d9e787**. If `requirements.md` and `design.md` are unchanged since this commit, the lenses will not be re-applied; the report will state "no changes since adversarial review at 8d9e787 — open findings remain as previously documented."
