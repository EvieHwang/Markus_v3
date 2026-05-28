# Adversarial review — open-path-hardening-10

Header: requirements.md @ 4e372170b2629a0944067279eef36220c58d22cb · design.md @ 4e372170b2629a0944067279eef36220c58d22cb · mode: fresh review

---

## Findings

### F-001 — Save-side byte change from BOM stripping crosses the feature's own scope boundary
- **Severity:** MEDIUM
- **Lens:** scope drift
- **Subject trace:** Feature `declaration.md` §"Shape touched" — "Does not touch: File access layer save side". Also OOS-4 in `requirements.md` — "No changes to the save path."
- **Finding:** DC-3 explicitly commits to a behavioral change on the save side: "a save of an unmodified BOM-prefixed file produces a file whose bytes are the original file's bytes *minus the BOM*." The feature's declaration and OOS-4 both forbid changes to save behavior; a BOM-prefixed file that is opened and saved with no edits is, today, byte-identical on disk. After this feature it is not. The user-observable failure mode: a writer whose sync pipeline (git, a build script, a downstream tool) treats the BOM as significant gets a one-time silent byte change the first time Markus is used to round-trip the file — exactly the "silent destructive round-trip" shape declaration §Why is trying to close. The fact that BR-1.3 leaves "whether the BOM survives the round trip" as an open question for design does not authorize design to resolve it by overriding the feature's own out-of-scope clause; OOS-4 is stricter than BR-1.3 is permissive.
- **Recommended action:** Either (i) retain the BOM in the buffer on load (resolve BR-1.3 the other way: still don't *render* it, but keep the bytes for the round trip) so save output is unchanged, or (ii) widen the feature declaration / OOS-4 explicitly to acknowledge this one-byte save-side effect and route it through `save-bridge-hardening-9` rather than absorbing it silently here. Architecture change.
- **Status:** addressed

### F-002 — Alert host coverage when no document is presented is not pinned
- **Severity:** MEDIUM
- **Lens:** coverage / failure modes
- **Subject trace:** BR-3.1 ("`loadMarkdownDocument`'s outcome is observable to the user as an alert before control returns to the browser idle state") and BR-3.5 ("callers in `BrowserHostController` must convert every failure into a surfaced alert"). Also DC-1 — "after the open path runs, the user observes one of two states: the document is presented in the editor, or an alert is on screen describing why it is not."
- **Finding:** DC-6/DC-10 say alerts render through "the host's alert modifier" and explicitly contrast with the editor's alert channel; the Ground-truth check names "`DocumentView`'s `activeAlert` channel" as the existing surface. But the alerts this feature adds fire on the *open path* — including the first-ever open from a cold launch, where no `DocumentView` (and therefore no `activeAlert` modifier) is yet on screen. Design does not pin where the alert is hosted when there is no presented document. The reachable failure mode: cold launch → pick a non-UTF-8 / oversized / permission-denied file → `ActiveAlert` is set but no view is hosting an `.alert(...)` bound to it → user sees nothing (the silent no-op the feature exists to close, recreated under a different shape).
- **Recommended action:** Pin the alert host explicitly in design — either confirm the system document browser's host view itself owns an `.alert(...)` bound to a no-document-present alert surface, or specify that the alerts are presented on a host view that is on screen during the browser-idle state. The behavioral guarantee DC-1 makes is unverifiable without naming the host. Architecture change.
- **Status:** addressed

### F-003 — Resume bookmark-fallback race with this feature's alerts is left ambiguous
- **Severity:** LOW
- **Lens:** failure modes / cross-feature boundary
- **Subject trace:** BR-16 — "a vanished resume target produces BR-3 (or is recovered by bookmark fallback per `resume-and-detector-hardening-11`'s BR — whichever runs first; the disambiguation is that feature's concern, not this one's)." DC-11 echoes this.
- **Finding:** Both requirements and design defer the ordering question to `resume-and-detector-hardening-11`, but DC-11 also asserts "the resume path uses the same load pipeline" without specifying whether the bookmark-fallback attempt happens *before* the pipeline runs (so the pipeline sees the recovered URL) or *after* the pipeline emits its moved/removed alert (in which case the user could see the alert and *then* the file opens silently, or two surfaces fire). The user-observable failure mode is small (a moved/removed alert fires and is then visually displaced by a successful open) but the disambiguation belongs in one of the two features, and currently belongs in neither in a load-bearing way. Named location: DC-11.
- **Recommended action:** Add one sentence to DC-11 specifying the ordering contract this feature relies on (e.g. "the resume path resolves its URL — including any bookmark fallback — before handing to the open pipeline; this feature never observes a vanished-then-recovered URL"). If the actual contract lives in `resume-and-detector-hardening-11`, cite the specific DC there. Architecture change (one sentence).
- **Status:** addressed

---

## Prescription feedback

None this pass. The design names in-repo seams (`MarkdownDocument`, `BrowserHostController`, `ActiveAlert`, `DocumentView.activeAlert`) only where the declaration or requirements already fix them as constraints, and phrases every DC as an observable property rather than a call signature. The `URLResourceValues.fileSize` / `FileManager.attributesOfItem` mention in DC-5 is correctly hedged as "e.g." rather than prescribed.

---

## Summary

Three findings, all addressed in the revision pass. F-001 (MEDIUM, scope drift on save side from BOM stripping) addressed by flipping DC-3 to retain the BOM in the in-memory buffer and suppress it at render time; the no-edit save now round-trips original bytes byte-for-byte, restoring OOS-4. F-002 (MEDIUM, alert host not pinned for the no-document case) addressed by new DC-6a pinning `BrowserHostController`'s root view as the alert host for open-path alerts. F-003 (LOW) addressed by a one-sentence ordering contract added to DC-11: resume URL — including bookmark fallback — is resolved before the open pipeline runs. No HIGH findings; no integrity contradictions; no standards-compliance issues against `constitution.md`.
