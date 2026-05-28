# Design — Open-Path Hardening

*Architecture for `open-path-hardening-10`. Source of truth for intent: `features/open-path-hardening-10/declaration.md`; behavior: `features/open-path-hardening-10/requirements.md` (stable at commit f9ed701). Every constraint below (DC-n) is phrased as an observable property of the running system — what the user or the system can detect — not as a call signature, attribute name, or library API detail. Where a name appears, it is an in-repo seam this feature extends and is marked accordingly.*

**Deferred-question resolution.** This design resolves all four architecture-flagged questions raised at the bottom of `requirements.md`:
- (1) Decode policy choice for non-UTF-8 (BR-2) → §Decode policy, DC-2 — **policy (b), surfaced encoding error**.
- (2) Size ceiling value (BR-4.3) → §Size ceiling, DC-5 — **20 MiB (20 × 1024 × 1024 = 20 971 520 bytes)**, inclusive.
- (3) BOM retention in the buffer (BR-1.3) → §Decode policy, DC-3 — **strip on load**, do not round-trip.
- (4) Permission-denied vs moved/removed mapping (BR-3.2) → §Failure mapping, DC-8 — explicit OS-error mapping with a generic-fallback alert variant for the ambiguous case.

None of the four resolutions required changing any requirement *text*. The requirements bottom marker has accordingly been flipped to "Requirements stable — architectural questions resolved in design.md (see DC-2, DC-3, DC-5, DC-8)".

---

## Ground-truth check (resolved before drafting)

- **Seams consulted (read before drafting):** `MarkdownDocument` (with the `init(file:contentType:)` path that currently throws `DocumentError.invalidEncoding` on non-UTF-8 bytes), `DocumentError`, `ActiveAlert`, `BrowserHostController` (and its `static loadMarkdownDocument(at:) -> MarkdownDocument?` which currently swallows every `catch` into `nil`), `presentDocument(at:)`, `DocumentView`'s `activeAlert` channel, and `external-change-5`'s use of the same `ActiveAlert.invalidEncoding` case for the running-document encoding-failure surface.
- **Cross-feature precedent:** the `Conflict & lifecycle UI` channel is the `ActiveAlert`-driven `.alert(...)` modifier on `DocumentView`. `external-change-5` (DC-14 / `ActiveAlert.invalidEncoding`, `iCloudDownloadFailed`) and `save-bridge-hardening-9` (declaration) both extend this same surface rather than introducing a parallel one. This feature follows the same rule (BR-5.1).
- **Concurrency:** Swift 6 strict concurrency. The size pre-check, the decode, the alert presentation, and the security-scope acquire/release all happen on the `@MainActor` host path (`presentDocument(at:)` is already `@MainActor`). The size pre-check uses a stat-style attribute read (no full file load), so off-main dispatch is not load-bearing for this feature.
- **Pattern reuse from `constitution.md`:** constitution.md registers Python/React patterns only; nothing iOS-specific. No component below is marked `Reuses pattern: [constitution name]`. In-repo seam reuse is marked `Reuses seam: [name]` or `Extends seam: [name]` as in `external-change-5`'s convention.

---

## High-level shape

The open path is one short pipeline. Today it is two lines: `loadMarkdownDocument` opens a `FileWrapper`, hands its bytes to `MarkdownDocument(file:contentType:)`, and on *any* throw catches into `nil` — at which point `presentDocument(at:)` does `guard let document = ... else { return }` and the user sees nothing. This feature converts that pipeline from "any failure → silent return" into a four-stage gated load whose every failure mode terminates in either a presented document or a presented alert, with no third "silent return" branch.

The four stages, in order, with the failure surface each one owns:

1. **Resolve & scope-acquire** — security-scoped resource access for the picked URL. Failure → permission-denied surface (DC-6, DC-8).
2. **Size pre-check** — attribute-only byte-size read against the ceiling. Failure → too-large surface (DC-5) OR moved/removed surface if the file no longer resolves (DC-6, DC-8).
3. **Coordinated read** — read the file bytes into `Data`. Failure → moved/removed or permission-denied or generic-read surface (DC-6, DC-8).
4. **Strict UTF-8 decode** — bytes → `String` under strict UTF-8 (with leading BOM stripped, DC-3). Failure → encoding error surface (DC-2).

Only if all four stages succeed is a `MarkdownDocument` constructed and `presentDocument(at:)` proceeds to install the detector, save bridge, and editor exactly as it does today. Every other terminal state is an alert through the existing `ActiveAlert` channel, with security scope released (DC-9) and the previously-presented document (if any) untouched (DC-10).

The three Shape seams map to three responsibilities:

- **Document model** (`MarkdownDocument`) — owns the decode policy and the BOM rule (DC-2, DC-3). *Extends `MarkdownDocument`.*
- **Document browser entry** (`BrowserHostController`) — owns the load pipeline, the size pre-check, the failure mapping, the scope-release on every exit, and the alert hand-off to the host's alert surface (DC-1, DC-5, DC-6, DC-8, DC-9, DC-10). *Extends `BrowserHostController`.*
- **Conflict & lifecycle UI** (`ActiveAlert` + the host's alert surface) — receives the four new failure cases as additional `ActiveAlert` cases and renders them with the existing `.alert(...)` modifier; no new component (DC-4, DC-7). *Extends `ActiveAlert` and the host's alert presentation.*

---

## Components

### 1. Load pipeline (Document browser entry) — *primary*

The pipeline replaces today's `loadMarkdownDocument` swallowing return-`nil`. It is owned by `BrowserHostController` and runs at exactly the same call sites the current `loadMarkdownDocument` runs at (browser pick, resume hand-off, system import). *Extends seam: `BrowserHostController.loadMarkdownDocument` + `presentDocument(at:)`.*

**DC-1 — Every open attempt terminates in either a presented document or a presented alert, never in a silent return.** For any picked URL, after the open path runs, the user observes one of two states: the document is presented in the editor, or an alert is on screen describing why it is not. There is no reachable end-state in which the open path has run, no document is presented, and no alert is on screen. (BR-3.1, BR-3.5; anchors the silent-no-op elimination from declaration §Why.) The observable test surface: drive every failure mode (permission denied, decode failure under DC-2, file moved mid-pick, oversized file) and assert an `ActiveAlert` is presented in each case before control returns to the browser idle state.

**DC-4 — Failure surfaces are sequenced: size first, then resolve/read errors, then decode.** Because the surfaces are exclusive (DC-1: exactly one terminal state), the pipeline runs its checks in a fixed order: scope-acquire → size pre-check → read → decode. The user-visible consequence: a file that is both oversized *and* not UTF-8 surfaces as too-large (the cheaper check that gates the expensive one); a file that is both non-UTF-8 *and* would have hit a read error never reaches the decode stage. This ordering is load-bearing for BR-4.2 (the size check runs before the full read into memory) and is the reason an oversized binary file does not trigger an OOM during a pre-emptive decode probe.

### 2. Decode policy (Document model) — *DEFERRED QUESTION 1*

**DC-2 — Non-UTF-8 bytes produce an encoding-error surface; Markus does not present a lossy buffer (policy (b)).** When the bytes read from the picked file do not decode under strict UTF-8, the open path emits the encoding-error surface (the existing `ActiveAlert.invalidEncoding`, reused) and presents no document. The observable property: for any file whose bytes contain a sequence that is not valid UTF-8, the user sees the encoding alert and the editor never opens; the buffer never contains `U+FFFD` substitutions from this load (BR-2.1 (b), BR-2.2, BR-2.4). *Reuses seam: `DocumentError.invalidEncoding` and `ActiveAlert.invalidEncoding`, already wired by `external-change-5` for the same failure shape on reload.*

Rationale for picking (b) over (a):
- **It matches the project's "no proprietary format / no silent magic" stance** (declaration: "No proprietary format — the file on disk is always plain `.md` / `.markdown`"). A labeled lossy decode would let the user edit and save a buffer that silently transcodes the on-disk encoding into UTF-8 with `U+FFFD` holes — a destructive round-trip for a "lens over my files" app, even with a label.
- **It is the lower-cost path.** `DocumentError.invalidEncoding` and `ActiveAlert.invalidEncoding` already exist, already alert correctly through the `Conflict & lifecycle UI` channel, and are already referenced by `external-change-5`. Policy (a) would require a new labeled-banner surface (BR-5.1 forbids a parallel surface; extending `ActiveAlert` is allowed, but a *banner* — non-modal, persistent label) is not currently in the channel and would be new UI grammar.
- **It is consistent with OOS-1 (no encoding detection / heuristics).** Once Markus has decided not to guess, "open with substitutions" is the partial-guess case: it pretends a Latin-1 file is a UTF-8 file with damage. Refusing to open is the honest answer.
- The user is not stuck: the alert names the file as not valid UTF-8; the user can convert it externally (the project assumes Files-app-fluent users) and re-pick.

**DC-3 — A leading UTF-8 BOM is stripped on load and is not re-emitted on save (DEFERRED QUESTION 3).** When the picked file's first three bytes are `EF BB BF` followed by valid UTF-8, the decode strips those three bytes; the resulting buffer (and therefore the round-trip save) does not contain the BOM. The observable properties: (i) the rendered surface does not display a leading zero-width character (BR-1.3); (ii) a save of an unmodified BOM-prefixed file produces a file whose bytes are the original file's bytes *minus the BOM*. Rationale: the project's "plain `.md`" stance treats the BOM as a non-content artifact; UTF-8 BOMs are advisory and most modern markdown tooling either ignores or actively dislikes them. Stripping on load makes the canonical in-memory form unambiguous (no "is the leading BOM part of the buffer or not?" question for the editor or for the content-equality gate `external-change-5`/DC-11 uses) and produces a deterministic round-trip. The save-side consequence (one byte difference between original and round-tripped file when the original had a BOM) is documented here and flagged to `save-bridge-hardening-9` only as an acknowledged round-trip difference — it does not require any change there.

### 3. Size ceiling (Document browser entry) — *DEFERRED QUESTION 2*

**DC-5 — The size ceiling is 20 MiB (20 × 1024 × 1024 = 20 971 520 bytes), inclusive.** A picked file whose on-disk byte size is less than or equal to the ceiling is admitted to the read stage; a file whose byte size is strictly greater than the ceiling is rejected with the too-large surface and no read is performed (BR-4.1, BR-4.6). The check is implemented as an attribute-only size lookup (e.g. `URLResourceValues.fileSize` / `FileManager.attributesOfItem`), not a streamed read — the file's bytes are not loaded into memory before the gate (BR-4.2). The observable property the test stages: a 20 971 520-byte file opens (inclusive boundary); a 20 971 521-byte file produces the too-large alert; a 500 MB file produces the too-large alert with no measurable memory spike on the open path.

Rationale for 20 MiB specifically:
- **Lower bound (no realistic prose file is rejected, declaration §Success).** A 20 MiB file at one byte per ASCII character is ~20 million characters, ~3.3 million English words — roughly 30–40 full novels concatenated. No prose markdown file from the target user (PM/writer keeping notes in iCloud) realistically approaches this. The largest plausible single-file markdown corpus a real user maintains (a years-long journal, a book draft with embedded base64 images inline) sits comfortably one to two orders of magnitude below this.
- **Upper bound (cannot OOM the open path on the lowest supported iOS device).** The decode allocates a `String` whose UTF-8 storage is at least the byte count of the input; Swift's `String` may carry up to ~2× that during the bridging copy from `Data`. 20 MiB in → ~20–40 MiB peak transient allocation, well inside the per-app extended-memory budget on the iOS 26 baseline device (iPhone XS / 4 GB RAM minimum) even under multitasking pressure. A ceiling at 100 MiB would also fit, but 20 MiB leaves headroom for the editor's TextKit storage (which carries its own copy of the string in attributed form), the rendered HTML/AttributedString for the rendered mode, and the undo buffer.
- **Round-number choice.** A power-of-two MiB ceiling is more discoverable than a "37 MB" figure if a future build agent needs to recall or change it; the constant is named in code, but the value is also a number a human can hold.

The ceiling is design-fixed and not user-configurable (OOS-6).

### 4. Failure surfaces (Conflict & lifecycle UI)

**DC-6 — The four new failure cases are presented through the existing `ActiveAlert` channel; no new UI grammar is introduced (BR-5.1).** The encoding-error case reuses `ActiveAlert.invalidEncoding` exactly. Three new `ActiveAlert` cases are added for the open-path-specific failures that today have no surface:
- a too-large case (DC-5),
- a permission-denied case (DC-8),
- a moved/removed case (DC-8),
- a generic-couldn't-read fallback case (DC-8, for the ambiguous OS error class).

These are additional cases on the existing enum; they render through the same `.alert(...)` modifier the host already drives. They are not a parallel surface, a banner, a toast, or a sheet (`Reuses seam: ActiveAlert + the host's alert modifier`).

**DC-7 — Alert text names the failure specifically enough for the user to act.** Each surface uses wording that distinguishes it from the other three:
- Encoding error: substantively "This file isn't UTF-8 and can't be opened in Markus." (BR-2.4, BR-3.2)
- Permission denied: substantively "Markus doesn't have permission to read this file. Re-pick it from the browser to grant access." (BR-3.2)
- Moved/removed: substantively "This file is no longer at the location you picked." (BR-3.2)
- Too-large: substantively "This file is too large for Markus to open." (BR-4.1)
- Generic-couldn't-read fallback: substantively "Markus couldn't read this file." (DC-8 fallback)

Each surface offers at least a Dismiss action (BR-3.3). The exact strings are owned by the build step; the behavioral guarantee is that the four cases are distinguishable to the user, not that any particular wording is used.

### 5. Failure mapping (Document browser entry) — *DEFERRED QUESTION 4*

**DC-8 — The mapping from OS error class to alert variant is deterministic, with an explicit generic-fallback for the ambiguous case.** The pipeline maps the errors it actually encounters as follows:

| OS error class observed during the load | Surface |
|---|---|
| `NSCocoaErrorDomain` / `NSFileNoSuchFileError`, `NSFileReadNoSuchFileError`; POSIX `ENOENT` | moved/removed |
| `NSCocoaErrorDomain` / `NSFileReadNoPermissionError`; POSIX `EACCES`, `EPERM`; security-scoped `startAccessingSecurityScopedResource()` returning `false` | permission-denied |
| Strict UTF-8 decode produces `nil` | encoding error (DC-2) |
| File size attribute read succeeds and size > ceiling | too-large (DC-5) |
| Any other `Cocoa`/POSIX file-read error, or an error whose class does not unambiguously fall into the above (including `NSFileReadUnknownError`, `EIO`, framework-internal errors) | generic-couldn't-read fallback |

The observable property the requirements pin (BR-3.2): the user is told which of the three named cases happened *when the OS unambiguously says so*; when the OS cannot or does not say so, the user sees the generic-couldn't-read alert — which is still strictly better than today's silent no-op (BR-3.1). This trades a deterministic-mapping guarantee against the cost of mis-classifying ambiguous errors as the wrong specific cause. The fallback also makes the design robust to OS error-class drift across iOS versions: a new error class introduced by a future iOS does not silently fall out the bottom into a no-op, it falls into the generic surface.

Rationale: the requirements explicitly named this fallback as the acceptable retreat ("If the mapping cannot be made deterministic, the fallback is a single combined 'couldn't read this file' alert, which is still strictly better than the silent no-op the declaration forbids"). Picking the deterministic-where-possible / generic-otherwise mapping satisfies BR-3.2 without claiming a precision the OS does not actually provide.

### 6. Scope, state, and prior-document safety

**DC-9 — Every terminal state of the load pipeline releases the security-scoped resource it acquired.** Whether the pipeline ends in a presented document, in any of the four alert surfaces, or in an exception path not anticipated by the mapping, the `startAccessingSecurityScopedResource()` it took on entry is paired with a `stopAccessingSecurityScopedResource()` before the terminal state is observable to the user (BR-3.3, BR-4.5). The observable property: repeated tap-rejection cycles on the same problem file (BR-15) do not leak scope counts — the system's per-URL scope count after N failed taps equals its count before them. The success path's existing scope handoff to the presented document is unchanged.

**DC-10 — A failure on a later open does not tear down a previously-presented document (BR-3.4).** The four new alert surfaces are presented through the host's alert channel, which is independent of the editor's own state. A pick that fails after a document is already presented produces only the alert; the previously-presented document, its buffer, its dirty state, its detector, and its save bridge are not torn down by the failure. The observable property: open file A (clean or dirty), pick file B that triggers any of the four surfaces, dismiss → file A is still presented and its edits, cursor, and mode are intact.

**DC-11 — The resume path uses the same load pipeline (BR-16).** When the resume flow (`resume-and-detector-hardening-11`) hands a URL into the open path, it goes through the same four stages with the same surfaces. A non-UTF-8 resume target produces the encoding alert (DC-2); an oversized resume target produces the too-large alert (DC-5); a vanished resume target produces the moved/removed alert (DC-8) — or is recovered by bookmark fallback per `resume-and-detector-hardening-11`'s own BR, whichever runs first. This feature does not introduce a resume-specific bypass.

---

## Seam relationships (data flow)

```
picked URL  ─────────────────────────────────────────────────────────────►
(browser pick / system import / resume hand-off)
        │
        ▼
   BrowserHostController.presentDocument(at:)
        │
        ▼
   load pipeline  (DC-1, DC-4)
        │
        │   stage 1: scope-acquire
        │      ├── ok ──► continue
        │      └── refused ──► permission-denied surface (DC-6/8) ──► release scope (DC-9) ──► alert
        │
        │   stage 2: size pre-check (attribute read; no file load — BR-4.2)
        │      ├── ≤ 20 MiB ──► continue
        │      ├── > 20 MiB ──► too-large surface (DC-5/6) ──► release scope ──► alert
        │      └── attribute lookup fails (file vanished) ──► failure mapping (DC-8)
        │
        │   stage 3: read bytes
        │      ├── ok ──► continue
        │      └── error ──► failure mapping (DC-8): moved/removed | permission-denied | generic
        │                  ──► release scope ──► alert
        │
        │   stage 4: strict UTF-8 decode (BOM stripped — DC-3)
        │      ├── ok ──► MarkdownDocument constructed
        │      └── fails ──► encoding-error surface (DC-2/6) ──► release scope ──► alert
        │
        ▼
   MarkdownDocument constructed
        │
        ▼
   existing presentDocument path: install save bridge + detector, present DocumentView
   (open settle window per external-change-5 DC-6; scope handed to the presented document)
```

A previously-presented document, if any, is *outside* this diagram: the failure surfaces (the right-hand exits at each stage) feed the host's alert channel, not the editor's, so DC-10's "prior document survives a failed pick" property holds by construction.

---

## Behavioral test anchors (for `/tests`)

These restate the now-pinned values so spec tests can assert concretely:

- **Size ceiling = 20 971 520 bytes, inclusive** (DC-5). Tests stage: a file at exactly 20 971 520 bytes opens (BR-4.6); a file at 20 971 521 bytes produces the too-large alert; a 500 MB file produces the too-large alert with no measurable memory spike (BR-4.2).
- **Decode policy = (b) surfaced encoding error** (DC-2). Tests stage: a Latin-1 file with high bytes → encoding alert, no document; a UTF-16 BE/LE file → encoding alert; a mixed-encoding file (valid UTF-8 prefix, invalid tail per BR-11) → encoding alert (no truncated document).
- **BOM stripped on load** (DC-3). Tests stage: an `EF BB BF` + valid UTF-8 file opens without an alert; the buffer's first character is the first character *after* the BOM; a save round-trip writes the file *without* the BOM.
- **Silent-no-op is unreachable** (DC-1). Tests stage every failure mode and assert an `ActiveAlert` is non-nil before the browser is idle again.
- **Failure mapping is deterministic where the OS is unambiguous, generic otherwise** (DC-8). Tests stage: simulate `NSFileReadNoPermissionError` → permission-denied alert; simulate `NSFileReadNoSuchFileError` → moved/removed alert; simulate an `NSFileReadUnknownError` → generic-couldn't-read alert.
- **Scope is released on every failure path** (DC-9). Tests stage repeated failed opens on the same URL and assert no scope-count leak (no zombie scope-access on subsequent successful opens).
- **Prior document survives a failed second pick** (DC-10). Tests stage: open file A, pick file B (failure of each of the four kinds in turn), dismiss → file A is still presented with intact buffer/cursor/mode.
- **Resume path goes through the same gate** (DC-11). Tests stage a resume URL of each problem class and assert the same surface fires.

---

## Upstream marker maintenance

The four deferred questions in `requirements.md` were the only items blocking its "stable" marker; each is resolved above (DC-2, DC-3, DC-5, DC-8) without any change to requirement *text*. The "Architectural feedback" section's closing in `requirements.md` has been flipped to "Requirements stable — architectural questions resolved in design.md (see DC-2, DC-3, DC-5, DC-8)." per the `/spec` Stage-2 instructions.

---

Architecture stable — no requirements changes flagged
