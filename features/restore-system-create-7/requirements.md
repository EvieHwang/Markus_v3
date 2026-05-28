# Requirements: restore-system-create-7

*Corrective feature. Removes custom new-file creation from `resume-and-create-2` and restores the system `UIDocumentBrowserViewController` create affordance. See `declaration.md` for intent.*

## User stories

### US-1 — New file is created where the user is browsing

**As** a Markus user who has navigated to a folder in the document browser
**I want** tapping "+" to create the new file in that folder
**so that** new files land where I expect them, matching every other iOS document app.

**Acceptance criteria**

- **AC-1.1** Tapping the system "+" affordance in the browser results in a new `.md` file appearing in the **folder currently shown by the browser**, and nowhere else. *(Traces: declaration Success #2.)*
- **AC-1.2** The new file's parent directory is **not** computed from the last-opened file's location. If the user is browsing folder X while their last-opened file lives in folder Y, the new file is in X. *(Traces: declaration Why #2.)*
- **AC-1.3** Markus does not compute the target directory, does not compute the file name, and does not withhold the on-disk write. Any implementation of `documentBrowser(_:didRequestDocumentCreationWithHandler:)` is template-only: it provides an empty `.md` template URL (e.g., in `NSTemporaryDirectory()`) and immediately completes the system handler, letting the system copy/place/rename in the browsed folder. No `CreateTargetResolver`-style directory selection and no `NameProbe`-style collision logic is present. *(Traces: declaration Success #1. Addresses adversarial F-001.)*

### US-2 — Naming uses the system's inline rename UI

**As** a Markus user creating a new file
**I want** to name the file using iOS's standard inline rename in the browser
**so that** my naming experience matches Files.app and every other iOS document app.

**Acceptance criteria**

- **AC-2.1** Immediately after the file is created, the system browser presents its **inline rename UI** with the keyboard focused on the filename. *(Traces: declaration Success #3.)*
- **AC-2.2** If the user enters a name and confirms, the file persists with that name (plus the `.md` extension preserved by the system). The editor then opens that file. *(Traces: declaration Success #3.)*
- **AC-2.3** If the user accepts the system default (no edit), the file persists with whatever default the system supplies and the editor opens it. Markus does not impose its own `Untitled n.md` naming. *(Traces: declaration Success #3, Why #1.)*
- **AC-2.4** Markus does not present any custom name-entry sheet, modal, or text field during the create flow. *(Traces: declaration Out of scope, "Any new UI for picking a target folder" — and by extension, no custom naming UI either.)*

### US-3 — New files exist on disk from creation

**As** the maintainer of Markus
**I want** new files to materialize on disk at creation time, like every other iOS document app
**so that** there is no deferred-write state machine to maintain.

**Acceptance criteria**

- **AC-3.1** After "+" creation completes (system rename UI dismissed with confirm), the file exists on disk in the browsed directory with non-deferred content (empty body is fine). *(Traces: declaration Success #4.)*
- **AC-3.2** There is no code path in Markus that holds a "new document" in memory while withholding its on-disk persistence. The `DC-9`-style deferred-write rule from `resume-and-create-2` is gone. *(Traces: declaration Success #4.)*
- **AC-3.3** Abandoning a create from the system rename UI (e.g., dismiss/cancel) results in whatever observable state the system browser produces — Markus does not add custom cleanup. The user manages any unwanted file via the standard browser delete gesture. *(Traces: declaration Out of scope, "Migration / cleanup of stray files."; declaration Why on Apple-way default.)*

### US-4 — Newly created files open in edit-ready mode

**As** a Markus user who just created and named a new file
**I want** the file to open ready to type
**so that** I am not forced to tap into raw mode before writing my first line.

**Acceptance criteria**

- **AC-4.1** When a file with **empty content** is opened (whether just created or pre-existing), `DocumentView` selects **raw mode** as the initial mode and presents the software keyboard with the raw editor as first responder. *(Traces: declaration Why — "prefer the Apple way," matching Notes/Pages new-doc behavior. Replaces the path-based DC-8 from `resume-and-create-2` with a content-based rule.)*
- **AC-4.2** The initial-mode decision is driven by the document's content (empty → raw; large → raw; otherwise → rendered), not by how the file was reached. There is no "is this a fresh creation?" signal threaded through the open path. *(Traces: declaration Why — reducing state.)*
- **AC-4.3** A file with non-empty content opened via the browser continues to open in **rendered** mode (existing behavior preserved). *(Regression guard for `walking-skeleton-1` behavior.)*

### US-5 — Resume-on-launch and last-opened tracking are unaffected

**As** a Markus user who has used the app before
**I want** the resume-on-launch and last-opened behaviors to keep working
**so that** removing the create flow does not regress unrelated behavior.

**Acceptance criteria**

- **AC-5.1** Launching the app with a valid last-opened bookmark continues to open that file directly, skipping the browser frame (existing C2 behavior). *(Regression guard for `resume-and-create-2`.)*
- **AC-5.2** A file created via the new system-create path is **recorded as the last-opened file** through C3's existing `DocumentView` lifecycle hook, with no special-case code for "this came from a create." On next launch, that file is the resume target. *(Traces: declaration Success #5.)*
- **AC-5.3** The back-to-browser leading affordance (C8) and edge-swipe pop continue to work from a system-created file's editor the same way they do from any browser-opened file. *(Regression guard for C8.)*
- **AC-5.4** No call site in Markus invokes any of: `CreateDocumentHandler`, `NameProbe`, `CreateTargetResolver`, `LocalDocumentsFallback`. The types themselves are removed from the codebase. *(Traces: declaration Success #6.)*

### US-6 — Test suite reflects the removal

**As** the maintainer of Markus
**I want** the test suite to no longer assert behaviors that have been removed
**so that** green tests reflect the actual product.

**Acceptance criteria**

- **AC-6.1** Unit tests covering `NameProbe`, `CreateTargetResolver`, `LocalDocumentsFallback`, the deferred-write seam, and the writability probe are removed. *(Traces: declaration Success #6.)*
- **AC-6.2** UI tests that asserted "+" routes through the custom handler are either removed or rewritten to assert the system-create path's observable outcome (file appears in current browser folder + rename UI shown). *(Traces: declaration Success #6.)*
- **AC-6.3** The full Xcode test suite passes after the removal (`xcodebuild test -scheme Markus_v3 -destination 'platform=iOS Simulator,name=iPhone 17'`). *(Traces: constitution Quality gates — "All tests pass.")*

## Edge cases and failure modes

- **EC-1 — Read-only / unwritable current folder.** The user navigates the browser into a folder where iOS cannot write (e.g. a non-writable provider location) and taps "+". *Behavior:* whatever the system `UIDocumentBrowserViewController` produces — Markus does not intercept. We do not pre-probe writability and do not present a custom error. *(Traces: declaration "prefer the Apple way.")*
- **EC-2 — Naming collision with an existing file.** The user attempts to rename their new file to a name already present in the folder. *Behavior:* the system handles the collision (typically appends a digit or rejects). Markus does not interpose. *(Traces: declaration Why #1.)*
- **EC-3 — User cancels rename.** The user dismisses the rename UI without confirming. *Behavior:* the file may or may not be retained depending on system behavior; Markus does not add cleanup logic. The user can delete via the browser. *(Traces: AC-3.3.)*
- **EC-4 — Last-opened file lives in the same folder being browsed.** The user is browsing folder X and their last-opened file is also in X. *Behavior:* indistinguishable from "browsing X with last-opened elsewhere" — the new file lands in X (the browser's current folder), C3 records it as the new last-opened. *(Traces: AC-5.2.)*
- **EC-5 — Creating a file immediately after resume-on-launch.** The user launches into resume (skipping the browser), then taps the back affordance to reach the browser, then taps "+". *Behavior:* the browser shows whatever folder it shows on first appearance from the dismissed editor (per `UIDocumentBrowserViewController` defaults). The new file lands there. Markus does not force any particular folder. *(Traces: declaration "prefer the Apple way.")*
- **EC-6 — Empty existing file opened from the browser.** A pre-existing zero-byte `.md` file is opened. *Behavior:* opens in raw mode with keyboard up (per AC-4.1). This is a behavior change vs. earlier features — surfaced explicitly because it follows from the content-driven initial-mode rule. *(Traces: AC-4.1, AC-4.2.)*
- **EC-7 — Existing tests that assumed deferred-write semantics.** Tests in `resume-and-create-2/tests/` that assert "no on-disk file until first keystroke" will fail after this change. *Behavior:* those tests are removed as part of AC-6.1; they assert removed behavior. *(Traces: AC-6.1.)*
- **EC-8 — Files created by the old flow already on disk.** Users upgrading the app may have `Untitled n.md` files created under the old flow in their last-opened directories. *Behavior:* unchanged. They remain where they are. Migration is the user's responsibility per declaration Out of scope. *(Traces: declaration Out of scope, "Migration of files created under the old flow.")*

## Out of scope

Mirrors `declaration.md`:

- Any change to resume-on-launch (C2), last-opened tracking (C1/C3), back-to-browser (C8), or the editor surfaces (RenderedView, RawEditorView, MarkdownEditorTextView, scroll-anchor, autosave).
- Mid-edit rename of an already-saved file. Rename happens in the system browser at create time; there is no mid-edit rename surface.
- Any new Markus-built UI for picking a target folder or naming a new file.
- Migration of `Untitled n.md` files created under the old flow.
- Editing `declaration.md`'s Roadmap (#5 is now stale but its cleanup is a separate `/declaration` pass).
- Adding the "prefer the Apple way" principle to `constitution.md` (worth doing, but separate).

## Standards-creep check

- **Accessibility (WCAG 2.1 AA / HIG):** the system browser's create + rename UI is Apple-provided and inherits VoiceOver / Dynamic Type / contrast support by default. Removing the custom create path **improves** accessibility surface area passively — no new criteria are added here. The forthcoming Roadmap #7 accessibility pass remains the right venue for editor-side accessibility work.
- **HIG:** restoring the system create affordance is itself an HIG conformance fix; no additional criteria needed.
- **Security / OWASP:** not applicable to this feature.
- **API contracts / OpenAPI:** not applicable (no API surface).

No cross-cutting standards are silently absorbing weight into this feature.

## Notes for design step

When `/architecture` runs, the open question to resolve is **where the content-driven initial-mode rule (AC-4.1, AC-4.2) lives**. It belongs in `DocumentView`'s existing initial-mode decision (the same `.onAppear` seam that handles the large-file case today). No new component is introduced. Surface any tension if design disagrees.

## Revision notes

- **2026-05-28 — Addresses adversarial F-001 (HIGH, integrity/feasibility).** AC-1.3 was reframed from a call-shape contract ("no code path calls `documentBrowser(_:didRequestDocumentCreationWithHandler:)` to override the system's location choice") to a behavioral one. The original framing rested on a mental model where omitting the delegate entirely yields the iOS-default create flow; in fact `UIDocumentBrowserViewController` requires the delegate to be implemented and to supply a template URL for "+" to function. The revised AC keeps the load-bearing observables (Markus does not choose the directory, the name, or defer the write) while permitting a minimal template-only implementation that hands off to the system. AC-1.1, AC-1.2, AC-2.*, AC-3.*, and AC-6.* were reviewed for ripple effects; all were already framed behaviorally (file lands in browsed folder; system rename UI; no custom naming UI; file exists on disk post-create; removed components are gone from tests) and required no edits. The feature declaration was updated in the same pass to soften Success #1 and the C4 removal bullet so they no longer assert "delegate fully un-implemented."

---

Requirements stable — design.md exists and is consistent with the revised AC-1.3 after F-001's recommended reframing; the design's DC-1 will be updated by the architecture revision pass following this one.
