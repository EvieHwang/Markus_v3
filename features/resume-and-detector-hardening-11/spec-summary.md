# Spec Summary — Resume and Detector Hardening

## Feature

Markus is a markdown editor for iOS that opens existing `.md` files in place. A post-shipping audit surfaced two narrow silent-failure paths in the File access layer: when the user moves or renames their last-opened file between launches, the app falls back to the document browser instead of resuming through the still-valid security-scoped bookmark; and the external-change detector's start sequence has a thin window in which a presenter callback could fire before the detector's initial disk-state baseline is recorded. Both are low-frequency today but each is a real source of subtle bugs as iCloud sync becomes more aggressive. This feature closes both gaps without changing any user-visible behavior.

## What it does

- **Resume across moves and renames.** If the user moves or renames their most-recent file between sessions, the next launch still opens that file directly into the rendered view instead of dropping to the document browser. There is no banner, no toast, no "your file moved" message — the resume feels indistinguishable from a launch where the file stayed put.
- **Cleaner detector startup.** When a document is presented and the external-change watcher comes online, the watcher now establishes its on-disk baseline before it begins listening for filesystem events. A write that lands during app launch is either absorbed silently into that baseline or processed as a normal change against the baseline; it can no longer be classified against an empty/placeholder state.
- **No new persisted state, no new UI, no new settings.** The store keeps the same two values it already kept (the bookmark and the last-known path). The detector keeps the same lifecycle and the same handlers. The only changes are ordering changes inside two existing functions.

## Risks carried

No risks acknowledged.

(One LOW adversarial finding is open as F-001 in `adversarial-review.md` — a reachability probe based on `fileExists` rather than a coordinated read leaves a narrow gap where the resume completes but the open fails downstream and surfaces in the editor frame via the open-path-hardening surfaces. The design's chosen behavior matches `open-path-hardening-10`'s stance and is recorded for awareness only; no decision required.)

## Out of scope

- Persisting any additional resume metadata (no new defaults keys, no "last-seen directory," no file identifier cache).
- Refreshing stale security-scoped bookmarks back to `UserDefaults` on a successful resolve.
- Any surface UI for "your last file moved" — silent successful resume is the goal.
- Reworking the `NSFilePresenter` registration model — only the ordering of initial read vs. presenter live-ness changes.
- Anything in the save path (covered by `save-bridge-hardening-9`) or the open path (covered by `open-path-hardening-10`).
- Cross-device handoff or multi-scene restoration.

## Build preview

**2 tasks across 1 wave.** Both tasks are independent single-function edits in different files (`LastFileStore.swift` and `ChangeDetector.swift`); they can land in either order or in parallel. This is at the low end of the DAG-size guidance, which is appropriate for a deliberately scoped post-shipping hardening feature. The build fits comfortably in one session with margin.

## Next step

Start a new session and run `/build feature-name: resume-and-detector-hardening-11`.
