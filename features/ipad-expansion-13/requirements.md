# Requirements — iPad Expansion (ipad-expansion-13)

## Changed from prior version

**⌘N (new-document creation) removed from scope.** The prior version specified
four shortcuts (⌘P / ⌘W / ⌘N / ⌘S); this version specifies **three** (⌘P / ⌘W /
⌘S). A product decision dropped ⌘N: the only new-document path is the system
document browser's create control (`didRequestDocumentCreationWithHandler`), a
delegate callback the OS invokes from the browser, with no programmatic trigger
reachable from inside the presented editor; and Markus's own programmatic create
path was deliberately removed (roadmap item 5, superseded by
`restore-system-create-7`). Story `US-3` / `AC-3.x` are retired (IDs not reused);
the discoverability overlay now lists three commands; failure modes and the
out-of-scope section are updated accordingly. This change **resolves adversarial
finding F-001** (the ⌘N invocation/double-present gap) by scope removal rather
than by adding an invocation path. The width-constraint requirements (Part 2) and
the ⌘P / ⌘W / ⌘S requirements are otherwise unchanged.

## Context

This feature makes Markus feel like a first-class iPad app through two bounded
additions to the existing editor surface. It adds **no new product surface** (no
library, no settings, no toolbar buttons) and **no new component** — all four
touched areas already exist.

### Relevant existing seams (ground truth)

- **Mode toggle.** `DocumentView` holds `@State private var mode: DocumentMode`
  (`.rendered` / `.raw`, see `Models/DocumentMode.swift`). The rendered→raw
  transition runs through `switchTo(.rendered, target: .raw)` (seeds the raw
  scroll anchor, sets `mode = .raw`, posts a VoiceOver announcement). The
  raw→rendered transition (the toolbar "eye" button and `switchToRenderedFromSwipe`)
  seeds the rendered scroll anchor from `rawScrollState.currentFractionalY`, calls
  `triggerSave()`, sets `mode = .rendered`, and posts an announcement. These are
  the **existing mode-toggle flows** the ⌘P shortcut must drive — it must not
  introduce a parallel toggle path.
- **Save.** `DocumentView.triggerSave()` calls `document.markDirty()`; the
  autosave/idle path and the `MarkdownDocumentSaveBridge` own the actual write.
  Background entry (`scenePhase == .background`) and editor dismissal
  (`BrowserHostController.dismissPresentedEditor()` → `saveSynchronously()`) also
  trigger saves. This is the **existing save flow** ⌘S must invoke. There is no
  user-facing save button, save confirmation, or save toast today, and this
  feature adds none.
- **Return to browser.** The editor is presented as a `UIHostingController` inside
  a full-screen `UINavigationController` by `BrowserHostController`. The `onBack`
  closure runs `dismissPresentedEditor()`, which saves synchronously, stops the
  detector, tears down the session, and dismisses back to the browser. The
  toolbar back button and the L→R edge/mid-screen swipe both go through this
  path. This is the **existing return-to-browser flow** ⌘W must invoke.
- **Editor surfaces.** Raw editing is `RawEditorView` (wrapping
  `MarkdownTextViewBridge`, a `UITextView`); rendered display is `RenderedView`
  (a `ScrollView` containing a `Markdown` view that today applies
  `.frame(maxWidth: .infinity, alignment: .leading)`). The width constraint
  applies to both.

This feature **changes only**: `DocumentView`, `RawEditorView`, `RenderedView`,
and the host (`BrowserHostController` / `SceneDelegate`) at the level needed to
register key commands and apply the width constraint. It changes no document
model, save bridge, detector, or storage code.

---

## Part 1 — Hardware keyboard shortcuts

The three shortcuts below are registered as `UIKeyCommand`s at a responder level
where the iPad discoverability overlay (hold ⌘) can enumerate them, and where
they are reachable both while the raw text editor is first responder and while
the rendered view is shown.

| Shortcut | Action | Drives existing flow |
|----------|--------|----------------------|
| ⌘P | Toggle raw ↔ rendered | mode-toggle flow (`switchTo` / eye-button path) |
| ⌘W | Close editor → file browser | return-to-browser flow (`onBack` / `dismissPresentedEditor`) |
| ⌘S | Explicit save | save flow (`triggerSave()` / `markDirty()`) |

*Addresses adversarial F-001 by removing ⌘N from scope: there is no programmatic
trigger for the system create flow reachable from inside the presented editor,
and Markus's own programmatic create path was deliberately removed (roadmap item
5, superseded by `restore-system-create-7`). See Out of Scope and the declaration.*

### US-1 — Toggle mode from the keyboard (⌘P)

**As a writer with a hardware keyboard, I want to press ⌘P to switch between raw
and rendered mode so I can move between writing and reading without touching the
screen.**

#### AC-1.1 — Rendered → raw
While the rendered view is shown, pressing ⌘P switches the editor to raw mode.
The result is identical to the existing tap-to-edit transition: the raw scroll
anchor is seeded and `mode` becomes `.raw`. No new transition path is introduced.

#### AC-1.2 — Raw → rendered
While the raw editor is shown (including while the text view is first responder
with the keyboard up), pressing ⌘P switches to rendered mode. The result is
identical to the existing "eye" toolbar button: the rendered scroll anchor is
seeded from the raw scroll fraction, a save is triggered, and `mode` becomes
`.rendered`.

#### AC-1.3 — Toggle is honored in both modes
⌘P performs the correct direction based on the current `mode`. Repeated ⌘P
presses alternate rendered ↔ raw with no accumulated drift and no second
transition path.

#### AC-1.4 — VoiceOver announcement preserved
A ⌘P-driven transition posts the same mode-change VoiceOver announcement
("Editing mode" / "Preview mode") the existing toggle paths post, because it
routes through those paths. Initial-mode assignment on appear still posts no
announcement.

#### Edge case — ⌘P with keyboard focus in the text view
When the raw `UITextView` is first responder, ⌘P is still delivered and toggles
to rendered. It is not swallowed as text input and does not insert a character.

---

### US-2 — Close the editor from the keyboard (⌘W)

**As a writer with a hardware keyboard, I want to press ⌘W to close the current
document and return to the file browser so I can pick another file without
reaching for the back button.**

#### AC-2.1 — Returns to browser via the existing path
Pressing ⌘W in either mode invokes the existing return-to-browser flow
(`onBack` → `dismissPresentedEditor()`): the document is saved synchronously, the
detector is stopped, the editor session is torn down, and the browser becomes
visible. The behavior is identical to tapping the back button.

#### AC-2.2 — Unsaved edits are preserved on close
Because ⌘W routes through `dismissPresentedEditor()` (which saves synchronously
before dismissing), edits made since the last autosave are written back before
the editor closes. ⌘W introduces no save prompt or "discard changes?"
confirmation — the existing flow has none and this feature adds none.

#### AC-2.3 — Honored in both modes
⌘W closes the editor whether the raw editor (first responder or not) or the
rendered view is shown.

#### Edge case — ⌘W at the browser (no editor presented)
When no document is open (the browser is the top surface), ⌘W is a no-op (or is
simply not registered at that level). It must not crash, dismiss the browser, or
leave the app with no visible root.

---

### US-3 — Create a new document from the keyboard (⌘N) — REMOVED

**This story has been removed from the feature.** ⌘N (new-document creation) is
out of scope. The existing creation flow is the system document browser's create
control (`didRequestDocumentCreationWithHandler`), a delegate callback the OS
invokes from the browser; it has no programmatic trigger reachable from inside
the presented editor. Markus's own programmatic create path was deliberately
removed (roadmap item 5, superseded by `restore-system-create-7`). The ID `US-3`
and the AC IDs `AC-3.x` are retired and not reused. See Out of Scope and the
feature declaration.

*Addresses adversarial F-001 by removing ⌘N from scope (the
invocation/double-present gap disappears because the shortcut is dropped, not
because a new invocation path was added).*

---

### US-4 — Explicit save from the keyboard (⌘S)

**As a writer with a hardware keyboard, I want to press ⌘S to save my work now so
I have the reassurance of an explicit save even though the app autosaves.**

#### AC-4.1 — Invokes the existing save flow
Pressing ⌘S invokes the existing save path (`triggerSave()` → `document.markDirty()`,
driving the autosave/bridge write). It introduces no new save mechanism.

#### AC-4.2 — No new confirmation or UI
⌘S surfaces no new toast, dialog, or status indicator beyond whatever the
existing save flow already shows (today: none on success). A save failure
surfaces through the **existing** save-failed alert path (the
`SaveFailedAlertRouter` / `ActiveAlert.saveFailed` lifecycle) unchanged — ⌘S adds
no new error handling.

#### AC-4.3 — Honored in both modes
⌘S triggers a save whether the raw editor (first responder or not) or the
rendered view is shown. In rendered mode (which does not edit text) ⌘S still
routes through the existing save path and is harmless — it is a no-op write when
nothing is dirty.

#### Edge case — ⌘S with no unsaved changes
Pressing ⌘S when the buffer is clean performs the existing save flow with nothing
to write. It must not corrupt the buffer, re-trigger a conflict, or produce a
spurious error.

---

### US-5 — Shortcuts appear in the discoverability overlay

**As an iPad user, I want to hold ⌘ and see the available shortcuts so I can
discover and remember them.**

#### AC-5.1 — All three listed
When a hardware keyboard is attached and the editor is the active surface,
holding ⌘ shows the discoverability overlay listing all three commands, each with
a human-readable title (e.g. "Toggle Preview", "Close", "Save"). Each command's
title is supplied via the key command's discoverability title so the overlay can
render it.

#### AC-5.2 — Titles are stable and descriptive
The three titles are distinct, describe the action (not the implementation), and
do not change based on mode (the same command may toggle direction internally,
but its overlay title is stable).

#### Edge case — overlay at the browser
If ⌘ is held while the browser is the active surface (no editor presented), the
editor-only commands need not appear (the editor-session-scoped provider does not
exist there). No crash either way. The feature registers no editor command at the
browser level (⌘N is out of scope, so there is nothing this feature offers at the
browser).

---

### US-6 — Graceful no-op without a hardware keyboard

**As an iPhone user (or an iPad user with no keyboard attached), I want the app
to behave exactly as before so the shortcut feature is invisible to me.**

#### AC-6.1 — No behavior change without a keyboard
On a device with no hardware keyboard, none of the three commands can fire (there
is no key source). All existing open / render / edit / save / mode-switch /
conflict behavior is unchanged. No device conditional is required — the commands
simply never receive input.

#### AC-6.2 — No crash from registration
Registering the key commands on every device (including iPhone) must not crash,
must not alter layout, and must not consume any on-screen control or gesture.

---

## Part 2 — Editor line-length constraint

A maximum readable content width of approximately **700pt**, centered in the
available space, applied to **both** the raw editor and the rendered preview,
**only** in the regular horizontal size class. The constraint reads the SwiftUI
horizontal size class (`@Environment(\.horizontalSizeClass)`); behavior is
governed by size class, not device model.

### US-7 — Readable width on full-screen iPad (regular width)

**As a writer on a full-screen iPad, I want my text capped at a readable column
width and centered so lines are easy to scan instead of stretching edge to
edge.**

#### AC-7.1 — Raw editor capped and centered (regular width)
In the regular horizontal size class, the raw editor's text content is laid out
within a maximum width of ~700pt, horizontally centered in the available space.
The surrounding gutters are background only.

#### AC-7.2 — Rendered preview capped and centered (regular width)
In the regular horizontal size class, the rendered preview's content is laid out
within the same ~700pt maximum width, horizontally centered. This replaces the
current full-width `maxWidth: .infinity` behavior for regular width only.

#### AC-7.3 — Consistent width across modes
The raw editor and the rendered preview use the same maximum content width, so
switching modes does not change the column width or horizontal position of the
text.

#### AC-7.4 — Full width usable below the cap
When the available width is at or below ~700pt (e.g. a narrow split view that is
still regular-width), the content uses the full available width with no
artificial cap — the 700pt is a maximum, not a fixed width.

#### Edge case — very wide window (e.g. ~1366pt landscape iPad)
At large widths the text column remains ~700pt and centered; the extra space is
empty background on both sides. No line stretches beyond ~700pt of usable text.

---

### US-8 — No layout change in compact width

**As an iPhone user, or an iPad user in Slide Over, I want the layout to be
exactly as it is today so the narrow-width experience is unchanged.**

#### AC-8.1 — Compact width is full-width
In the compact horizontal size class (iPhone, Slide Over, narrow multitasking),
neither the raw editor nor the rendered preview applies the ~700pt cap or any new
horizontal centering. Content fills the available width as it does today.

#### AC-8.2 — No regression to current iPhone layout
On iPhone the raw editor and rendered view render byte-for-byte the same layout
as before this feature (modulo the inert key-command registration of Part 1).

---

### US-9 — Live response to size-class transitions

**As an iPad user, I want the column width to update immediately when I enter or
leave Slide Over or rotate the device, without having to reopen the document.**

#### AC-9.1 — Compact → regular updates live
Transitioning from compact to regular width (e.g. dragging the app out of Slide
Over, or rotating into a regular-width configuration) applies the ~700pt centered
cap to whichever surface is showing, live, without reopening the document or
losing scroll position/edit state.

#### AC-9.2 — Regular → compact updates live
Transitioning from regular to compact width removes the cap live, returning to
full-width layout, without reopening the document.

#### AC-9.3 — Applies to the currently shown surface and survives a mode switch
The live update applies to whichever mode is visible at the moment of transition,
and a subsequent mode switch shows the other surface already at the correct width
for the current size class.

---

### US-10 — The width cap never clips or hides text

**As a writer, I want the full ~700pt of column width to be usable for my text,
with no characters hidden, clipped, or pushed off-screen by the centering.**

#### AC-10.1 — Centering, not clipping
The constraint centers the content within a ~700pt-wide region. The gutters on
either side are background/padding only — they contain no text and hide no text.
Long lines wrap within the ~700pt column exactly as they would within a ~700pt
viewport.

#### AC-10.2 — Full column width usable
The full ~700pt of horizontal space is available for text; the cap does not
reserve part of that width for padding such that the usable text column is
materially narrower than ~700pt.

#### AC-10.3 — Caret and selection remain visible
In the raw editor at regular width, the text caret, selection, and scrolling
behave within the centered column. Typing at the right edge of the column wraps
or scrolls normally; no caret position is rendered in or hidden behind a gutter.

#### Edge case — long unbreakable token
A very long unbreakable token (e.g. a long URL with no spaces) is handled by the
same wrapping/scrolling behavior the surface uses today within a ~700pt width; it
is not silently clipped by the centering. (Whatever the surface does at a 700pt
viewport today is the acceptable behavior — the cap introduces no new clipping.)

---

## Failure Modes (what must NOT happen)

**FM-1** — A ⌘P / ⌘W / ⌘S press must not introduce a *parallel*
implementation of its action. Each must route through the existing flow named in
the table above. A divergent save, toggle, or close path is a defect even if it
appears to work.

**FM-2** — ⌘S and ⌘W must not introduce any new confirmation dialog, save
prompt, "discard changes?" sheet, or success toast beyond what the existing flows
already display. Save failures must continue to surface only through the existing
`SaveFailedAlertRouter` / `ActiveAlert.saveFailed` path.

**FM-3** — A ⌘P press while the raw `UITextView` is first responder must not be
swallowed as text and must not insert a literal character.

**FM-4** — Registering key commands must not crash, change layout, or disable any
existing touch gesture (tap-to-edit, swipe-to-rendered, swipe-to-browser,
edge-pan dismiss) on any device, with or without a keyboard.

**FM-5** — The width cap must not be applied in the compact horizontal size
class. iPhone and Slide Over layouts must be unchanged.

**FM-6** — The width cap must not clip, hide, or push text into a non-text
gutter. The full ~700pt column must remain usable (AC-10.1–AC-10.3).

**FM-7** — A size-class transition must not require reopening the document, must
not reset scroll position to the top, and must not discard unsaved edits, in
order to apply or remove the cap.

**FM-8** — The width cap must not desynchronize the two surfaces: raw and
rendered must use the same maximum width so switching modes does not shift the
text column (AC-7.3).

**FM-9** — No new document model, storage scheme, app-managed copy, or naming
logic may be introduced by ⌘S. It invokes the existing save flow unchanged.
(⌘N, which would have touched the create/storage path, is out of scope — see
Out of Scope.)

---

## Out of Scope

Consistent with the feature declaration:

- **⌘N / new-document creation** — dropped from this feature. The existing
  creation flow is the system browser's create control
  (`didRequestDocumentCreationWithHandler`), a delegate callback the OS invokes
  from the browser; it has **no programmatic trigger reachable from inside the
  presented editor**. Markus's own programmatic create path was deliberately
  removed (roadmap item 5, superseded by `restore-system-create-7`).
  Reintroducing one would reverse that decision and add storage-write scope this
  feature excludes; a no-op shortcut would mislead. This removal *addresses
  adversarial finding F-001*. ⌘N may return in a future feature if a programmatic
  create is reconsidered. See the feature declaration.
- **Formatting shortcuts (⌘B / ⌘I / ⌘K) and any formatting toolbar** — this
  feature deliberately excludes all text-mutating shortcuts and toolbar buttons.
- **⌘/ as the mode-toggle key** — the toggle is bound to ⌘P; ⌘/ is not used.
- **⌘O / open as a distinct shortcut** — returning to the browser is covered by
  ⌘W; there is no separate open shortcut.
- **Conflict-sheet relayout verification at iPad / Slide-Over widths** — the
  conflict sheet is a system-adaptive sheet; its relayout is not part of this
  feature.
- **Width constraint in the compact horizontal size class** — explicitly not
  applied (US-8, FM-5).
- **Sidebar / file-navigation panel, drag and drop, pointer/hover interactions,
  and Mac-aware entry flow** — none are part of this feature.
- **New document model or storage changes** — ⌘S invokes the existing save flow
  unchanged (FM-9); no new creation, model, or storage path is added (⌘N, which
  would have, is out of scope above).
- **New save UI** — no save button, save toast, or save indicator beyond the
  existing flow (FM-2).
- **Customizable / remappable shortcuts** — the three bindings (⌘P / ⌘W / ⌘S)
  are fixed.

---

Requirements stable — no architectural feedback to incorporate
