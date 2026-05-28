# Requirements: open-path-hardening-10

Behavioral requirements for the three silent-failure paths the post-shipping audit found on the open/load flow: (1) non-UTF-8 decode, (2) load failures from `BrowserHostController.loadMarkdownDocument`, and (3) absent file-size ceiling. Derived from `declaration.md` (project) and `features/open-path-hardening-10/declaration.md` (feature). Requirements are behavioral and stay independent of any specific implementation; references to existing types (`MarkdownDocument`, `BrowserHostController`, `ActiveAlert`) appear only where the declaration fixes them as design constraints, not as test obligations.

## Definitions

These terms are used with fixed meaning throughout. Acceptance criteria reference them by name.

- **Open path** — the sequence from a file URL handed to `BrowserHostController` (system browser pick or resume) through `loadMarkdownDocument` and `MarkdownDocument` construction to the point a document is presented in `DocumentView`. This feature governs that span and nothing downstream.
- **Picked file** — the URL the user selected in the system document browser (or that resume hands in). It may or may not still resolve, be readable, or be UTF-8 by the time the load runs.
- **Well-formed UTF-8** — bytes that decode under strict UTF-8 with no replacement, with or without a leading BOM (`EF BB BF`). A leading BOM is permitted input; whether it is stripped from the buffer is a design call (see open items).
- **Non-UTF-8 bytes** — bytes that do not decode under strict UTF-8 (e.g. Latin-1 with high bytes, UTF-16 with a BOM, mixed-encoding files, truncated multi-byte sequences).
- **Lossy decode** — a decode that replaces undecodable byte sequences with the Unicode replacement character (`U+FFFD`) and returns a `String` rather than failing. Behaviorally observable: the resulting buffer contains `U+FFFD` where bytes were unmappable.
- **Labeled lossy decode** — a lossy decode whose result is presented to the user with a visible label (banner, alert, or equivalent surface) stating the file was not valid UTF-8 and was opened with substitutions. "Labeled" means the user is told before they edit; an unlabeled lossy decode is a silent failure and is forbidden.
- **Encoding error surface** — a user-visible alert (or equivalent modal surface) that names the failure as "this file isn't UTF-8" (or substantively equivalent text) and offers at least a Dismiss action. No document is presented.
- **Load failure** — any failure encountered by `loadMarkdownDocument` between receiving a URL and returning a constructed `MarkdownDocument`. The three named in the declaration are: permission denied (security-scoped resource access refused or read returns a permission error), decode failure (per the UTF-8 rule above when the chosen policy is "surface"), file moved or removed mid-pick (URL no longer resolves to a regular file by the time the read runs).
- **Size ceiling** — a single design-fixed maximum byte count for the on-disk file. A file whose byte size exceeds the ceiling is rejected before its contents are loaded into a `String`. The exact byte value is a design decision (see open items); the requirement is that one exists and is enforced.
- **Too-large surface** — a user-visible alert (or equivalent modal surface) that names the failure as "file too large for Markus" (or substantively equivalent text) and offers at least a Dismiss action. No document is presented and no full read into memory occurs.
- **Silent no-op** — the user-observable state in which a tap on a file in the browser produces no document, no alert, no banner, and no log surfaced to the user. This is the failure mode being eliminated.

---

## User stories and acceptance criteria

### BR-1 — Well-formed UTF-8 opens unchanged
**As a** user with ordinary markdown files,
**when** I open a well-formed UTF-8 `.md` or `.markdown` file of typical size,
**so that** the hardening does not get in my way,
**I want** the open path to behave exactly as it does today — straight into the rendered view with no extra prompt.

Acceptance criteria:
- BR-1.1 Given a well-formed UTF-8 file at or below the size ceiling, opening it produces a presented document and no alert, no banner, no label.
- BR-1.2 The buffer equals the on-disk content (byte-for-byte after the existing newline-normalization rules already applied by the load path).
- BR-1.3 A well-formed UTF-8 file with a leading BOM opens without error; the rendered output does not display the BOM as a visible character. (Whether the BOM byte is retained in the buffer for the round-trip save is a design decision — see open items — but its visible absence in the rendered surface is a requirement.)
- BR-1.4 No measurable latency regression on the normal-size happy path attributable to this feature's added checks (size pre-check, decode policy). "Measurable" here is on the order of human perception, not a microbenchmark.

### BR-2 — Non-UTF-8 file produces a labeled outcome, never silent failure
**As a** user who opens a file that turns out not to be UTF-8 (a Latin-1 export, a UTF-16 file, a file with mixed encodings),
**when** the file cannot be strictly decoded as UTF-8,
**so that** I am never left staring at "nothing happened,"
**I want** either a clearly labeled lossy open or a clearly named encoding error — one of the two, decided by design, but never a silent throw the UI swallows.

Acceptance criteria:
- BR-2.1 Given a file whose bytes are not valid UTF-8, the open path produces exactly one of: (a) a presented document with a labeled-lossy surface visible to the user before any edit, OR (b) an encoding error surface and no presented document. The choice between (a) and (b) is design-fixed (see open items) and consistent across files — not per-file heuristic.
- BR-2.2 Under no input does the non-UTF-8 case result in a silent no-op: the user always sees either the labeled document or the error surface.
- BR-2.3 If policy (a) is chosen: the labeled-lossy surface names the file as not valid UTF-8 and warns that substitutions were made. Editing and saving the buffer is permitted; the existing save path's behavior for the substituted buffer is governed by `save-bridge-hardening-9` and is out of scope here.
- BR-2.4 If policy (b) is chosen: no `MarkdownDocument` is constructed for the picked URL; the error surface is dismissable; after dismissal the user is returned to the browser in a state that permits picking another file (no stuck modal, no zombie scope-access).
- BR-2.5 The non-UTF-8 outcome reuses the existing `Conflict & lifecycle UI` alert surface (the declaration fixes this: "no new surface invented"). Concretely, the surface is presented through the same `ActiveAlert`-style channel the rest of the app uses; no novel UI component is introduced for this case.

### BR-3 — `loadMarkdownDocument` surfaces every load failure
**As a** user who taps a file in the system browser,
**when** the load fails for any reason,
**so that** I always know why my tap did not open the file,
**I want** a user-visible alert with text I can act on — never a silent return-to-browser.

Acceptance criteria:
- BR-3.1 For every load-failure case named in the declaration (permission denied, decode failure under policy (b) of BR-2, file moved/removed mid-pick), `loadMarkdownDocument`'s outcome is observable to the user as an alert before control returns to the browser idle state. No load-failure path produces a silent no-op.
- BR-3.2 The alert text distinguishes the three named cases sufficiently for the user to act: a permission-denied alert says permission was refused (and, where applicable, suggests re-picking the file from the browser); a decode-failure alert is the BR-2 encoding error surface; a moved/removed-mid-pick alert says the file is no longer at the picked location.
- BR-3.3 The alert is dismissable; after dismissal the user is returned to the browser with no stale document, no half-initialized save bridge, and no retained security-scoped resource access from the failed attempt (scope is released on the failure path, mirroring the success path).
- BR-3.4 If a load failure happens while a previously-opened document is already presented (e.g. picking a second file fails), the previously-presented document is not torn down by the failure. Editing state on the prior document is preserved; only the failed pick is reported.
- BR-3.5 `loadMarkdownDocument` may continue to return `nil`/throw internally as an implementation seam, but its callers in `BrowserHostController` must convert every failure into a surfaced alert before yielding control. A `nil` that leads to a silent no-op for the user is the regression this requirement forbids.
- BR-3.6 No load-failure surface is produced for the success path: a successful open shows zero alerts (cross-check with BR-1.1).

### BR-4 — Hard size ceiling rejects oversized files with a clear message
**As a** user who accidentally taps a multi-hundred-MB file,
**when** the file exceeds the size ceiling,
**so that** the app does not crash, hang, or thrash,
**I want** a "file too large for Markus" message and a clean return to the browser, before any attempt to load the full file into memory.

Acceptance criteria:
- BR-4.1 Given a file whose on-disk byte size is greater than the size ceiling, the open path produces a too-large surface and no presented document.
- BR-4.2 The size check runs before the full file contents are read into a `String` (i.e. before the allocation that would OOM). It is a pre-read gate, not a post-read recovery. Observable consequence: a 500 MB file does not cause a measurable memory spike on the open path before the rejection.
- BR-4.3 The size ceiling value is a single design-fixed constant, high enough that no realistic prose markdown file is rejected (the declaration's "no regression to the normal open path"). The value is pinned by design (see open items); the requirement is that one exists, is enforced, and is documented in design.
- BR-4.4 The too-large surface is the existing `Conflict & lifecycle UI` alert channel (BR-2.5 rationale); no novel UI is introduced.
- BR-4.5 Rejection releases any security-scoped resource access acquired for the picked URL (mirrors BR-3.3) and returns the user to the browser in a pickable state.
- BR-4.6 A file exactly equal to the ceiling in bytes is **accepted** (the ceiling is inclusive of the boundary; "above the ceiling" in the declaration means strictly greater). Edge behavior pinned here so the test for the at-boundary case is unambiguous.

### BR-5 — Reuse of `Conflict & lifecycle UI` (constraint, not behavior)
This requirement records a declaration-fixed design constraint so downstream stages do not regress it. It is verified by design review, not by a behavioral test.
- BR-5.1 The three new user-visible surfaces (labeled-lossy banner or encoding error, permission-denied alert, moved-mid-pick alert, too-large alert) are presented through the existing alert/banner channel used by `Conflict & lifecycle UI`. No new surface type is invented. Concretely: extending `ActiveAlert` with additional cases is permitted; introducing a parallel alerting system is not.

---

## Edge cases and failure modes

- BR-6 **Empty file (zero bytes).** A zero-byte `.md` file is well-formed UTF-8 (the empty string decodes trivially) and is below the size ceiling. It opens as a presented document with an empty buffer; no alert, no label. (Consistency: the existing happy path already does this; the new checks must not regress it.)
- BR-7 **Exactly-at-ceiling file.** A file whose byte size equals the ceiling exactly opens normally (BR-4.6). A file one byte larger is rejected with the too-large surface. Tests should cover both sides of the boundary.
- BR-8 **File becomes unreadable mid-load.** The file is resolvable when the size pre-check runs, but is deleted, unmounted, or has permissions revoked before the full read completes. The result is a load-failure surface (BR-3.1) — either the moved/removed alert or the permission-denied alert depending on the OS-reported error class — never a silent no-op and never a crash. The buffer is not partially populated.
- BR-9 **BOM-prefixed UTF-8.** A file beginning with `EF BB BF` followed by valid UTF-8 opens via the happy path (BR-1.3). It is NOT classified as non-UTF-8 and does not trigger BR-2.
- BR-10 **UTF-16 with BOM.** A file beginning with `FF FE` or `FE FF` is non-UTF-8 under strict UTF-8 decode and triggers BR-2. (This is the canonical "Latin-1 / UTF-16 file" case from the declaration's Why.)
- BR-11 **Mixed encoding (valid prefix, invalid tail).** A file whose first N bytes decode as UTF-8 but whose later bytes do not is non-UTF-8 and triggers BR-2. The open path does not present a truncated document built from only the valid prefix.
- BR-12 **iCloud not-yet-downloaded file.** A picked file whose contents are not yet downloaded from iCloud is handled by the existing iCloud-download path and is out of scope for this feature; the size pre-check and decode policy run against the materialized content once the OS makes it readable. If iCloud download fails, that failure is surfaced via the existing `iCloudDownloadFailed` alert path, not via the BR-3 surfaces. (Cross-feature boundary with `external-change-5`'s `SaveStatusObserver`.)
- BR-13 **Symbolic link / alias to a regular file.** Loading follows the link to the underlying regular file; size and decode rules apply to the resolved target. If the link target is missing, that is a moved/removed case (BR-3.2).
- BR-14 **Picked URL is a directory or non-regular file.** The system browser already filters to `.md`/`.markdown` content types, but if a non-regular URL nevertheless reaches `loadMarkdownDocument`, it produces a load-failure surface (BR-3.1) rather than a silent no-op or a crash on `FileWrapper` construction.
- BR-15 **Repeated failures on the same file.** Tapping the same problem file repeatedly produces the same surface each time (idempotent). No accumulation of stale alerts, no stacked modals, no leaked scope access across attempts.
- BR-16 **Resume path uses the same load gate.** When the resume flow (governed by `resume-and-detector-hardening-11`) hands a URL to the open path, the same BR-1 through BR-4 rules apply: a non-UTF-8 resume target produces BR-2, an oversized resume target produces BR-4, a vanished resume target produces BR-3 (or is recovered by bookmark fallback per `resume-and-detector-hardening-11`'s BR — whichever runs first; the disambiguation is that feature's concern, not this one's).

---

## Out of scope (restating and sharpening the declaration)

- OOS-1 **No encoding detection / heuristics.** Markus does not attempt to guess that a file is Latin-1, Windows-1252, UTF-16, etc., and does not consult chardet-style libraries. The decision is binary: strict UTF-8 or not.
- OOS-2 **No conversion or re-save in a different encoding.** A non-UTF-8 file is not transcoded and re-saved as UTF-8 by Markus. The buffer (if a labeled lossy open is presented) is what gets saved on a user-driven save, and that save's interaction with the original encoding is the user's problem to resolve outside Markus.
- OOS-3 **No streaming or chunked load for large files.** The size ceiling is a hard reject. There is no progressive loader, no "open the first N MB," no background paging.
- OOS-4 **No changes to the save path.** Write-error surfacing, coordinated writes, and reconciliation-lift refresh are governed by `save-bridge-hardening-9`. If the save side throws on a substituted buffer (post-BR-2 lossy open), that is `save-bridge-hardening-9`'s problem, not this feature's.
- OOS-5 **No changes to resume bookmark resolution or detector start ordering.** Both are governed by `resume-and-detector-hardening-11`. This feature's only contact with resume is BR-16 (resume URLs go through the same load gate).
- OOS-6 **No new settings or toggles.** The decode policy choice (BR-2 (a) vs (b)), the size ceiling value, and the surface wording are design-fixed; the user has no preference to set.
- OOS-7 **No file types beyond `.md`/`.markdown`** (inherited from the project declaration). A `.txt` or `.rtf` is not eligible to reach the open path at all.
- OOS-8 **No new UI surface type.** Alerts go through the existing `Conflict & lifecycle UI` channel (BR-5).
- OOS-9 **No accessibility-pass-level VoiceOver labeling of the new alerts.** That is deferred to Roadmap #7 (`accessibility-8`); controls must exist and be readable here, but the full a11y semantics pass is not part of this feature.

---

## Consistency notes and tensions

- **Decode policy is a single decision, not a per-file heuristic.** BR-2 deliberately permits design to choose between (a) labeled lossy and (b) surfaced encoding error, but forbids picking per-file. Mixing the two is the silent-failure shape the declaration is closing — a user who sometimes sees a lossy open and sometimes sees an error has no mental model of what Markus does with their file. Design picks one and tests assert that one.
- **BR-2 (b) is consistent with the existing `DocumentError.invalidEncoding` / `ActiveAlert.invalidEncoding` path.** That path already exists in code and is referenced by `external-change-5`'s BR-13. Choosing policy (b) is a no-cost path; choosing (a) requires the labeled-lossy surface to be designed in. The decision belongs in design, not requirements.
- **Size ceiling vs. "no realistic prose file is rejected."** The declaration's success criterion that no realistic markdown file is rejected is what bounds the ceiling from below; the OOM-prevention goal is what bounds it from above. The acceptable range is wide (tens of MB is comfortably above any prose use, comfortably below the OOM threshold on iOS), but the specific number is design's call.
- **BR-3.4 (failure on a second pick does not tear down the first document)** matters because `BrowserHostController` can be re-entered while a document is already presented. The current `loadMarkdownDocument` returning `nil` happens to be safe here (no tear-down occurs); the requirement pins the safety so a future refactor cannot regress it.
- **BR-12's iCloud boundary.** The existing `iCloudDownloadFailed` alert path is owned by `external-change-5`/`SaveStatusObserver`. This feature does not replace or duplicate it. A picked file that is not yet downloaded reaches the open path's checks only after the OS has made it readable; failure to make it readable is reported via the existing channel.

---

## Architectural feedback

The following need architectural resolution before requirements can be marked fully stable:

1. **Decode policy choice for non-UTF-8 (BR-2).** Design must pick (a) labeled lossy decode OR (b) surfaced encoding error, and pin it. Until pinned, BR-2's tests can only assert "not a silent no-op" and cannot assert the specific surface. Recommendation surfaced for design's consideration only: (b) is the lower-cost path (reuses `DocumentError.invalidEncoding` and `ActiveAlert.invalidEncoding` as already wired in `external-change-5`); (a) is the more user-friendly path but requires a new labeled banner. The choice belongs in design.

2. **Size ceiling value (BR-4.3).** Design must pin the numeric byte ceiling. The behavioral constraint is "high enough that no realistic prose markdown file is rejected, low enough that the largest accepted file cannot OOM the open path on the lowest supported iOS device." Until pinned, BR-4 tests can assert the at-boundary, just-above, and far-above shapes (using whatever constant design provides) but cannot independently judge whether the number is well-chosen.

3. **BOM retention in the buffer (BR-1.3).** Design must decide whether a leading UTF-8 BOM is stripped from the buffer on load (and therefore not round-tripped on save) or retained. The requirement pins that the BOM does not display as a visible character; whether it survives a round-trip is a save-path interaction with `save-bridge-hardening-9` and needs a single answer.

4. **Disambiguation of permission-denied vs. moved/removed at the OS-error layer (BR-3.2).** The OS does not always cleanly distinguish "file is gone" from "you can't see it any more" — both can manifest as `NSCocoaErrorDomain` codes that overlap. Design must specify the mapping from the OS error classes the load path actually encounters to the two named alert variants, so BR-3.2's tests have a deterministic mapping to assert. If the mapping cannot be made deterministic, the fallback is a single combined "couldn't read this file" alert, which is still strictly better than the silent no-op the declaration forbids.

These are scoping/parameter decisions, not contradictions in intent. The behavioral surface above is complete; only the four parameters/decisions above must be pinned by design and fed back into BR-1.3, BR-2, BR-3.2, and BR-4.

Requirements stable — architectural questions resolved in design.md (see DC-2, DC-3, DC-5, DC-8).
