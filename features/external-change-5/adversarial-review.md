# Adversarial Review — external-change-5

requirements.md @ d30fe8a44784a8220a1a988fab353cebdd1936bc · design.md @ d30fe8a44784a8220a1a988fab353cebdd1936bc · mode: FRESH REVIEW

Reviewer judgment: requirements and the four deferred decisions (settle window, Keep-Theirs/Discard-Mine equivalence, move-vs-deletion disambiguation, two-observer reconciliation) are coherent and trace cleanly to the declarations. The restraint promise, the settle/in-flight split (DC-6/DC-7/DC-8), the presence-first ordering (DC-4/DC-16), and the Keep-Theirs ≡ Discard-Mine collapse (DC-13) are sound and carry no data-loss ambiguity (both are explicit user taps adopting disk). Two concrete concurrency gaps remain, both on the *apply* edge of the detector's classify→act flow, where the design's mutual-exclusion guarantee (save bridge vs. detector) is scoped only to "while a sheet/banner is up" and leaves the silent (absorb) path and the pre-presentation collision window unguarded.

---

## Findings

### F-001 — Absorb decision applied against a buffer that may have changed since classification
- **Severity:** HIGH
- **Status:** addressed (requirements portion) — covered by BR-19 (BR-19.1–BR-19.4); architecture portion (the main-actor re-validation mechanism) flagged for the architecture stage in requirements.md architectural-feedback item 5.
- **Lens:** failure modes / integrity
- **Trace:** feature declaration "Spurious prompts … treated as a defect" and its inverse — the feature must "never silently overwrite the user's work"; BR-1.1, BR-1.5 (absorb without losing edits/mode), BR-2.3 (buffer/cursor preserved).
- **Finding:** DC-19/§Concurrency state that coordinated reads run off the main actor and are "hopped back to the main actor before touching the buffer." The detector classifies `absorb` from the buffer state *as sampled during that off-main read* (clean buffer → absorb, DC-12). Nothing in the design requires re-checking the buffer at the moment the absorb is applied on the main actor. Sequence: buffer is clean → external change arrives → detector begins coordinated read → user types one character → read completes → detector hops to main and adopts disk content + resets last-known-disk (DC-12). The just-typed edits are silently overwritten, with no sheet, because the collision check was made against a stale (clean) snapshot. This is precisely the "silently drop user edits" failure the feature exists to prevent, and it fires in normal single-device editing where a real external change coincides with active typing — not an exotic case.
- **Recommended action (architecture):** Add a DC stating that the absorb/collision classification is re-validated against the current buffer on the main actor immediately before any buffer mutation: if the buffer changed since the read snapshot, the outcome is re-derived (a buffer that became dirty re-runs the equality gate → collision or a fresh coordinated read), and absorb never adopts disk over edits made during the read. Make this an observable property anchored to BR-1.1/BR-2.3.

### F-002 — Autosave write can clobber disagreeing disk content in the gap between `collision` classification and sheet presentation
- **Severity:** HIGH
- **Status:** addressed (requirements portion) — covered by BR-20 (BR-20.1–BR-20.4); architecture portion (keying suspension to classification rather than presentation) flagged for the architecture stage in requirements.md architectural-feedback item 6.
- **Lens:** failure modes / integrity
- **Trace:** BR-4.3 ("no resolution happens without the user's tap"; the open document is not silently overwritten by either side while the choice is pending); declaration "user is the only authority."
- **Finding:** DC-14 suspends the save bridge's autosave "while [the sheet] is up." But the detector emits `collision` from an off-main read and the sheet is presented later on the main actor. The save bridge runs on a 500ms idle debounce (inherited architecture). In the window between the detector deciding `collision` and the sheet actually being presented (off-main read latency + main-actor hop + SwiftUI presentation), a queued autosave can fire and write the user's dirty buffer to disk, clobbering the disagreeing external content that the collision was about — before the user ever sees Keep Theirs. The pending external content is then lost, and a Keep-Theirs/Discard-Mine choice can no longer recover it. The suspension must begin at *classification*, not at *presentation*.
- **Recommended action (architecture):** Specify that autosave suspension for the document begins the instant the detector classifies `collision` (and `deleted`), not when the surface is presented — i.e., suspension is keyed to the outcome being latched, closing the present-the-sheet latency gap. Anchor to BR-4.3 / BR-9.3.

---

## Prescription feedback
*(implementation prescription, not behavioral constraint — recorded, not filed as findings)*

- §Concurrency / DC-9 name specific owned interfaces (`MarkdownDocument.text`, `MarkdownDocumentSaveBridge`, `LastFileStore.recordLastOpened`, the four outcome cases) and the 500ms debounce. These are internal call/attribute shapes; they are appropriate as design detail and are not behavioral constraints to test directly. No action required.

---

## Lens summary
- **Scope drift:** none. The design stays within the three declared Shape seams (File access layer, Document model, Conflict & lifecycle UI); no new surface, setting, or file-type scope is introduced.
- **Declaration tension:** none. Keep-Theirs ≡ Discard-Mine (DC-13) and silent clean-buffer absorption (BR-1) are reconciled in the requirements' consistency notes and do not contradict "no silent merge" or "user is the only authority."
- **Standards (constitution.md):** no violation; constitution holds no iOS patterns, so no `Reuses pattern: [constitution]` HIGH-only scoping applies.
- **Security:** no located findings (no network, auth, or untrusted-input surface beyond UTF-8 decode, which BR-13/DC reuse the existing alert path for).

Open findings: 2 HIGH, 0 MEDIUM, 0 LOW.

## Revision status (requirements pass)
- F-001 — requirements portion addressed by BR-19; architecture portion open for the architecture stage.
- F-002 — requirements portion addressed by BR-20; architecture portion open for the architecture stage.
