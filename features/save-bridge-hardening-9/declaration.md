# Declaration

## What

Make file saves fail loudly and stay coordinated with the rest of the file system. Three changes on the write/reconcile path:

1. Errors from `MarkdownDocumentSaveBridge.writeNow()` surface to the user via the existing save-status surface instead of being swallowed.
2. Writes are wrapped in `NSFileCoordinator.coordinate(writingItemAt:)`, matching how reads are already coordinated.
3. `ChangeDetector.reconcileOnForeground()`'s `lift` path refreshes the in-memory buffer when disk and buffer are content-identical, so a subsequent save can't clobber a fresher-but-equal disk state.

## Why

The post-shipping audit identified the only plausible silent-data-loss path in the app on the write side: a failed `writeNow()` returns silently, the buffer stays dirty, and the user keeps editing under the false belief the file is saved. Separately, atomic-but-uncoordinated writes can clobber a fresher iCloud version that landed between our last read and our save, and the reconciliation lift can leave the buffer stale in a way that the next save then clobbers. All three failures violate the core promise of declaration.md — Markus as a faithful lens over the user's existing files, never a source of silent loss.

## Success

- A forced write failure (e.g. revoked permission, simulated disk-full) produces a visible, dismissable surface the user can act on; the document stays dirty until a successful save lands.
- An injected concurrent external write during save does not produce a torn or clobbered file; the coordinator serializes them.
- After a foreground reconciliation that lifts on equality, the in-memory buffer matches disk; a subsequent save is a no-op rather than an overwrite of a fresher version.
- No regression to the steady-state save path, external-change reconciliation under non-collision conditions, or external-change three-option sheet under collision.

## Shape touched

- **File access layer** — primary. Save coordination and write-error propagation.
- **Conflict & lifecycle UI** — error surface for failed saves (reuse existing surface where possible).

Does not touch: Document model schema, Rendered view, Raw editor, Mode switcher, Document browser entry.

## Out of scope

- Retry queues or transient-failure backoff — surface the error, let the user decide.
- Sidecar / recovery file on write failure.
- Migrating `MarkdownDocumentSaveBridge` to `UIDocument`.
- Open-side hardening (UTF-8 fallback, load error surface, large-file ceiling) — see `open-path-hardening-10`.
- Resume bookmark fallback and detector-start race — see `resume-and-detector-hardening-11`.
- Diagnostic detail beyond what the underlying `Error` carries.
