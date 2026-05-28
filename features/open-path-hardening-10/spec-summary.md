# Spec summary — open-path-hardening-10

## Feature

Markus's open path today fails silently in three specific ways: a non-UTF-8 file becomes permanently unopenable with no hint why; a file that's been moved, deleted, or had its permissions revoked between the user picking it and Markus reading it produces a no-op tap on the document browser; and a multi-hundred-MB markdown file crashes the app on decode rather than being declined. This feature closes all three silent-failure paths. It is part of the post-shipping hardening series prompted by the audit that uncovered them, and it sits alongside `save-bridge-hardening-9` (write side) and `resume-and-detector-hardening-11` (resume + presenter) as the three lifecycle-hardening features that together harden the file-handling boundary without changing product surface.

## What it does

- Opens well-formed UTF-8 files (including those that start with the invisible UTF-8 BOM marker) exactly as today, with no behavior change.
- For a file whose bytes are not valid UTF-8 (Latin-1, UTF-16, mixed encodings, partial encoding), Markus shows a specific "this file isn't UTF-8" alert and does not present a document. The user always gets information about why their file didn't open.
- For a file that can't be read because permission was revoked, the file was moved, or the file was deleted between pick and load, Markus shows a specific alert naming what happened. The document browser never silently no-ops.
- Files above a fixed 20 MiB ceiling are declined with a "too large to open" alert before any full-file read happens — so the app cannot run out of memory trying to load them. Files at exactly the ceiling are accepted. No realistic prose markdown file approaches this ceiling.
- A leading invisible BOM marker is preserved in memory so that opening a BOM-prefixed file and saving it back with no edits produces a byte-identical file on disk. The user never sees the BOM as a visible character, and the save side is not changed.
- Alerts ride the same alert channel `external-change-5` and `save-bridge-hardening-9` already use — no new UI surface is invented. The alert is hosted on the document browser's root view so it appears even on a cold launch when no document is yet open.
- A failure on a second file pick does not tear down the document the user already had open.
- The resume-on-launch entry point uses the same gated pipeline, so an oversized, non-UTF-8, or vanished resume target produces the same alerts rather than crashing or silently no-oping.

## Risks carried

No risks acknowledged. All three adversarial findings (F-001 BOM-strip scope drift, F-002 alert host not pinned for cold launch, F-003 resume-ordering ambiguity) were resolved by architecture changes, not acknowledged or deferred.

## Out of scope

- Encoding detection heuristics — Markus either decodes as strict UTF-8 or surfaces a "not UTF-8" alert; no chardet-style guessing.
- Encoding conversion or re-save in a different encoding.
- Streaming or chunked load for files above the ceiling — the ceiling is a hard reject, not a workaround.
- Save-path changes (covered by `save-bridge-hardening-9`).
- Resume-bookmark fallback and the presenter-callback race (covered by `resume-and-detector-hardening-11`).
- New settings, toggles, or user preferences for any of the above — every behavior is design-fixed.
- New UI surface types — alerts go through the existing channel.
- Full VoiceOver / accessibility-pass labeling of the new alerts (deferred to `accessibility-8`).
- File types beyond `.md` / `.markdown` (inherited from the project declaration).

## Build preview

5 tasks across 3 waves. Wave 1 (T-001, T-002) introduces leaf seams: the four new alert cases + copy, and the 20 MiB ceiling constant. Wave 2 (T-003, T-004) adds the strict-UTF-8 decode + BOM retention in `MarkdownDocument` and the pure classification + failure-mapper logic. Wave 3 (T-005) integrates the pipeline into `BrowserHostController`, binds the alert to the host root view, and pulls the resume entry through the same gate. No new framework, dependency, or deploy path. The DAG fits comfortably in one build session.

## Next step

Start a new session and run `/build feature-name: open-path-hardening-10`.
