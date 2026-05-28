# Declaration

## What

Make the open/load path fail visibly and predictably for the three edge cases the audit found silent. Three changes:

1. `MarkdownDocument` decode of non-UTF-8 bytes either falls back to a labeled lossy decode or raises a user-visible "this file isn't UTF-8" error — no silent `invalidEncoding` throw that the UI swallows.
2. `BrowserHostController.loadMarkdownDocument` surfaces load failures (permission denied, decode failure, file moved mid-pick) to the user instead of returning `nil` into a silent no-op.
3. Files above a defined byte ceiling are rejected with a clear "file too large for Markus" message before the full-string allocation can OOM the app.

## Why

The post-shipping audit found three failure modes on the open path where the app does the wrong thing silently: a Latin-1 or UTF-16 file becomes permanently unopenable in Markus with no hint why; a permission-revoked or moved file makes the document browser appear to "do nothing" when the user taps it; and a multi-hundred-MB markdown file crashes the app on decode rather than being declined with a message. All three break the "shortest path from launch to editing my file" experience promised in declaration.md — the user is left with no information about why their file didn't open.

## Success

- Opening a non-UTF-8 `.md` file either renders (lossy with a visible label) or shows a specific encoding error — never silent failure.
- Any load error from the document browser flow produces a user-visible alert with enough text to act on; the browser does not silently no-op.
- A file above the ceiling produces a "too large to open" message and the app does not crash or hang; the ceiling is high enough that no realistic prose markdown file is rejected.
- No regression to the normal open path for well-formed UTF-8 files of typical size.

## Shape touched

- **Document model** — encoding handling on load.
- **Document browser entry** — error surface from picked-file load failure.
- **Conflict & lifecycle UI** — reused for the user-facing alerts (no new surface invented).

Does not touch: File access layer save side, Rendered view, Raw editor, Mode switcher.

## Out of scope

- Encoding *detection* heuristics — either it decodes as UTF-8 or it's surfaced as not-UTF-8; no chardet-style guessing.
- Conversion / re-save in a different encoding.
- Streaming or chunked load for large files — the ceiling is a hard reject, not a workaround.
- Save-side hardening — see `save-bridge-hardening-9`.
- Resume bookmark and detector-start race — see `resume-and-detector-hardening-11`.
