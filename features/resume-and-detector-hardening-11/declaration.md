# Declaration

## What

Close two remaining audit findings on the resume and external-change-setup paths:

1. `LastFileStore.resolveLastOpened()` falls back to the stored security-scoped bookmark when the recorded path no longer points at the file, instead of discarding the bookmark and dropping the user back to the browser.
2. `ChangeDetector.start()` guarantees the initial coordinated disk read completes before the `NSFilePresenter` callbacks are live, so an external change that lands during setup cannot race against unset initial state.

## Why

Bookmarks survive moves and renames; the current resume logic defeats that by treating the recorded path as the source of truth. A user who reorganizes their iCloud folders between launches loses the resume target unnecessarily — a quiet erosion of the "open straight to your last file" promise. Separately, the detector's start sequence has a narrow window where a presenter callback can fire before initial state is captured; this is a low-frequency race today but a real source of subtle reconciliation bugs if iCloud is actively syncing at launch.

## Success

- Launching after the last-opened file has been moved or renamed (but is still resolvable via its bookmark) resumes into that file rather than the browser.
- An external write injected during `ChangeDetector.start()` is either observed cleanly after initial state is captured or absorbed without producing an inconsistent detector state — no torn `lastKnownDiskContent`.
- No regression to the existing resume flow when the recorded path is still valid, and no regression to steady-state external-change behavior.

## Shape touched

- **File access layer** — both the bookmark resolution policy and the detector start sequence live here.

Does not touch: Document model, Rendered view, Raw editor, Mode switcher, Conflict & lifecycle UI, Document browser entry.

## Out of scope

- Persisting any additional resume metadata beyond what `LastFileStore` already tracks.
- Reworking the `NSFilePresenter` registration model — only the ordering of initial read vs. presenter live-ness changes.
- Save-side and open-side hardening — see `save-bridge-hardening-9` and `open-path-hardening-10`.
- Surface UI for "your last file moved" — silent successful resume is the goal.
