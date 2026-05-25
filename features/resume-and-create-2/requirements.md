# Requirements — Resume and Create

*Behavioral requirements for the "resume-and-create-2" feature. Combines Roadmap #2 (last-file resume on launch) and #5 (new file creation). Source of truth: `features/resume-and-create-2/declaration.md`. Each requirement (BR-n) is phrased as observable behavior so later stages can map tests to it.*

---

## User stories with acceptance criteria

### Story A — Resume on launch

> As a writer who returns to the same file across many short sessions, I want the app to reopen my last-edited file directly so I never have to re-navigate the document browser.

**BR-1 — Persist last-opened file.**
When a file is opened (from the document browser, via resume, or as a newly created file once it persists), the app records a durable reference to that file as the "last-opened file" such that it survives full app termination and relaunch.
*Observable:* After opening file X and terminating the app, a stored last-opened reference resolving to X exists.

**BR-2 — Resume on subsequent launch.**
On any launch where a last-opened reference exists and resolves to a still-reachable file, the app opens that file directly into the rendered view as the first interactive screen.
*Observable:* Launch with a valid stored reference to X → first interactive screen is the rendered view of X; the document browser is not the landing screen.

**BR-3 — No document-browser flash on resume.**
On a resuming launch, the document browser is not presented (even momentarily) before the rendered view appears.
*Observable:* During a resuming launch, the document browser view is never the visible top view controller before the rendered view of X.

**BR-4 — First-ever launch falls through to the browser.**
On a launch where no last-opened reference exists (first-ever launch, or after the reference has been cleared), the app presents the system document browser as the entry point.
*Observable:* Launch with no stored reference → first interactive screen is the document browser.

**BR-5 — Unreachable last file falls through to the browser, silently.**
On a launch where a last-opened reference exists but cannot be resolved to a reachable, readable file (stale/invalid bookmark, file deleted, moved beyond bookmark tracking, sync placeholder not downloadable, permission lost), the app falls through to the document browser with no error UI.
*Observable:* Launch with a stored reference that fails to resolve → first interactive screen is the document browser; no alert, banner, toast, or error text is shown attributing the fallback to a missing file.

**BR-6 — Resumed file behaves identically to a browser-opened file.**
A file reached via resume supports the same read/edit/save behaviors the walking skeleton provides for a browser-opened file (tap to enter raw mode, edit, save back to the original location).
*Observable:* After resume of X, editing and saving X produces the same on-disk result as if X had been opened from the browser.

---

### Story B — New file creation

> As a writer with no in-app way to start a new note, I want "Create Document" to drop me straight into typing in a new empty file located alongside my recent work.

**BR-7 — Create-Document affordance creates an `.md` file.**
Invoking the document browser's "Create Document" affordance produces a new file with an `.md` extension (not `.markdown`, not `.txt`).
*Observable:* After invoking Create Document, the resulting open document's filename ends in `.md`.

**BR-8 — Default name `Untitled.md`.**
When no name collision exists in the target directory, the new file is named exactly `Untitled.md`.
*Observable:* Create Document into an empty/collision-free directory → filename is `Untitled.md`.

**BR-9 — Deterministic collision auto-increment.**
When `Untitled.md` already exists in the target directory, the new file is named `Untitled 2.md`; if that also exists, `Untitled 3.md`; and so on, choosing the lowest available integer ≥ 2. Existing files are never overwritten.
*Observable:* With `Untitled.md` present → new file is `Untitled 2.md`. With `Untitled.md` and `Untitled 2.md` present → new file is `Untitled 3.md`. With `Untitled.md` and `Untitled 3.md` present (gap) → new file is `Untitled 2.md`. No pre-existing file's contents change.

**BR-10 — Target directory is the last-opened file's directory.**
When a last-opened file exists and its containing directory is reachable and writable, the new file is created in that same directory.
*Observable:* With last-opened file at directory D (writable) → new file's parent directory is D.

**BR-11 — Fallback to local Documents.**
When there is no last-opened file, or its containing directory is unreachable or not writable, the new file is created in Markus's local "On My iPhone" app Documents directory.
*Observable:* With no last-opened reference → new file's parent is the app's local Documents directory. With a last-opened file whose directory is non-writable → new file's parent is the app's local Documents directory.

**BR-12 — New file opens in the raw editor with the keyboard active.**
A newly created file opens directly into the raw text editor (not the rendered view) with the text input focused and the software keyboard presented.
*Observable:* After Create Document → top screen is the raw editor for the new file; the editor's text view is first responder; the keyboard is shown.

**BR-13 — Empty file is not persisted.**
A newly created file is not written to disk until the user enters at least one character. If the user closes/dismisses the new file without typing anything, no file is left on disk and no collision-incremented name is consumed.
*Observable:* Create Document then leave without typing → no new file exists in the target directory; a subsequent Create Document still yields `Untitled.md` (the name was not consumed).

**BR-14 — File persists once content is entered.**
Once the user types at least one character into a newly created file and the file is saved per the existing save flow, the file exists on disk at the resolved name and location with the typed content.
*Observable:* Create Document, type text, trigger save → file exists at target directory with the chosen `Untitled[ n].md` name containing the typed text.

**BR-15 — A persisted new file becomes the last-opened file.**
Once a newly created file persists to disk (per BR-14), it becomes the last-opened file for resume purposes (BR-1).
*Observable:* Create + type + save file Y, terminate, relaunch → app resumes into Y.

---

### Story C — Back navigation

> As a user editing or reading a file, I want a clear way back to the document browser at any time.

**BR-16 — Back chevron returns to the document browser.**
A standard navigation-bar back chevron in the top-left of the rendered and raw-editor views returns the user to the document browser when tapped.
*Observable:* From the rendered view of X, tapping the back chevron → top screen is the document browser. Same from the raw editor.

**BR-17 — Edge-swipe-back returns to the document browser.**
The standard screen-edge left-to-right swipe-back gesture (provided by the navigation controller) returns the user to the document browser from the rendered and raw-editor views.
*Observable:* From the rendered view of X, performing an edge swipe from the left screen edge → top screen is the document browser.

**BR-18 — Back navigation does not clear the last-opened reference.**
Returning to the document browser via back chevron or edge-swipe does not erase the last-opened reference; a subsequent relaunch still resumes the last-opened file.
*Observable:* Open X, tap back to the browser, terminate, relaunch → app resumes into X.

---

## Edge cases and failure modes

**BR-19 — Stale or invalid bookmark.**
If the stored reference is a security-scoped bookmark that is stale or fails to resolve, the app discards/ignores it for the current launch and falls through to the document browser (per BR-5) without crashing.
*Observable:* Launch with a corrupted/stale stored bookmark → document browser is shown; app does not crash.

**BR-20 — Last file unreachable but reference retained vs. cleared.**
A single failed resolution of the last-opened reference does not, by itself, require erasing the reference; behavior on the failing launch is the silent browser fallback (BR-5). [Whether the reference is permanently cleared or retained for a later retry is an implementation choice deferred to architecture — see end of file.]
*Observable:* Launch with an unreachable reference → document browser shown, no error UI (BR-5 holds regardless of the retention choice).

**BR-21 — Non-writable last-opened directory at create time.**
If the last-opened file's directory exists but is read-only (e.g. a read-only shared location, a permission-revoked bookmark), Create Document does not fail or surface a write error; it falls back to local Documents (BR-11).
*Observable:* Last-opened directory read-only → Create Document yields a file in local Documents, no write-error alert.

**BR-22 — Collision probing happens in the resolved target directory.**
The collision check and auto-increment (BR-9) are evaluated against the directory actually chosen by BR-10/BR-11, not a different directory.
*Observable:* When the create falls back to local Documents, the `Untitled[ n].md` name is computed from the files present in local Documents, not from the (unwritable/absent) last-opened directory.

**BR-23 — First-ever launch then create.**
On a first-ever launch (no last-opened file), the user lands in the document browser (BR-4); invoking Create Document there creates the file in local Documents (BR-11) and opens it in the raw editor (BR-12).
*Observable:* Fresh install → browser shown → Create Document → new `Untitled.md` in local Documents opens in raw editor with keyboard.

**BR-24 — Empty-file-not-persisted survives app interruption.**
If a newly created (not-yet-typed-into) file's session is dismissed by returning to the browser, backgrounding, or termination, no empty file is left on disk (consistent with BR-13).
*Observable:* Create Document, do not type, return to browser → no file on disk; the previously chosen name is still available for the next create.

**BR-25 — Back navigation from an untyped new file leaves no file.**
Tapping back or edge-swiping out of a newly created, untyped file returns to the document browser and leaves no file on disk (BR-13 + BR-16/BR-17).
*Observable:* Create Document, do not type, tap back → browser shown, no new file on disk.

**BR-26 — Resolved name remains collision-free at write time.**
The name chosen by BR-9 is the name written at persist time; if no concurrent external creation occurred, the persisted file uses exactly that name and overwrites nothing.
*Observable:* Create Document → name resolves to `Untitled 2.md` → type and save → exactly `Untitled 2.md` exists; pre-existing `Untitled.md` is unchanged.

---

## Out of scope

*Carried forward verbatim from the feature declaration's Out of scope, plus the project declaration's standing exclusions that bear on this feature.*

- **External-change detection, conflict resolution, deletion handling, follow-on-move** — all Roadmap item #3.
- **Scroll-anchor preservation across mode switches** — Roadmap item #4.
- **Swipe gestures beyond the standard edge-swipe-back** — the prototype's "swipe R→L on edit view to formatted view" and "swipe L→R on formatted view to edit view" belong to Roadmap item #6.
- **Handoff between devices** — `NSUserActivity` may be the chosen mechanism, but advertising the activity for cross-device continuation is not in scope here.
- **Multi-window / multi-scene state restoration on iPad** — single-scene only for now.
- **User-configurable last-file behavior** — no settings, no "always start at browser" toggle. Resume is the fixed behavior.
- **Any UI for the stale-bookmark case** — silent fallback only, no banner, no toast, no error.
- **Renaming, moving, or deleting files from within Markus** — file management lives in the document browser / Files app.
- **Templates or starter content for new files** — new means empty.
- **No library or vault; no app-managed copies** (project declaration) — beyond the single last-opened bookmark and the local-Documents fallback for new files, Markus introduces no indexing or relocation of the user's files.
- **No file types beyond `.md` and `.markdown`** (project declaration) — new files are created as `.md`; no `.txt`/`.rtf`/Word support.

---

## Architectural resolution needed

The two architecture-flagged questions below were resolved in `design.md` without requiring any change to the requirement text:

1. **Last-opened-reference retention policy (BR-20).** Resolved in design.md DC-5 as RETAIN-on-failure, REPLACE-on-success — a failed resolution does not clear the reference; it is only replaced when a different file is successfully opened.

2. **"Reachable and writable" determination for the create target (BR-10/BR-11/BR-21).** Resolved in design.md DC-12 as a pre-write probe (decide the directory at create time via a side-effect-free writability check), not attempt-and-fall-back.

**Requirements stable — no architectural feedback to incorporate.**
