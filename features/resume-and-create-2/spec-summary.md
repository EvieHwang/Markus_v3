# Spec summary — resume-and-create-2

## Feature

Markus opens markdown files where the user already keeps them, but today every session starts at the system document browser and there is no way to create a new file in the app at all. This feature adds the two behaviors that live at the edges of the open-file flow: **resume on launch** (relaunching the app reopens the last file directly, skipping the browser) and **new file creation** (the browser's "Create Document" affordance makes an empty `Untitled.md` in the right place and opens it ready to type). Both keep the project's promise of the shortest path from launch to editing — no accounts, no library, no settings, and no app-managed copies.

## What it does

- **Resume on launch.** After the first launch, opening Markus takes the user straight back into the last file they had open, rendered, with no flash of the document browser. The very first launch — and any launch where the last file can no longer be reached (deleted, moved off a sync service, etc.) — quietly shows the document browser instead, with no error message.
- **New file creation.** "Create Document" makes an empty file named `Untitled.md`, auto-incrementing to `Untitled 2.md`, `Untitled 3.md`, … if those names are taken, never overwriting an existing file. The file is placed in the same folder as the last-opened file; if there is no last folder or it isn't writable, it goes to Markus's local "On My iPhone" Documents folder. The new file opens straight into the editor with the keyboard up. Nothing is written to disk until the user types the first character — abandon a blank new file and it leaves no trace.
- **Back navigation.** A standard back chevron (and the system edge-swipe-back) returns the user to the document browser from any open file.

## Risks carried

No risks acknowledged. One LOW finding (F-004) remains open and non-blocking: the last-file reference is stored as a security-scoped bookmark in unencrypted `UserDefaults`, a minor path-disclosure surface on a compromised device or backup. It was not acknowledged or deferred as a formal risk; it can be revisited if the project's security posture tightens.

## Out of scope

- External-change detection, conflict resolution, deletion handling, follow-on-move (Roadmap #3).
- Scroll-anchor preservation across mode switches (Roadmap #4, already built separately).
- Swipe gestures beyond the standard edge-swipe-back (Roadmap #6).
- Cross-device Handoff via `NSUserActivity`, multi-window/iPad scene restoration.
- Any user-configurable resume behavior or settings; any UI for the stale-bookmark case (silent fallback only).
- Renaming, moving, or deleting files from within Markus; templates or starter content for new files.

## Build preview

**8 tasks across 4 waves.** Wave 1 builds three independent value/store types (last-file bookmark store, name-collision probe, local-Documents fallback); Wave 2 composes the create-target resolver; Wave 3 swaps the app host to a custom `UIDocumentBrowserViewController`-backed browser (the one structural change — no new external dependency, UIKit is in-SDK); Wave 4 attaches the resume branch, create-document handler, and back-navigation to that host. The DAG fits comfortably in a single build session; the only item warranting attention is the Wave 3 host swap, which carries a build-time feasibility check for the zero-flash resume timing (DC-3) — flagged in design.md as an escalation trigger if frame-zero presentation proves unachievable.

## Next step

Start a new session and run `/build feature-name: resume-and-create-2`.
