# Design — Resume and Create

*Architecture for `resume-and-create-2`. Source of truth for intent: `features/resume-and-create-2/declaration.md`; behavior: `features/resume-and-create-2/requirements.md`. Every constraint below (DC-n) is phrased as an observable property of the running system, not a call signature.*

**Deferred-question resolution:** This design resolves both architecture-flagged questions from `requirements.md` — BR-20 retention policy (see DC-5) and BR-10/11/21 writability determination (see DC-12). Neither resolution required changing any requirement text, so the requirements bottom marker was flipped to "Requirements stable — no architectural feedback to incorporate" as part of this step.

---

## Existing codebase: the seam we attach to

The app today is a **SwiftUI `DocumentGroup` app**:

- `Markus_v3App.swift` declares `DocumentGroup(newDocument: { MarkdownDocument() }) { config in DocumentView(config) }`. The system supplies the document browser, the create-document affordance, and the navigation stack that pushes `DocumentView` when a file opens. There is no custom browser view controller to subclass.
- `DocumentView` receives a `ReferenceFileDocumentConfiguration<MarkdownDocument>` and reads `configuration.document` + `configuration.fileURL`. It owns the rendered ↔ raw mode (`DocumentMode`), autosave (`AutosaveCoordinator`), and the save-on-background hook (`scenePhase`). It already shows a navigation title and a `.raw`-only trailing "Show rendered" toolbar item. The leading area (back chevron) is currently the system-supplied document-group back button.
- `MarkdownDocument` is a `ReferenceFileDocument`; persistence and security-scoped access to user files are handled by the `DocumentGroup` machinery, not by app code today. Save-back writes through `snapshot`/`fileWrapper`.
- `Info.plist` already sets `LSSupportsOpeningDocumentsInPlace`, the `.md`/`.markdown` document type, and a multiple-scenes-enabled manifest.

### Architectural decision: replace the `DocumentGroup` host with a `UIDocumentBrowserViewController`-backed launch path

*(Addresses adversarial F-001, F-002, F-003 at their shared root.)*

The adversarial review correctly identified that all three HIGH findings share one root: three declared behaviors each require a capability that SwiftUI's default `DocumentGroup` does **not** expose:

1. **Deferred-write create (F-001).** SwiftUi's `DocumentGroup(newDocument:)` create affordance materializes a file on disk (in a system-chosen temporary/inbox location) and presents the system rename UI as part of the create flow. The file exists before the user types. There is no public `DocumentGroup` hook that withholds that write until first keystroke. BR-13/DC-9 (no on-disk trace, name not consumed) cannot be satisfied through it.
2. **Last-directory-targeted create (F-002).** The same `DocumentGroup` create affordance places the new document in a system-/browser-determined location. There is no public API to force it into an app-computed directory resolved from a stored bookmark. BR-10/DC-12 cannot be satisfied through it.
3. **Zero-flash resume (F-003).** In a `DocumentGroup` app the browser is the scene's root content. SwiftUI exposes no public, supported mechanism to open a specific document URL at frame zero with *zero* browser frames; any restoration path that has been observed either flashes the browser or is undocumented/fragile. BR-3/DC-3 ("never the visible top screen, not even momentarily") cannot be guaranteed through it.

The project declaration (`declaration.md`) and the feature declaration both name the **UIKit-canonical** hooks for exactly these roles: "`UIDocumentBrowserViewController`'s creation handler is the canonical hook for new-document flow" and "state restoration via `NSUserActivity` is the HIG-canonical mechanism for reopen-the-last-document." These named mechanisms are the concrete seams the three findings demand. The earlier design treated them as interchangeable role-names; the feasibility analysis shows they are **not** interchangeable with `DocumentGroup` — only the UIKit spellings give the app the control points the behaviors require.

**Therefore this design replaces the SwiftUI `DocumentGroup` scene with a custom UIKit host** built on `UIDocumentBrowserViewController`, wrapped for SwiftUI via `UIViewControllerRepresentable` and hosted from the existing `App`/`Scene` entry. This is a legitimate architectural decision *within* the declared intent — it adopts the very mechanisms the declaration names as canonical, and the declaration's Shape already anticipates "the system-provided document browser as the app's only home" (`UIDocumentBrowserViewController` *is* that system browser, exposed with the control points `DocumentGroup` hides).

What the UIKit host gives us, mapped to the findings:

- **Custom create handler (F-001, F-002):** `UIDocumentBrowserViewController`'s `documentBrowser(_:didRequestDocumentCreationWithHandler:)` delegate callback hands the app full control: the app decides the new document's URL (its directory and name — solving F-002), and the app decides *whether and when* to materialize it. The new document can be created in memory and the on-disk write withheld until first keystroke (solving F-001), then imported into place via the creation handler's completion at persist time.
- **Programmatic open with no browser frame (F-003):** A UIKit host can perform the resume decision in the scene's `willConnectTo`/`scene(_:continue:)` path (driven by a restored `NSUserActivity` carrying the last-file bookmark) and present the editor as the scene's first content — so the browser view controller is never the visible top view controller on a resuming launch.

**Hard seam rule (unchanged):** No component below modifies `MarkdownDocument` (the Document model) or the `.rendered`/`.raw` transition logic in `DocumentView.switchTo`/`toolbarContent` (the Mode switcher). `DocumentView` itself is reused essentially intact as the editor surface; the change is *underneath* it — swapping the scene host that presents it — and *around* it (launch branch, create handler, leading back affordance). The editor's rendering, autosave, mode-switch, and save-back paths are untouched.

**Scope note on the host swap.** Replacing `DocumentGroup` is a structural change to `Markus_v3App.swift` and adds a UIKit host layer, but it does not change *what* `DocumentView` does or *what* `MarkdownDocument` is. The walking-skeleton open → render → edit → save loop must continue to pass its existing tests through the new host (BR-6 explicitly requires resumed files behave identically to browser-opened files). If during build the team finds the host swap cannot preserve the walking-skeleton behavior without touching the Document model or Mode switcher, that is a hard-seam violation and must escalate to the loop rather than be worked around.

---

## Components and responsibilities

### C0 — BrowserHost (UIKit `UIDocumentBrowserViewController` scene host)
*(Addresses adversarial F-001, F-002, F-003.)* The new scene-root host that replaces the SwiftUI `DocumentGroup`. A `UIDocumentBrowserViewController` subclass (or delegate) wrapped in `UIViewControllerRepresentable`, presented from the app's `Scene`. It owns three control points the previous `DocumentGroup` host did not expose: (1) the create-document delegate callback that C4 drives; (2) presentation of `DocumentView` (via `UIHostingController`) when a document opens — reused unchanged as the editor surface; (3) the scene-activation path where C2 makes the resume decision before any browser frame is drawn. It introduces no document-model or mode-switch logic; it is purely the host that wires the system browser to the existing editor and to this feature's components.
*Reuses pattern: `UIDocumentBrowserViewController` (declaration "Document browser entry"; project declaration names it the canonical new-document hook).*

### C1 — LastFileStore (last-opened reference persistence)
Owns the single durable reference to the last-opened file. Records a security-scoped bookmark for a file when that file is opened-and-persisted, and resolves the stored bookmark back to a usable, access-scoped URL on demand. It is the *only* persistent state this feature introduces. Holds the retention decision for failed resolution (DC-5). Behavioral constraint: the reference is durable across full termination (BR-1); the specific storage location (e.g. `UserDefaults`) is implementation latitude (see Prescription, F-004). No library, index, or copy is created.
*Reuses pattern: security-scoped bookmark (declaration "File access layer").*

### C2 — LaunchResumeBranch (resume-vs-browser decision at launch)
Runs once at scene activation inside C0's host, before any browser frame is drawn. Asks C1 for a resolvable last file. If one resolves to a reachable, readable file, it presents that file's editor (rendered view) as the scene's first content so the browser never becomes the visible top view controller (DC-3). If none resolves, it does nothing — the `UIDocumentBrowserViewController` is then the natural landing screen. This is the launch-time branch the declaration assigns to "Document browser entry," realized through the UIKit scene-activation / `NSUserActivity` restoration path.

### C3 — DocumentOpenObserver (records every open as last-opened)
Sits at the moment a `DocumentView` becomes active for a real on-disk file (whether reached via browser, resume, or a newly-persisted file) and hands that file's URL to C1 to record. Single funnel so BR-1 holds for all three entry paths. Attaches in the open path (C0's present-document callback and/or `DocumentView` lifecycle) without altering the Document model.

### C4 — CreateDocumentHandler (new-file flow)
Fulfils the browser's "Create Document" affordance via C0's `UIDocumentBrowserViewController` creation delegate callback (`documentBrowser(_:didRequestDocumentCreationWithHandler:)`). Determines the target directory (via C6), computes a collision-free name (via C5), and produces a new empty in-memory document opened directly into the **raw** editor with the keyboard active. Defers the on-disk write until first content (DC-9): it holds the chosen URL but completes the system creation handler so as to import the file into the app-chosen location only once content exists. On first persistence, routes the file through C3 so it becomes the last-opened file. The creation delegate callback is the concrete seam that lets the app both choose the directory (F-002) and withhold the write (F-001).

### C5 — NameProbe (collision-free `Untitled` naming)
Given a target directory, returns the lowest available `Untitled[ n].md`: `Untitled.md`, then `Untitled 2.md`, `Untitled 3.md`, … never colliding with an existing entry, never overwriting. Probes the *resolved* target directory only (DC-11). Pure function of directory contents.

### C6 — CreateTargetResolver (target directory + writability)
Chooses where a new file goes: the last-opened file's containing directory when that directory is reachable and writable; otherwise the app's local "On My iPhone" Documents directory. Owns the writability determination (DC-12). Depends on C1 (to find the last directory) and falls back deterministically.

### C7 — LocalDocumentsFallback (always-available create target)
Vends the app's local Documents directory (`FileManager` `.documentDirectory` in the app container) as the guaranteed-writable fallback target for C6. This directory is the app's own container, not a user vault, and is exempt from the "no app-managed copies" rule because it only holds files the user explicitly created there.

### C8 — BackToBrowser (navigation-bar leading back affordance)
Supplies the standard navigation-bar back chevron in the leading position of the rendered and raw views, returning to the document browser. The editor is presented from C0's `UIDocumentBrowserViewController` (via `UIHostingController`), so dismissing the presented editor returns to the browser; the system interactive edge-swipe-pop comes with that presentation/navigation controller. C8's job is to ensure the affordance is present and labeled on both modes and that dismissing does **not** touch C1's stored reference (DC-15).
*Reuses pattern: standard navigation-bar back item / interactive pop gesture (UIKit `UINavigationController` / presented-controller dismiss, surfaced by the `UIDocumentBrowserViewController` host).*

---

## Behavioral contracts (design constraints)

### Resume

**DC-1 — Exactly one durable last-file reference exists.** After any file is opened and has persisted on disk, the system holds a single stored reference that survives full termination and resolves to that file on next launch. Opening a different file replaces it; there is never more than one. *(BR-1)*

**DC-2 — A resolvable reference lands the user in the rendered view, not the browser.** On a launch where the stored reference resolves to a reachable, readable file, the first interactive screen the user can act on is that file's rendered view. *(BR-2, BR-6)*

**DC-3 — The browser is never the visible top screen during a successful resume.** Across a resuming launch, no frame shows the document browser as the top view before the rendered view appears — no flash, no intermediate browser presentation. *(BR-3)* **Named mechanism (addresses adversarial F-003):** the resume decision is made by C2 in the UIKit scene-activation / `NSUserActivity`-restoration path of the C0 host, and the editor is presented as the scene's first content *before* the `UIDocumentBrowserViewController` is made the visible top view controller. Because C0 is a custom UIKit host (not SwiftUI `DocumentGroup`, whose browser is the unconditional scene root), the host controls presentation order at frame zero. This is the load-bearing reason the host was changed; if at build time the UIKit host still cannot achieve zero browser frames, escalate to the loop (see bottom of file).

**DC-4 — Absence or failure of the reference lands the user in the browser, silently.** On a launch with no stored reference, or with a stored reference that fails to resolve to a reachable/readable file for any reason (stale/invalid bookmark, deleted, moved beyond tracking, undownloadable sync placeholder, lost permission), the first interactive screen is the document browser, and no alert, banner, toast, or error text attributes the outcome to a missing file. The app does not crash on a stale/corrupt bookmark. *(BR-4, BR-5, BR-19)*

**DC-5 — RESOLVED (BR-20): Retention policy is RETAIN-on-failure, REPLACE-on-success.** A failed resolution of the stored reference does **not** clear it. The reference is only ever replaced when a new file is successfully opened-and-persisted (DC-1), or overwritten/cleared when the user successfully opens a different file. *Rationale:* the dominant failure mode for the target user (iCloud Drive / sync-service files) is a not-yet-downloaded sync placeholder or a temporarily-offline location — a condition that commonly clears itself on a later launch. Permanently clearing on the first miss would convert a transient hiccup into permanent loss of resume for a file that is still exactly where the user left it, contradicting the feature's whole purpose. Retaining costs nothing observable on the failing launch (DC-4 holds either way) and lets a later launch recover automatically.
*Observable:* Launch with an unreachable reference → browser shown (DC-4); make the same file reachable again and relaunch → app resumes into it without the user having reopened it from the browser. A failing launch followed by another failing launch still shows the browser, never an error.

### Create

**DC-6 — Create yields an `.md` document.** Invoking the browser's Create Document affordance produces an open document whose filename ends in `.md` (never `.markdown`, never `.txt`). *(BR-7)*

**DC-7 — Naming is deterministic and non-destructive.** In a collision-free target directory the new file is named exactly `Untitled.md`. When that name is taken, the name is the lowest available `Untitled n.md` for integer n ≥ 2, skipping no lower available integer and never altering or overwriting any existing file. The probe runs against the directory actually chosen by DC-10/DC-12, not any other. *(BR-8, BR-9, BR-22, BR-26)*

**DC-8 — A new file opens straight into editing.** A freshly created file's first screen is the raw editor (not the rendered view) with its text input as first responder and the software keyboard presented. *(BR-12)*

**DC-9 — An untyped new file leaves no trace.** A newly created file is not written to disk until the user enters at least one character. If the session ends before any character is typed — by back navigation, edge-swipe, backgrounding, or termination — no file exists at the target and the name it would have taken remains available for the next create. *(BR-13, BR-24, BR-25)* **Named mechanism (addresses adversarial F-001):** create flows through C0's `UIDocumentBrowserViewController` creation delegate callback (`documentBrowser(_:didRequestDocumentCreationWithHandler:)`), which hands the app control over whether and when the document is materialized. C4 holds the new document in memory (via `MarkdownDocument`'s existing empty `init()`) and the on-disk file is written only at first-keystroke persistence (DC-10) into the C6-resolved location; an abandoned create completes the system handler without leaving a file at the target, so the name is not consumed. This is feasible specifically because the host is the custom UIKit browser and not SwiftUI `DocumentGroup`, whose create affordance materializes the file up front.

**DC-10 — A typed new file persists at its resolved name and becomes the last-opened file.** Once at least one character is typed and the existing save flow runs, a file exists at the resolved directory and resolved `Untitled[ n].md` name containing the typed text, overwriting nothing; that file then satisfies DC-1 as the new last-opened reference. *(BR-14, BR-15, BR-26)*

**DC-11 — Collision probing is evaluated in the resolved target directory only.** The name in DC-7 is computed from the contents of the directory selected by DC-10/DC-12 at create time, never from a different (e.g. unwritable or absent) directory. *(BR-22)*

**DC-12 — RESOLVED (BR-10/11/21): Target is the last directory only when a pre-write reachability/writability PROBE succeeds; otherwise local Documents.** **Named mechanism (addresses adversarial F-002):** the new file's parent directory is chosen by C6 from C1's stored bookmark and supplied to C0's `UIDocumentBrowserViewController` creation delegate callback, which lets the app dictate the created document's URL (directory and name). The system create affordance no longer chooses the location. At create time the resolver (a) requires a resolvable last-opened reference whose containing directory is currently reachable, and (b) confirms that directory is writable by an explicit probe *before* attempting the real file write — not by attempting the real write and catching its failure. The probe is a minimal, side-effect-free-on-success writability check (specific technique is implementation latitude — see Prescription) inside the security-scoped access of the resolved directory. If either (a) or (b) fails, the target is the local Documents directory. *Rationale chosen over attempt-and-fall-back:* DC-9 forbids leaving any on-disk trace from a create that the user might abandon, and the real first write happens lazily at first-keystroke (DC-10), long after the directory was chosen and the editor opened. Deciding the directory at create time by a clean probe keeps the chosen directory stable for the whole editing session and keeps collision probing (DC-11) anchored to one directory; an attempt-and-fall-back model would only discover non-writability at first-keystroke, forcing a mid-session directory change (and a re-probe of a different directory's collisions), which is observably worse and harder to test. The probe leaves no residual file on success.
*Observable:* last-opened directory writable → new file's parent is that directory; no last reference, or last directory unreachable, or last directory read-only → new file's parent is local Documents; in every case no write-error alert is shown and no stray probe file remains. *(BR-10, BR-11, BR-21, BR-23)*

### Back navigation

**DC-13 — Both modes expose a leading back affordance to the browser.** The rendered view and the raw editor each present a standard navigation-bar back chevron in the leading position that, when tapped, returns to the document browser. *(BR-16)*

**DC-14 — The standard edge-swipe-back returns to the browser.** A left-edge left-to-right swipe from either mode returns to the document browser, as the standard interactive pop. *(BR-17)*

**DC-15 — Leaving a file does not erase the last-opened reference.** Returning to the browser via chevron, edge-swipe, backgrounding, or termination leaves C1's stored reference intact, so a subsequent relaunch still resumes the same file (subject to DC-2/DC-4). *(BR-18)*

---

## Seam relationships

*(All seams below attach to the C0 `UIDocumentBrowserViewController`-backed host that replaces the SwiftUI `DocumentGroup`, per the architectural decision above. The previous draft of this section described `DocumentGroup` seams; it was rewritten to the UIKit host so the seam descriptions no longer contradict the host swap that resolves F-001/F-002/F-003.)*

- **C2 (LaunchResumeBranch) ↔ scene activation in the C0 host.** *(Addresses adversarial F-003.)* Attaches at the UIKit scene-activation path (`scene(_:willConnectTo:options:)` / `scene(_:continue:)` driven by a restored `NSUserActivity` carrying the last-file bookmark) inside C0, *before* the `UIDocumentBrowserViewController` is made the visible top view controller. When C1 yields a resolvable file, C2 presents that file's editor (`UIHostingController` wrapping the unchanged `DocumentView`) as the scene's first content, so the browser is never the visible top screen (DC-3). When none resolves, C2 does nothing and the browser is the natural landing screen (DC-4). Because C0 is a custom host rather than `DocumentGroup` (whose browser is the unconditional scene root), the host — not the framework — controls presentation order at frame zero. No change to `MarkdownDocument` or the mode switch.

- **C3 (DocumentOpenObserver) ↔ `DocumentView` lifecycle.** Hooks the point where `DocumentView` becomes active with a non-nil `fileURL` (e.g. its existing `.onAppear`/configuration path, or C0's present-document callback) and forwards that URL to C1. It does not alter `DocumentView`'s rendering, autosave, or mode logic — it only reads the already-present `fileURL`.

- **C4 (CreateDocumentHandler) ↔ C0's `UIDocumentBrowserViewController` creation delegate callback.** *(Addresses adversarial F-001, F-002.)* Binds to `documentBrowser(_:didRequestDocumentCreationWithHandler:)`, the UIKit delegate hook that hands the app control over both the new document's URL (directory + name → F-002) and *whether and when* it is materialized on disk (→ F-001). It produces the new in-memory `MarkdownDocument` (using the model's existing empty `init()`) and signals "open in raw mode, keyboard up." The raw-vs-rendered initial mode is conveyed to `DocumentView` *without* changing the Mode switcher: `DocumentView` already chooses an initial mode in `.onAppear` (large-file → `.raw`); the create path reuses that same initial-mode seam to request `.raw` for a new file, rather than adding a new transition. The on-disk write is withheld until first keystroke (DC-9); an abandoned create completes the creation handler without leaving a file at the target. *Implementation latitude (Prescription): the exact way the initial-mode request and the empty-`init()` reuse are wired is a build choice; the behavioral constraint is BR-12/DC-8 (new file opens in raw editor, keyboard up) and BR-13/DC-9 (no trace until first keystroke).*

- **C5/C6/C7 ↔ File access layer.** Pure-ish helpers invoked by C4 at create time; they read directory listings and resolve URLs, never touching the Document model. C6 consults C1 for the last directory and C7 for the fallback. *Implementation latitude (Prescription): C6's writability probe technique (e.g. create-and-remove a uniquely-named temporary entry, or a platform writability query) is a build choice; the behavioral constraint is DC-12 (target is last directory only when writable, else local Documents, with no stray file left behind).*

- **C8 (BackToBrowser) ↔ navigation chrome.** Adds/ensures the leading toolbar back item on both modes in `DocumentView`'s existing `.toolbar`, alongside the current trailing "Show rendered" item. It uses the system dismiss/pop provided by the `UIHostingController` presented from C0's `UIDocumentBrowserViewController`; dismissing the presented editor returns to the browser, and the interactive edge-swipe-pop (DC-14) comes free with that presentation/navigation controller. C8 guarantees the dismiss path does not call into C1's clear (DC-15).

---

## HIG alignment

- Resume-on-launch is implemented as state restoration of the last document — the HIG-canonical "reopen what the user was working on" — realized through the UIKit scene-activation / `NSUserActivity` restoration path of the C0 host (the mechanism the project declaration names canonical) rather than a custom splash, honoring the declaration's "no onboarding, no splash."
- Create flows through the system browser's own creation handler (`UIDocumentBrowserViewController`'s `documentBrowser(_:didRequestDocumentCreationWithHandler:)`, HIG-canonical for document-based apps and named canonical by the project declaration); the app adds no custom new-file UI — it supplies the target URL and defers the write, but the entry point is still the browser's own Create affordance.
- The back chevron and edge-swipe are the standard navigation-bar/interactive-pop affordances; no custom gesture is introduced (other swipes are explicitly Roadmap #6).
- The stale/unreachable case is silent by design (DC-4) per both the declaration and HIG guidance against alarming the user about routine, recoverable conditions.

---

## Build-time feasibility trigger (not a requirements change)

The three HIGH findings (F-001, F-002, F-003) are addressed by adopting the UIKit `UIDocumentBrowserViewController`-backed host (C0) and its named control points — the create delegate callback and the scene-activation/`NSUserActivity` restoration path — which are the mechanisms both declarations name as canonical. These are well-established UIKit capabilities, so the resolution is an architectural decision within the declared intent, not a product/scope change requiring user input.

One residual risk is recorded as a build-time escalation trigger, not a requirements change: DC-3 requires *zero* browser frames on resume. If, at build, the C0 host cannot present the editor as the scene's first content without the `UIDocumentBrowserViewController` momentarily becoming the visible top view controller, that is a feasibility miss against BR-3 and must escalate to the requirements↔architecture loop (per the constitution's "feature files are the spec; if they are wrong, fix the document and restart the affected step"), rather than being silently relaxed at build. No requirement text needs to change to record this — the escalation path is the standard loop.

Architecture stable — no requirements changes flagged
