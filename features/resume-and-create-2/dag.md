# DAG: resume-and-create-2

Three concerns (resume, create, back-navigation) plus a UIKit host swap. Eight tasks, four waves.

Generated: 2026-05-25

Drives `/build`. Wave N starts only after Wave N-1 completes. Tasks within a wave run in parallel.

The architectural through-line: foundational value types and stores (C1 LastFileStore, C5 NameProbe, C7 LocalDocumentsFallback) come first with no host dependency; the CreateTargetResolver (C6) composes them in Wave 2; the UIKit `UIDocumentBrowserViewController` host (C0) lands in Wave 3 as the structural seam swap that everything else attaches to; the launch/create/observe/back wiring (C2, C3, C4, C8) lands in Wave 4 once the host exists to attach to.

---

## Wave 1 — Foundational value types & stores (parallel, no host dependency)

### T-001 — `LastFileStore` (C1) — durable last-opened reference
**Description:** Create `Markus_v3/Resume/LastFileStore.swift`. A type that records a security-scoped bookmark for an opened file and resolves it back to an access-scoped URL on demand. Injectable `UserDefaults` (default `.standard`; tests pass an isolated suite). `recordLastOpened(_ url: URL)` writes a single bookmark, replacing any prior one (DC-1). `resolveLastOpened() -> URL?` returns the resolved, reachable URL or `nil`. A failed/stale/corrupt bookmark resolves to `nil` without crashing and **without clearing** the stored reference (DC-5, RETAIN-on-failure). Resolution is read-only — repeated reads never erase the reference (DC-15).
**Inputs:** design.md C1, DC-1, DC-5, DC-15; requirements BR-1, BR-15, BR-18, BR-20.
**Outputs:** `Markus_v3/Resume/LastFileStore.swift` (new).
**Dependencies:** none.
**Wave:** 1.
**Acceptance:** `LastFileStoreTests` suite passes — `recordAndResolve`, `referenceIsDurable`, `recordReplaces`, `deletedFileResolvesNil`, `corruptReferenceResolvesNil`, `retainOnFailure`, `readsAreNonDestructive`.

### T-002 — `NameProbe` (C5) — collision-free `Untitled` naming
**Description:** Create `Markus_v3/Create/NameProbe.swift`. A pure helper exposing `static func availableName(in dir: URL) -> URL` returning the lowest available `Untitled[ n].md`: `Untitled.md`, then `Untitled 2.md`, `Untitled 3.md`, … choosing the lowest free integer ≥ 2, gap-filling, never colliding with or mutating an existing entry, and never materializing the candidate file on disk. Always `.md` extension. Ignores non-`Untitled n` files. Anchored solely to the supplied directory (DC-11).
**Inputs:** design.md C5, DC-6, DC-7, DC-11; requirements BR-7, BR-8, BR-9, BR-22, BR-26.
**Outputs:** `Markus_v3/Create/NameProbe.swift` (new).
**Dependencies:** none.
**Wave:** 1.
**Acceptance:** `NameProbeTests` suite passes — `emptyDirectoryYieldsUntitled`, `probedNameHasMdExtension`, `firstCollisionYieldsTwo`, `secondCollisionYieldsThree`, `gapIsFilled`, `existingFilesUntouched`, `unrelatedFilesIgnored`, `anchoredToSuppliedDirectory`.

### T-003 — `LocalDocumentsFallback` (C7) — always-available create target
**Description:** Create `Markus_v3/Create/LocalDocumentsFallback.swift`. Vends the app container's local Documents directory (`FileManager` `.documentDirectory`, `.userDomainMask`) via `static func documentsDirectory() throws -> URL`, guaranteed to exist (creating if needed) and be writable. This is the guaranteed-writable fallback target C6 falls back to.
**Inputs:** design.md C7; requirements BR-11.
**Outputs:** `Markus_v3/Create/LocalDocumentsFallback.swift` (new).
**Dependencies:** none.
**Wave:** 1.
**Acceptance:** `LocalDocumentsFallbackTests` suite passes — `vendsDocumentsDirectory`, `directoryExistsAndWritable`.

---

## Wave 2 — Create-target composition

### T-004 — `CreateTargetResolver` (C6) + `LastDirectoryProviding` — target directory + writability probe
**Description:** Create `Markus_v3/Create/CreateTargetResolver.swift`. Declare a `LastDirectoryProviding` protocol with `func resolveLastDirectory() -> URL?` (the observable surface C6 consults; C1 will conform via T-008's wiring, and the resolver accepts any conformer for testability). `CreateTargetResolver(lastDirectoryProvider:)` exposes `resolveTargetDirectory() throws -> URL`: chooses the last directory **only** when it is reachable AND a side-effect-free-on-success writability probe succeeds (DC-12); otherwise falls back to `LocalDocumentsFallback.documentsDirectory()`. The probe leaves no residual file on success. The name probe (T-002) is anchored to whichever directory this resolver returns (DC-11/DC-12).
**Inputs:** design.md C6, DC-11, DC-12; requirements BR-10, BR-11, BR-21, BR-22, BR-23; T-002 (NameProbe), T-003 (LocalDocumentsFallback).
**Outputs:** `Markus_v3/Create/CreateTargetResolver.swift` (new), `LastDirectoryProviding` protocol (in the same file or a sibling).
**Dependencies:** T-002, T-003.
**Wave:** 2.
**Acceptance:** `CreateTargetResolverTests` suite passes — `writableLastDirectoryChosen`, `noLastReferenceFallsBack`, `unreachableLastDirectoryFallsBack`, `readOnlyLastDirectoryFallsBack`, `probeLeavesNoResidue`, `nameProbeAnchoredToResolvedDirectory`.

---

## Wave 3 — UIKit host swap (structural seam)

### T-005 — `BrowserHost` (C0) — `UIDocumentBrowserViewController`-backed scene host
**Description:** Replace the SwiftUI `DocumentGroup` scene in `Markus_v3/App/Markus_v3App.swift` with a custom UIKit host. Add `Markus_v3/Host/BrowserHostController.swift` (a `UIDocumentBrowserViewController` subclass or its delegate) and `Markus_v3/Host/BrowserHost.swift` (`UIViewControllerRepresentable`) presented from the app's `Scene`. The host owns three control points the `DocumentGroup` did not expose: (1) the create-document delegate callback (`documentBrowser(_:didRequestDocumentCreationWithHandler:)`) — exposed as a hook for T-007 to drive, stubbed here to a no-op/default; (2) presenting `DocumentView` via `UIHostingController` when a document opens, reusing `DocumentView` **unchanged** as the editor surface; (3) the scene-activation path where T-006 makes the resume decision — exposed as a hook, defaulting to the plain browser. This task delivers the host that opens a browser-selected file through the new presentation path and preserves the walking-skeleton open → render → edit → save loop (BR-6 hard-seam rule); the resume branch, create handler, open-observer, and back affordance are wired in Wave 4. No change to `MarkdownDocument` or the `.rendered`/`.raw` mode-switch logic.
**Inputs:** design.md C0, "Architectural decision" section, "Hard seam rule"; existing `Markus_v3App.swift`, `DocumentView.swift`, `MarkdownDocument.swift`.
**Outputs:** `Markus_v3/Host/BrowserHostController.swift` (new), `Markus_v3/Host/BrowserHost.swift` (new), rewritten `Markus_v3/App/Markus_v3App.swift`.
**Dependencies:** none (host is structural; it depends on existing walking-skeleton code, not on Wave 1/2 outputs — those attach in Wave 4).
**Wave:** 3.
**Acceptance:** App compiles and launches. A browser-selected `.md` file opens through the UIKit host into the existing rendered view and supports the existing tap → raw → edit → save loop with no regression (walking-skeleton + editor-foundation UI tests that exercise browser-open continue to pass). `testFirstLaunchShowsDocumentBrowser` passes (host's default landing is the browser). The build agent confirms the swap did not require touching `MarkdownDocument` or the mode switch; if it did, that is a hard-seam violation to escalate per design.md.

---

## Wave 4 — Feature wiring onto the host (parallel)

### T-006 — `LaunchResumeBranch` (C2) — resume-vs-browser decision at scene activation
**Description:** Add `Markus_v3/Resume/LaunchResumeBranch.swift` and wire it into C0's scene-activation / `NSUserActivity`-restoration path (T-005's exposed hook). At scene activation, before the browser is made the visible top view controller, ask `LastFileStore` (T-001) for a resolvable last file; if one resolves, present that file's editor (`UIHostingController` wrapping the unchanged `DocumentView`) as the scene's first content so the browser is never the visible top screen (DC-3). If none resolves, do nothing — the browser is the natural landing (DC-4). No error UI on failure. Also wire the test-launch arguments the UI tests rely on (`-uitest-reset-last-file`, `-uitest-stale-last-file`, `-uitest-seed-last-file`) into this path so launch state is deterministic.
**Inputs:** design.md C2, DC-2, DC-3, DC-4; requirements BR-2, BR-3, BR-4, BR-5, BR-6, BR-19; T-001 (LastFileStore), T-005 (host scene-activation hook).
**Outputs:** `Markus_v3/Resume/LaunchResumeBranch.swift` (new), scene-activation wiring + UI-test launch-argument handling in the host.
**Dependencies:** T-001, T-005.
**Wave:** 4.
**Acceptance:** UI tests pass — `testResumeLaunchOpensRenderedView`, `testResumeLaunchDoesNotLandOnBrowser`, `testStaleReferenceFallsThroughSilently`, `testResumedFileIsEditable`. `testFirstLaunchShowsDocumentBrowser` continues to pass. `testNoBrowserFlashOnResume` remains an executable `XCTSkip` (device-only; build-escalation trigger per design.md DC-3).

### T-007 — `CreateDocumentHandler` (C4) — deferred-write new-file flow
**Description:** Add `Markus_v3/Create/CreateDocumentHandler.swift` and bind it to C0's `documentBrowser(_:didRequestDocumentCreationWithHandler:)` callback (T-005's exposed hook). On Create: ask `CreateTargetResolver` (T-004) for the target directory, ask `NameProbe` (T-002) for the collision-free `Untitled[ n].md` URL in that directory, produce a new in-memory `MarkdownDocument` (existing empty `init()`), and open it directly into the **raw** editor with the keyboard active (DC-8) by reusing `DocumentView`'s existing initial-mode seam — no new mode transition. Withhold the on-disk write until first keystroke (DC-9): an abandoned (untyped) create completes the system creation handler leaving no file at the target and not consuming the name. On first persistence, route the file through `LastFileStore` (T-001) so it becomes the last-opened reference (DC-10). No change to `MarkdownDocument` or the mode switch.
**Inputs:** design.md C4, DC-6, DC-8, DC-9, DC-10, DC-12; requirements BR-7, BR-8, BR-12, BR-13, BR-14, BR-15, BR-23, BR-24, BR-25, BR-26; T-001, T-002, T-004, T-005.
**Outputs:** `Markus_v3/Create/CreateDocumentHandler.swift` (new), create-callback wiring in the host.
**Dependencies:** T-001, T-002, T-004, T-005.
**Wave:** 4.
**Acceptance:** UI tests pass — `testCreateDocumentOpensUntitledMd`, `testNewFileOpensInRawEditor`, `testNewFileEditorHasKeyboardFocus`, `testUntypedNewFileDoesNotConsumeName`, `testFirstLaunchThenCreate`, `testBackFromUntypedNewFileLeavesNoFile`. `testTypedNewFilePersists` and `testTypedNewFileBecomesLastOpened` remain executable `XCTSkip` stubs (on-disk container inspection); the build agent additionally inspects the container to confirm DC-9/DC-10 on-disk behavior per verify.md's untestable section.

### T-008 — `DocumentOpenObserver` (C3) + `BackToBrowser` (C8) — record-on-open and leading back affordance
**Description:** Two small wiring units that both attach at the `DocumentView`/host boundary and share the host's present-document seam, so they form one coupled session:
- **C3 (DocumentOpenObserver):** Add `Markus_v3/Resume/DocumentOpenObserver.swift`. At the point `DocumentView` becomes active for a real on-disk file (its existing `.onAppear`/configuration path or C0's present-document callback), forward the file's `fileURL` to `LastFileStore.recordLastOpened` (T-001). Single funnel so BR-1 holds for browser-open, resume, and newly-persisted files. Reads the already-present `fileURL` only — no Document-model change.
- **C8 (BackToBrowser):** Add the standard navigation-bar leading back chevron to **both** rendered and raw modes in `DocumentView`'s existing `.toolbar` (alongside the trailing "Show rendered" item), dismissing the `UIHostingController` presented from C0 to return to the browser (DC-13). The interactive edge-swipe-pop comes free with that presentation (DC-14). The dismiss path must **not** call into `LastFileStore`'s clear (DC-15).
**Inputs:** design.md C3, C8, DC-13, DC-14, DC-15, seam "C3 ↔ DocumentView lifecycle", seam "C8 ↔ navigation chrome"; requirements BR-1, BR-16, BR-17, BR-18; T-001, T-005.
**Outputs:** `Markus_v3/Resume/DocumentOpenObserver.swift` (new), toolbar back-item additions in `Markus_v3/Views/DocumentView.swift`.
**Dependencies:** T-001, T-005.
**Wave:** 4.
**Acceptance:** UI tests pass — `testBackChevronFromRenderedReturnsToBrowser`, `testBackChevronFromRawEditorReturnsToBrowser`, `testEdgeSwipeBackReturnsToBrowser`, `testBackThenRelaunchStillResumes`. Logic-level `LastFileStoreTests.readsAreNonDestructive` (already green from T-001) confirms the dismiss path's non-clearing contract holds. The build agent confirms the record-on-open funnel fires for all three entry paths.

---

## Wave summary

| Wave | Tasks | Can parallelize? |
|------|-------|-----------------|
| 1 | T-001, T-002, T-003 | Yes — all independent |
| 2 | T-004 | Single task (composes T-002 + T-003) |
| 3 | T-005 | Single task (structural host swap) |
| 4 | T-006, T-007, T-008 | Yes — all attach to T-005's host via independent hooks |

**Total tasks:** 8
**Total waves:** 4

No sizing warning — 8 tasks across 4 waves, within the 3–4 wave target and fitting one screen.

**Host-swap sizing note.** Replacing the SwiftUI `DocumentGroup` with a `UIDocumentBrowserViewController`-backed host (T-005) is a significant structural change, but UIKit is already in the SDK — no new framework, dependency, or deploy path is introduced. It is therefore a single well-bounded task, not grounds for splitting the feature. T-005 is intentionally isolated in its own wave so the host exists and is proven (walking-skeleton loop preserved) before the four feature behaviors attach to it in Wave 4; this keeps each Wave-4 task to a single hook on a known-good host.

**Why T-008 bundles C3 and C8.** Both attach at the same `DocumentView`/host present-document boundary and both are small. C3 reads `fileURL` to record; C8 adds toolbar items and guarantees the dismiss path does not clear C1. Splitting them would force two separate touches of the same `DocumentView` toolbar/lifecycle seam in the same wave; bundling produces one coherent, testable boundary in one session.

---

## Dependency graph

```
T-001   T-002   T-003          ← Wave 1 (all independent)
  |       \      /
  |        T-004                ← Wave 2  (T-004 ← T-002, T-003)
  |          |
  |        T-005                ← Wave 3  (structural host swap, no Wave 1/2 dep)
  |       /  |  \
  |      /   |   \
T-006   T-007   T-008           ← Wave 4
```

More precisely:

- T-004 ← T-002, T-003
- T-005 ← (existing walking-skeleton code only)
- T-006 ← T-001, T-005
- T-007 ← T-001, T-002, T-004, T-005
- T-008 ← T-001, T-005

---

## Next step

After this DAG is committed, `verify.md`'s task → test mapping is filled in (Stage 5), then `/build` orchestrates the build wave-by-wave.
