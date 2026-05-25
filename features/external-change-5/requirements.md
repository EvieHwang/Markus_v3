# Requirements: external-change-5

Behavioral requirements for handling the three ways the currently-open file can change underneath Markus while it is open: (1) its content changes on disk, (2) it is moved or renamed, (3) it is deleted. Derived from `declaration.md` (project) and `features/external-change-5/declaration.md` (feature). Requirements are behavioral and stay independent of any specific implementation; references to `NSFileVersion`/`NSFileCoordinator` appear only where the declaration fixes them as a design constraint, not as test obligations.

## Definitions

These terms are used with fixed meaning throughout. Acceptance criteria reference them by name.

- **Open document** — the single `.md`/`.markdown` file currently presented in the editor (the file behind the active `DocumentView`). External-change handling applies to this file only.
- **Buffer** — the in-memory text of the open document (`MarkdownDocument.text`).
- **Clean buffer** — the buffer is byte-for-byte identical to the content Markus last wrote to, or last read from, disk for this document. Equivalent to "no unsaved local edits."
- **Dirty buffer** — the buffer differs from the content Markus last wrote to or read from disk (the user has unsaved local edits).
- **On-disk content** — the current bytes of the file at the followed location, as read back from disk.
- **Materially differs** — on-disk content is NOT equal to the buffer after newline normalization (CRLF/CR → LF) and trailing-whitespace-insensitive comparison is NOT required; the canonical comparison is: equal if byte-identical OR equal after newline normalization to LF. Any difference beyond newline encoding is "material."
- **Content-identical** — on-disk content equals the buffer either byte-for-byte or after newline normalization to LF.
- **True collision** — dirty buffer AND on-disk content materially differs AND iCloud has settled (see settle window).
- **Settle window** — a short, design-fixed grace period after a create, open, or save during which conflict signals are suppressed and allowed to resolve. The exact duration is a design decision (see open items), not a requirement value.
- **iCloud settled** — the file is not mid-download/mid-upload and no settle-window timer for the relevant event is active. (Detection mechanism is design's concern; the behavioral test is "no prompt while a sync is in flight.")
- **Conflict sheet** — the modal three-option UI: **Keep Mine**, **Keep Theirs**, **Discard Mine**.
- **Deletion banner** — the non-modal, non-destructive surface offering **Save As** when the open document is deleted on disk.

---

## User stories and acceptance criteria

### BR-1 — Silent absorption when buffer is clean
**As a** user whose open file is changed on another device,
**when** my buffer has no unsaved edits,
**so that** I am never interrupted for a change I have no stake in,
**I want** the new content adopted silently.

Acceptance criteria:
- BR-1.1 Given a clean buffer and an external content change to the open document, no conflict sheet appears.
- BR-1.2 After absorption, the buffer reflects the new on-disk content (the user sees the externally-changed text).
- BR-1.3 After absorption, the buffer is clean with respect to the newly-adopted content (a subsequent save would be a no-op against disk).
- BR-1.4 No toast, alert, or banner is shown for this absorption (silent means silent).
- BR-1.5 Absorption occurs in both rendered and raw mode without losing the current editing mode.

### BR-2 — Silent absorption when on-disk content is content-identical
**As a** user with unsaved edits that happen to match what landed on disk,
**when** the external content equals my buffer,
**so that** an echo of my own save (or a coincidentally-identical change) never prompts me,
**I want** the change resolved silently even though my buffer is dirty.

Acceptance criteria:
- BR-2.1 Given a dirty buffer and an external change whose on-disk content is byte-for-byte identical to the buffer, no conflict sheet appears.
- BR-2.2 Given a dirty buffer and an external change whose on-disk content equals the buffer after newline normalization to LF, no conflict sheet appears.
- BR-2.3 In both BR-2.1 and BR-2.2 the buffer and the user's cursor/scroll position are preserved (no reload that disrupts editing).
- BR-2.4 No toast, alert, or banner is shown.

### BR-3 — Settle-window suppression of spurious signals
**As a** user who just created or saved a file in iCloud Drive,
**when** sync churn produces change signals while iCloud is still settling,
**so that** I am not prompted by my own just-completed action,
**I want** those signals suppressed until state settles.

Acceptance criteria:
- BR-3.1 A change signal that arrives within the settle window after a create does not produce a conflict sheet.
- BR-3.2 A change signal that arrives within the settle window after a local save does not produce a conflict sheet.
- BR-3.3 A change signal that arrives while the file is mid-download or mid-upload from/to iCloud does not produce a conflict sheet.
- BR-3.4 Once the settle window elapses and iCloud is settled, a still-present true collision (BR-4) is evaluated and surfaced; suppression delays evaluation, it does not permanently discard a real collision.
- BR-3.5 Creating a new file, typing, and saving (the normal single-device create flow) produces zero conflict sheets and zero deletion banners.
- BR-3.6 Ordinary single-device editing and saving in a loop produces zero conflict sheets.

### BR-4 — Conflict sheet on a true collision
**As a** user with unsaved edits that genuinely diverge from what another device wrote,
**when** a true collision exists,
**so that** I — the only authority — decide the outcome,
**I want** exactly the three-option conflict sheet, with no silent merge.

Acceptance criteria:
- BR-4.1 The conflict sheet appears if and only if: dirty buffer AND on-disk content materially differs AND iCloud is settled. (If any of the three is false, no sheet — cross-checked against BR-1, BR-2, BR-3.)
- BR-4.2 The sheet presents exactly three options: Keep Mine, Keep Theirs, Discard Mine. No "merge" option exists.
- BR-4.3 The sheet is modal enough that the open document is not silently overwritten by either side while the choice is pending (no resolution happens without the user's tap).
- BR-4.4 At most one conflict sheet is presented at a time for the open document; further collision signals while a sheet is pending do not stack additional sheets.

### BR-5 — Conflict resolution: Keep Mine
**As a** user who chooses Keep Mine,
**so that** my version wins,
**I want** my buffer written to disk at the followed location.

Acceptance criteria:
- BR-5.1 After Keep Mine, the followed file's on-disk content equals the buffer (newline-normalization-permitting per the save path).
- BR-5.2 After Keep Mine, the buffer is unchanged and becomes clean against disk.
- BR-5.3 The conflict sheet is dismissed and editing resumes in the same mode.

### BR-6 — Conflict resolution: Keep Theirs
**As a** user who chooses Keep Theirs,
**so that** the external version wins,
**I want** the on-disk content loaded into the buffer, discarding my edits.

Acceptance criteria:
- BR-6.1 After Keep Theirs, the buffer equals the on-disk content that triggered the collision.
- BR-6.2 After Keep Theirs, the buffer is clean against disk; no write that would clobber the external content is performed.
- BR-6.3 The conflict sheet is dismissed and editing resumes in the same mode.

### BR-7 — Conflict resolution: Discard Mine
**As a** user who chooses Discard Mine,
**so that** I abandon my local edits and take what is on disk,
**I want** my edits dropped and the on-disk content adopted.

Acceptance criteria:
- BR-7.1 After Discard Mine, the buffer equals the current on-disk content (behaviorally the same end-state as Keep Theirs).
- BR-7.2 No local edits remain; the buffer is clean against disk.
- BR-7.3 The conflict sheet is dismissed and editing resumes in the same mode.

> Note: Keep Theirs and Discard Mine produce the same end-state (adopt disk, drop local). Both options are retained because the declaration's success criteria and the project declaration name the three-option set verbatim; the distinction is intent/labeling, not divergent behavior. Flagged for architectural confirmation in the open items below.

### BR-8 — Follow on move / rename
**As a** user whose open file is moved or renamed on disk,
**when** the file relocates,
**so that** my editing session is uninterrupted,
**I want** the session to continue against the new location and saves to write there.

Acceptance criteria:
- BR-8.1 After the open document is moved or renamed externally, no conflict sheet and no deletion banner appear solely because of the move (a move alone is not a collision and is not a deletion).
- BR-8.2 After a move/rename, a subsequent save writes to the new location, not the old path, and does not recreate a file at the old path.
- BR-8.3 The editor's displayed title updates to reflect a rename when the change is a rename. (Title source is `fileURL.lastPathComponent`; a rename must propagate to it.)
- BR-8.4 A move that also carries a content change is evaluated for collision at the new location using the same rules (BR-1/BR-2/BR-4); the move itself does not suppress a genuine collision.
- BR-8.5 The last-opened reference used for resume is updated to the new location so a later relaunch resumes the moved file, not the stale path.

### BR-9 — Deletion surfaces a recoverable banner
**As a** user whose open file is deleted on disk,
**when** the file disappears,
**so that** I do not silently lose unsaved work,
**I want** a non-destructive banner offering Save As.

Acceptance criteria:
- BR-9.1 When the open document is deleted on disk, a deletion banner appears offering Save As.
- BR-9.2 The banner does NOT discard the buffer; the buffer remains intact and editable while the banner is shown.
- BR-9.3 The app does not silently recreate the deleted file at its old path on the next autosave (deletion must not be undone behind the user's back).
- BR-9.4 Choosing Save As lets the user write the current buffer to a new location; on success the editing session continues against that new location and the deletion banner dismisses.
- BR-9.5 A deletion that is actually a move (the file reappears at a new location via the follow-on-move path within the settle window) is treated as a move (BR-8), not a deletion — no deletion banner for a move.
- BR-9.6 If the user dismisses the banner without choosing Save As, the buffer is still not lost (it remains in memory; no forced data loss).

### BR-10 — Detection basis (constraint, not behavior)
This requirement records a declaration-fixed design constraint so downstream stages do not regress it. It is verified by design review, not by a behavioral test.
- BR-10.1 External-change, move, and deletion detection is based on `NSFileVersion`/`NSFileCoordinator` coordination rather than interpreting raw `UIDocument.documentState` bits as the source of truth. (The existing `SaveStatusObserver`'s use of `documentState` for download/save-error reporting is permitted to remain for those purposes; it must not be the collision-detection authority.)

---

## Edge cases and failure modes

- BR-11 **Empty-file and whitespace-only changes.** A change from non-empty to empty (or vice versa) on disk is a material difference and, with a dirty buffer, is a true collision. An external change that only alters newline encoding (CRLF↔LF) is content-identical and absorbed silently (BR-2.2).
- BR-12 **Rapid successive external changes.** Multiple external changes arriving in quick succession while a single collision is pending do not produce multiple stacked sheets (BR-4.4); the most recent settled on-disk content is the one compared and, on resolution, acted upon.
- BR-13 **Invalid UTF-8 lands on disk.** If the external content cannot be decoded as UTF-8, Markus does not crash and does not silently overwrite it; the buffer is preserved and the existing invalid-encoding failure path (an alert) is reused rather than a conflict sheet. (Consistency check: `MarkdownDocument` throws `DocumentError.invalidEncoding`; `ActiveAlert.invalidEncoding` already exists.)
- BR-14 **Save failure during a resolution.** If writing the resolved content fails (Keep Mine / Save As), the buffer is preserved and the existing save-failure alert path is used (`ActiveAlert.saveFailed`, "Your edits are still in memory…"). The conflict is not falsely marked resolved.
- BR-15 **Backgrounding mid-conflict.** If the app is backgrounded while a conflict sheet or deletion banner is showing, the pending choice is not auto-resolved in a way that loses the buffer; on return the user can still complete the choice (or the buffer is preserved if the sheet was dismissed by the system).
- BR-16 **Move + delete race.** If signals for both a move and a deletion arrive, the file's actual resolvable presence at a location wins: if the file is resolvable at a new location, treat as move (BR-8); if it is genuinely absent, treat as deletion (BR-9). No double-prompt.
- BR-17 **Document not yet persisted (deferred-write create).** A freshly created file that has not yet been written to disk (deferred-write create flow) is not subject to deletion detection (there is nothing on disk to delete) and the settle window covers the create (BR-3.1). No deletion banner fires for a never-persisted new document.
- BR-18 **Closed / backgrounded document.** External-change handling applies only while the document is the open document. Changes to files that are not currently open produce no UI (consistent with the feature's out-of-scope statement on non-open files).

---

## Concurrency integrity (apply-edge guarantees)

These requirements constrain the *moment of action* — when an external-change outcome is applied to the buffer or the disk — independent of how detection is implemented. They exist because detection and classification may occur on a snapshot of state that is no longer current by the time the action lands. They are behavioral and testable: each asserts an observable end-state (no edit lost, no clobber), not a mechanism.

### BR-19 — Absorption never discards edits made after the read snapshot
**As a** user who is actively typing when an external change is absorbed,
**when** my buffer changes between the moment the disk content was read and the moment absorption is applied,
**so that** silent absorption can never silently destroy work I just typed,
**I want** the absorb decision re-validated against my current buffer before any buffer mutation, never applied against a stale snapshot.
*Addresses adversarial F-001 (requirements portion).*

Acceptance criteria:
- BR-19.1 If the buffer was clean when an external change was read but became dirty (the user typed) before absorption is applied, the clean-buffer absorb path (BR-1) does NOT run: the just-typed edits are not overwritten. The change is re-evaluated against the now-dirty buffer using the standard rules (BR-2/BR-4): it is absorbed silently only if content-identical, otherwise it surfaces a conflict sheet — it is never silently adopted over the edits.
- BR-19.2 No external-change resolution (absorb, Keep Theirs, Discard Mine) ever discards buffer edits the user made after the on-disk content used for that resolution was read. The end-state observable: any character the user typed after the read snapshot is either preserved or is the subject of an explicit user choice — never silently lost.
- BR-19.3 The content-identical absorb path (BR-2) likewise compares against the buffer as it stands at the moment of application; if the buffer diverged from content-identical in the interim, the change is re-evaluated rather than applied as a silent no-op.
- BR-19.4 Re-validation introduces no new prompt for the safe cases: if the buffer is genuinely unchanged since the read (the common case), absorption proceeds silently exactly as in BR-1/BR-2 — re-validation must not create spurious sheets.

### BR-20 — No write to disk while a collision is classified-but-unresolved
**As a** user for whom a true collision has been detected,
**when** the collision has been classified but the conflict sheet has not yet appeared (or is pending resolution),
**so that** Keep Theirs / Discard Mine can actually recover the external content,
**I want** autosave and any save-back suspended from the moment the collision is classified, not merely from the moment the sheet is presented.

Acceptance criteria:
- BR-20.1 From the instant a collision is classified for the open document until the user resolves it, no autosave or save-back writes the buffer to the followed location. The disagreeing on-disk content that the collision is about remains intact and recoverable via Keep Theirs / Discard Mine. *Addresses adversarial F-002 (requirements portion); strengthens BR-4.3.*
- BR-20.2 The suspension covers the latency gap between classification and sheet presentation: a save that was queued or debounced before classification does not fire during this gap and overwrite the external content.
- BR-20.3 Equivalently, when a deletion is classified, no autosave recreates the file at the vanished path during the gap before the deletion banner is presented (strengthens BR-9.3, extending it from "on the next autosave" to "from the instant deletion is classified").
- BR-20.4 Suspension lifts only on explicit resolution: Keep Mine performs the single deliberate write (BR-5), while Keep Theirs / Discard Mine / Save As perform no write that clobbers the content the collision was about. Normal autosave resumes only after the collision (or deletion) is resolved.

---

## Out of scope (restating and sharpening the declaration)

- OOS-1 No version history or browsing past versions — only the live divergence is resolved.
- OOS-2 No automatic or line-level content merge — resolution is whole-file (Keep Mine / Keep Theirs / Discard Mine).
- OOS-3 No conflict or change handling for files other than the currently-open document; no background or batch reconciliation.
- OOS-4 No new settings or toggles — settle-window duration and normalization rules are fixed by design.
- OOS-5 No changes to the rendered or raw editing surfaces themselves; this feature is the file lifecycle around them.
- OOS-6 Full accessibility labeling (VoiceOver/Dynamic Type semantics) of the conflict sheet and deletion banner is deferred to the Roadmap #7 accessibility pass; the controls must exist and function here.
- OOS-7 No file types beyond `.md`/`.markdown` (inherited from the project declaration).

---

## Consistency notes and tensions

- **No-silent-merge is honored.** The project declaration's "No silent merge on conflict" and "user is the only authority" are reflected directly in BR-4 (explicit three-option choice) and OOS-2.
- **Silent absorption vs. "user is the only authority."** Absorbing a clean-buffer change (BR-1) does not violate user-authority: with no unsaved edits, there is nothing of the user's to overwrite, so adopting disk content is the only non-destructive outcome. This is an intentional, declaration-aligned reading, not a contradiction.
- **Keep Theirs vs. Discard Mine equivalence** (see BR-7 note) is the one place where the three named options do not map to three distinct behaviors. The declaration names all three verbatim, so requirements keep all three; whether to collapse them or keep distinct labels for clarity is a design/UX call flagged below.
- **`SaveStatusObserver` role.** The existing observer reads `documentState` for iCloud-download and save-error signals. BR-10 permits this to continue for those narrow purposes but forbids it being the collision-detection authority. This is a potential implementation seam tension (two sources observing document state) that design must reconcile.

---

## Architectural feedback

The following need architectural resolution before requirements can be marked fully stable:

1. **Settle-window duration and trigger set.** Requirements fix the *behavior* (suppress within the window after create/open/save and while sync is in flight) but deliberately leave the numeric duration and the precise set of trigger events to design. Design must pin these so the spec tests have concrete timing to assert against (BR-3). Until then, BR-3 tests can only assert "suppressed during in-flight sync" and "evaluated after settle," not a specific millisecond bound.

2. **Keep Theirs vs. Discard Mine behavioral distinction (BR-6/BR-7).** The two options currently resolve to the same end-state. Design/UX must decide whether they remain two labels for one behavior (and justify the redundancy to the user) or whether one carries a distinct effect (e.g., Discard Mine = local discard with no on-disk read echo). This affects how many distinct outcomes the tests assert.

3. **Move detection vs. deletion detection disambiguation window (BR-9.5 / BR-16).** Whether a "file gone" signal should wait a bounded interval to see if it reappears as a move, and how long, is unspecified here and must be a design decision so BR-9.5/BR-16 are testable without flakiness.

4. **Reconciliation of the two state observers (BR-10 / consistency note).** Design must specify how the new `NSFileVersion`/`NSFileCoordinator`-based detector and the existing `SaveStatusObserver` coexist without double-counting or racing.

These are scoping/timing decisions, not contradictions in intent. The behavioral surface above is complete; only the four parameters/decisions above must be pinned by design and fed back into the BR-3, BR-6/BR-7, BR-9, and BR-10 acceptance criteria.

### Apply-edge guarantees added in the adversarial revision pass

5. **Re-validation of the absorb/collision classification at the apply edge (BR-19).** Requirements now fix the *behavior* — an absorb decision must be re-validated against the current buffer before any buffer mutation, and edits typed after the read snapshot are never silently lost (BR-19). The *mechanism* (where the main-actor re-check sits in the classify→act flow, and how a buffer that turned dirty mid-read re-derives its outcome) is an architecture concern. Design must add a constraint making this an observable property anchored to BR-1.1/BR-2.3/BR-19. *Addresses adversarial F-001 (architecture portion).*

6. **Autosave suspension keyed to classification, not presentation (BR-20).** Requirements now fix the *behavior* — autosave/save-back is suspended the instant a collision (or deletion) is classified, closing the classification→presentation latency gap (BR-20). The *mechanism* (latching the outcome at classification and gating the save bridge on it, rather than on sheet/banner presentation) is an architecture concern; DC-14/DC-16 currently scope suspension to "while the surface is up" and must be tightened. Design must specify this and anchor it to BR-4.3/BR-9.3/BR-20. *Addresses adversarial F-002 (architecture portion).*

Items 5 and 6 above are now resolved by design.md: re-validation at the apply edge (DC-21, addressing F-001 architecture portion, anchoring BR-19) and autosave suspension keyed to classification rather than presentation (DC-22, tightening DC-14/DC-16, addressing F-002 architecture portion, anchoring BR-20). Items 1–4 remain resolved by design.md as before. No requirement text changed in either pass.

Requirements stable — no architectural feedback to incorporate
