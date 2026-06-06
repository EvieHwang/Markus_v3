# Architecture — iPad Expansion (ipad-expansion-13)

Stage 2 design for two bounded additions to the existing editor surface:
Part 1 — four hardware-keyboard shortcuts (⌘P / ⌘W / ⌘N / ⌘S) that re-trigger
existing actions; Part 2 — a ~700pt centered max content width on the raw editor
and rendered preview, active only in the regular horizontal size class.

This feature adds **no new Shape component**. Every constraint below is a
behavioral property — what the user or system observes — not a call signature or
modifier name, except where a call shape is itself the public contract Markus
exposes to the OS (the `UIKeyCommand` discoverability mechanism), which is named
and justified.

No entry in constitution.md's Patterns-in-use registry covers SwiftUI key-command
registration or size-class-conditional layout (the registry is React/TypeScript
and Python-service oriented), so no `Reuses pattern:` marker applies to the
components below. The design instead reuses *this app's own* existing action
flows, which is the load-bearing reuse and is called out per-shortcut.

---

## Resolved deferred question

Requirements deferred one question to architecture: **at which responder level
the key commands are registered** so that (a) the discoverability overlay
enumerates them, (b) they fire in both rendered and raw mode, and (c) ⌘P is not
swallowed by the raw `UITextView` while it is first responder. This design
resolves it (see Component A and Seam S-1): the commands are owned by a single
**editor-session-scoped key-command provider** that sits on the responder chain
*above* the SwiftUI editor surfaces but *inside* the presented editor session —
specifically on the presented `UIHostingController` (or an equivalent responder
the `BrowserHostController` installs when it presents the editor nav). Because
requirements.md's text already anticipated "a responder level where the overlay
can enumerate them and they are reachable in both modes," no requirement text
changes; only the stability marker is affected (see bottom).

---

## Part 1 — Hardware keyboard shortcuts

### Component A — EditorKeyCommandProvider (editor-session-scoped)

A single responder, installed by the host when (and only when) an editor session
is presented, that vends the four `UIKeyCommand`s and routes each to an existing
action. It is the only new "component" and it is a *router*, not an
implementation of any action.

**Why this level (the architectural decision).** The four actions already have
single, canonical homes:

| Action | Canonical home (existing) |
|--------|---------------------------|
| Toggle mode | `DocumentView`'s mode state + `switchTo` / eye-button / `switchToRenderedFromSwipe` logic |
| Return to browser | `DocumentView.onBack` → `BrowserHostController.dismissPresentedEditor()` |
| New document | `BrowserHostController.documentBrowser(_:didRequestDocumentCreationWithHandler:)` (system create flow) |
| Save | `DocumentView.triggerSave()` → `document.markDirty()` |

Two of these (toggle, save) live in SwiftUI `DocumentView` state; two (close,
new) live on the UIKit host. A key-command owner placed *inside* the SwiftUI tree
cannot reach the host create flow cleanly, and a `UITextView`-level
`keyCommands` override would not fire in rendered mode (no text view present) and
would entangle the shortcuts with first-responder churn. Placing the provider on
the **presented editor session's hosting responder** gives one owner that:

- is on the responder chain in *both* modes (it is above the mode-switched
  SwiftUI subtree), satisfying "honored in both modes" for all four commands;
- is above the raw `UITextView`, so the system delivers a matching ⌘-chord to
  this provider rather than letting the text view consume it as input
  (resolves the ⌘P-swallow risk, FM-3);
- exists only while an editor is presented, so editor-only commands naturally
  cease to exist at the browser (the ⌘W browser-edge case becomes structural,
  not a runtime guard).

**C-A.1 — Each command is a trigger onto an existing action, never a second
implementation.** The provider holds *references to the existing action
entry points* and invokes them unchanged. Observable property: a shortcut and
its existing UI counterpart (eye button, back button, browser create control,
background-save) produce byte-identical downstream effects, because they call the
same code. There is no alternate save, toggle, close, or create path. (FM-1, FM-9.)

**C-A.2 — Toggle (⌘P) reproduces the existing mode transition exactly, including
direction selection and scroll-anchor preservation.** ⌘P consults the *current*
`mode` and runs the same transition the screen would: rendered→raw seeds the raw
scroll anchor and sets `mode = .raw` (the tap-to-edit / `switchTo(.rendered,
target: .raw)` effect); raw→rendered seeds the rendered anchor from the raw
scroll fraction, triggers a save, and sets `mode = .rendered` (the eye-button /
`switchToRenderedFromSwipe` effect). Repeated presses alternate with no drift and
no second transition path. The VoiceOver announcement ("Editing mode" / "Preview
mode") is posted because the transition routes through the same call sites that
post it; initial-mode assignment still posts nothing. (AC-1.1–1.4, FM-1.)

> Seam note: because the toggle's direction and effects depend on `DocumentView`
> private state (`mode`, `rawScrollState`, the pending-anchor bindings), the
> *toggle action must be owned by `DocumentView`* and merely *invoked* by the
> provider. The provider does not read `mode` or seed anchors itself — doing so
> would be a parallel toggle path and is forbidden by FM-1. See Seam S-2.

**C-A.3 — Close (⌘W) reproduces the back-button/return-to-browser effect
exactly.** ⌘W invokes the same `onBack` the toolbar back button and the L→R swipe
invoke, which runs `dismissPresentedEditor()`: synchronous save before dismiss,
detector stopped, session torn down, browser visible. Unsaved edits are therefore
preserved (the existing flow saves synchronously); no discard prompt or save
confirmation is introduced. Honored in both modes. (AC-2.1–2.3, FM-1, FM-2.)

**C-A.4 — New (⌘N) reproduces the system create flow exactly.** ⌘N reaches the
host so the system template-copy create runs
(`didRequestDocumentCreationWithHandler`): empty `.md` template, system copy into
the browsed folder, system inline rename UI, open via the normal pick/import
path. Works while a document is already open (the request reaches the host, which
owns the browser). Cancelling the system rename/create UI returns the user to the
prior state with no file created and no crash — identical to cancelling a
browser-initiated create. No app-managed copy, naming scheme, or persistence is
added. (AC-3.1–3.3, FM-1, FM-9.)

**C-A.5 — Save (⌘S) reproduces the existing save flow exactly.** ⌘S invokes
`triggerSave()` → `document.markDirty()`, driving the existing autosave/bridge
write. No new toast, dialog, or status indicator. A write failure surfaces only
through the existing `SaveFailedAlertRouter` / `ActiveAlert.saveFailed`
lifecycle, unchanged. Honored in both modes; in rendered mode (no text editing)
it is a harmless no-op write when nothing is dirty; pressing it on a clean buffer
neither corrupts the buffer nor re-triggers a conflict nor produces a spurious
error. (AC-4.1–4.3, FM-1, FM-2.)

**C-A.6 — The four commands are enumerable by the discoverability overlay, with
stable, action-describing titles.** *This is the one place a call shape is the
public contract:* the iPad discoverability overlay is an OS mechanism that reads
each `UIKeyCommand`'s discoverability title from a responder on the chain when ⌘
is held. The contract is therefore "the four commands are vended, each carrying a
human-readable title, from a responder that is on the chain while the editor is
the active surface." Titles are distinct, describe the action not the
implementation (e.g. "Toggle Preview", "Close", "New Document", "Save"), and do
not change with mode even though ⌘P toggles direction internally. (AC-5.1, 5.2,
US-5.)

**C-A.7 — Registration is inert without a hardware keyboard and never disturbs
the existing UI.** The commands exist on every device but can only fire when a
key source delivers the chord; on a keyboard-less device they simply never
receive input. Their mere existence does not crash, alter layout, consume any
on-screen control, or disable any existing gesture (tap-to-edit,
swipe-to-rendered, swipe-to-browser, edge-pan dismiss). No device conditional is
needed. (AC-6.1, 6.2, FM-4.)

### Behavioral seams — Part 1

**S-1 — Provider lifetime is bound to the editor session, not the app.**
The provider comes into existence when the host presents the editor and ceases to
exist when the editor is dismissed. Observable consequences: (a) at the browser
with no editor presented, the four editor commands are absent, so ⌘W there is a
structural no-op that cannot crash, dismiss the browser, or leave a rootless app
(AC-2 edge case); (b) ⌘N *may* additionally be offered at the browser level so a
keyboard user can create from the browser (AC-5 edge case allows "⌘N at minimum"
there), but that is the browser's own create control re-triggered, not a second
create path — if offered, it routes to the same `didRequestDocumentCreationWithHandler`.

**S-2 — Toggle and Save actions are owned by `DocumentView` and exposed to the
provider as invocable handles, not reimplemented.** `DocumentView` already holds
the mode state, scroll-anchor bindings, and `triggerSave`. The behavioral
contract of the seam: the provider can *ask* DocumentView to "toggle" and to
"save," and DocumentView performs the identical transition/save it performs for
the eye button / back button. The seam carries an intent, not a recomputation;
DocumentView remains the single authority on direction, anchor seeding, and the
announcement. (Protects FM-1, FM-8-adjacent.)

**S-3 — Close and New actions are owned by the host and exposed to the provider
unchanged.** Close re-uses the *same* `onBack` closure DocumentView already
receives (which the host wires to `dismissPresentedEditor()`); New re-uses the
host's existing create-delegate entry. The provider holds these as the same
references the existing UI uses. (Protects FM-1, FM-9.)

**S-4 — A ⌘-chord that matches a registered command is claimed by the provider
before the raw `UITextView` treats it as text.** Because the provider sits above
the text view on the responder chain and the chord is a registered command, the
system routes it to the command rather than inserting a character. Observable
property: ⌘P (and ⌘W/⌘N/⌘S) with the keyboard up and the text view focused
performs its action and inserts no literal character. (AC-1 edge case, FM-3.)

---

## Part 2 — Editor line-length constraint (~700pt, centered, regular width only)

### Component B — RegularWidthContentColumn (a width-capping container applied to
both editor surfaces)

A layout treatment, applied identically to `RawEditorView`'s text surface and
`RenderedView`'s content, that caps usable content width at a shared maximum
(~700pt) and centers it horizontally **only** when the horizontal size class is
regular. It is a presentation-only container: it changes where content sits, not
what content is, and introduces no model, storage, or scroll-state change.

**C-B.1 — Single shared maximum width across both surfaces.** Both surfaces draw
from one shared width value, so the raw column and the rendered column occupy the
same width and the same horizontal position. Switching modes does not shift the
text column left/right or change its width. (AC-7.3, FM-8.)

**C-B.2 — The cap is governed by the SwiftUI horizontal size class, not by device
model.** In the *regular* horizontal size class the cap and centering apply; in
the *compact* horizontal size class neither applies and the surface fills the
available width exactly as today (iPhone byte-for-byte unchanged modulo Part 1's
inert command registration). Behavior keys on
`@Environment(\.horizontalSizeClass)`; the value is the named environment input
because it is the literal signal requirements specify, but the contract is the
behavioral one: "capped+centered when space is ample, full-width when not."
(AC-7.x, AC-8.1, 8.2, FM-5.)

**C-B.3 — The cap is a maximum, not a fixed width.** When the available width is
at or below the cap (a narrow-but-still-regular split view), content uses the full
available width with no artificial cap and no centering gutters; the gutters
appear only once available width exceeds the cap. At very wide widths (~1366pt
landscape iPad) the column stays at ~700pt and centered, with empty background on
both sides; no line of text stretches beyond ~700pt of usable column. (AC-7.4,
AC-7 edge case.)

**C-B.4 — The gutter is non-interactive background only; the full column is
usable and nothing is clipped.** The space on either side of the centered column
is background/padding that contains no text and hides no text. The full ~700pt is
available for text — the cap does not reserve part of that width as padding such
that the usable column is materially narrower than ~700pt. Long lines wrap within
the ~700pt column exactly as they would in a ~700pt viewport; a long unbreakable
token (e.g. a spaceless URL) is handled by whatever wrap/scroll behavior each
surface already uses at a 700pt width — the cap introduces no new clipping. In the
raw editor the caret, selection, and scrolling stay within the centered column;
no caret is rendered in or hidden behind a gutter. (AC-10.1–10.3, AC-10 edge
case, FM-6.)

> Seam note (raw editor): `RawEditorView` wraps a `UITextView`
> (`MarkdownTextViewBridge`). "Centered ~700pt column" must be realized as the
> *text container / usable text width*, not as an outer clip that hides
> characters. The behavioral guard is C-B.4: caret and selection must remain
> visible and the full column usable. Whether this is achieved by constraining
> the text view's content inset/container width or by centering the text view
> itself within a capped region is an implementation choice the build step makes,
> bounded by C-B.4 — the design fixes the observable property, not the mechanism.

### Behavioral seams — Part 2

**S-5 — The cap reads size class live and re-lays out in place on transition.**
A compact→regular transition (dragging out of Slide Over, rotating into
regular width) applies the cap+centering to whichever surface is showing, live,
without reopening the document and without losing scroll position or edit state.
A regular→compact transition removes the cap live, returning to full-width. The
update applies to the visible surface at the moment of transition. (AC-9.1, 9.2,
FM-7.)

**S-6 — Both surfaces independently observe the same size class, so a mode switch
after a transition shows the other surface already correct.** Because each
surface reads the size class itself (not a value snapshotted at open time), after
a size-class transition a subsequent mode switch renders the newly shown surface
at the correct width for the *current* size class — no stale cap, no reopen.
(AC-9.3, FM-8.)

**S-7 — The width treatment is purely presentational and orthogonal to scroll
and save.** Applying or removing the cap does not reset scroll position to the
top, does not discard unsaved edits, and does not interact with the
scroll-anchor preservation used by the mode switch. The cap changes horizontal
layout only. (FM-7.)

---

## Cross-cutting constraints

**X-1 — No new product surface.** No library, settings, toolbar button, save
button, save toast, discard prompt, or open shortcut is added. The only
user-visible additions are the discoverability-overlay entries (a system
affordance, not a Markus surface) and the centered column in regular width.
(Honors declaration Out-of-scope; FM-2.)

**X-2 — Out-of-scope items are structurally excluded, not merely unimplemented.**
No formatting shortcuts (⌘B/⌘I/⌘K), no ⌘/, no ⌘O, no conflict-sheet relayout, no
width cap in compact, no model/storage change. The provider vends exactly four
commands; the width container touches only horizontal layout of the two editor
surfaces.

**X-3 — Existing behavior is preserved.** Open/render/edit/save/conflict/
resume/detector behavior is unchanged. The conflict sheet, deletion banner,
share, and save-failed alert paths are untouched.

---

## Components → requirements traceability

| Component / seam | Requirements covered |
|------------------|----------------------|
| C-A.1, S-1, S-2, S-3 | FM-1, FM-9 (single existing-flow routing) |
| C-A.2, S-2, S-4 | US-1 / AC-1.1–1.4 + ⌘P edge case; FM-3 |
| C-A.3 | US-2 / AC-2.1–2.3; FM-2 |
| C-A.4 | US-3 / AC-3.1–3.3 + cancel edge case; FM-9 |
| C-A.5 | US-4 / AC-4.1–4.3 + clean-buffer edge case; FM-2 |
| C-A.6 | US-5 / AC-5.1–5.2 |
| C-A.7, S-1 | US-6 / AC-6.1–6.2 + browser-overlay/⌘W edge cases; FM-4 |
| C-B.1, S-6 | AC-7.3; FM-8 |
| C-B.2 | US-7/US-8 / AC-7.x, AC-8.1–8.2; FM-5 |
| C-B.3 | AC-7.4 + wide-window edge case |
| C-B.4 | US-10 / AC-10.1–10.3 + long-token edge case; FM-6 |
| S-5, S-7 | US-9 / AC-9.1–9.2; FM-7 |
| S-6 | AC-9.3; FM-8 |

---

## Requirements changes flagged

None. Every architectural decision is consistent with requirements.md as written;
the only deferred question (key-command registration level) was answered without
needing a text change, because the requirements text already framed it as an
architecture decision. The requirements.md stability marker is flipped to stable
in this pass for that reason.

**Architecture stable — no requirements changes flagged**
