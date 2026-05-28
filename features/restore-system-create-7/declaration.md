# Declaration: restore-system-create-7

*Corrective feature — reverts a design choice made in `resume-and-create-2`.*

## What

Remove Markus's custom new-file creation flow and let the system's `UIDocumentBrowserViewController` create affordance handle new files the way iOS does it everywhere else: a "+" tap creates an empty file in the **currently-browsed folder**, with the system's **inline rename UI** in the browser, before opening the file in the editor.

Concretely, this feature removes from `resume-and-create-2`:

- **C4 CreateDocumentHandler** — the directory-choosing, naming, and deferred-write logic layered on top of the create delegate. The delegate method itself may still need a minimal template-providing implementation for the system "+" affordance to function; the *intercepting* behavior — choosing the location, computing the name, withholding the write — is what goes.
- **C5 NameProbe** — the `Untitled[ n].md` collision-avoidance helper.
- **C6 CreateTargetResolver** — the last-directory-vs-fallback chooser and writability probe.
- **C7 LocalDocumentsFallback** — the app-container Documents fallback target.
- **Deferred-write behavior** (DC-9 in `resume-and-create-2`/design.md) — the "no on-disk trace until first keystroke" rule. With system create, the empty file exists on disk from frame zero, like every other iOS document app.

It keeps everything else from `resume-and-create-2`:

- **C0 BrowserHost** — the `UIDocumentBrowserViewController` scene host.
- **C1 LastFileStore** — last-opened security-scoped bookmark.
- **C2 LaunchResumeBranch** — resume-on-launch decision.
- **C3 DocumentOpenObserver** — record-on-open funnel; continues to fire for system-created files via the existing `DocumentView` lifecycle hook.
- **C8 BackToBrowser** — leading back affordance and edge-swipe pop.

## Why

The custom create path in `resume-and-create-2` was an error. It solved two problems Markus doesn't have:

1. **Auto-naming with collision avoidance.** iOS already provides this: the system browser creates a default-named file and immediately presents inline rename. Re-implementing `Untitled n.md` collision logic added code without adding behavior the user couldn't already get from the OS.
2. **Forcing the new file into the last-opened directory.** This deviates from every iOS document app the target user has used (Files, Pages, Apple Notes via Files). Users browsing folder X expect "+" to create in folder X — not in folder Y because that's where they last opened a file. The deviation has no payoff and breaks Files-app intuition, which the project declaration's "for whom" section names as a baseline expectation.

The **deferred-write behavior** was load-bearing only for the custom create path — its purpose was to keep an abandoned `Untitled.md` from leaving a stray file when the user backed out. With the system handling creation and the rename UI gating the open, the abandonment case becomes "user creates a file in the browser and immediately discards it via the standard browser gesture," which is the same observable behavior any other iOS document app has. No special handling needed.

Removing this reduces Markus's surface area: fewer components, fewer delegate overrides, fewer invariants to maintain. It also restores compliance with the declaration's principle that Markus is "a lens over the user's existing files" — the system browser, not Markus, decides where new files live.

## Success

After this feature ships:

1. Tapping "+" in the document browser uses the **system's** create affordance — Markus does not choose the create location or name. Any implementation of `documentBrowser(_:didRequestDocumentCreationWithHandler:)` is minimal (template-only), hands off to the system, and contains none of the logic that lived in C4/C5/C6/C7.
2. The new file lands in the **folder the user is currently browsing**, not in any app-resolved directory.
3. The user sees the **system's inline rename UI** in the browser before the editor opens; the file persists with whatever name the user enters (or the system default if they accept without renaming).
4. The new file exists on disk from creation — no deferred-write logic anywhere in the codebase.
5. Resume-on-launch, last-opened tracking, back-to-browser, and the edge-swipe pop all continue to work unchanged. A system-created file opened via the browser is recorded as the last-opened file by C3 the same way any browser-opened file is.
6. C4, C5, C6, C7, and any code referencing them are gone from the project. The build is green and the existing unit/UI test suite passes (with tests of the removed components also removed).

## Shape touched

From declaration.md's Shape:

- **Document browser entry** — restoring the system's create affordance is the central change.
- **File access layer** — removal of the writability probe, the local-Documents fallback target resolution, and the deferred-write seam.
- **Conflict & lifecycle UI** — removal of the new-file-specific lifecycle around deferred persistence; the "abandoned create" case dissolves into standard browser behavior.

No changes to: Document model, Rendered view, Raw editor, Mode switcher.

## Out of scope

- **Any change to resume-on-launch (C2) or last-opened tracking (C1/C3).** Resume continues to work exactly as it does today.
- **Any change to the editor surfaces themselves.** RenderedView, RawEditorView, MarkdownEditorTextView, scroll-anchor, autosave — untouched.
- **Renaming an *existing* file from inside Markus.** The system browser's rename is what the user sees at create time; mid-edit rename of an already-saved file is a separate concern and not part of this feature.
- **Any new UI for picking a target folder.** The browser's current folder *is* the target — no picker, no recents list, no app-built directory chooser.
- **Updating declaration.md's Roadmap.** The Roadmap line for "New file creation" is now stale and should be removed or rewritten, but that edit is a separate `/declaration` pass — not part of this feature's commit.
- **Migration of files created under the old flow.** Any `Untitled n.md` files that landed in the last-opened directory under `resume-and-create-2` stay where they are; the user owns those files now.
