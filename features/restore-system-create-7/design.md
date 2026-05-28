# Design — Restore System Create

*Architecture for `restore-system-create-7`. Source of truth for intent: `features/restore-system-create-7/declaration.md`; behavior: `features/restore-system-create-7/requirements.md`. Every constraint below (DC-n) is phrased as an observable property of the running system, not a call signature — with the one named exception called out explicitly (DC-1, the template-only create-delegate seam).*

This is a **corrective removal feature**. It deletes the custom new-file creation path added in `resume-and-create-2` and lets `UIDocumentBrowserViewController` handle creation the way iOS handles it everywhere else. Resume-on-launch, last-opened tracking, and back-to-browser are preserved unchanged. The only behavioral seam being *added* is a content-based initial-mode rule inside `DocumentView`'s existing `.onAppear` decision.

---

## What this design is, structurally

Three moves:

1. **Remove the directory-choosing, naming, and deferred-write *logic*** layered on top of the create delegate (C4–C7 from `resume-and-create-2/design.md` plus the deferred-write behavior, old DC-9). The create-delegate method itself remains in the host, but as a minimal template-only implementation (see DC-1).
2. **Reduce the system create delegate to a template-only handoff** — `documentBrowser(_:didRequestDocumentCreationWithHandler:)` provides an empty `.md` template URL (e.g., in `NSTemporaryDirectory()`) and immediately completes the system handler, supplying no Markus-chosen directory and no Markus-chosen name. The system then runs its default create + inline-rename flow.
3. **Add one behavioral rule** — content-based initial-mode selection in `DocumentView` — replacing the old "is this a fresh creation?" signal that the create path used to thread through `initialMode`.

No new components are introduced. No components are renamed. The remaining components (C0, C1, C2, C3, C8) keep their responsibilities and observable contracts from `resume-and-create-2/design.md`.

---

## Components being removed

Each is named with the file(s) where it currently lives, confirmed by grep against the codebase. The behavioral observable that licenses the removal is AC-5.4: no call site in Markus references any of these types or their methods after this feature.

- **C4 CreateDocumentHandler** — the directory-choosing, naming, and deferred-write *logic*. Currently lives in `Markus_v3/Create/CreateDocumentHandler.swift`, with its wiring in `Markus_v3/Host/SceneDelegate.swift` (the `createHandler` property and its construction at scene connect) and its invocation from the create-delegate override in `Markus_v3/Host/BrowserHostController.swift`. The *delegate method* itself stays (as the minimal template-only implementation described in DC-1); what goes is the `CreateDocumentHandler` type, its wiring, and any logic in the delegate body beyond "create empty template, complete handler." Tests: any `CreateDocumentHandler*Tests` (none present today by that name; the behavior is covered indirectly by `ResumeAndCreateUITests` and `Markus_v3Tests/MarkdownDocumentSaveBridgeTests` where it asserts deferred-write semantics).
- **C5 NameProbe** — `Markus_v3/Create/NameProbe.swift` and `Markus_v3Tests/NameProbeTests.swift`.
- **C6 CreateTargetResolver** — `Markus_v3/Create/CreateTargetResolver.swift` and `Markus_v3Tests/CreateTargetResolverTests.swift`. This includes the writability probe logic that satisfied the old DC-12.
- **C7 LocalDocumentsFallback** — `Markus_v3/Create/LocalDocumentsFallback.swift` and `Markus_v3Tests/LocalDocumentsFallbackTests.swift`.
- **Deferred-write behavior (old DC-9)** — the in-memory-until-first-keystroke state held in `BrowserHostController` (the "for deferred-write create, the file becoming real on disk for the first time…" branch around line ~200) and any deferred-write path in `MarkdownDocument`/`MarkdownDocumentSaveBridge`. After this feature, new files exist on disk from the moment the system create completes; there is no "is this document materialized yet?" state to track anywhere.
- **The threading of a create-driven `initialMode` from the create path → `DocumentView`.** Behaviorally: no `initialMode` flag is supplied by a create path; initial mode is decided in-place by document content (DC-4). *Implementation note (non-normative): `DocumentView.init` currently exposes an `initialMode:` parameter. Whether that parameter is removed outright or retained for other call sites is a build choice; the load-bearing observable is that no create-site supplies a non-nil value to it.*

*Implementation note (non-normative): once C5/C6/C7 are gone and `CreateDocumentHandler.swift` is removed, the `Markus_v3/Create/` directory is expected to be empty and the Xcode group reference can be cleaned up. The normative requirement is AC-5.4 (no call site references the removed components) and AC-6.3 (build green); directory deletion is hygiene, not a behavioral observable.*

---

## Component being kept (no behavioral change)

These keep their `resume-and-create-2/design.md` contracts verbatim. They are listed here only to make explicit that this feature does not touch them.

- **C0 BrowserHost** — `Markus_v3/Host/BrowserHostController.swift`. Continues to host the `UIDocumentBrowserViewController` and present `DocumentView` (via `UIHostingController`) on document open. Retains the create-delegate method as a minimal template-only handoff (see DC-1); loses the directory/naming/deferred-write logic that previously lived in the delegate body. Everything else — the open-document delegate path, the resume entry point, the presentation of the editor — is unchanged.
- **C1 LastFileStore** — security-scoped bookmark persistence. Unchanged.
- **C2 LaunchResumeBranch** — `Markus_v3/Resume/LaunchResumeBranch.swift`. Resume-on-launch decision; unchanged. The old `resume-and-create-2` DC-1 through DC-5 (durable reference, lands in rendered view, zero browser frames on resume, silent failure, retain-on-failure) all remain in force.
- **C3 DocumentOpenObserver** — record-on-open funnel attached to `DocumentView`'s lifecycle. Unchanged. A system-created file enters this funnel via the same `DocumentView` activation path as any browser-opened file; no special "this came from a create" branch is needed. This is the load-bearing reason AC-5.2 holds with zero new code.
- **C8 BackToBrowser** — leading back affordance and edge-swipe pop on both modes. Unchanged.

---

## The one new behavioral seam: content-based initial mode

`DocumentView` already chooses an initial mode in its `.onAppear` block (currently: large file → `.raw`, otherwise `.rendered`, with an optional `initialMode` override). This feature widens that decision to include the empty-content case.

This is *not* a new component. It is an extension of the existing initial-mode decision in `DocumentView.swift`. After this change, no create-path-threaded flag is the mechanism by which a freshly-created file lands in raw mode — the document's *content* is.

---

## Behavioral contracts (design constraints)

### Removal contracts

**DC-1 — The system create delegate is template-only.** *Addresses adversarial F-001.* *(Named-mechanism exception — `UIDocumentBrowserViewController`'s create contract is itself the framework's API surface, and the requirement is that Markus contributes nothing to it beyond the minimum the framework requires.)* `BrowserHostController` (the project's `UIDocumentBrowserViewControllerDelegate`) implements `documentBrowser(_:didRequestDocumentCreationWithHandler:)` **minimally**: it produces an empty `.md` template file in an app-managed temporary location (e.g., `NSTemporaryDirectory()`), invokes the system completion handler with that template URL and a success mode, and returns. The delegate body contains no Markus-chosen target directory, no Markus-chosen file name, no collision-avoidance logic, no writability probe, no fallback-target logic, and no deferred-write branching. The system, on receiving the template URL, copies the template into the folder currently shown by the browser, presents its inline rename UI, and on confirm opens the file through the normal open-document delegate path. *Rationale for the named-mechanism exception:* the framework requires the delegate to be present and to supply a template for the "+" affordance to function; an "un-overridden" framing would actually disable create. Naming the call surface lets the contract distinguish "delegate exists, minimal" (correct) from "delegate exists, contains logic" (the regression we are removing). The behavioral observables — file lands in browsed folder, system rename UI shown, no Markus-supplied directory or name, on-disk from creation — are what AC-1.*, AC-2.*, and AC-3.1/3.2 verify; the named-mechanism note ensures the delegate isn't quietly re-grown with logic that produces the same observables under benign test conditions but deviates under others. *(AC-1.1, AC-1.2, AC-1.3, AC-2.1, AC-2.2, AC-2.3, AC-2.4, AC-3.1.)*
*Reuses pattern: `UIDocumentBrowserViewController` template-handoff create affordance (project declaration "Document browser entry"; matches Files.app / Pages / Apple-default usage).*

**DC-2 — No code path defers a new file's on-disk persistence.** A document held by the app is either backed by a real on-disk file or it is not a document the app is editing. There is no in-memory "new but not yet written" state anywhere — no flag, no holding URL, no first-keystroke trigger that materializes a file. After the system create completes (the template has been copied into the browsed folder and renamed), the file exists on disk; from that moment forward it is treated identically to any other browser-opened file. The template file itself, sitting in the app temp location before the system copies it, is not a Markus-edited document — it is inert input to the framework's create flow. *(AC-3.1, AC-3.2.)*

**DC-3 — No code path observes or reacts to an abandoned create.** If the user dismisses the system rename UI without confirming, Markus runs no cleanup, no logging, no banner, no recovery branch. The observable state is whatever `UIDocumentBrowserViewController` produces; the user manages any resulting file via the standard browser delete gesture. There is no Markus-owned signal that "a create was abandoned" — that concept does not exist in the post-feature codebase. *(AC-3.3, EC-3.)*

### New behavioral seam

**DC-4 — Initial mode is a pure function of document content.** When `DocumentView` becomes active for a file, it selects its initial mode from the document's content alone:
- **Empty content (zero bytes of text):** `.raw`, with the raw editor's text input as first responder and the software keyboard presented.
- **Large content (at or above the existing large-file threshold, currently 500 KB):** `.raw`. *(Existing behavior, preserved.)*
- **Otherwise:** `.rendered`. *(Existing behavior, preserved.)*

The decision uses no signal about how the file was reached — not the URL, not a "fresh creation" flag, not a caller-supplied initial-mode hint. A pre-existing zero-byte `.md` opened from the browser and a just-system-created zero-byte `.md` are indistinguishable at this seam and produce the same result: raw mode, keyboard up. *How* "empty" is determined (text emptiness, byte size, or a combination) is left to the build; the behavioral constraint is the outcome, not the predicate. *(AC-4.1, AC-4.2, AC-4.3, EC-6.)*

### Preserved contracts (restated for traceability)

**DC-5 — Resume-on-launch is unchanged.** All of `resume-and-create-2/design.md` DC-1 through DC-5 remain in force. A valid stored bookmark resumes directly into the rendered view with no browser frame; an unresolvable bookmark falls back silently to the browser; the reference is retained across resolution failures. *(AC-5.1.)*

**DC-6 — Last-opened tracking funnels system-created files through C3 unchanged.** C3 records every `DocumentView` activation for a non-nil `fileURL`. A system-created file opens via the same open-document delegate path as any browser-opened file, so it enters this funnel with no special-case code. On next launch it is the resume target. *(AC-5.2.)*

**DC-7 — Back navigation is unchanged.** C8's leading back chevron and the standard edge-swipe-pop both return to the browser from a system-created file's editor exactly as they do from any other browser-opened file. *(AC-5.3.)*

---

## Seam relationships

- **C0 (BrowserHost) ↔ `UIDocumentBrowserViewController` create affordance.** Template-only delegate (DC-1). The host produces an empty `.md` in the app temp location and hands the URL to the system completion handler; the system copies it into the currently-browsed folder, runs the inline rename UI, and on confirm opens the file through C0's existing open-document delegate path (the same path used for any user-tapped file in the browser). The open-document path is unchanged from `resume-and-create-2`.

- **C3 (DocumentOpenObserver) ↔ `DocumentView` lifecycle.** Unchanged. Reads the already-present `fileURL` when `DocumentView` activates and forwards it to C1. The fact that the file came from a system create is invisible at this seam, which is exactly what AC-5.2 requires.

- **DC-4 (initial mode) ↔ `DocumentView.onAppear`.** Attaches to the same `.onAppear` block in `Markus_v3/Views/DocumentView.swift` that today chooses `.raw` for large files. The block is widened to also choose `.raw` for empty documents. No new view, no new state object, no new callback — the rule lives where the existing rule already lives. *Implementation note (non-normative): whether `DocumentView.init`'s existing `initialMode:` parameter is removed or retained for other call sites is a build choice; the load-bearing observable is that no create-path supplies it.*

- **Removed seams (no relationships to draw).** The directory/naming/deferred-write *logic* (C4–C7 and the deferred-write branch in `BrowserHostController`) ceases to exist. The minimal create-delegate method remains as the framework-required handoff surface; it carries no Markus-side decisions.

---

## HIG alignment

- Restoring the system create affordance is itself the HIG-canonical move: `UIDocumentBrowserViewController`'s template-handoff create + inline rename is what Files.app, Pages, and every Apple document-based app uses. The previous feature's custom create flow was the HIG deviation; this feature reverses it.
- The empty-document → raw-mode + keyboard rule matches Apple Notes / Pages new-document behavior: a brand-new document opens ready to type, not in a read-only preview.
- No alerts, banners, or custom UI are added or removed-with-replacement. Removal is silent.

---

## Build-time considerations (not requirements changes)

These are non-normative notes for the build agent. The normative requirements are the AC-* lines and the DC-* contracts above.

- **Tests are removed, not rewritten in place.** Per AC-6.1, the unit tests for the removed components (`NameProbeTests`, `CreateTargetResolverTests`, `LocalDocumentsFallbackTests`, plus any deferred-write assertions in `MarkdownDocumentSaveBridgeTests` and the create-flow assertions in `Markus_v3UITests/ResumeAndCreateUITests`) are deleted as part of the same change that removes the production code. The DAG should pair each removal with its test removal in a single task so the suite is never broken between tasks. *Normative observable: AC-6.1 (removed tests are gone), AC-6.3 (suite is green).*
- **`Markus_v3/Create/` directory.** Once C5/C6/C7 and the `CreateDocumentHandler` type are gone, this directory is expected to be empty; deleting it along with the Xcode group reference is hygiene. *Normative observable: AC-5.4 (no call site references the removed components); directory state is not itself an acceptance criterion.*
- **`SceneDelegate.createHandler` and its construction at scene connect** are removed; the host's delegate set no longer includes a Markus-built create handler. `BrowserHostController` keeps its open-document delegate role *and* keeps the minimal template-only `documentBrowser(_:didRequestDocumentCreationWithHandler:)` method itself (DC-1).
- **No migration logic.** Per declaration Out of scope and EC-8, any `Untitled n.md` files left in user directories by the old flow stay where they are. The build adds no detection or cleanup of these.

---

## Revision notes

- **2026-05-28 — Revision addressing adversarial F-001 (architecture side).** DC-1 was reframed from "the system create delegate is un-overridden" to "the system create delegate is template-only." The previous framing rested on a mental model in which omitting `documentBrowser(_:didRequestDocumentCreationWithHandler:)` would yield the iOS-default create flow; in actual `UIDocumentBrowserViewController` semantics, the delegate must be implemented and must supply a template URL for the "+" affordance to function. The revised DC-1 keeps the load-bearing behavioral observables (Markus contributes no directory choice, no name, no deferred write, no fallback/probe logic) and confines the framework-required surface to a minimal template handoff in `NSTemporaryDirectory()`. The named-mechanism exception is retained but rejustified: the call surface is the framework's API contract, and naming it lets us distinguish "minimal handoff" (correct) from "delegate body re-grown with logic" (the regression we are removing). The C4-removal section, seam-relationships section, and build-time-considerations section were rewritten in the same pass to refer to the directory/naming/deferred-write *logic* being removed rather than "the delegate method being removed." DC-4 and the components-being-removed section were audited against the three prescription-feedback items in `adversarial-review.md` (empty-content check mechanism, `initialMode` parameter retention, `Markus_v3/Create/` directory deletion) and restated as behavioral observables with the implementation specifics demoted to non-normative notes. Requirements text did not need to change again in this pass; AC-1.3 was already revised in the prior Stage 1 pass.

---

Architecture stable — no requirements changes flagged.

The `/architecture` "open question" from `requirements.md` Notes for design step (where the content-driven initial-mode rule lives) is resolved in DC-4 above without changing any requirement text: it lives in `DocumentView.onAppear`'s existing initial-mode decision, exactly as the requirements suggested. The requirements bottom marker stays at "Requirements stable — no architectural feedback to incorporate."
