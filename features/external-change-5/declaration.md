# Declaration: external-change-5

## What

Handle the three ways the currently-open file can change underneath Markus while it is open: its **content** changes on disk (another device or app saves it), it is **moved/renamed**, or it is **deleted**. Content changes are absorbed silently when it is safe to do so; a choice is surfaced to the user only on a genuine collision. Moves are followed transparently so the user keeps editing the same file. Deletion surfaces a recoverable path rather than silently losing the user's work.

The defining quality of this feature is restraint: the conflict UI must appear *only* when there is a true, unresolvable collision. Spurious prompts — the kind that fire while iCloud is still settling after a save or a new-file creation — are treated as a defect, not an acceptable cost.

## Why

Markus is a lens over files that live in iCloud Drive and similar sync services, where the same file is routinely touched by other devices and apps. Roadmap #1 and #2 established open/edit/save and resume; this feature makes the app trustworthy in the multi-device reality its users actually live in. Without it, an external edit can silently overwrite the user's work, a moved file breaks save-back, and a deleted file loses unsaved changes. It directly serves the declaration's purpose — editing files where they already live — by making "where they live" a place that can change without breaking the editing session or violating the user-is-the-only-authority principle.

## Success

- **Clean buffer → always silent.** If the in-app buffer matches what was last saved, any external content change is absorbed with no prompt.
- **Content-identical → always silent.** Even with a dirty buffer, if the on-disk content is identical to the buffer (byte-for-byte or after newline normalization), the change is resolved silently — no prompt.
- **Settle-aware.** Conflict signals that occur while iCloud is mid-sync, or within a short grace window after create/open, do not produce a prompt; they resolve once state settles.
- **True collision → explicit choice.** Only when the buffer is dirty AND the on-disk content materially differs AND iCloud has settled does the three-option sheet appear: Keep Mine / Keep Theirs / Discard Mine. No silent merge.
- **Move/rename → followed.** If the open file is moved or renamed on disk, the editing session continues against the new location and subsequent saves write to the moved file.
- **Deletion → recoverable.** If the open file is deleted, the user sees a non-destructive deletion banner offering Save As, so unsaved work can be written to a new location rather than lost.
- **No false positives in normal use.** Creating a new file, saving, and ordinary single-device editing never produce a conflict prompt.

## Shape touched

- **File access layer** — primary; external-change detection (`NSFileVersion`/`NSFileCoordinator`-based rather than raw `UIDocument.documentState` bits), settle-window suppression, follow-on-move, deletion detection, save-back to the followed location.
- **Document model** — last-known-disk state used to distinguish clean from dirty and to run the content-equality gate.
- **Conflict & lifecycle UI** — the three-option conflict sheet and the deletion banner with Save As.

## Out of scope

- **No version history or browsing of past versions** — the OS and sync services own that; this feature only resolves the live divergence.
- **No automatic content merge** — resolution is whole-file (Keep Mine / Keep Theirs / Discard Mine), never a line-level merge.
- **No conflict handling for files that are not the currently-open document** — background or batch reconciliation is not in scope.
- **No new settings or toggles** — all thresholds (grace window, normalization rules) are fixed by design.
- **No change to the rendered/raw editing surfaces themselves** — this feature is about the file lifecycle around them, not the editors.
- **Accessibility labeling of the new sheet/banner** is deferred to the Roadmap #7 accessibility pass (the controls exist and function here; full VoiceOver/Dynamic Type semantics come later).
