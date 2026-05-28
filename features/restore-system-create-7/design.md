# Design — Restore System Create

*Architecture for `restore-system-create-7`. Source of truth for intent: `features/restore-system-create-7/declaration.md`; behavior: `features/restore-system-create-7/requirements.md`. Every constraint below (DC-n) is phrased as an observable property of the running system, not a call signature — with the one named exception called out explicitly (DC-1, the un-overridden delegate seam).*

This is a **corrective removal feature**. It deletes the custom new-file creation path added in `resume-and-create-2` and lets `UIDocumentBrowserViewController` handle creation the way iOS handles it everywhere else. Resume-on-launch, last-opened tracking, and back-to-browser are preserved unchanged. The only behavioral seam being *added* is a content-based initial-mode rule inside `DocumentView`'s existing `.onAppear` decision.

---

## What this design is, structurally

Three moves:

1. **Remove four components** that exist only to override the system create flow (C4–C7 from `resume-and-create-2/design.md`) plus the deferred-write behavior (the old DC-9).
2. **Stop overriding one UIKit delegate seam** (`documentBrowser(_:didRequestDocumentCreationWithHandler:)`) so the system's default create path runs end-to-end. This is the one place a call-shape contract is load-bearing; the requirement *is* "do not override this method," not a behavioral surrogate.
3. **Add one behavioral rule** — content-based initial-mode selection in `DocumentView` — replacing the old "is this a fresh creation?" signal that the create path used to thread through `initialMode`.

No new components are introduced. No components are renamed. The remaining components (C0, C1, C2, C3, C8) keep their responsibilities and observable contracts from `resume-and-create-2/design.md`.

---

## Components being removed

Each is named with the file(s) where it currently lives, confirmed by grep against the codebase.

- **C4 CreateDocumentHandler** — `Markus_v3/Create/CreateDocumentHandler.swift`, plus its wiring in `Markus_v3/Host/SceneDelegate.swift` (the `createHandler` property and its construction at scene connect) and the `documentBrowser(_:didRequestDocumentCreationWithHandler:)` override in `Markus_v3/Host/BrowserHostController.swift`. Tests: any `CreateDocumentHandler*Tests` (none present today by that name; the behavior is covered indirectly by `ResumeAndCreateUITests` and `Markus_v3Tests/MarkdownDocumentSaveBridgeTests` where it asserts deferred-write semantics).
- **C5 NameProbe** — `Markus_v3/Create/NameProbe.swift` and `Markus_v3Tests/NameProbeTests.swift`.
- **C6 CreateTargetResolver** — `Markus_v3/Create/CreateTargetResolver.swift` and `Markus_v3Tests/CreateTargetResolverTests.swift`. This includes the writability probe logic that satisfied the old DC-12.
- **C7 LocalDocumentsFallback** — `Markus_v3/Create/LocalDocumentsFallback.swift` and `Markus_v3Tests/LocalDocumentsFallbackTests.swift`.
- **Deferred-write behavior (old DC-9)** — the in-memory-until-first-keystroke state held in `BrowserHostController` (the "for deferred-write create, the file becoming real on disk for the first time…" branch around line ~200) and any deferred-write path in `MarkdownDocument`/`MarkdownDocumentSaveBridge`. After this feature, new files exist on disk from the moment the system browser's create completes; there is no "is this document materialized yet?" state to track anywhere.
- **The `initialMode` threading from create → DocumentView** — `DocumentView.init(initialMode:)` is currently used by the create path to force `.raw` on a freshly-created file. The parameter itself can stay if it is still used by other call sites, but the *create path* no longer supplies it; if no remaining call site supplies a non-nil value after C4 is gone, the parameter is removed. Either way, the initial-mode choice for a freshly-created file now flows through DC-4 below, not through a threaded "fresh creation" flag.

Once these are gone, the `Markus_v3/Create/` directory should be empty and can be removed.

---

## Component being kept (no behavioral change)

These keep their `resume-and-create-2/design.md` contracts verbatim. They are listed here only to make explicit that this feature does not touch them.

- **C0 BrowserHost** — `Markus_v3/Host/BrowserHostController.swift`. Continues to host the `UIDocumentBrowserViewController` and present `DocumentView` (via `UIHostingController`) on document open. Loses its create-delegate override (see DC-1); everything else — the open-document delegate path, the resume entry point, the presentation of the editor — is unchanged.
- **C1 LastFileStore** — security-scoped bookmark persistence. Unchanged.
- **C2 LaunchResumeBranch** — `Markus_v3/Resume/LaunchResumeBranch.swift`. Resume-on-launch decision; unchanged. The old `resume-and-create-2` DC-1 through DC-5 (durable reference, lands in rendered view, zero browser frames on resume, silent failure, retain-on-failure) all remain in force.
- **C3 DocumentOpenObserver** — record-on-open funnel attached to `DocumentView`'s lifecycle. Unchanged. A system-created file enters this funnel via the same `DocumentView` activation path as any browser-opened file; no special "this came from a create" branch is needed. This is the load-bearing reason AC-5.2 holds with zero new code.
- **C8 BackToBrowser** — leading back affordance and edge-swipe pop on both modes. Unchanged.

---

## The one new behavioral seam: content-based initial mode

`DocumentView` already chooses an initial mode in its `.onAppear` block (currently: large file → `.raw`, otherwise `.rendered`, with an optional `initialMode` override). This feature widens that decision to include the empty-content case.

This is *not* a new component. It is an extension of the existing initial-mode decision in `DocumentView.swift`. After this change, the threaded `initialMode` parameter is no longer the mechanism by which a freshly-created file lands in raw mode — the document's *content* is.

---

## Behavioral contracts (design constraints)

### Removal contracts

**DC-1 — The system create delegate is un-overridden.** *(Named-mechanism exception — the call shape is itself the contract.)* `BrowserHostController` (and any other `UIDocumentBrowserViewControllerDelegate` in the project) does not implement `documentBrowser(_:didRequestDocumentCreationWithHandler:)`. With no override present, `UIDocumentBrowserViewController` runs its default create affordance: a new file is materialized in the currently-browsed folder, the system's inline rename UI is presented, and on confirm the file is opened through the normal open-document delegate path. *Rationale for naming the call shape:* the requirement (AC-1.3) is specifically that this method is not overridden. There is no behavioral surrogate — any other framing ("Markus does not choose the create location") is satisfied trivially by an unrelated override that happens to forward to the system. Naming the method by name is the only way to make the contract checkable. *(AC-1.1, AC-1.2, AC-1.3, AC-2.1, AC-2.2, AC-2.3, AC-2.4.)*
*Reuses pattern: `UIDocumentBrowserViewController` default create affordance (project declaration "Document browser entry").*

**DC-2 — No code path defers a new file's on-disk persistence.** A document held by the app is either backed by a real on-disk file or it is not a document the app is editing. There is no in-memory "new but not yet written" state anywhere — no flag, no holding URL, no first-keystroke trigger that materializes a file. After the system create completes, the file exists on disk; from that moment forward it is treated identically to any other browser-opened file. *(AC-3.1, AC-3.2.)*

**DC-3 — No code path observes or reacts to an abandoned create.** If the user dismisses the system rename UI without confirming, Markus runs no cleanup, no logging, no banner, no recovery branch. The observable state is whatever `UIDocumentBrowserViewController` produces; the user manages any resulting file via the standard browser delete gesture. There is no Markus-owned signal that "a create was abandoned" — that concept does not exist in the post-feature codebase. *(AC-3.3, EC-3.)*

### New behavioral seam

**DC-4 — Initial mode is a pure function of document content.** When `DocumentView` becomes active for a file, it selects its initial mode from the document's content alone:
- **Empty content (zero bytes of text):** `.raw`, with the raw editor's text input as first responder and the software keyboard presented.
- **Large content (at or above the existing large-file threshold, currently 500 KB):** `.raw`. *(Existing behavior, preserved.)*
- **Otherwise:** `.rendered`. *(Existing behavior, preserved.)*

The decision uses no signal about how the file was reached — not the URL, not a "fresh creation" flag, not the presence of an `initialMode` parameter supplied by the caller. A pre-existing zero-byte `.md` opened from the browser and a just-system-created zero-byte `.md` are indistinguishable at this seam and produce the same result: raw mode, keyboard up. *(AC-4.1, AC-4.2, AC-4.3, EC-6.)*

### Preserved contracts (restated for traceability)

**DC-5 — Resume-on-launch is unchanged.** All of `resume-and-create-2/design.md` DC-1 through DC-5 remain in force. A valid stored bookmark resumes directly into the rendered view with no browser frame; an unresolvable bookmark falls back silently to the browser; the reference is retained across resolution failures. *(AC-5.1.)*

**DC-6 — Last-opened tracking funnels system-created files through C3 unchanged.** C3 records every `DocumentView` activation for a non-nil `fileURL`. A system-created file opens via the same open-document delegate path as any browser-opened file, so it enters this funnel with no special-case code. On next launch it is the resume target. *(AC-5.2.)*

**DC-7 — Back navigation is unchanged.** C8's leading back chevron and the standard edge-swipe-pop both return to the browser from a system-created file's editor exactly as they do from any other browser-opened file. *(AC-5.3.)*

---

## Seam relationships

- **C0 (BrowserHost) ↔ `UIDocumentBrowserViewController` create affordance.** No delegate override (DC-1). The system runs its default flow: file appears in the currently-browsed folder, inline rename UI is shown, on confirm the file is opened through C0's existing open-document delegate path (the same path used for any user-tapped file in the browser). The open-document path is unchanged from `resume-and-create-2`.

- **C3 (DocumentOpenObserver) ↔ `DocumentView` lifecycle.** Unchanged. Reads the already-present `fileURL` when `DocumentView` activates and forwards it to C1. The fact that the file came from a system create is invisible at this seam, which is exactly what AC-5.2 requires.

- **DC-4 (initial mode) ↔ `DocumentView.onAppear`.** Attaches to the same `.onAppear` block in `Markus_v3/Views/DocumentView.swift` that today chooses `.raw` for large files. The block is widened to also choose `.raw` for empty documents. No new view, no new state object, no new callback — the rule lives where the existing rule already lives. The `initialMode` parameter on `DocumentView.init` may remain as latitude for other call sites, but the create path no longer drives it; if no remaining call site supplies a non-nil value after C4 removal, the parameter is dropped. *Implementation latitude: whether "empty" is checked via `document.text.isEmpty` or `document.initialByteSize == 0` (or both, with a tiebreak) is a build choice; the behavioral constraint is that a zero-content document opens in raw mode with the keyboard up regardless of how it was reached.*

- **Removed seams (no relationships to draw).** C4/C5/C6/C7 and the deferred-write branch in `BrowserHostController` cease to exist. There is no replacement seam — the system handles the role.

---

## HIG alignment

- Restoring the system create affordance is itself the HIG-canonical move: `UIDocumentBrowserViewController`'s default create + inline rename is what Files.app, Pages, and every Apple document-based app uses. The previous feature's custom create flow was the HIG deviation; this feature reverses it.
- The empty-document → raw-mode + keyboard rule matches Apple Notes / Pages new-document behavior: a brand-new document opens ready to type, not in a read-only preview.
- No alerts, banners, or custom UI are added or removed-with-replacement. Removal is silent.

---

## Build-time considerations (not requirements changes)

- **Tests are removed, not rewritten in place.** Per AC-6.1, the unit tests for the removed components (`NameProbeTests`, `CreateTargetResolverTests`, `LocalDocumentsFallbackTests`, plus any deferred-write assertions in `MarkdownDocumentSaveBridgeTests` and the create-flow assertions in `Markus_v3UITests/ResumeAndCreateUITests`) are deleted as part of the same change that removes the production code. The DAG should pair each removal with its test removal in a single task so the suite is never broken between tasks.
- **`Markus_v3/Create/` becomes empty.** After the four removals it should be deleted along with the Xcode group reference, not left as an empty folder.
- **`SceneDelegate.createHandler` and its construction at scene connect** are removed; the host's delegate set no longer includes a create handler. `BrowserHostController` keeps its open-document delegate role.
- **No migration logic.** Per declaration Out of scope and EC-8, any `Untitled n.md` files left in user directories by the old flow stay where they are. The build adds no detection or cleanup of these.

---

Architecture stable — no requirements changes flagged.

The `/architecture` "open question" from `requirements.md` Notes for design step (where the content-driven initial-mode rule lives) is resolved in DC-4 above without changing any requirement text: it lives in `DocumentView.onAppear`'s existing initial-mode decision, exactly as the requirements suggested. The requirements bottom marker stays at "Requirements stable — no architectural feedback to incorporate."
