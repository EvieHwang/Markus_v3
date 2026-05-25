# Adversarial Review — Resume and Create

requirements.md @ 4004e490e7fcb6f850209fd886fb740f3eb88563 · design.md @ 4004e490e7fcb6f850209fd886fb740f3eb88563 · mode: FRESH REVIEW

---

## Findings

### F-001 — Deferred-write create is in tension with the `DocumentGroup` create affordance
- **Severity:** HIGH
- **Lens:** integrity / feasibility (subject traces to BR-13, BR-24, BR-25; declaration "empty files do not persist")
- **Finding:** BR-13/DC-9 require that a newly created file is *not* written to disk until the first character is typed, with the chosen name remaining un-consumed if the user abandons it. The design (C4, seam "C4 ↔ `DocumentGroup` create affordance") binds the create flow to "the browser's Create Document hook." In a SwiftUI `DocumentGroup` app whose document is a `ReferenceFileDocument`, the system's create affordance materializes the document on disk as part of the create/save flow — the file exists before editing begins. The design asserts the write can be deferred to first keystroke but routes through the very system affordance whose normal behavior is to create the file up front, and names no concrete `DocumentGroup` hook that suppresses that write. The reuse-pattern surface ("C4 ↔ `DocumentGroup` create affordance") is exactly where this must be proven.
- **Concrete failure mode:** Every "Create Document" then-abandon leaves an empty `Untitled[ n].md` on disk and consumes that collision name, so the next create yields `Untitled 2.md` for an empty directory — directly contradicting BR-13's observable ("a subsequent Create Document still yields `Untitled.md`") and BR-24/BR-25.
- **Recommended action (architecture):** Before build, design must name the concrete mechanism by which a new document is held in memory and withheld from disk until first content under `DocumentGroup` — or, if `DocumentGroup`'s create affordance cannot defer the write, escalate to the requirements↔architecture loop: either (a) adopt a custom create path not routed through the system create affordance, or (b) surface a deviation request against BR-13. State the chosen mechanism as a DC-level observable.
- **Status:** open

### F-002 — Programmatically targeting the last-opened directory is in tension with the system create affordance
- **Severity:** HIGH
- **Lens:** integrity / feasibility (subject traces to BR-10, BR-11, BR-22; declaration "in the directory of the last-opened file")
- **Finding:** BR-10/DC-12 require the new file's parent directory to be the last-opened file's directory (when reachable+writable), else local Documents. The `DocumentGroup` create affordance creates the document in a system-/browser-determined location, not a directory chosen by app code from a stored bookmark. The design's CreateTargetResolver (C6) computes a target directory, but the seam that would force the system create affordance to honor that computed directory is not named — same unproven `DocumentGroup` hook as F-001.
- **Concrete failure mode:** New files land wherever the document browser defaults (e.g. the browser's current location or the app container root) rather than the last-opened directory, so the resumed-file workflow the feature is built around ("new note alongside my recent work") silently does not hold; BR-10's observable ("new file's parent directory is D") fails.
- **Recommended action (architecture):** Demonstrate the mechanism that places the created document in C6's resolved directory under `DocumentGroup`, or escalate to the loop with a custom create path. If both F-001 and F-002 resolve only via a non-`DocumentGroup` create path, design should consolidate them into a single create-path component and re-scope C4.
- **Status:** open

### F-003 — "No browser flash on resume" depends on an unnamed `DocumentGroup` launch hook
- **Severity:** HIGH
- **Lens:** integrity / feasibility (subject traces to BR-2, BR-3; declaration "no document browser flash, no intermediate UI")
- **Finding:** BR-3/DC-3 require the document browser is *never* the visible top screen — not even momentarily — before the resumed file's rendered view appears. In a `DocumentGroup` app the browser is the scene's root content; the design (C2, seam "C2 ↔ app entry") states the resume decision must run "before the browser would be drawn as the top screen" but explicitly "binds... to whichever concrete mechanism `DocumentGroup` exposes" without naming one. Whether a `DocumentGroup` scene can open a specific file at launch with zero browser frames is the load-bearing feasibility question and it is deferred to the build.
- **Concrete failure mode:** A visible browser flash on every resuming launch — the precise outcome BR-3 forbids and a regression against the feature's first success criterion ("no document browser flash"). If the only available mechanism shows the browser for one frame, the requirement is unmet and discovered only at build/QA.
- **Recommended action (architecture):** Identify and record the concrete launch/state-restoration mechanism (e.g. scene activation conditions, restoration of the document URL into the navigation stack) that satisfies DC-3, and state its observable. If no `DocumentGroup` mechanism can guarantee zero browser frames, escalate to the requirements↔architecture loop rather than leaving DC-3 as an assertion.
- **Status:** open

### F-004 — Last-file bookmark persisted in `UserDefaults`
- **Severity:** LOW
- **Lens:** security (located: C1 LastFileStore; traces to BR-1)
- **Finding:** C1 stores the security-scoped bookmark for the last-opened user file in `UserDefaults`, which is an unencrypted plist in the app container. The bookmark is a persistent handle to a user file that may live outside the sandbox (iCloud Drive, etc.).
- **Concrete failure mode:** On a device backup or a compromised/jailbroken device, the plist exposes which file path the user last edited (information disclosure). The bookmark cannot be resolved without the app's entitlements, so this is disclosure of a path/handle, not direct file access — hence LOW, not HIGH.
- **Recommended action (architecture):** Acceptable to acknowledge given the low sensitivity and the project's "no accounts, no secrets" posture; if recorded as acknowledged, add the standard row to constitution.md "Acknowledged risks." No requirement change needed.
- **Status:** open

---

## Prescription feedback

These items concern HOW the design implements behavior (call shapes, storage choice, internal seam names) rather than WHAT the feature requires. Recorded here, not filed as findings — implementation prescription, not behavioral constraint.

- **DC-12 probe mechanism** ("create-and-remove a uniquely-named temporary entry, or the platform's writability query") — implementation prescription, not behavioral constraint. Design section: DC-12. The behavioral constraint (target is last directory only when writable, else local Documents, with no stray file) is sound; the specific probe technique is a build choice.
- **C1 storage = `UserDefaults`** — storage-mechanism prescription (the behavioral constraint is durability across termination, BR-1). Captured separately as F-004 only for its security dimension; the choice itself is prescription. Design section: C1.
- **C4 reuse of `DocumentView.onAppear` initial-mode seam / `MarkdownDocument` empty `init()`** — implementation prescription, not behavioral constraint. Design section: seam "C4 ↔ `DocumentGroup` create affordance." The behavioral constraint (new file opens in raw editor, keyboard up — BR-12/DC-8) stands independent of which seam conveys it.

---

## Summary

3 HIGH findings (F-001, F-002, F-003) share one root: the design adopts the existing SwiftUI `DocumentGroup` seam (declared correctly as the current codebase shape) but three declared behaviors — deferred-write create, last-directory-targeted create, and zero-flash resume — each require a `DocumentGroup` capability the design asserts rather than names. These are the highest-risk surfaces and were elevated per the reuse-pattern rule. 1 LOW security finding (F-004) on bookmark storage locality. Requirements text is internally consistent and testable; the risk is concentrated in the design's feasibility against the chosen framework, not in the requirements.
