# Design — Resume and Create

*Architecture for `resume-and-create-2`. Source of truth for intent: `features/resume-and-create-2/declaration.md`; behavior: `features/resume-and-create-2/requirements.md`. Every constraint below (DC-n) is phrased as an observable property of the running system, not a call signature.*

**Deferred-question resolution:** This design resolves both architecture-flagged questions from `requirements.md` — BR-20 retention policy (see DC-5) and BR-10/11/21 writability determination (see DC-12). Neither resolution required changing any requirement text, so the requirements bottom marker was flipped to "Requirements stable — no architectural feedback to incorporate" as part of this step.

---

## Existing codebase: the seam we attach to

The app is a **SwiftUI `DocumentGroup` app**, not a hand-built `UIDocumentBrowserViewController` host:

- `Markus_v3App.swift` declares `DocumentGroup(newDocument: { MarkdownDocument() }) { config in DocumentView(config) }`. The system supplies the document browser, the create-document affordance, and the navigation stack that pushes `DocumentView` when a file opens. There is no custom browser view controller to subclass.
- `DocumentView` receives a `ReferenceFileDocumentConfiguration<MarkdownDocument>` and reads `configuration.document` + `configuration.fileURL`. It owns the rendered ↔ raw mode (`DocumentMode`), autosave (`AutosaveCoordinator`), and the save-on-background hook (`scenePhase`). It already shows a navigation title and a `.raw`-only trailing "Show rendered" toolbar item. The leading area (back chevron) is currently the system-supplied document-group back button.
- `MarkdownDocument` is a `ReferenceFileDocument`; persistence and security-scoped access to user files are handled by the `DocumentGroup` machinery, not by app code today. Save-back writes through `snapshot`/`fileWrapper`.
- `Info.plist` already sets `LSSupportsOpeningDocumentsInPlace`, the `.md`/`.markdown` document type, and a single-scene-friendly manifest.

The declaration's named hooks — "`UIDocumentBrowserViewController`'s creation handler" and "`NSUserActivity` state restoration" — are the **UIKit-canonical** spellings of two roles. In a `DocumentGroup` app the same two roles are filled by the SwiftUI/iOS-18 equivalents: the `DocumentGroup` browser's built-in create affordance, and scene-level activity/state restoration. This design names the roles behaviorally and binds them to whichever concrete mechanism `DocumentGroup` exposes, so the build can pick the smallest hook that satisfies the constraint without changing the Document model or the Mode switcher (both declared off-limits).

**Hard seam rule:** No component below modifies `MarkdownDocument` (the Document model) or the `.rendered`/`.raw` transition logic in `DocumentView.switchTo`/`toolbarContent` (the Mode switcher). Resume and create attach *around* `DocumentView` — at launch, at the browser, and at the navigation-bar leading edge.

---

## Components and responsibilities

### C1 — LastFileStore (last-opened reference persistence)
Owns the single durable reference to the last-opened file. Records a security-scoped bookmark for a file when that file is opened-and-persisted, and resolves the stored bookmark back to a usable, access-scoped URL on demand. It is the *only* persistent state this feature introduces. Holds the retention decision for failed resolution (DC-5). Stored via `UserDefaults` (the app already declares the `UserDefaults` privacy API in `PrivacyInfo.xcprivacy`); no library, index, or copy is created.
*Reuses pattern: security-scoped bookmark (declaration "File access layer").*

### C2 — LaunchResumeBranch (resume-vs-browser decision at launch)
Runs once at scene activation, before any user-visible UI settles. Asks C1 for a resolvable last file. If one resolves to a reachable, readable file, it drives the app straight into that file's open state (rendered view) without the browser becoming the visible top screen. If none resolves, it does nothing — the `DocumentGroup` browser is the natural landing screen. This is the launch-time branch the declaration assigns to "Document browser entry."

### C3 — DocumentOpenObserver (records every open as last-opened)
Sits at the moment a `DocumentView` becomes active for a real on-disk file (whether reached via browser, resume, or a newly-persisted file) and hands that file's URL to C1 to record. Single funnel so BR-1 holds for all three entry paths. Attaches in `DocumentView` lifecycle without altering the Document model.

### C4 — CreateDocumentHandler (new-file flow)
Fulfils the browser's "Create Document" affordance. Determines the target directory (via C6), computes a collision-free name (via C5), and produces a new empty in-memory document opened directly into the **raw** editor with the keyboard active. Defers the on-disk write until first content (DC-9). On first persistence, routes the file through C3 so it becomes the last-opened file.

### C5 — NameProbe (collision-free `Untitled` naming)
Given a target directory, returns the lowest available `Untitled[ n].md`: `Untitled.md`, then `Untitled 2.md`, `Untitled 3.md`, … never colliding with an existing entry, never overwriting. Probes the *resolved* target directory only (DC-11). Pure function of directory contents.

### C6 — CreateTargetResolver (target directory + writability)
Chooses where a new file goes: the last-opened file's containing directory when that directory is reachable and writable; otherwise the app's local "On My iPhone" Documents directory. Owns the writability determination (DC-12). Depends on C1 (to find the last directory) and falls back deterministically.

### C7 — LocalDocumentsFallback (always-available create target)
Vends the app's local Documents directory (`FileManager` `.documentDirectory` in the app container) as the guaranteed-writable fallback target for C6. This directory is the app's own container, not a user vault, and is exempt from the "no app-managed copies" rule because it only holds files the user explicitly created there.

### C8 — BackToBrowser (navigation-bar leading back affordance)
Supplies the standard navigation-bar back chevron in the leading position of the rendered and raw views, returning to the document browser. In a `DocumentGroup` stack the system back/dismiss already provides this plus the edge-swipe; C8's job is to ensure the affordance is present and labeled on both modes and that dismissing does **not** touch C1's stored reference (DC-15).
*Reuses pattern: standard navigation-bar back item / interactive pop gesture (UIKit `UINavigationController`, surfaced by `DocumentGroup`).*

---

## Behavioral contracts (design constraints)

### Resume

**DC-1 — Exactly one durable last-file reference exists.** After any file is opened and has persisted on disk, the system holds a single stored reference that survives full termination and resolves to that file on next launch. Opening a different file replaces it; there is never more than one. *(BR-1)*

**DC-2 — A resolvable reference lands the user in the rendered view, not the browser.** On a launch where the stored reference resolves to a reachable, readable file, the first interactive screen the user can act on is that file's rendered view. *(BR-2, BR-6)*

**DC-3 — The browser is never the visible top screen during a successful resume.** Across a resuming launch, no frame shows the document browser as the top view before the rendered view appears — no flash, no intermediate browser presentation. *(BR-3)*

**DC-4 — Absence or failure of the reference lands the user in the browser, silently.** On a launch with no stored reference, or with a stored reference that fails to resolve to a reachable/readable file for any reason (stale/invalid bookmark, deleted, moved beyond tracking, undownloadable sync placeholder, lost permission), the first interactive screen is the document browser, and no alert, banner, toast, or error text attributes the outcome to a missing file. The app does not crash on a stale/corrupt bookmark. *(BR-4, BR-5, BR-19)*

**DC-5 — RESOLVED (BR-20): Retention policy is RETAIN-on-failure, REPLACE-on-success.** A failed resolution of the stored reference does **not** clear it. The reference is only ever replaced when a new file is successfully opened-and-persisted (DC-1), or overwritten/cleared when the user successfully opens a different file. *Rationale:* the dominant failure mode for the target user (iCloud Drive / sync-service files) is a not-yet-downloaded sync placeholder or a temporarily-offline location — a condition that commonly clears itself on a later launch. Permanently clearing on the first miss would convert a transient hiccup into permanent loss of resume for a file that is still exactly where the user left it, contradicting the feature's whole purpose. Retaining costs nothing observable on the failing launch (DC-4 holds either way) and lets a later launch recover automatically.
*Observable:* Launch with an unreachable reference → browser shown (DC-4); make the same file reachable again and relaunch → app resumes into it without the user having reopened it from the browser. A failing launch followed by another failing launch still shows the browser, never an error.

### Create

**DC-6 — Create yields an `.md` document.** Invoking the browser's Create Document affordance produces an open document whose filename ends in `.md` (never `.markdown`, never `.txt`). *(BR-7)*

**DC-7 — Naming is deterministic and non-destructive.** In a collision-free target directory the new file is named exactly `Untitled.md`. When that name is taken, the name is the lowest available `Untitled n.md` for integer n ≥ 2, skipping no lower available integer and never altering or overwriting any existing file. The probe runs against the directory actually chosen by DC-10/DC-12, not any other. *(BR-8, BR-9, BR-22, BR-26)*

**DC-8 — A new file opens straight into editing.** A freshly created file's first screen is the raw editor (not the rendered view) with its text input as first responder and the software keyboard presented. *(BR-12)*

**DC-9 — An untyped new file leaves no trace.** A newly created file is not written to disk until the user enters at least one character. If the session ends before any character is typed — by back navigation, edge-swipe, backgrounding, or termination — no file exists at the target and the name it would have taken remains available for the next create. *(BR-13, BR-24, BR-25)*

**DC-10 — A typed new file persists at its resolved name and becomes the last-opened file.** Once at least one character is typed and the existing save flow runs, a file exists at the resolved directory and resolved `Untitled[ n].md` name containing the typed text, overwriting nothing; that file then satisfies DC-1 as the new last-opened reference. *(BR-14, BR-15, BR-26)*

**DC-11 — Collision probing is evaluated in the resolved target directory only.** The name in DC-7 is computed from the contents of the directory selected by DC-10/DC-12 at create time, never from a different (e.g. unwritable or absent) directory. *(BR-22)*

**DC-12 — RESOLVED (BR-10/11/21): Target is the last directory only when a pre-write reachability/writability PROBE succeeds; otherwise local Documents.** At create time the resolver (a) requires a resolvable last-opened reference whose containing directory is currently reachable, and (b) confirms that directory is writable by an explicit probe *before* attempting the real file write — not by attempting the real write and catching its failure. The probe is a minimal, side-effect-free-on-success writability check (e.g. create-and-remove a uniquely-named temporary entry, or the platform's writability query, inside the security-scoped access of the resolved directory). If either (a) or (b) fails, the target is the local Documents directory. *Rationale chosen over attempt-and-fall-back:* DC-9 forbids leaving any on-disk trace from a create that the user might abandon, and the real first write happens lazily at first-keystroke (DC-10), long after the directory was chosen and the editor opened. Deciding the directory at create time by a clean probe keeps the chosen directory stable for the whole editing session and keeps collision probing (DC-11) anchored to one directory; an attempt-and-fall-back model would only discover non-writability at first-keystroke, forcing a mid-session directory change (and a re-probe of a different directory's collisions), which is observably worse and harder to test. The probe leaves no residual file on success.
*Observable:* last-opened directory writable → new file's parent is that directory; no last reference, or last directory unreachable, or last directory read-only → new file's parent is local Documents; in every case no write-error alert is shown and no stray probe file remains. *(BR-10, BR-11, BR-21, BR-23)*

### Back navigation

**DC-13 — Both modes expose a leading back affordance to the browser.** The rendered view and the raw editor each present a standard navigation-bar back chevron in the leading position that, when tapped, returns to the document browser. *(BR-16)*

**DC-14 — The standard edge-swipe-back returns to the browser.** A left-edge left-to-right swipe from either mode returns to the document browser, as the standard interactive pop. *(BR-17)*

**DC-15 — Leaving a file does not erase the last-opened reference.** Returning to the browser via chevron, edge-swipe, backgrounding, or termination leaves C1's stored reference intact, so a subsequent relaunch still resumes the same file (subject to DC-2/DC-4). *(BR-18)*

---

## Seam relationships

- **C2 (LaunchResumeBranch) ↔ app entry.** Attaches at scene activation in/around `Markus_v3App` (the `DocumentGroup` scene). It drives the system to open the resolved file *as if* the user had selected it, so the existing `DocumentGroup → DocumentView` push is reused unchanged. It must run early enough that DC-3 (no browser flash) holds — i.e. the resume decision is made before the browser would be drawn as the top screen. No change to `MarkdownDocument` or the mode switch.

- **C3 (DocumentOpenObserver) ↔ `DocumentView` lifecycle.** Hooks the point where `DocumentView` becomes active with a non-nil `fileURL` (e.g. its existing `.onAppear`/configuration path) and forwards that URL to C1. It does not alter `DocumentView`'s rendering, autosave, or mode logic — it only reads the already-present `fileURL`.

- **C4 (CreateDocumentHandler) ↔ `DocumentGroup` create affordance.** Binds to the browser's Create Document hook. It produces the new in-memory `MarkdownDocument` (using the model's existing empty `init()`) and signals "open in raw mode, keyboard up." The raw-vs-rendered initial mode is conveyed to `DocumentView` *without* changing the Mode switcher: `DocumentView` already chooses an initial mode in `.onAppear` (large-file → `.raw`); the create path reuses that same initial-mode seam to request `.raw` for a new file, rather than adding a new transition. *Reuses pattern: initial-mode selection in `DocumentView.onAppear`.*

- **C5/C6/C7 ↔ File access layer.** Pure-ish helpers invoked by C4 at create time; they read directory listings and resolve URLs, never touching the Document model. C6 consults C1 for the last directory and C7 for the fallback.

- **C8 (BackToBrowser) ↔ navigation chrome.** Adds/ensures the leading toolbar back item on both modes in `DocumentView`'s existing `.toolbar`, alongside the current trailing "Show rendered" item. It uses the system dismiss/pop already provided by the `DocumentGroup` stack; the edge-swipe (DC-14) comes free with that navigation controller. C8 guarantees the dismiss path does not call into C1's clear.

---

## HIG alignment

- Resume-on-launch is implemented as state restoration of the last document — the HIG-canonical "reopen what the user was working on," realized through the `DocumentGroup`/scene restoration role rather than a custom splash, honoring the declaration's "no onboarding, no splash."
- Create flows through the document browser's own create affordance (HIG-canonical for document-based apps); the app adds no custom new-file UI.
- The back chevron and edge-swipe are the standard navigation-bar/interactive-pop affordances; no custom gesture is introduced (other swipes are explicitly Roadmap #6).
- The stale/unreachable case is silent by design (DC-4) per both the declaration and HIG guidance against alarming the user about routine, recoverable conditions.

---

Architecture stable — no requirements changes flagged
