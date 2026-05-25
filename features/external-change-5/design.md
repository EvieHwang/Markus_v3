# Design — External Change Handling

*Architecture for `external-change-5`. Source of truth for intent: `features/external-change-5/declaration.md`; behavior: `features/external-change-5/requirements.md`. Every constraint below (DC-n) is phrased as an observable property of the running system — what the user or the system can detect — not as a call signature, attribute name, or library API detail. Where a name appears, it is a public interface this project exposes to its own callers (the host, the editor) and is marked as such.*

**Deferred-question resolution:** This design resolves all four architecture-flagged questions from `requirements.md`:
- (1) settle-window duration and triggers → §Settle Window, DC-6/DC-7
- (2) Keep-Theirs vs Discard-Mine behavioral equivalence → §Conflict Resolution, DC-13
- (3) move-vs-deletion disambiguation timing → §Presence Disambiguation, DC-16
- (4) reconciliation of the new detector with `SaveStatusObserver` → §Two Observers, DC-3

None of the four resolutions required changing any requirement *text* — they pin values and relationships the requirements deliberately deferred.

**Revision-pass resolution (this step).** This pass also resolves the two architecture-flagged apply-edge items in `requirements.md`:
- (5) re-validation of the absorb/collision classification at the apply edge → §Apply-edge integrity, DC-21 (addresses adversarial F-001 architecture portion, anchors BR-19).
- (6) autosave suspension keyed to classification rather than presentation → §Apply-edge integrity, DC-22, with DC-14/DC-16 tightened (addresses adversarial F-002 architecture portion, anchors BR-20).

Neither item required changing any requirement *text* — BR-19/BR-20 already fix the behavior; this pass supplies the mechanism that makes them verifiable. It also resolves the adversarial **prescription feedback** by restating the flagged implementation names and the debounce value as the behavioral properties they protect (see §Prescription-feedback resolution). Accordingly the requirements bottom marker remains "Requirements stable — no architectural feedback to incorporate."

---

## Ground-truth check (resolved before drafting)

- **Seams consulted (read before drafting):** `MarkdownDocument`, `SaveStatusObserver`, `ActiveAlert`, `DocumentError`, `BrowserHostController`, `MarkdownDocumentSaveBridge`, `SceneDelegate`, `DocumentView`, `AutosaveCoordinator`, `LastFileStore`, `CreateDocumentHandler`, `ToastModifier`.
- **Inherited architecture:** the app is no longer a SwiftUI `DocumentGroup` app. `resume-and-create-2` replaced the host with `BrowserHostController` (a `UIDocumentBrowserViewController` subclass) that owns the open path (`presentDocument(at:)`) and a per-document `MarkdownDocumentSaveBridge` that watches `MarkdownDocument.$text` and writes the file atomically on a 500ms idle debounce. There is no `DocumentGroup` machinery watching the file for us; **all** file observation in this feature is code we own.
- **Concurrency:** Swift 6 strict concurrency. The detector, the document-model additions, and all UI live `@MainActor` (they read/write `MarkdownDocument.text` and present UI). File coordination work that must run off-main is dispatched through the coordinator and its results are hopped back to the main actor before touching the buffer or UI.
- **Pattern reuse from constitution.md:** constitution.md registers Python/React patterns only; it holds no iOS patterns. So nothing here is marked `Reuses pattern: [constitution name]`. Where this design reuses an *in-repo* iOS seam established by an earlier feature, it cites it as `Reuses seam: [name]` or `Extends seam: [name]`.

---

## High-level shape

One new owned component — the **change detector** — sits beside the existing save bridge, under the editor, owned by the host for the lifetime of one presented document. It is the single authority on "what is happening to the open file on disk." It coordinates reads through the file-coordination layer, classifies each settled disk state into exactly one of four *outcomes* — **absorb**, **collision**, **moved**, **deleted** — and hands that outcome to the document model (for the buffer) and to the editor (for any UI). It never decides UI directly; it emits a classified outcome and the editor maps outcomes to surfaces.

The three Shape seams map to three responsibilities:

- **File access layer** — the change detector: coordinated reads, settle-window suppression, in-flight-sync suppression, follow-on-move (including updating the followed location and the resume reference), and deletion detection. *Primary seam.*
- **Document model** — `MarkdownDocument` gains a notion of **last-known-disk state** so clean/dirty and the content-equality gate are answerable without re-reading disk on every keystroke. *Extends `MarkdownDocument`.*
- **Conflict & lifecycle UI** — `DocumentView` gains a conflict sheet (three options) and a deletion banner (Save As), each driven by detector outcomes. *Extends `DocumentView`.*

---

## Components

### 1. Change detector (File access layer) — *primary*

The detector is the owned component the requirements call for in BR-10. It is created when the host presents a document and torn down when that document is dismissed; exactly one is live at a time, observing only the open document (BR-18, OOS-3).

**Public interface this project exposes:** the detector is constructed by `BrowserHostController.presentDocument(at:)` alongside the save bridge, given the same followed `URL` and the same `MarkdownDocument`. It exposes one outbound channel to the editor: a stream of classified **outcomes** (`absorb`, `collision`, `moved`, `deleted`) plus, for `absorb`/`collision`/`moved`, the settled on-disk content and the current followed location. This is named because `DocumentView` is the caller that must bind to it; the four outcome cases are the contract the UI and the document model both depend on.

**DC-1 — Single detection authority.** Detection of content change, move/rename, and deletion of the open document is grounded in coordinated file access and version observation, not in interpreting raw document-state bits as the source of truth (BR-10). The behavioral property: if a collision sheet, deletion banner, or silent absorption occurs, it is because a *coordinated read of the followed file* established the disk state — never because a transient document-state flag was sampled.

**DC-2 — Coordinated, never-torn reads.** Every comparison of disk against buffer reads the file under coordination so a read never observes a half-written file mid-sync. The property: Markus never classifies a partially-written or being-replaced file as a material difference; a change is only ever evaluated against a settled, whole file.

**DC-4 — Outcomes are exclusive and ordered by presence.** For any settled disk state the detector emits exactly one outcome. Presence is resolved first: if the followed file (or its moved successor) is resolvable, the outcome is `absorb`, `collision`, or `moved`; only a file that is genuinely absent yields `deleted` (BR-16). A move never also fires a deletion, and a deletion never fires while the file is resolvable elsewhere.

**DC-5 — Quiescence while a choice is pending.** Once the detector has emitted a `collision` (sheet up) or `deleted` (banner up), it does not emit a second competing outcome for the same document until the user resolves the current one. Later disk changes update the *content to be compared/acted upon* but do not stack a second sheet or banner (BR-4.4, BR-12). The property the user sees: at most one conflict sheet and at most one deletion banner at a time.

### 2. Two observers — reconciling the detector with `SaveStatusObserver` (DEFERRED QUESTION 4)

**DC-3 — `SaveStatusObserver` keeps its narrow job; the detector owns collisions.** `SaveStatusObserver` continues to do exactly what it does today and nothing more: read document-state bits to drive the "downloading from iCloud" loading view and to surface save-error and invalid-download alerts. It is **never** consulted to decide whether a collision, move, or deletion exists. The two observers do not race because they answer different questions and feed different surfaces:

- `SaveStatusObserver` answers "is the system busy with this file right now?" → loading view + save/download alerts.
- The detector answers "has the file's settled content/identity/presence changed relative to my buffer?" → absorb / sheet / banner.

The detector *consumes* the busy signal as one input to its settle gate (it will not classify while the system reports the file mid-download/mid-upload, DC-7) but it does not delegate the collision decision to it. The behavioral guarantee against double-counting: a single external change produces at most one user-visible response — either the loading view (busy) or, once settled, exactly one detector outcome. The two never both fire a prompt for the same change. *Reuses seam: `SaveStatusObserver` (unchanged, scope-narrowed by contract).*

### 3. Settle window (File access layer) (DEFERRED QUESTION 1)

**DC-6 — Settle window: 2 seconds, opened by create / open / local save.** The settle window is a fixed **2-second** grace period. It opens (or re-opens, resetting the 2s) on exactly three triggers, all of which are actions Markus itself just took or just observed completing:
1. a document is first opened/presented (the open path),
2. a deferred-write create first persists to disk (the file first appears),
3. a local save completes (the save bridge finishes a write).

While the window is open, the detector suppresses classification of *change* and *deletion* signals for that document (it does not emit `collision`, `absorb`, or `deleted`). The duration is fixed by design with no setting (OOS-4). Rationale for 2s: long enough to cover the round-trip churn iCloud generates when echoing a just-completed local write back as an "external" change (the dominant false-positive source named in the feature declaration), short enough that a genuine collision arriving after the user's own action settles is surfaced promptly (BR-3.4). The save trigger specifically defeats the self-echo: Markus's own 500ms-debounced write is followed by sync churn that would otherwise read back as an external change.

**DC-7 — In-flight sync suppression is independent of the timer.** Independently of the 2s timer, the detector does not classify a change or deletion while the system reports the followed file mid-download or mid-upload (the busy signal from DC-3). The property: no sheet and no banner ever appears while a sync is in flight; suppression here is keyed to the *system's own busy state*, not to the timer, so a slow sync that outlasts 2s is still suppressed until it actually settles.

**DC-8 — Suppression delays, never discards.** When the window closes (timer elapsed *and* sync settled), the detector re-evaluates the current settled disk state against the current buffer and emits the appropriate outcome. A real collision that was suppressed during the window is therefore still surfaced after it (BR-3.4). The property: suppression can only postpone a prompt, never silently swallow a true collision.

### 4. Document model — last-known-disk state (Document model)

**DC-9 — `MarkdownDocument` carries its last-known-disk content.** `MarkdownDocument` gains a last-known-disk-content value: the bytes Markus last *wrote to* or last *read from* disk for this document. This is the single reference both for clean/dirty and for the content-equality gate. *Public interface:* the save bridge updates it after a successful write; the detector updates it after an absorb or a resolution; the document model derives clean/dirty from it. Named because three owned components read and write it.

**DC-10 — Clean/dirty is a buffer-vs-last-known-disk comparison, not an undo flag.** A buffer is *clean* when it equals the last-known-disk content (DC-9), *dirty* otherwise (per the requirements' definitions). This replaces "dirty = the undo manager registered an edit" as the authority for conflict decisions. The property: a buffer that the user typed into and then manually reverted to exactly the disk content is treated as clean for collision purposes (no sheet), because what matters is content divergence, not edit history.

**DC-11 — Content-equality gate.** Two contents are *equal* iff they are byte-identical OR equal after newline normalization (CRLF/CR → LF). The detector applies this gate to (on-disk content, buffer) to decide absorb-vs-collision, and the document model applies it to (buffer, last-known-disk) to decide clean-vs-dirty. The property: a change that only re-encodes line endings is never material — it never produces a sheet (BR-2.2, BR-11); any difference beyond newline encoding is material (an empty↔non-empty change is always material, BR-11).

**DC-12 — Absorb preserves the editing surface.** When the detector resolves to `absorb` (clean buffer, BR-1; or content-identical dirty buffer, BR-2), it adopts the new on-disk content and resets last-known-disk to it, leaving the buffer clean — without tearing down or reloading the editor in a way that loses the current mode, cursor, or scroll position (BR-1.5, BR-2.3). For a clean buffer the visible text updates to the new content; for a content-identical dirty buffer the visible text and cursor are untouched (they already match).

### 5. Conflict & lifecycle UI (Conflict & lifecycle UI)

The editor maps detector outcomes to surfaces. The three pre-existing alert paths (`saveFailed`, `invalidEncoding`, `iCloudDownloadFailed`) are unchanged and remain the response for their own failure modes (BR-13, BR-14). *Extends seam: `DocumentView` + `ActiveAlert`.*

**DC-14 — Conflict sheet appears iff true collision.** A modal three-option sheet (Keep Mine / Keep Theirs / Discard Mine) appears if and only if the detector emits `collision`: dirty buffer AND on-disk content materially differs AND settled (BR-4.1). It offers exactly those three options and no "merge" (BR-4.2, OOS-2). From classification onward, neither side overwrites the document without the user's tap (BR-4.3): autosave/save-back is suspended from the instant `collision` is classified — not merely while the sheet is on screen — per DC-22, and the detector does not adopt disk into the buffer, until the user chooses. At most one sheet is up at a time (BR-4.4, DC-5).

**DC-15 — Sheet survives backgrounding without auto-resolving.** If the app is backgrounded while the sheet (or banner) is up, the pending choice is not auto-resolved in a way that loses the buffer; on return the user can still complete the choice, and if the system dismissed the surface the buffer is preserved in memory (BR-15). The property: backgrounding never silently picks a winner.

**DC-16 — Deletion banner appears only after presence disambiguation (DEFERRED QUESTION 3).** A "file gone" signal does not immediately produce a deletion banner. The detector waits a bounded **2-second** disambiguation interval (matching the settle window, DC-6) to see whether the file reappears at a new resolvable location via the follow-on-move path. If it reappears within that interval, the outcome is `moved` (BR-8) and **no** deletion banner shows (BR-9.5, BR-16). If the file is still genuinely absent after the interval, the outcome is `deleted` and the non-modal banner appears offering Save As (BR-9.1). Rationale for 2s and for reusing the settle value: iCloud commonly expresses a move as a delete-then-recreate; 2s covers that round-trip while keeping a true deletion's banner prompt. The banner does not discard the buffer (BR-9.2), the app does not silently recreate the deleted file (BR-9.3): save-back to the vanished path is suspended from the instant `deleted` is classified, including the gap before the banner appears, per DC-22 — and dismissing the banner without Save As still preserves the buffer in memory (BR-9.6).

**DC-17 — Save As continues the session at the new location.** Choosing Save As writes the current buffer to a user-chosen new location; on success the editing session continues against that new location (it becomes the followed location, the save bridge and detector retarget to it, and the resume reference is updated), last-known-disk is reset to the just-written content, and the banner dismisses (BR-9.4). If the Save As write fails, the existing save-failure alert path is used and the banner is not falsely cleared (BR-14).

**DC-18 — Never-persisted creates are exempt from deletion.** A freshly created, deferred-write document that has not yet been written to disk is not subject to deletion detection (there is nothing on disk to delete) and the settle window covers the create; no deletion banner fires for a never-persisted new document (BR-17).

### 6. Follow-on-move (File access layer)

**DC-19 — Moves are followed transparently.** When the open file is moved or renamed on disk, the detector emits `moved`: the followed location updates to the new location, subsequent saves write there and do not recreate a file at the old path (BR-8.2), the editor's displayed title reflects a rename (it is derived from the followed location's last path component, BR-8.3), and the resume reference is updated to the new location (BR-8.5). A move alone produces neither a sheet nor a banner (BR-8.1). *Reuses seam: `LastFileStore.recordLastOpened` for the resume-reference update — the same hook the host already calls on open.*

**DC-20 — A move carrying a content change is still gated.** If a move arrives together with a content change, the collision rules (DC-11/DC-14) are applied to the buffer against the on-disk content *at the new location*; the move does not suppress a genuine collision (BR-8.4). The property: relocating a file is never a way to smuggle an overwrite past the user.

---

## Apply-edge integrity (concurrency at the moment of action)

*These two constraints close the two HIGH adversarial findings. Both are stated as observable end-state properties — what the user can never lose, and what the disk can never gain — independent of which actor or queue the work runs on. They constrain the **moment an outcome is applied**, not how detection samples state. Addresses adversarial F-001, F-002.*

**DC-21 — An outcome is re-validated against the live buffer before any mutation; an absorb never overwrites edits made after the read. (Addresses adversarial F-001; anchors BR-19.)** A classification (`absorb` / `collision`) is derived from the buffer as it stood when the coordinated read began, but it is never *applied* against that historical snapshot. Before any buffer mutation occurs, the outcome is re-derived against the buffer as it stands at the instant of application. The behavioral properties:

- If the buffer was clean at read time but the user typed before the outcome is applied, the clean-buffer absorb (DC-12, BR-1) does **not** run over those edits. The change is re-evaluated against the now-dirty buffer using the standard equality gate (DC-11): content-identical → silent absorb (BR-2), otherwise → `collision` sheet. The just-typed characters are never silently discarded (BR-19.1, BR-19.2).
- The content-identical absorb path is likewise compared against the buffer *as it stands at application*, not at read time; if it diverged in the interim it is re-evaluated rather than applied as a stale no-op (BR-19.3).
- No external-change resolution (absorb, Keep Theirs, Discard Mine) ever drops a character the user typed after the on-disk content used for that resolution was read: every such character is either preserved or is the subject of an explicit user choice (BR-19.2).
- Re-validation adds no prompt to the safe path: when the buffer is genuinely unchanged since the read — the common case — absorption proceeds silently exactly as DC-12 (BR-19.4). The property is "no silent loss," not "more sheets."

The observable test surface: stage a clean buffer, begin an external change, mutate the buffer before the outcome lands, and assert the typed edits survive (preserved or surfaced as a collision) — never silently replaced.

**DC-22 — Save-back is suspended from the instant a collision or deletion is *classified*, not from when its surface appears. (Addresses adversarial F-002; tightens DC-14/DC-16, anchors BR-20.)** The mutual exclusion between save-back and the detector is keyed to the *classified outcome*, not to the presence of a sheet or banner on screen. The behavioral properties:

- From the moment the detector classifies `collision` (or `deleted`) for the open document until the user resolves it, no autosave or save-back writes the buffer to the followed (or vanished) location. The disagreeing on-disk content the collision is about stays intact and recoverable via Keep Theirs / Discard Mine (BR-20.1).
- The suspension covers the latency gap between classification and surface presentation: a save that was queued or idle-debounced before classification does not fire during that gap and overwrite the external content (BR-20.2). This closes the window the prior "while the sheet is up" scoping left open.
- On a classified deletion, no autosave recreates the file at the vanished path during the gap before the banner appears (BR-20.3, strengthening BR-9.3 from "the next autosave" to "from classification").
- Suspension lifts only on explicit resolution: Keep Mine performs the single deliberate write (DC-13, BR-5); Keep Theirs / Discard Mine / Save As perform no write that clobbers the content the collision was about; normal autosave resumes only after the outcome is resolved (BR-20.4).

The observable test surface: classify a collision, then drive the autosave trigger before the sheet is presented, and assert the disagreeing disk content is unchanged when the sheet appears — Keep Theirs still recovers it.

---

## Conflict resolution (Conflict & lifecycle UI + Document model)

**DC-13 — Keep Theirs and Discard Mine are the same outcome, retained as two labels (DEFERRED QUESTION 2).** The three sheet options resolve to two distinct behaviors:

- **Keep Mine** — the buffer is written to disk at the followed location; the buffer is unchanged and becomes clean; the sheet dismisses and editing resumes in the same mode (BR-5).
- **Keep Theirs** and **Discard Mine** — *behaviorally identical*: the settled on-disk content that triggered the collision is loaded into the buffer, local edits are dropped, the buffer becomes clean against disk, no write that would clobber the external content is performed, and editing resumes in the same mode (BR-6, BR-7).

Both labels are retained because the project declaration and the feature success criteria name all three verbatim, and the two phrasings frame the *same* outcome from two intents the user may hold ("I trust the other version" vs. "I give up on my edits"). The decision: **do not collapse them in the UI; do not give them divergent effects.** The behavioral contract asserts two distinct end-states for three buttons, with Keep Theirs ≡ Discard Mine. This keeps the no-silent-merge guarantee (every option is a deliberate whole-file choice) while being honest in the design that there are two outcomes, not three.

---

## Seam relationships (data flow)

```
host presents document
        │
        ▼
  presentDocument(at:) ── creates ──► save bridge (writes on 500ms idle)
        │                                   │ on successful write: open settle window (DC-6),
        │                                   │ update last-known-disk (DC-9)
        └───────────── creates ──► change detector (one per document)
                                            │ coordinated reads (DC-2), settle gate (DC-6/7),
                                            │ presence disambiguation (DC-16)
                                            ▼
                              classified outcome: absorb | collision | moved | deleted
                                            │
                ┌───────────────┬───────────┴───────────┬───────────────┐
                ▼               ▼                        ▼               ▼
            absorb          collision                 moved           deleted
        adopt disk,      three-option sheet        retarget URL,    deletion banner
        keep clean       (Keep Mine / Theirs       save bridge +    (Save As) after
        (DC-12)          / Discard, DC-13/14)      detector +       2s no-reappear
                                                   LastFileStore    (DC-16/17)
                                                   (DC-19/20)
```

The save bridge and the detector share two pieces of state owned by `MarkdownDocument`: last-known-disk content (DC-9) and the followed location. They never both act on the buffer at once: from the instant the detector classifies `collision` or `deleted` (not merely once the surface is on screen), the save bridge's autosave is suspended for that document (DC-22, tightening DC-14/DC-16), so the only writer is the user's explicit resolution. And at the apply edge, every outcome is re-validated against the live buffer before mutation, so an absorb derived from an off-main read can never overwrite edits typed during that read (DC-21).

---

## Prescription-feedback resolution

*The adversarial review flagged that some design content named internal interface shapes (`MarkdownDocument.text`, `MarkdownDocumentSaveBridge`, `LastFileStore.recordLastOpened`, the four outcome cases) and the 500ms debounce as implementation prescription rather than behavioral constraint. Those names remain in the design as orientation for the build agent (they are real in-repo seams), but the **properties they protect** are restated here as the behavioral surface — so tests assert behavior, not call shapes.*

- **Internal interface names → behavioral properties.** The names are descriptive, not load-bearing. What the system guarantees, independent of how the seams are wired: (a) exactly one component is the collision/move/deletion authority and it observes only the open document (DC-1, DC-4, BR-10, BR-18); (b) clean/dirty and absorb/collision are decided by a single last-known-disk reference that the writer and the detector keep in agreement, so a save and a detect never disagree about what disk holds (DC-9, DC-10); (c) on a followed move, the location the session saves to, the title shown, and the resume reference all track the new location together (DC-19, BR-8.2/8.3/8.5). None of these require a test to name an attribute or method.

- **500ms debounce → "autosave does not fire on every keystroke."** The 500ms idle debounce is an inherited implementation value, not a guarantee this feature owns. The behavioral property it serves: autosave coalesces continuous typing into at most one write per short idle gap rather than writing on each character, and — load-bearing for this feature — a save that was *queued or pending* when a collision/deletion is classified must not fire during the classify→present gap (DC-22, BR-20.2). Tests assert the no-clobber end-state across the gap, not the millisecond figure.

- **2s settle / 2s disambiguation → genuine behavioral thresholds, kept as properties.** Unlike the debounce, these two are thresholds the user/system observably cares about and they stay pinned: a conflict signal arriving within 2s of the user's own create/open/save is suppressed (DC-6, BR-3), and a "file gone" signal is treated as a move (no banner) if the file reappears within 2s, else a deletion (DC-16, BR-9.5/BR-16). Framed as properties: "Markus does not prompt about a change for ~2s after the user's own action settles" and "a delete-then-recreate within ~2s is a move, not a deletion."

## Behavioral test anchors (for `/tests`)

These restate the now-pinned values so spec tests can assert concretely:
- Settle window = **2000ms**, opened by open / first-persist / save-complete (DC-6); plus independent in-flight-sync suppression (DC-7).
- Move-vs-deletion disambiguation interval = **2000ms** of continued absence before `deleted` (DC-16).
- Keep Theirs and Discard Mine assert the **same** end-state (adopt disk, drop local, clean); Keep Mine asserts buffer→disk (DC-13).
- A single external change produces at most one user-visible response across `SaveStatusObserver` and the detector (DC-3).
- Apply-edge re-validation (DC-21): a clean buffer that turns dirty between read and apply is never silently overwritten by absorb — typed edits are preserved or surfaced as a collision; an unchanged buffer still absorbs silently (no spurious sheet).
- Classification-keyed suspension (DC-22): a queued/debounced autosave driven during the classify→present gap does not write — the disagreeing disk content is unchanged when the sheet appears, and Keep Theirs still recovers it; same for a classified deletion not recreating the vanished path.

---

Architecture stable — no requirements changes flagged
