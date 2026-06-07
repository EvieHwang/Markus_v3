# Architecture — Mac Catalyst Shell (mac-catalyst-shell-14)

Stage 2 design for the Mac Catalyst **platform shell** over the existing
iOS/iPad build: a standard File / Edit / View menu bar driving the *existing*
`EditorActions` handles and open path; **File → Open (⌘O)** as the Mac entry
idiom funneling through `presentDocument(at:)`; pointer/hover feedback on the
two existing tap targets; single-window state restoration deferring to the
existing resume path; and Mac app-icon assets. **No new product capability and
no new Shape component** — every menu action, the open pipeline, the resume
decision, and the conflict/lifecycle flows are inherited unchanged.

Resolves the AC-3.5 deferred question on the open-while-open single-window
transition.

This design follows the house style of `ipad-expansion-13/design.md`: every
constraint below is a **behavioral property** — what the user or system observes
— not a call signature or modifier name, except where a call shape is itself the
public contract Markus exposes to the OS (the Catalyst menu-builder and key-
command discoverability mechanisms), which are named and justified.

No entry in constitution.md's Patterns-in-use registry covers Catalyst menu
construction, `UIPointerInteraction`, or scene state restoration (the registry
is React/TypeScript and Python-service oriented), so no `Reuses pattern:` marker
applies to the components below. The load-bearing reuse is **this app's own**
existing action flows — `EditorActions` (`toggleMode` / `saveNow` /
`closeEditor`), `BrowserHostController.presentDocument(at:)`, and
`LaunchResumeBranch` / `LastFileStore` — and it is called out per-component.

---

## Existing seams confirmed (ground truth read at design time)

- **`EditorActions`** (`Host/EditorActions.swift`) — three optional closures
  `toggleMode` / `saveNow` / `closeEditor`. Wired only for the editor-session
  lifetime: the host sets `closeEditor` and `DocumentView.installEditorActions()`
  sets `toggleMode` / `saveNow` on appear; all three are absent (the owning
  `EditorActions` does not exist) at the browser. Feature 13's ⌘P/⌘W/⌘S already
  route through these via `EditorKeyCommandHostingController`.
- **`EditorKeyCommandHostingController`** (`Host/EditorKeyCommandHostingController.swift`)
  — the responder, above the raw `UITextView`, that vends ⌘P/⌘W/⌘S and forwards
  each to the matching `EditorActions` closure. The Mac menu bar must drive the
  **same** handles, not duplicate this chain.
- **`BrowserHostController.presentDocument(at:)`** — the single open funnel:
  `loadMarkdownDocument(at:)` (scope acquire → size pre-check → coordinated read
  → strict UTF-8 decode), `installEditorSession(...)` on success which fires
  `didOpenDocument` → `LastFileStore.recordLastOpened`, and routes every failure
  to `openPathAlert` ("Couldn't open"). `activeDocument` is mutated only on
  success, so a failed open never tears down the prior document (DC-10).
- **Accepted types** — `MarkdownDocument.readableContentTypes`, the same set
  passed to `UIDocumentBrowserViewController(forOpening:)` in the host's `init`.
- **Resume** — `LaunchResumeBranch.resume(into:)` → `LastFileStore.resolveLastOpened()`
  (bookmark, path fallback); presents the file as first content if reachable,
  otherwise does nothing and the browser is the landing screen, **no error UI**.
  Driven from `SceneDelegate.scene(_:willConnectTo:options:)` via
  `host.initialResumeAction`.
- **Close** — `dismissPresentedEditor()` (synchronous save → detector stop →
  session teardown → dismiss); reached by `closeEditor`, the back button, and the
  edge swipe.
- **Save** — `DocumentView.triggerSave()` → `document.markDirty()`; failures
  surface only via `SaveFailedAlertRouter` / `ActiveAlert.saveFailed`.
- **Pointer targets** — tap-to-edit is `RenderedView`'s `.onTapGesture` over the
  `.contentShape(Rectangle())` surface; the mode-switch control is the **eye
  button** (`Image(systemName: "eye")`) shown in `DocumentView`'s toolbar in raw
  mode, whose action is the eye-button transition (seed rendered anchor → save →
  `mode = .rendered`).
- **No menu builder exists today.** `AppDelegate` (`App/Markus_v3App.swift`) is a
  `UIResponder` `UIApplicationDelegate`; it is the natural host for the Catalyst
  menu-build override.
- **Icon catalog** — `Assets.xcassets/AppIcon.appiconset/Contents.json` already
  declares the 12 `"idiom":"mac"` slots, but they carry **no `filename`** (empty
  placeholders); the iOS slot references `Markus-app-icon.png`.

---

## Resolved deferred question — AC-3.5 (open-while-open, single window)

Requirements AC-3.5 deferred to architecture the concrete single-window
transition when File → Open is chosen while a document is already open: *reuse
the session* vs. *dismiss-and-represent*. This design resolves it as a
**behavioral constraint** without introducing any multi-document model, and
without changing requirement text (AC-3.5 already framed it as deferred-to-
architecture, so the "Requirements stable" marker stands — see bottom).

**Resolution (constraint C-2.4):** Open-while-open is **dismiss-and-represent**
on the single window. Choosing Open while an editor is presented runs the
existing teardown (`dismissPresentedEditor()` — synchronous save of the current
document, detector stop, session teardown) and then presents the newly chosen
file through the same `presentDocument(at:)` path the browser pick uses. The
observable result is one window showing one document, the prior document saved
and its detector stopped, and the new document recorded as the resume target —
identical to closing then opening, with no second document model, no second
window, and no two-documents-live moment.

**Why dismiss-and-represent, not reuse-the-session.** Reusing the session would
mean swapping a new `MarkdownDocument` + `ChangeDetector` + `SaveBridge` +
`SaveFailedAlertRouter` into the live editor in place — a per-component
hot-swap the existing code does not support and which would be a *new* document-
lifecycle path (FM-1, FM-8). The host already builds an entire editor session
atomically in `installEditorSession(...)` and already tears one down atomically
in `dismissPresentedEditor()`; composing those two existing operations
introduces no new mechanism and inherits their save/detector guarantees exactly.
This is the single-document behavior the requirement points at ("the existing
present/dismiss behavior"). See Seam S-4 for the ordering guard (failed new open
must not have torn down the prior document — DC-10).

---

## Part 1 — Mac menu bar

### Component A — CatalystMenuBuilder (a menu-construction hook, not an action owner)

The Catalyst menu bar is built by overriding the application's menu-build hook
(an OS-level mechanism — see C-1.5) on `AppDelegate`. Component A constructs the
File / Edit / View structure and maps each Markus item to an **existing flow**;
it owns no save, toggle, close, or open *implementation*. It is the menu-bar
analogue of `EditorKeyCommandHostingController`: a router that exposes the same
`EditorActions` handles and the same `presentDocument(at:)` open path through a
different OS affordance.

**Why `AppDelegate` and a build-time hook (the architectural decision).** The
menu bar is a process-level surface on Catalyst, constructed once when the OS
asks the application to build its menus; the app delegate is the responder that
receives that request and the only place with application scope. Building the
menu there — rather than on the scene or the editor — keeps the structure stable
across the open/close lifecycle while letting *enablement* (C-2.x) follow the
responder chain at validation time, which is where document scope actually lives.

**C-1.1 — File menu exposes Open / Save / Close, each showing its ⌘ equivalent,
and no New.** The File menu contains **Open…** (⌘O), **Save** (⌘S), and
**Close** (⌘W). Each displays its shortcut. **No New item appears** — there is
no programmatic create path reachable here (roadmap item 5 superseded by
`restore-system-create-7`); a disabled or no-op New would mislead. (AC-1.1,
FM-4.)

**C-1.2 — View menu exposes a stable-titled mode toggle on ⌘P.** The View menu
contains a **Toggle Preview** item bound to ⌘P that switches raw ↔ rendered. Its
title is **stable** (does not change with current mode), matching feature 13's
discoverability title. (AC-1.2, FM-10.)

**C-1.3 — Edit menu defers entirely to the system responder chain.** The Edit
menu presents the system-standard **Undo, Redo, Cut, Copy, Paste, Select All**
with their standard ⌘ equivalents, operating on the standard text responder (the
raw editor's `UITextView`) via the responder chain. This feature adds **no**
custom Edit action and **no** custom enablement for these items; their
enable/disable follows the standard text-responder rules (Cut/Copy with a
selection, Paste with compatible pasteboard contents). (AC-1.3, AC-2.4.)

**C-1.4 — Every Markus menu item is a trigger onto the existing flow, never a
second implementation.** Choosing **Save** performs the same effect as ⌘S
(`saveNow` → `triggerSave()`); **Close** the same as ⌘W (`closeEditor` →
`dismissPresentedEditor()`); **Toggle Preview** the same as ⌘P (`toggleMode` →
`performToggleMode()`); **Open…** the same path a browser pick uses
(`presentDocument(at:)`, via Component B). Menu invocation and shortcut
invocation produce byte-identical downstream effects because they call the same
code. No menu item introduces a parallel save/toggle/close/open path. (AC-1.4,
AC-1.5, FM-1.)

**C-1.5 — Menu items and their shortcuts agree, and every item is keyboard-
reachable.** *This is one place a call shape is the public contract:* the
Catalyst menu bar is an OS mechanism that reads each command's title, key
equivalent, and enablement when it builds and validates the menu. The contract
is therefore "Markus contributes commands carrying human-readable titles and the
⌘ equivalents that match the bindings which actually fire, into the OS menu
build." For Open/Save/Close/Toggle Preview the shown shortcut equals the firing
binding, and triggering by menu vs. by shortcut is identical (C-1.4). Every menu
and every enabled item is reachable and operable by keyboard alone (menu-bar
navigation), with no Markus action available only via pointer (WCAG 2.1 AA full
keyboard access; Apple HIG menu conventions). (AC-1.5, AC-1.6.)

### Component-A behavioral seams — enablement

**C-2.1 — Document-scoped items are disabled when no document is open.** When the
browser is the top surface and no editor session exists, **Save**, **Close**,
and **Toggle Preview** are **disabled** (grayed). Enablement reflects the
*presence of an editor session* — observably, the absence of installed
`EditorActions` handles — rather than firing into a `nil` handle. (AC-2.1, FM-6.)

**C-2.2 — Document-scoped items are enabled when a document is open and then
perform their actions.** With an editor session presented, Save / Close / Toggle
Preview are enabled and drive their existing flows (C-1.4). (AC-2.2.)

**C-2.3 — Open is always enabled.** **File → Open (⌘O)** is enabled whether or
not a document is open; opening another file is always valid. Choosing Open while
a document is open behaves per US-3 and constraint C-2.4. (AC-2.3.)

**C-2.4 — Open-while-open replaces the single current document via existing
present/dismiss (the resolved AC-3.5 transition).** See *Resolved deferred
question*. Open-while-open is dismiss-and-represent on the one window: the prior
session is torn down by the existing teardown (saving synchronously, stopping the
detector) and the new file is presented through `presentDocument(at:)`. No
multi-window, tab, or multi-document state is created. (AC-3.5, FM-8.)

**C-2.5 — A disabled item's shortcut with no document is a structural no-op.**
Pressing ⌘S / ⌘W / ⌘P at the browser does nothing: the command is unavailable
(no editor session, no installed handle) rather than firing into `nil`. It must
not crash, must not dismiss or disturb the browser, and must not leave the app
with no visible root — matching feature 13's browser-level edge cases. (AC-2
edge case, FM-6.)

**Behavioral seam S-1 — Enablement is driven by editor-session presence, read
through the same responder/validation chain that vends the action, not by a
duplicated state flag.** The menu's document-scoped items become available
exactly when an editor session is presented and unavailable exactly when it is
dismissed — the same lifetime that governs `EditorActions` installation (S-1 of
feature 13) and the key-command provider. The observable contract: there is no
moment where a Save/Close/Toggle item is enabled with no session, or disabled
with a session present; enablement and the live handle are the same fact viewed
through the menu. This makes the disabled-shortcut edge case (C-2.5) structural,
not a runtime nil-guard. (Protects FM-1, FM-6.)

**Behavioral seam S-2 — Menu actions reach the *same* `EditorActions` /
`presentDocument` seams the shortcuts and browser already use.** Toggle/Save/
Close route to `toggleMode` / `saveNow` / `closeEditor`; Open routes to
`presentDocument(at:)`. The menu holds intents onto existing entry points, never
recomputed effects — so menu, keyboard chord, and on-screen control (eye button,
back button, browser pick) all converge on one implementation. (Protects FM-1,
FM-2, FM-7.)

---

## Part 2 — File → Open (⌘O)

### Component B — MacOpenCommand (a picker-to-funnel adapter, not a second open path)

File → Open presents the system open panel constrained to Markus's existing
readable types and funnels the chosen URL into `presentDocument(at:)`. It is an
*adapter*: panel in, existing-funnel out. It introduces no open, decode, read,
or security-scoped-bookmark mechanism of its own (FM-2). Component B is reachable
from both the File → Open menu item (Component A) and the ⌘O shortcut, which are
the same command.

**C-3.1 — Open presents the system open panel.** Choosing File → Open (or ⌘O)
presents the system document-picker open panel for file selection. (AC-3.1.)

**C-3.2 — The panel is constrained to the app's markdown types.** The panel
offers/accepts only `MarkdownDocument.readableContentTypes` (`.md` / `.markdown`)
— the same type set the browser is constructed with. Other types are not
selectable as openable documents, consistent with the project's "no file types
beyond `.md` and `.markdown`" stance. (AC-3.2.)

**C-3.3 — A chosen file opens through the existing funnel, with no new
mechanism.** On selection the URL is handed to `presentDocument(at:)`:
security-scoped access is acquired by the existing pipeline, the gated load runs
(scope → size pre-check → coordinated read → strict UTF-8 decode), and on success
the editor is presented by `installEditorSession(...)`. No second open, decode,
read, or bookmark path is added. (AC-3.3, FM-2.)

> Security note (OWASP): File → Open adds **no new attack surface**. By funneling
> through `presentDocument(at:)` it *inherits* the existing gated pipeline's
> protections — the size ceiling (OOM guard), strict UTF-8 decode, coordinated
> read, and the directory/non-regular-URL rejection — rather than introducing a
> parallel read. The only new input is a user-chosen URL, which is subjected to
> the identical gates a browser-picked URL faces.

**C-3.4 — A successfully opened file becomes the resume target via the existing
recording path.** Because Open routes through `presentDocument(at:)` (which on
success fires `didOpenDocument` → `LastFileStore.recordLastOpened`), a file
opened via File → Open is recorded as the last-opened file for
resume/restoration, exactly as a browser pick is. No separate recording path is
added. (AC-3.4.)

**C-3.5 — Open canceled leaves everything untouched.** Dismissing the panel
without choosing opens nothing, shows no error, and leaves any currently open
document (and its session) untouched. (AC-3 cancel edge case.)

**C-3.6 — A failing open surfaces the existing alert and preserves the prior
document.** A chosen file that fails the existing pipeline (unreadable, invalid
encoding, over the ceiling, moved between pick and read) surfaces through the
existing `openPathAlert` "Couldn't open" copy and releases the security-scoped
resource — identical to a failing browser pick. Because `activeDocument` is
mutated only on success, a previously open document is **not** torn down by a
failed open (DC-10 inherited). No new error UI. A non-markdown file that somehow
reaches the path is handled by the existing type/decode gates. (AC-3 failing/
non-md edge cases, FM-2.)

**Behavioral seam S-3 — The open panel's only output is a URL into the existing
funnel.** The seam carries a chosen URL into `presentDocument(at:)` and nothing
else; success, recording, and failure semantics are entirely the existing
pipeline's. The picker contributes selection and the type constraint; it
contributes no decision about how the file is read or recorded. (Protects FM-2.)

**Behavioral seam S-4 — Open-while-open orders teardown-then-present and never
tears down on a failed open.** When Open is chosen with a document already open
(C-2.4), the existing session is torn down (synchronous save, detector stop)
*then* the new file is presented. If the new open fails its pipeline gates, the
prior document — if the design chose to tear it down first — must not be left
with the app showing no document erroneously; the inherited DC-10 guarantee is
that a failed open does not destroy a healthy prior document. The build step must
preserve this: the prior document is only relinquished once the new document has
successfully loaded, OR the user has accepted the equivalent of a close. The
observable contract is "a failed File → Open never leaves the user worse off than
a canceled one." (Protects DC-10, FM-8.)

---

## Part 3 — Pointer / hover feedback

### Component C — PointerAffordanceLayer (an enhancement overlay on two existing targets)

Pointer/hover feedback is attached to the two existing tap targets — the
`RenderedView` tap-to-edit surface and the eye mode-switch control — as a
**pure enhancement layer**. It is never the sole affordance for any action, never
changes a hit area or an existing gesture, and is simply never triggered when no
pointer device is present (WCAG 2.1 AA). It adds no new interactive element and
no new action.

**C-4.1 — The tap-to-edit surface shows pointer feedback; clicking it performs
the existing rendered → raw transition.** When a pointer hovers over
`RenderedView`'s tap-to-edit surface, the app shows pointer/hover feedback
indicating interactivity. A click performs the existing `onTap` → rendered → raw
transition (identical to a tap), driving no parallel toggle path. (AC-4.1.)

**C-4.2 — The mode-switch (eye) control shows pointer feedback; clicking it
performs the existing transition.** When a pointer hovers over the eye button,
the app shows pointer/hover feedback. A click performs the existing eye-button
transition (seed rendered anchor → save → `mode = .rendered`), identical to a
tap, driving no parallel path. (AC-4.2.)

**C-4.3 — Pointer feedback changes no action, hit area, or gesture.** Adding
hover feedback does not alter the underlying action, its hit area, or any
existing gesture (tap-to-edit, the rendered-view L→R swipe-to-raw, vertical
scroll, the edge-pan dismiss, the toolbar buttons). The action performed by click
is identical to the action performed by tap today. (AC-4.3, FM-5.)

**C-4.4 — Pointer is never the sole affordance.** Every action carrying pointer
feedback is also reachable without a pointer: the mode switch via ⌘P / View →
Toggle Preview and the eye button's tap; tap-to-edit via tap/click and via ⌘P.
No interaction is gated behind hover. (AC-4.4, FM-5.)

**C-4.5 — Absent a pointer device, nothing is hidden, disabled, or changed.**
With no trackpad/mouse (touch-only, or no pointer connected) the hover
affordances are simply never triggered; all tap/click and keyboard behavior is
unchanged and nothing is hidden or disabled for lack of a pointer. The feedback
is additive on every device. (AC-4 no-pointer edge case, FM-5.)

**Behavioral seam S-5 — Pointer feedback is layered over the existing targets'
hit regions, not a new control with its own hit region.** The hover region
coincides with the *existing* tap/click region of each target; the layer reports
"this region is interactive" to the pointer system but routes activation through
the same `onTap` / eye-button action the touch path uses. The observable
contract: the clickable area equals the tappable area, before and after the
feedback is added. (Protects AC-4.3, FM-5.)

---

## Part 4 — Single-window state restoration ("resume last file" on Mac)

### Component D — MacRestorationBridge (defers to the existing resume decision)

On the Mac, "resume last file" is the Mac surface of the existing resume
behavior: on relaunch the app restores the previously open document by deferring
to `LaunchResumeBranch` / `LastFileStore.resolveLastOpened()`. It introduces **no
new persistence store** for document identity and **no new "file missing"
recovery UI**, and restores **one** window only. It is a thin bridge from the
Mac scene-restoration entry into the same `host.initialResumeAction` →
`LaunchResumeBranch.resume(into:)` decision the scene already runs.

**C-5.1 — Restoration restores via the existing resume path.** On relaunch the
app restores the previously open document by deferring to the existing resume
decision (`LaunchResumeBranch` → `LastFileStore.resolveLastOpened` via the
security-scoped bookmark, path fallback). It does **not** introduce a separate
Mac-only document-identity persistence store. (AC-5.1, FM-3.)

**C-5.2 — Single window.** Restoration restores a **single** window/document. No
multiple windows, tabs, or documents are restored or opened. (AC-5.2, FM-8.)

**C-5.3 — Consistent with iOS/iPad resume — same file, same resolution.** The
restored document is the same file the existing resume behavior would resume to,
resolved the same way. Restoration changes the *Mac surface* of resume
(window-state restoration), not *which* file is chosen or *how* it is resolved.
(AC-5.3.)

**C-5.4 — A moved/deleted prior document defers to the existing fail-closed
fallback.** If the previously open document moved or was deleted, restoration
defers to the existing resume/bookmark fallback: the bookmark fallback retargets
a moved file where the existing path allows; if nothing resolves, the app lands
on the browser with **no error UI**. No new "file missing" dialog or recovery
flow is added; the existing fail-closed behavior (DC-4 / resume-hardening
fallback) is inherited. (AC-5 moved/deleted edge case, FM-3.)

**C-5.5 — First-ever launch resolves nothing and lands on the browser.** With no
recorded last file, restoration resolves nothing and the app lands on its natural
entry (the browser), exactly as existing first-launch behavior. No empty or
placeholder window is fabricated. (AC-5 first-launch edge case.)

**C-5.6 — A restored document enters the unchanged conflict/lifecycle.** A
restored document enters the same conflict/deletion/save lifecycle as a freshly
opened one. Restoration adds no new conflict prompt, deletion-banner behavior, or
save behavior — all inherited unchanged. (AC-5 lifecycle edge case, FM-7.)

**Behavioral seam S-6 — The Mac scene-restoration entry point hands control to
the existing resume decision and contributes no new persisted identity.** The
seam's contract: whatever Mac restoration mechanism activates the scene, the
*document choice* is made solely by `LaunchResumeBranch.resume(into:)` reading
`LastFileStore`. The Mac restoration path may persist scene/window chrome (the
OS owns that), but the **document identity** is never stored or resolved by a new
Mac-only store — it is always the existing bookmark/path resolution. The
observable consequence: deleting/moving the file, or first launch, behaves
identically to iOS/iPad resume. (Protects FM-3.)

---

## Part 5 — Mac app-icon assets

### Component E — MacAppIconSlots (populate existing empty Mac slots)

`AppIcon.appiconset/Contents.json` already declares the 12 `"idiom":"mac"` slots
but they carry no `filename` (empty). This component populates the Mac slots so
the Dock/Finder/switcher show a real icon, without touching the iOS/iPad slots.

**C-6.1 — The Mac icon slots are populated; no empty/placeholder slots remain.**
The asset catalog provides the icon assets the Mac build requires (the macOS icon
set, sized per its declared slots). The Dock, Finder, and app switcher show a
real Markus icon, not a generic placeholder or blank. (AC-6.1.)

**C-6.2 — Populating Mac slots does not regress the iOS/iPad icon.** The existing
iOS/iPad icon (light/dark/tinted universal slots referencing
`Markus-app-icon.png`) is unchanged; both platforms show their correct icon. The
Mac slots are additive. (AC-6.2, FM-9.)

> The 12 Mac slots are size/scale-specific (16/32/128/256/512 @1x/@2x), distinct
> from the single 1024 universal iOS image. The build step supplies Mac-idiom
> assets for these slots (a sized macOS icon set) and assigns each a `filename`;
> it does not repoint or delete the iOS universal entries. The observable
> contract is C-6.1 + C-6.2; the exact source images are a build choice bounded
> by "real Mac icon present, iOS/iPad icon unchanged."

---

## Cross-cutting constraints

**X-1 — No new product surface.** No library, settings/preferences window,
sidebar, toolbar button, save button, save toast, discard prompt, drag-and-drop,
or formatting command is added. The only user-visible additions are the Mac menu
bar (a system shell affordance exposing existing actions), the system open panel,
pointer/hover feedback on two existing targets, Mac-window restoration, and the
Mac app icon. (Honors declaration Out-of-scope; FM-7, FM-8.)

**X-2 — Out-of-scope items are structurally excluded, not merely unimplemented.**
No File → New / ⌘N (no programmatic create path reachable here; FM-4); no
formatting shortcuts (⌘B/⌘I/⌘K) or formatting toolbar; ⌘/ is not wired as a
toggle (the toggle stays on ⌘P; FM-10); the ~700pt content-width cap is **not**
re-implemented (inherited from feature 13 via the regular horizontal size class;
FM-10); no multi-window / document-tab / multi-document model (FM-8). The Edit
menu adds no custom command — it is purely the system responder chain (C-1.3).

**X-3 — Existing behavior is preserved unchanged.** Open / render / edit / save /
conflict / deletion / resume / detector behavior is inherited intact. The
conflict sheet, deletion banner, share, save-failed alert, and the gated open
pipeline are untouched. Catalyst inherits conflict/lifecycle unchanged; ⌘S /
File → Save surface failures only through the existing
`SaveFailedAlertRouter` / `ActiveAlert.saveFailed` path — no save confirmation is
added. (FM-7.)

**X-4 — One implementation per action across all entry points.** For each of
toggle / save / close, the menu item, the keyboard chord (feature 13's provider),
and the on-screen control (eye button, back button) converge on a single
`EditorActions` handle / `DocumentView` effect. For open, the menu item, ⌘O, and
the browser pick converge on `presentDocument(at:)`. A divergent path is a defect
even if it appears to work. (FM-1, FM-2.)

---

## Components → requirements traceability

| Component / seam | Requirements covered |
|------------------|----------------------|
| C-1.1–C-1.5, S-2 | US-1 / AC-1.1–1.6; FM-1, FM-4, FM-10 |
| C-1.3 | AC-1.3, AC-2.4 (Edit defers to responder chain) |
| C-2.1–C-2.3, C-2.5, S-1 | US-2 / AC-2.1–2.3 + disabled-shortcut edge case; FM-6 |
| C-2.4, S-4 | AC-3.5 (resolved open-while-open transition); FM-8 |
| Component B, C-3.1–C-3.4, S-3 | US-3 / AC-3.1–3.4; FM-2 |
| C-3.5, C-3.6, S-4 | AC-3 cancel / failing / non-md edge cases; FM-2, FM-7 (DC-10 inherited) |
| Component C, C-4.1–C-4.5, S-5 | US-4 / AC-4.1–4.4 + no-pointer edge case; FM-5 |
| Component D, C-5.1–C-5.6, S-6 | US-5 / AC-5.1–5.3 + moved/first-launch/lifecycle edge cases; FM-3, FM-7, FM-8 |
| Component E, C-6.1, C-6.2 | US-6 / AC-6.1–6.2; FM-9 |
| X-1, X-2, X-3, X-4 | Out-of-scope; FM-1, FM-2, FM-7, FM-8, FM-10 |

---

## Requirements changes flagged

None. Every architectural decision is consistent with requirements.md as written.
The one question requirements.md deferred to architecture — the AC-3.5 open-
while-open single-window transition — is resolved here as a behavioral constraint
(C-2.4: dismiss-and-represent on the single window, composing the existing
teardown and `presentDocument(at:)`) **without changing requirement text**.
requirements.md already reads "Requirements stable — no architectural feedback to
incorporate" and AC-3.5 already framed the transition as deferred-to-architecture,
so its stability marker needs no change in this pass.

**Architecture stable — no requirements changes flagged**
