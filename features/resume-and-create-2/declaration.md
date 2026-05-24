# Feature Declaration — Resume and Create

*Combines Roadmap items #2 (Last-file resume on launch) and #5 (New file creation). Paired here because both live at the edges of the file lifecycle, both touch the File access layer and Document browser entry, and #5 depends on the last-file bookmark that #2 introduces.*

## What

Two related capabilities at the edges of the open-file flow:

1. **Resume on launch.** On every launch after the first, Markus skips the document browser and opens the user's last-opened file directly into the rendered view. First-ever launch (and any launch where the last file can no longer be reached) falls through silently to the document browser.

2. **New file creation.** The existing "Create Document" affordance in the document browser creates an empty `.md` file named `Untitled.md` (auto-incremented to `Untitled 2.md`, `Untitled 3.md`, … on collision) in the directory of the last-opened file. If there is no last-opened file, or that directory is not writable, the new file is created in Markus's local "On My iPhone" Documents folder instead. The new file opens directly into the raw editor with the keyboard active. The file is not written to disk until the user types — empty files do not persist.

A back affordance — the standard navigation-bar back chevron in the top-left of the editing/rendered views — returns the user to the document browser at any time. The screen-edge left-to-right swipe-back gesture comes with the standard navigation controller and is therefore in scope as a free consequence; other prototype swipe gestures are deferred to Roadmap item #6.

## Why

The walking skeleton proved the end-to-end open → render → edit → save loop works, but every session still starts at the document browser, and there is no in-app way to create a new file at all. For the target user — a writer who returns to the same file across many short sessions on iPhone — re-navigating the document browser on every launch is the dominant friction. Resume-on-launch eliminates it. New-file creation closes the other obvious gap: the walking skeleton can only edit files that already exist somewhere the user put them.

Both behaviors align with the project declaration's commitment to "the shortest possible path from launch app to editing my file, with no accounts, no onboarding, no library, and no settings to configure." Neither introduces app-managed copies, a vault, or any persistent state beyond a single bookmark to the last-opened file.

Both behaviors also follow Apple's Human Interface Guidelines for document-based apps: state restoration via `NSUserActivity` is the HIG-canonical mechanism for "reopen the last document," and `UIDocumentBrowserViewController`'s creation handler is the canonical hook for new-document flow.

## Success

- A user who opens a file, closes the app, and relaunches lands directly in that file's rendered view — no document browser flash, no intermediate UI.
- A user on first-ever launch (or after the last file becomes unreachable) sees the document browser as the entry point, with no error UI explaining why.
- A user can tap "Create Document" in the document browser and immediately begin typing into a new, empty file in the directory of their last-opened file (or in local Documents if there is no last directory).
- A user who creates a new file and closes it without typing leaves no file on disk.
- A user can tap the back chevron (or perform the standard edge-swipe-back) from any open file to return to the document browser.
- `Untitled.md` name collisions resolve deterministically to `Untitled 2.md`, `Untitled 3.md`, … without overwriting existing files.

## Shape touched

From declaration.md's Shape:

- **Document browser entry** — the launch-time branch (resume vs. browser) and the create-document handler.
- **File access layer** — security-scoped bookmark persistence and resolution, last-opened-directory lookup, name-collision probing, write of the new file, fallback to local Documents.
- **Rendered view** *(lightly)* — the back chevron in the nav bar; the resumed-file path renders the same view the walking skeleton already produces.
- **Raw editor** *(lightly)* — opening a new empty file directly in raw mode with the keyboard active.

Not touched: Document model (no change to the in-memory representation), Mode switcher (no change to the rendered ↔ raw transition itself), Conflict & lifecycle UI (the conflict sheet and deletion banner belong to Roadmap item #3).

## Out of scope

- **External-change detection, conflict resolution, deletion handling, follow-on-move** — all Roadmap item #3.
- **Scroll-anchor preservation across mode switches** — Roadmap item #4.
- **Swipe gestures beyond the standard edge-swipe-back** — the prototype's "swipe R→L on edit view to formatted view" and "swipe L→R on formatted view to edit view" belong to Roadmap item #6.
- **Handoff between devices** — although `NSUserActivity` is the chosen mechanism and Handoff is a natural extension, advertising the activity for cross-device continuation is not in scope here.
- **Multi-window / multi-scene state restoration on iPad** — single-scene only for now.
- **User-configurable last-file behavior** — no settings, no "always start at browser" toggle. Resume is the fixed behavior.
- **Any UI for the stale-bookmark case** — silent fallback only, no banner, no toast, no error.
- **Renaming, moving, or deleting files from within Markus** — file management lives in the document browser / Files app.
- **Templates or starter content for new files** — new means empty.
