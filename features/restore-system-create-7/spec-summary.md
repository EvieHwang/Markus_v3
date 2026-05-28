# Spec summary — restore-system-create-7

## Feature

Markus's new-file creation flow was custom-built in `resume-and-create-2`: it intercepted the system's "+" affordance to force new files into the last-opened folder, applied app-side `Untitled n.md` naming, and deferred the on-disk write until the user typed a first character. That choice was an error — it ignored the iOS-standard behavior (new files land in the folder the user is currently browsing, with the system's inline rename UI), and added a deferred-write state machine that only existed to mask the deviation. **This feature reverts that choice.** New files now flow through the system's `UIDocumentBrowserViewController` create affordance the way Files.app, Pages, and Apple Notes (via Files) handle it — Markus supplies a minimal template and lets the system place, name, and persist the file. Resume-on-launch, last-opened tracking, and back-to-browser navigation are untouched.

## What it does

After this feature ships, the user sees the iOS-standard create flow inside Markus:

- Tapping "+" in the document browser creates the new `.md` file in the **folder the user is currently browsing** — not in any app-chosen location.
- The system's **inline rename UI** appears immediately, with the keyboard focused on the filename. The user can rename or accept the system default.
- The new file **exists on disk from creation**, like every other iOS document app — no "phantom file that becomes real on first keystroke."
- Once the user finishes naming, the editor opens the file. **Empty files open straight into the raw editor with the keyboard up** so the user can start typing immediately; non-empty files open in rendered mode as before.
- Everything else continues to work: launching the app re-opens the last-opened file directly, back-to-browser still works, edge-swipe pop still works, and a system-created file is tracked as the new last-opened just like any browser-opened file.

What disappears from the user's experience: the app-imposed "Untitled.md / Untitled 2.md / Untitled 3.md" naming, the silent override of the create location, and any edge cases tied to deferred-write (e.g., a file that appears in the file system "out of nowhere" after the first keystroke).

## Risks carried

No risks acknowledged. The one adversarial finding raised during spec (F-001 — the spec's original premise that omitting the create delegate would yield the iOS-default flow was factually wrong; the delegate must be implemented minimally) was **resolved** by reframing the contract behaviorally before the DAG locked. No findings were deferred or acknowledged into `constitution.md`.

## Out of scope

- Any change to resume-on-launch, last-opened tracking, back-to-browser, or the editor surfaces themselves (RenderedView, RawEditorView, scroll-anchor, autosave).
- Mid-edit rename of an already-saved file. Rename happens via the system browser at create time; there is no in-editor rename surface in this feature.
- Any new Markus-built UI for picking a target folder or naming a new file.
- Migration of `Untitled n.md` files created under the old flow. They stay where they are; the user owns those files.
- Cleanup of declaration.md's Roadmap (#5 is now stale but its rewrite is a separate `/declaration` pass).
- Promoting the "prefer the Apple way" tiebreaker into `constitution.md`'s Patterns section (worth doing, but separate).

## Build preview

**6 tasks across 3 waves.**

- **Wave 1** — three independent component deletions (`NameProbe`, `CreateTargetResolver`, `LocalDocumentsFallback`), fully parallel.
- **Wave 2** — two parallel rewrites: reduce `CreateDocumentHandler` to a template-only delegate body (and strip deferred-write from `BrowserHostController` / `MarkdownDocumentSaveBridge`), and add the content-based initial-mode rule to `DocumentView`.
- **Wave 3** — single closing sweep: confirm `Markus_v3/Create/` is gone, remove obsolete UI test assertions, mirror new spec UI tests into the Xcode test target, run the full suite green.

The DAG fits comfortably in a single build session. The largest task (T-004, the template-only rewrite) touches four source files but each delta is small and self-contained — it's the load-bearing task, but not an oversized one. No new dependency, framework, or deploy path is introduced.

## Next step

Start a new session and run `/build feature-name: restore-system-create-7`.
