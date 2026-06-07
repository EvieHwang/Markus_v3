# Requirements — Mac Catalyst Shell (mac-catalyst-shell-14)

## Context

This feature brings Markus to the Mac as a native **Mac Catalyst** build — the
platform **shell only**. It adds **no new product capability**: every action the
menu bar exposes already exists in the iOS/iPad build, and every file-access,
render, edit, save, conflict, and lifecycle behavior is inherited unchanged.

Feature 13 (`ipad-expansion-13`) already shipped the ⌘P / ⌘W / ⌘S key commands
and the ~700pt centered max content width (which applies on Mac via the regular
horizontal size class). This feature does **not** re-implement either. It makes
the existing build feel like a Mac app by conforming to Apple HIG at the shell
level: a standard menu bar, **File → Open (⌘O)**, pointer/hover feedback, Mac
window-state restoration, and proper Mac icon assets.

### Relevant existing seams (ground truth)

- **Editor actions.** `EditorActions` (`Host/EditorActions.swift`) holds three
  closures — `toggleMode`, `saveNow`, `closeEditor` — each a *trigger onto an
  existing flow*, wired for the editor-session lifetime and `nil` at the browser.
  Feature 13's ⌘P / ⌘W / ⌘S route through these. The View/Edit/File menu items
  this feature adds must drive the **same** handles, never a parallel path.
- **Open + bookmark path.** `BrowserHostController.presentDocument(at:)` runs the
  gated open pipeline (`loadMarkdownDocument(at:)`: scope acquire → size pre-check
  → coordinated read → strict UTF-8 decode), records the file via the resume store
  on success (`didOpenDocument` → `LastFileStore.recordLastOpened`), and routes
  every failure to `openPathAlert` with the existing "Couldn't open" copy. The
  accepted document types are `MarkdownDocument.readableContentTypes`. **File →
  Open must funnel the user's chosen URL through this same `presentDocument(at:)`
  path** — it introduces no second open, decode, or bookmark mechanism.
- **Resume.** `LaunchResumeBranch.resume(into:)` resolves the last-opened file via
  `LastFileStore.resolveLastOpened()` (security-scoped bookmark, path fallback)
  and, if reachable, presents it as the scene's first content; if nothing
  resolves (first launch, stale bookmark, moved/deleted file) it does nothing and
  the browser is the landing screen, with **no error UI**. Mac window-state
  restoration must **defer to this existing resume/bookmark behavior**, not add a
  new persistence or recovery path.
- **Return to browser / close.** `dismissPresentedEditor()` saves synchronously,
  stops the detector, tears down the session, and dismisses to the browser. ⌘W and
  the host's `closeEditor` handle both route here.
- **Save.** `DocumentView.triggerSave()` → `document.markDirty()` drives the
  autosave/bridge write; failures surface only through the existing
  `SaveFailedAlertRouter` / `ActiveAlert.saveFailed` path. No save button, toast,
  or success confirmation exists today, and this feature adds none.
- **Editor surfaces.** Raw editing is `RawEditorView` (wrapping a `UITextView`);
  rendered display is `RenderedView`. The tap-to-edit surface (rendered → raw) and
  the mode-switch control are the targets for pointer/hover feedback.

This feature **changes only**: the host/scene level (menu-bar command structure,
File → Open entry, window-state restoration), pointer/hover affordances on the
rendered tap-to-edit surface and the mode-switch control, and the app-icon asset
catalog. It changes **no** document model, save bridge, detector, resume store,
or open pipeline.

---

## Part 1 — Mac menu bar

On the Catalyst build the app presents a standard Mac menu bar. The **File**,
**Edit**, and **View** menus expose the app's existing actions plus the
system-standard Edit items. Every menu item that maps to a keyboard shortcut
displays its ⌘ equivalent, and every item is reachable by keyboard alone
(WCAG 2.1 AA full keyboard access; Apple HIG menu conventions).

| Menu | Item | Shortcut | Drives existing flow |
|------|------|----------|----------------------|
| File | Open… | ⌘O | open + security-scoped-bookmark path (`presentDocument(at:)`) |
| File | Save | ⌘S | save flow (`saveNow` → `triggerSave()`) |
| File | Close | ⌘W | return-to-browser flow (`closeEditor` → `dismissPresentedEditor()`) |
| Edit | Undo / Redo / Cut / Copy / Paste / Select All | system defaults | system text responder (operates on the raw editor) |
| View | Toggle Preview | ⌘P | mode-toggle flow (`toggleMode`) |

The mode toggle stays on **⌘P** (per feature 13); ⌘/ is not used. File → New /
⌘N is **not** present (no programmatic create path; see Out of Scope). Formatting
items (⌘B / ⌘I / ⌘K) and any toolbar are **not** present.

### US-1 — The menu bar exposes the app's existing actions

**As a Mac user, I want a standard menu bar with File / Edit / View menus so the
app behaves like a Mac app and I can find its actions where I expect them.**

#### AC-1.1 — File menu contains Open / Save / Close
The File menu contains **Open…** (⌘O), **Save** (⌘S), and **Close** (⌘W), each
displaying its ⌘ equivalent. No **New** item appears.

#### AC-1.2 — View menu contains the mode toggle
The View menu contains a **Toggle Preview** item bound to **⌘P** that switches
raw ↔ rendered. Its title is stable (it does not change with the current mode),
consistent with feature 13's discoverability title.

#### AC-1.3 — Edit menu contains the system-standard items
The Edit menu contains the system-standard **Undo, Redo, Cut, Copy, Paste, Select
All** items with their standard ⌘ equivalents. These operate on the standard text
responder (the raw editor's text view) via the system responder chain.

#### AC-1.4 — Menu actions drive the existing flows, not parallel ones
Choosing **Save** performs the same save as ⌘S (`saveNow` → `triggerSave()`);
choosing **Close** performs the same close as ⌘W (`closeEditor` →
`dismissPresentedEditor()`); choosing **Toggle Preview** performs the same toggle
as ⌘P (`toggleMode`). No menu item introduces a second implementation of its
action.

#### AC-1.5 — Shortcuts and menu items agree
For every action that has both a menu item and a keyboard shortcut (Open, Save,
Close, Toggle Preview), the menu shortcut shown matches the binding that actually
fires, and triggering by menu and by shortcut produce identical behavior.

#### AC-1.6 — Full keyboard access
Every menu and every enabled menu item is reachable and operable using the
keyboard alone (menu-bar navigation), with no action available only via pointer.

### US-2 — Menu items are enabled/disabled to match document state

**As a Mac user, I want document-scoped menu items to be grayed out when no
document is open so the menu never offers an action that can't be performed.**

#### AC-2.1 — Document-scoped items disabled with no document open
When no document is open (the browser is the top surface, so the
`EditorActions` handles are `nil`), **Save**, **Close**, and **Toggle Preview**
are **disabled** (grayed out). They reflect the absence of an editor session
rather than firing into a `nil` handle.

#### AC-2.2 — Document-scoped items enabled with a document open
When a document is open, **Save**, **Close**, and **Toggle Preview** are
**enabled** and perform their actions.

#### AC-2.3 — Open is always available
**File → Open (⌘O)** is enabled whether or not a document is currently open
(opening another file is always a valid action). Choosing Open while a document
is already open behaves per US-3 / the existing open path.

#### AC-2.4 — Standard Edit items follow system enablement
Undo / Redo / Cut / Copy / Paste / Select All enable and disable according to
the standard text-responder rules (e.g. Cut/Copy enabled only with a selection,
Paste only with compatible pasteboard contents) — this feature defers entirely to
system behavior and adds no custom enablement logic for them.

#### Edge case — invoking a disabled action's shortcut with no document
Pressing ⌘S, ⌘W, or ⌘P while no document is open is a no-op (the handle is `nil`
/ the command is unavailable). It must not crash, must not dismiss or disturb the
browser, and must not leave the app with no visible root. (This matches feature
13's browser-level edge cases for ⌘W / ⌘P / ⌘S.)

---

## Part 2 — File → Open (⌘O)

File → Open is the Mac entry idiom. It lets the user pick a `.md` / `.markdown`
file from the filesystem and open it through the **existing** open +
security-scoped-bookmark path.

### US-3 — Open a file from the Mac File menu

**As a Mac user, I want File → Open (⌘O) to let me pick a markdown file in the
Finder-style open panel and open it, the same as picking one in the browser.**

#### AC-3.1 — Open presents a system file picker
Choosing **File → Open** (or pressing ⌘O) presents the system open panel for
file selection.

#### AC-3.2 — Picker is constrained to the app's markdown types
The picker offers / accepts only the app's existing readable content types
(`MarkdownDocument.readableContentTypes` — `.md` / `.markdown`). Files of other
types are not selectable as openable documents, consistent with the project's
"no file types beyond `.md` and `.markdown`" stance.

#### AC-3.3 — A chosen file opens via the existing path
On selecting a markdown file, the file opens through the existing
`presentDocument(at:)` path: security-scoped access is acquired, the gated load
pipeline runs, and on success the editor is presented. No new open, decode, or
read mechanism is introduced.

#### AC-3.4 — A successfully opened file becomes the resume target
Because Open routes through `presentDocument(at:)` (which fires `didOpenDocument`
→ `LastFileStore.recordLastOpened`), a file opened via File → Open is recorded as
the last-opened file for resume/restoration, exactly as a browser pick is. No
separate recording path is added.

#### AC-3.5 — Opening replaces the single current document
Because the Mac app is single-window (multi-window is out of scope), opening a
file while another is open results in the chosen file being shown in the one
window via the existing present/dismiss behavior. (The exact transition — reuse
the session vs. dismiss-and-represent — defers to the existing single-document
presentation behavior; this feature adds no multi-document model.)

#### Edge case — Open canceled
If the user dismisses the open panel without choosing a file, nothing opens, no
error is shown, and any currently open document is left untouched.

#### Edge case — Open of an unreadable / failing file
If a chosen file fails the existing load pipeline (e.g. unreadable, invalid
encoding, over the size ceiling, moved between pick and read), the failure
surfaces through the **existing** open-path alert (`openPathAlert`, "Couldn't
open" copy) and the security-scoped resource is released — identical to a failing
browser pick. No new error UI is introduced, and a previously open document is
not torn down by a failed open (DC-10 behavior is inherited).

#### Edge case — Open of a non-.md / non-.markdown file
The picker's type constraint (AC-3.2) should prevent selecting such a file. If a
non-markdown file nonetheless reaches the open path (e.g. via a type the system
permits), it is handled by the existing pipeline's type/decode gates and surfaces
the existing "Couldn't open" alert — this feature adds no new non-markdown
handling.

---

## Part 3 — Pointer / hover feedback

Under a trackpad or mouse, the existing tap targets give pointer/hover feedback
so the app feels native on the Mac (advances backlog #13). Pointer feedback is an
**enhancement layer**: it is never the *sole* affordance for any action (WCAG
2.1 AA — every action remains reachable by tap/click and by keyboard).

### US-4 — Pointer feedback on the tap-to-edit surface and mode-switch control

**As a Mac user with a trackpad or mouse, I want the tap-to-edit surface and the
mode-switch control to respond to my pointer so I can tell they're interactive.**

#### AC-4.1 — Tap-to-edit surface shows pointer feedback
When the pointer hovers over the rendered view's tap-to-edit surface, the app
provides pointer/hover feedback indicating the surface is interactive. Clicking
it still performs the existing rendered → raw transition (identical to tap-to-
edit), driving no parallel toggle path.

#### AC-4.2 — Mode-switch control shows pointer feedback
When the pointer hovers over the mode-switch control, the app provides
pointer/hover feedback. Clicking it performs the existing mode transition
(identical to the toolbar control), driving no parallel path.

#### AC-4.3 — Pointer feedback does not alter touch/click behavior
Adding pointer feedback does not change the underlying action, its hit area, or
any existing gesture. The action performed by click is identical to the action
performed by tap today.

#### AC-4.4 — Pointer is not the sole affordance
Every action that has pointer feedback is also reachable without a pointer — by
keyboard shortcut and/or menu item (⌘P / View → Toggle Preview for the mode
switch; tap/click and ⌘P for tap-to-edit). No interaction is gated behind hover.

#### Edge case — no pointer device present
With no pointer device (e.g. touch-only interaction, or running where no
trackpad/mouse is connected), the hover affordances are simply never triggered.
All tap/click and keyboard behavior is unchanged, and nothing is hidden or
disabled for lack of a pointer.

---

## Part 4 — Single-window state restoration ("resume last file" on Mac)

On the Mac, "resume last file" is expressed as single-window state restoration:
on relaunch, the app restores the previously open document. This is the **Mac
expression of the existing resume behavior** — it must defer to the existing
resume/bookmark path and introduce no new persistence or recovery logic.

### US-5 — Relaunch restores the previously open document

**As a Mac user, I want relaunching the app to bring back the document I had open
so I can pick up where I left off, the same as resume does today.**

#### AC-5.1 — Restores via the existing resume path
On relaunch, the app restores the previously open document by deferring to the
existing resume decision (`LaunchResumeBranch` / `LastFileStore.resolveLastOpened`
via the security-scoped bookmark). It does not introduce a separate Mac-only
persistence store for the document identity.

#### AC-5.2 — Single window
Restoration restores a **single** window/document. The app does not restore or
open multiple windows, tabs, or documents (multi-window is out of scope).

#### AC-5.3 — Consistent with iOS/iPad resume
The restored state is the same document the existing resume behavior would
resume to. Restoration changes the *Mac surface* of resume (window-state
restoration) but not *which* file is chosen or *how* it is resolved.

#### Edge case — previously open document moved or deleted
If the previously open document has moved or been deleted, restoration defers to
the existing resume/bookmark fallback: the bookmark fallback retargets a moved
file where the existing path allows, and if nothing resolves the app lands on the
browser with **no error UI**. Restoration introduces no new "file missing"
dialog or recovery flow — it inherits the existing fail-closed behavior (DC-4 /
the resume-hardening fallback).

#### Edge case — first-ever launch (no prior document)
On first launch with no recorded last file, restoration resolves nothing and the
app lands on its natural entry (the browser), exactly as the existing first-launch
behavior does. No empty/placeholder window is fabricated.

#### Edge case — no conflict/lifecycle change on restore
A restored document enters the same conflict/deletion/save lifecycle as a
freshly opened one. Restoration adds no new conflict prompt, deletion banner
behavior, or save behavior — these are inherited unchanged (per the declaration's
"Catalyst inherits conflict/lifecycle unchanged").

---

## Part 5 — Mac app-icon assets

### US-6 — The Mac build shows a proper app icon

**As a Mac user, I want the app to have a proper icon in the Dock, Finder, and
app switcher so it doesn't look unfinished.**

#### AC-6.1 — No empty or placeholder Mac icon slots
The asset catalog provides the icon assets the Mac build requires; the Mac icon
slots are populated (advancing backlog #16). The Dock/Finder/switcher show a real
Markus icon, not a generic placeholder or blank.

#### AC-6.2 — No regression to iOS/iPad icons
Populating the Mac icon slots does not remove or break the existing iOS/iPad
icon. Both platforms show their correct icon.

---

## Failure Modes (what must NOT happen)

**FM-1** — No menu item (Save / Close / Toggle Preview / Open) may introduce a
*parallel* implementation of its action. Each must route through the existing
flow it shares with the corresponding shortcut (`saveNow` / `closeEditor` /
`toggleMode` / `presentDocument(at:)`). A divergent path is a defect even if it
appears to work.

**FM-2** — File → Open must not introduce a second open, decode, read, or
security-scoped-bookmark mechanism. It funnels the chosen URL through
`presentDocument(at:)` and inherits the gated load pipeline and the existing
"Couldn't open" failure surface unchanged.

**FM-3** — Window-state restoration must not introduce a new document-identity
persistence store or a new "file missing" recovery dialog. It defers to the
existing resume/bookmark path and its fail-closed (browser-landing, no-error-UI)
behavior.

**FM-4** — No File → New / ⌘N may be present. There is no programmatic create
path reachable here (roadmap item 5 superseded by `restore-system-create-7`), and
a disabled-or-no-op New item would mislead.

**FM-5** — Pointer/hover feedback must not be the *sole* affordance for any
action, must not change any hit area or existing gesture, and must not disable or
hide anything where no pointer device is present (WCAG 2.1 AA).

**FM-6** — Document-scoped menu items (Save / Close / Toggle Preview) must not be
invocable into a `nil` handle when no document is open; they must be disabled in
that state and must not crash if their shortcut is pressed.

**FM-7** — No conflict, deletion, or save behavior may change. The Catalyst build
inherits the existing lifecycle; this feature adds no new prompt, banner, toast,
or save confirmation (including for ⌘S / File → Save, which surface failures only
through the existing `SaveFailedAlertRouter` / `ActiveAlert.saveFailed` path).

**FM-8** — No multi-window, document-tab, or multi-document-model behavior may be
added; the app is single-window. Opening a file replaces the single current
document via existing behavior.

**FM-9** — Populating Mac icon slots must not remove, break, or downgrade the
existing iOS/iPad icon assets.

**FM-10** — The mode toggle must remain bound to ⌘P; ⌘/ must not be wired as a
toggle. The ~700pt content-width constraint must not be re-implemented (it is
inherited from feature 13 via the regular horizontal size class).

---

## Out of Scope

Mirroring the feature declaration:

- **Multi-window / document tabs and any multi-document model** — deferred to
  backlog item 19. The Mac app is single-window; restoration restores a single
  document.
- **Formatting commands (⌘B / ⌘I / ⌘K) and any formatting toolbar** —
  text-mutating new capability; excluded, consistent with feature 13.
- **File → New / ⌘N** — no programmatic create path exists (roadmap item 5
  superseded by `restore-system-create-7`); excluded (FM-4).
- **⌘/ as a mode toggle** — the toggle stays on ⌘P per feature 13.
- **Editor max content width (#11)** — already delivered by feature 13; applies on
  Mac via the regular horizontal size class; not re-implemented here.
- **Settings / preferences window, accounts, library / sidebar, drag and drop** —
  none added.
- **Conflict / lifecycle behavior changes** — the Catalyst build inherits the
  existing conflict, deletion, and save flows unchanged (FM-7).
- **New save UI** — no save button, toast, or success indicator beyond the
  existing flow; save failures surface only through the existing alert path.

---

Requirements stable — no architectural feedback to incorporate
