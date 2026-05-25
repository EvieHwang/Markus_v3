# Spec Summary: external-change-5

## Feature

Markus is a lens over markdown files that live in iCloud Drive and similar sync services, where the same file is routinely touched by other devices and apps. This feature makes the app trustworthy in that multi-device reality: it handles the three ways the currently-open file can change underneath the editor — its content changes on disk, it gets moved or renamed, or it gets deleted — without breaking the editing session and without ever silently overwriting the user's work. Its defining quality is restraint: the app resolves changes invisibly whenever it safely can, and asks the user to choose only when there is a genuine, unavoidable collision.

## What it does

While a file is open, Markus quietly keeps it in sync with what's on disk:

- **Most external changes are absorbed silently.** If you haven't made unsaved edits, an external change to the file just flows in. Even if you have edits, but the disk version turns out to be identical to yours (ignoring trivial line-ending differences), it resolves with no interruption.
- **No spurious prompts.** Routine activity — creating a new file, saving, ordinary single-device editing, or iCloud still settling after a save — never triggers a conflict prompt. The app waits for the file system to settle before deciding anything is wrong.
- **A real collision asks you to choose.** Only when you have unsaved edits AND the on-disk content has genuinely diverged AND iCloud has settled does Markus present a three-option choice — Keep Mine, Keep Theirs, or Discard Mine. It never merges or guesses on your behalf.
- **Your edits are never silently lost.** Anything you type right up to the moment a change is applied is preserved or surfaced; the app re-checks against your current text before changing anything, and stops auto-saving the instant it detects a collision so it can't overwrite the disk version you might want to keep.
- **Moves are followed.** If the open file is moved or renamed, your editing session continues seamlessly against the new location, and saves go to the right place.
- **Deletion is recoverable.** If the open file is deleted out from under you, Markus shows a non-destructive banner offering Save As, so unsaved work can be written somewhere new rather than lost.
- **Nothing gets stranded.** If a conflict prompt is dismissed by the system (e.g. you background the app) rather than by an explicit choice, the unresolved state is preserved and re-presented when you return — auto-save stays safely paused until you actually decide.

## Risks carried

No risks acknowledged. All three adversarial findings raised during the spec (two silent-data-loss races on the detector's apply edge, and one stuck-suspended state introduced by the first fix) were resolved in requirements and design, not deferred.

## Out of scope

- No version history or browsing of past versions — the OS and sync services own that; this feature only resolves the live divergence.
- No automatic line-level content merge — resolution is always whole-file (Keep Mine / Keep Theirs / Discard Mine).
- No conflict handling for files other than the currently-open document — no background or batch reconciliation.
- No new settings or toggles — all thresholds (settle window, normalization rules) are fixed by design.
- No change to the rendered or raw editing surfaces themselves — this feature is the file lifecycle around them.
- Full VoiceOver / Dynamic Type semantics for the new sheet and banner are deferred to the Roadmap #7 accessibility pass; the controls exist and function here.

## Build preview

10 tasks across 4 waves. Wave 1 builds the pure primitives (content-equality gate, last-known-disk state, conflict-resolution outcomes); Wave 2 adds the change classifier, settle gate, and the apply-edge re-validation + save-suspension latch; Wave 3 stands up the owned change detector and reconciles it with the existing SaveStatusObserver; Wave 4 delivers the user-facing surfaces (conflict sheet, deletion banner with Save As, follow-on-move) plus the foreground reconciler. The DAG passed its size check — it fits one screen, stays within the 3–4 wave target, and introduces no new framework, dependency, or deploy path (NSFileCoordinator and UIKit are already in the SDK; the detector attaches to the existing host and save bridge). It fits comfortably in one build session.

## Next step

Start a new session and run `/build feature-name: external-change-5`.
