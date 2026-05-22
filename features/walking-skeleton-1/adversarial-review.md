# Adversarial review: walking-skeleton-1

Reviewed against `requirements.md` + `design.md` at commit **cdefd5a**. First pass; no prior findings to verify.

No pattern-reuse markers in `design.md` (this is the first iOS surface in the repo), so all lenses applied at full scrutiny — no surfaces scoped down.

## Open findings

### F-001 — MEDIUM — Integrity
**Lens:** Integrity
**Finding:** Requirements EC-6 says pending edits are saved when the app backgrounds and the document is "re-presented in the same mode the user was in when backgrounded." Design models `DocumentMode` as `@State` in `DocumentView`. SwiftUI `@State` does not survive scene tear-down — if iOS reclaims the scene during a long backgrounding (which it routinely does), the mode resets to the default (`rendered` per AC-2.2 / AC-5.4) on resume. The result is that EC-6's contract holds for short backgrounding (scene preserved) and silently breaks for long backgrounding (scene torn down). The user would see this as "I left the app in raw mode and came back later to find I'm in rendered mode" — confusing but not data-losing.
**Recommended action:** `t3-requirements` — either tighten EC-6's wording to "across short backgrounding while the scene is preserved" (acknowledging the OS reality), or escalate by asking `t3-architecture` to add explicit state restoration via `SceneStorage` for the mode.
**Status:** addressed (requirements.md EC-6 second pass — tightened to acknowledge scene tear-down; SceneStorage-backed mode restoration deferred)

### F-002 — MEDIUM — Failure modes
**Lens:** Failure modes
**Finding:** Requirements EC-9, EC-10, EC-12 (file deleted, moved, or read-only) all say "save fails non-fatally; in-memory text is preserved." Design's `DocumentError.saveFailed` surfaces an alert/banner. But Roadmap #3 owns "Save As" and the conflict sheet, so the skeleton has **no recovery action** for the user holding unsaved edits against a failed save: they can't save elsewhere, can't export, can't copy to clipboard. If they close the app to investigate, in-memory text is gone. Concrete failure mode: a user editing on iCloud Drive while offline experiences a save failure, dismisses the alert (which is the only available action), then closes the app and loses 20 minutes of work.
**Recommended action:** `t3-requirements` — either add a minimum recovery surface to the skeleton (e.g., AC-RECOVER-1: when save fails, the alert offers a "Copy contents to clipboard" action), or explicitly state in EC-9/EC-10/EC-12 that data loss is acceptable for the skeleton and Roadmap #3 is the fix.
**Status:** addressed (requirements.md AC-RECOVER-1 + AC-RECOVER-2 — alert offers "Copy contents to clipboard" with confirmation toast)

### F-003 — MEDIUM — Failure modes
**Lens:** Failure modes
**Finding:** `AutosaveCoordinator` (design.md component #7) doesn't trigger saves directly — it just calls `markDirty()` and relies on `UIDocument`'s built-in auto-save-in-place to flush. Save errors from `UIDocument` are reported via `UIDocument.documentStateChangedNotification`, which neither `DocumentView`, `MarkdownDocument`, nor `AutosaveCoordinator` subscribes to in the design. Concrete failure mode: iCloud Drive goes offline mid-session, `UIDocument` enters `.savingError`, the user keeps editing for 30 minutes believing everything is saved, then closes the app — the file on disk is the pre-offline version, and the alert path from F-002 never fires because nothing observes the error notification.
**Recommended action:** `t3-architecture` — add a save-status observer (e.g., extend `MarkdownDocument` or add a `SaveStatusCoordinator`) that subscribes to `UIDocument.documentStateChangedNotification` and pipes errors into the existing `errorBanner` surface.
**Status:** addressed (design.md component #11 SaveStatusObserver — subscribes to `UIDocument.stateChangedNotification`, exposes `lastSaveError`; `DocumentView` pipes it into the AC-RECOVER-1 alert)

### F-004 — MEDIUM — Coverage
**Lens:** Coverage
**Finding:** Requirements EC-2 ("very large file") says "opens within a reasonable time; rendering may take a moment but does not deadlock." Design renders via `MarkdownUI` on `@MainActor` with no length cap and no async rendering. A 2–5 MB markdown file (not unheard of for note-takers with monolithic vaults) will block the main thread for multiple seconds during parse + layout, presenting as a frozen UI. EC-2's "does not deadlock" is technically met (the work completes), but the user perception is a hang. Concrete failure mode: user opens their "everything.md" file from Obsidian; the app appears frozen; they force-quit, thinking the app crashed.
**Recommended action:** `t3-requirements` or `t3-architecture` — either tighten EC-2 with a concrete size/time budget (e.g., "files >500 KB open into raw mode by default, with a manual toggle to render"), or add an async rendering path to `RenderedView` with a progress affordance. The lighter-touch fix is the requirements one.
**Status:** addressed (requirements.md EC-2 — files ≥ 500 KB open in raw mode by default; eye icon renders on demand)

### F-005 — LOW — Security
**Lens:** Security
**Finding:** design.md "Dependencies" pins MarkdownUI as `>= 2.4.0`. With SwiftPM resolution, a future build could pull in a 3.x release with breaking API changes or, worse, a compromised intermediate version. The right pin for a single external dep on a critical render path is `.upToNextMinor(from: "2.4.0")`. Located: design.md, Dependencies section.
**Recommended action:** `t3-architecture` — change the version constraint to `.upToNextMinor(from: "2.4.0")` (or pin to exact minor) and note it in the design.
**Status:** addressed (design.md Dependencies — pinned to `.upToNextMinor(from: "2.4.0")`)

### F-006 — LOW — Security / Standards compliance
**Lens:** Security
**Finding:** design.md component #10 says `PrivacyInfo.xcprivacy` declares "no required-reason API usage beyond the standard file-access categories" — but doesn't enumerate which categories. Apple's required-reason API rules (iOS 17+) demand explicit declarations for APIs like `NSPrivacyAccessedAPICategoryFileTimestamp`, `NSPrivacyAccessedAPICategoryUserDefaults`, and `NSPrivacyAccessedAPICategoryDiskSpace`. `UIDocument` internally calls file-timestamp APIs at minimum. Concrete failure mode: App Store submission is rejected for an incomplete Privacy Manifest. Located: design.md, component #10.
**Recommended action:** `t3-architecture` — enumerate the expected required-reason API categories in the design (at minimum `FileTimestamp`; likely `UserDefaults` if any preferences are stored later), each with the standard "C617.1" / equivalent reason code.
**Status:** addressed (design.md component #10 — enumerates `FileTimestamp` C617.1, `UserDefaults` CA92.1, `DiskSpace` E174.1 with the standard reason codes)

### F-007 — LOW — Coverage
**Lens:** Coverage
**Finding:** Requirements EC-13 says an iCloud-download-pending file "presents whatever loading affordance the system provides" — `UIDocument` actually surfaces this via `documentState.contains(.editingDisabled)` and the file may not be readable until download completes. design.md doesn't specify what `MarkdownDocument.init(configuration:)` does when the read returns an empty `Data` because the file body isn't downloaded yet. Concrete failure mode: user picks a not-yet-downloaded iCloud file; `init(configuration:)` succeeds with an empty `text`; the rendered view is blank; the user thinks the file is corrupt. Located: design.md, `MarkdownDocument` component.
**Recommended action:** `t3-architecture` — add a note that the document observes `.editingDisabled` and shows a loading indicator while the iCloud body is downloading; or `t3-requirements` to specify the user-visible affordance explicitly.
**Status:** addressed (requirements.md EC-13 specifies the user-visible affordance; design.md component #11 `SaveStatusObserver.isDownloadingFromiCloud` observes `.editingDisabled` and component #12 `DocumentLoadingView` renders the spinner)

## Resolved findings

*(none yet)*

---

## Severity summary

After both 2nd-pass runs (`/t3-requirements` then `/t3-architecture`):

- HIGH: 0 — DAG generation not blocked.
- MEDIUM: 4 total — **all addressed** (F-001, F-002, F-003, F-004).
- LOW: 3 total — **all addressed** (F-005, F-006, F-007).

All 7 findings are now `addressed` and await verification on the next `/t3-adversarial` re-run, which will re-attack each fix and promote to `resolved` if it holds.

## Re-run guard

The next `/t3-adversarial` run will compare against commit **cdefd5a**. If `requirements.md` and `design.md` are unchanged since this commit, the lenses will not be re-applied; the report will state "no changes since adversarial review at cdefd5a — open findings remain as previously documented."
