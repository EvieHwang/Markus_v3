# Requirements: resume-and-create-2

*Builds on `walking-skeleton-1`. Combines Roadmap #2 (Last-file resume on launch) and #5 (New file creation). All walking-skeleton requirements still hold; this document adds the resume and create behaviors and the back-to-browser affordance that ties them together.*

## User stories

### US-1 — Relaunch lands directly in the last-opened file
**As** a returning user
**I want** the app to open straight into the file I was last reading or editing
**So that** I do not have to re-navigate the document browser for every short session

**Acceptance criteria:**
- AC-1.1: After a user has opened at least one file in a prior session, the next cold launch presents the document view for that file as the first visible UI — no document browser flash, no intermediate screen.
- AC-1.2: The resumed file opens in **rendered mode** (per walking-skeleton AC-2.2), regardless of which mode the user was in when they last left it. Mode-on-resume is not preserved in this feature.
- AC-1.3: "Last-opened" means the most recently opened file, not the most recently saved. Reading-only sessions count.
- AC-1.4: Resume works after a cold launch (process killed, device rebooted) and after the app is foregrounded from a long-suspended state where the scene was torn down. Short-background-return (scene still alive) continues to use the existing scene state per walking-skeleton EC-6.
- AC-1.5: Persistence uses `NSUserActivity` carrying a security-scoped bookmark to the last-opened file. UserDefaults-only persistence is rejected as the primary mechanism; `NSUserActivity` is the HIG-canonical surface for "current document."

### US-2 — First-ever launch (and unrecoverable resume) falls through to the document browser
**As** a first-time user, or a returning user whose last file is no longer reachable
**I want** the app to show me the document browser without any error UI
**So that** I can pick a file and continue, with no friction explaining why my last file is gone

**Acceptance criteria:**
- AC-2.1: On first-ever launch (no persisted `NSUserActivity`), the first visible UI is the system document browser, matching walking-skeleton AC-1.1.
- AC-2.2: If the persisted bookmark cannot be resolved (file deleted, moved outside scope, permissions revoked, parent volume not mounted, iCloud not signed in), the app silently falls through to the document browser.
- AC-2.3: No alert, banner, toast, or "couldn't find your file" message is shown for an unresolvable bookmark. The fall-through is indistinguishable to the user from a first-ever launch.
- AC-2.4: A stale bookmark is cleared once the fall-through fires, so the next launch does not re-attempt resolution. The next file the user opens replaces it.

### US-3 — Return to the document browser from inside a file
**As** a user with a file open
**I want** a clear, standard way to get back to the document browser
**So that** the resume behavior does not trap me in one file

**Acceptance criteria:**
- AC-3.1: The document view's navigation bar shows the standard back chevron in the top-left, labeled per system convention (chevron alone, or chevron + previous-screen title — whatever `UINavigationController` produces by default).
- AC-3.2: Tapping the back chevron returns the user to the document browser. Any pending edits are saved first per walking-skeleton AC-4.4.
- AC-3.3: The standard screen-edge left-to-right swipe-back gesture (`UINavigationController.interactivePopGestureRecognizer`) also returns the user to the document browser, with the same save-first behavior.
- AC-3.4: The back affordance is available from both rendered mode and raw mode.
- AC-3.5: After returning to the browser, the user can pick a different file or use Create Document. The previously open file remains the "last-opened" file for resume purposes **until** another file is opened or created.

### US-4 — Create a new file in the directory of the last-opened file
**As** a user with a file already opened at least once
**I want** to tap Create Document and immediately start typing into a new empty file in the same folder as my last file
**So that** new notes land next to my existing notes, where I already keep them, without me navigating folders

**Acceptance criteria:**
- AC-4.1: The document browser's existing **Create Document** affordance is wired to `UIDocumentBrowserViewController`'s `documentBrowser(_:didRequestDocumentCreationWithHandler:)` (HIG-canonical creation hook).
- AC-4.2: The creation handler resolves the **directory of the last-opened file** as the target directory. This is the parent of the file referenced by the persisted bookmark; security scope to that parent must be acquired the same way it is for the file itself.
- AC-4.3: The handler chooses a filename of the form `Untitled.md`, `Untitled 2.md`, `Untitled 3.md`, … selecting the **lowest unused integer suffix** (no suffix for the first, then 2, 3, 4, …). Existing files in the directory — whether created by Markus or any other app — are never overwritten.
- AC-4.4: The new file is created on disk **with zero bytes** as a placeholder for the `UIDocumentBrowserViewController` handoff. It is opened immediately into the document view in **raw mode** with the **keyboard active** and the cursor at the start of the document.
- AC-4.5: On successful creation and open, the new file becomes the "last-opened" file for future resume and future create-in-last-directory operations.

### US-5 — Create a new file when there is no last-opened directory
**As** a first-time user, or a user whose last directory is no longer writable
**I want** Create Document to still work
**So that** I can start a new note even before I have anywhere of my own to keep it

**Acceptance criteria:**
- AC-5.1: If no `NSUserActivity` bookmark is persisted, or the bookmark resolves to a directory that is not writable (read-only volume, permission denied, sync provider error), the creation handler creates the new file in Markus's local `FileManager.default.url(for: .documentDirectory, …)` location — the "On My iPhone / Markus" folder.
- AC-5.2: The fallback location uses the same Untitled-numbering rule as AC-4.3, scoped to that directory.
- AC-5.3: The fallback is silent — no UI explains why the file landed locally instead of in iCloud. The user can move it later via the Files app.
- AC-5.4: The "On My iPhone / Markus" folder must be visible in the Files app. This requires `UISupportsDocumentBrowser=YES` and `LSSupportsOpeningDocumentsInPlace=YES` in `Info.plist` (verify these are set by walking-skeleton; if not, this feature sets them).

### US-6 — An untouched new file leaves no trace
**As** a user who tapped Create Document but then changed my mind
**I want** the new file to disappear if I never typed anything
**So that** my folder does not fill up with empty `Untitled.md` files

**Acceptance criteria:**
- AC-6.1: A newly-created file with zero bytes that is closed (back to browser, app backgrounded into scene tear-down, or app killed) **before any keystroke** is deleted from disk.
- AC-6.2: "A keystroke" means any change to the document text — typing a character, pasting, deleting (in a non-empty document; deleting in an empty document is a no-op). Mode switches, scroll, and cursor moves do not count.
- AC-6.3: Once the user has typed even one character, the file persists per walking-skeleton AC-4.3 / AC-4.4 (autosave on idle, mode switch, back, background).
- AC-6.4: If deletion of the empty file fails (e.g., volume gone offline between create and close), the failure is silent — the file may remain as a zero-byte stub. No error UI is shown for this case.
- AC-6.5: After an untouched-and-deleted new file, the "last-opened" file pointer reverts to whatever it was before the create operation — the deleted Untitled file is not the new resume target.

## Edge cases and failure modes

### Resume resolution
- **EC-1: Bookmark to file moved within the same security scope.** iOS bookmarks auto-follow within scope. The resume opens the file at its new location. The bookmark is refreshed if iOS provides updated data.
- **EC-2: Bookmark to file renamed in place.** Same as EC-1 — bookmark follows. Navigation bar shows the new filename per walking-skeleton AC-2.3.
- **EC-3: Bookmark to file moved outside its original security scope.** Resolution fails; fall through to browser per AC-2.2; bookmark cleared per AC-2.4.
- **EC-4: Bookmark to file on an iCloud Drive item whose contents are not yet downloaded.** Resume proceeds; the document view shows the "Downloading…" loading indicator from walking-skeleton EC-13 until contents are available.
- **EC-5: Bookmark to file on a sync provider that is offline.** Resolution fails; fall through to browser per AC-2.2.
- **EC-6: Bookmark to file that was deleted externally between sessions.** Resolution fails; fall through to browser per AC-2.2. (Deletion-while-open is still Roadmap #3 — this is the across-sessions case.)
- **EC-7: Bookmark from a previous device / restored backup.** Resolution may or may not succeed depending on iCloud state. Either outcome is acceptable — success resumes per AC-1.1, failure falls through per AC-2.2.
- **EC-8: Multiple rapid relaunches.** Resume must be idempotent — relaunching while the previous launch is still resolving the bookmark must not produce duplicate document views or duplicate save fires.

### Create — naming and location
- **EC-9: Last-opened directory exists and is writable but contains `Untitled.md` and `Untitled 3.md` (with `Untitled 2.md` missing).** New file is named `Untitled 2.md` — lowest unused integer, gaps are filled.
- **EC-10: Last-opened directory contains `Untitled.md` through `Untitled 999.md`.** The handler continues incrementing. No upper bound is enforced by this feature — the user reaches Files-app pain long before any reasonable limit. If the OS or filesystem refuses creation, the failure is surfaced as a save-failure-style alert (see EC-12).
- **EC-11: Last-opened directory contains a *folder* named `Untitled.md`.** Counted as a name collision; numbering advances to `Untitled 2.md`. The handler does not attempt to enter or rename the folder.
- **EC-12: Creation of the new file on disk fails** (volume full, permissions revoked between resolution and write, sync provider error). The user is returned to the document browser with a non-fatal alert: "Couldn't create new file." The alert reuses the recovery surface from walking-skeleton AC-RECOVER-1 in style (non-blocking, single Dismiss action) but does not need clipboard recovery since there is no in-memory content to rescue.
- **EC-13: Create Document tapped on first-ever launch (no last-opened file).** New file is created in the local "On My iPhone / Markus" folder per AC-5.1.
- **EC-14: Last-opened file lives in a directory the user no longer has write permission to** (sync provider downgraded the share, file was in a shared folder now read-only). Fall back to local "On My iPhone / Markus" per AC-5.1.

### Create — untouched-file lifecycle
- **EC-15: User taps Create Document, types nothing, taps back chevron.** File is deleted per AC-6.1. Last-opened pointer reverts per AC-6.5.
- **EC-16: User taps Create Document, types nothing, app is force-quit.** Best-effort deletion fires on scene disconnect or app terminate notification. If the app is killed before the deletion fires, a zero-byte stub may remain — acceptable per AC-6.4.
- **EC-17: User taps Create Document, types a character, deletes it back to empty, closes file.** File persists with zero bytes — the user took action on it, so it counts as touched per AC-6.2. (This is a deliberate choice: detecting "net-empty after edits" would require diffing against the empty initial state and is more cleverness than the feature warrants.)
- **EC-18: User taps Create Document twice in rapid succession.** Each tap goes through `UIDocumentBrowserViewController`'s creation handler. The system serializes these per its own behavior — the requirement here is only that the handler does not deadlock or share state across invocations in a way that produces two files with the same name.

### Back and edge-swipe
- **EC-19: Edge-swipe started but not completed (released before threshold).** The view returns to the document with no save fired. This is `UINavigationController` default behavior and is in scope as-is.
- **EC-20: Edge-swipe interrupted by an incoming alert or system UI.** Standard system behavior — feature does not override it.
- **EC-21: Back tapped while a save is in flight.** The pending save completes before the navigation pop returns to the browser; the user does not see the document re-appear or flicker. (Walking-skeleton AC-4.4 implies this; called out explicitly here because the back affordance is new.)

### Concurrency
- **EC-22: User opens a file, force-quits before the new bookmark is persisted.** The previous bookmark (if any) remains as the resume target. The newly opened file is not yet the resume target — this is acceptable; persistence is best-effort and only the file actually committed to `NSUserActivity` counts.
- **EC-23: User creates a new file, app dies before any save.** The new file (zero bytes) exists on disk per AC-4.4. On next launch, resume attempts to open it; it opens to an empty rendered view, then the user is in the normal open-file flow. The untouched-deletion rule does not retroactively apply across launches.

## Out of scope

- **External-change detection while a file is open, conflict resolution, follow-on-move, deletion banner** — Roadmap #3.
- **Scroll-anchor preservation across mode switches** — Roadmap #4.
- **Mode preservation across resume** (resuming into raw mode if the user left in raw mode) — explicitly out per AC-1.2.
- **Cross-device Handoff continuation via `NSUserActivity`** — although the mechanism supports it, advertising the activity for Handoff (`isEligibleForHandoff = true` and related) is not in scope. The activity is used only for local restoration.
- **iPad multi-window / multi-scene state restoration** — single-scene only. If the project later supports iPad multi-window, per-scene restoration becomes Roadmap work then.
- **Settings toggle to disable resume** — declaration is explicit: no settings.
- **Stale-bookmark UI** — explicitly silent per AC-2.3.
- **Renaming `Untitled.md` files from inside Markus** — file management still lives in the Files app and document browser.
- **Templates / starter content for new files** — new means empty.
- **List continuation, smart-quote/dash suppression, Cmd+/, prototype non-edge-swipe gestures** — Roadmap #6.
- **Full accessibility pass** — Roadmap #7. See Standards check below.

## Standards check

- **Apple HIG (Interface).** This feature leans on three HIG-canonical surfaces by name: `NSUserActivity` for last-document restoration (AC-1.5), `UIDocumentBrowserViewController`'s `didRequestDocumentCreationWithHandler` for new-file creation (AC-4.1), and the standard `UINavigationController` back chevron + edge-swipe-back for the return-to-browser affordance (AC-3.1, AC-3.3). No custom chrome competes for HIG; behavior follows what Apple's own document-based apps do.
- **WCAG 2.1 AA (Accessibility).** Full pass remains Roadmap #7. This feature absorbs **no new accessibility criteria** beyond what the system controls provide by default — the back chevron's VoiceOver label is inherited from `UINavigationController`, the Create Document affordance's label is inherited from `UIDocumentBrowserViewController`, and the new file opening into raw mode reuses the editor whose accessibility was scoped (minimally) in walking-skeleton AC-A11Y-1/2/3. Adding more here would be standards creep against a thin feature; declined.
- **OWASP Top 10 (Security).** No new surface — no network, no auth, no input from external systems beyond the file the user explicitly picked. The persisted bookmark must not leak file paths to logs or analytics (no analytics exist; reaffirmed here for the bookmark write path specifically).
- **OpenAPI (API contracts).** N/A.

## Notes on changes

First pass for this feature. No prior `design.md` or `adversarial-review.md` to reconcile against. Once `t3-architecture` runs and surfaces design constraints, this document is revised; once `t3-adversarial` runs, any `open` findings tagged for requirements come back here.
