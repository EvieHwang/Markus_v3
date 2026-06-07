# DAG — mac-catalyst-shell-14

Dependency graph of build tasks for the Mac Catalyst **platform shell** over the
existing iOS/iPad build: enable the Mac (Catalyst) destination, then a standard
File / Edit / View menu bar driving the *existing* `EditorActions` handles and
open path; **File → Open (⌘O)** funneling through `presentDocument(at:)`; the
F-001-resolved load-success-gated open-while-open composed host operation;
pointer/hover feedback on the two existing tap targets; single-window state
restoration deferring to the existing resume path; and Mac app-icon assets. **No
new product capability and no new Shape component.**

Sources: `requirements.md` (US-*, AC-*, FM-*, edge cases), `design.md`
(Components A–E, seams S-1..S-6, cross-cutting X-1..X-4, the *Resolved deferred
question — AC-3.5* section), `adversarial-review.md` (F-001 resolved/verified),
`verify.md` (test→task mapping), `tests/` (reference spec tests).

## Conventions

- **Inputs**: spec files and source files the task reads.
- **Outputs**: source/asset files modified/added; behavior delivered
  (AC-/FM-/C-/S- refs).
- **Acceptance**: an objectively checkable condition for marking the task
  `complete` in `state.md`. The default is "the tests tagged to this task in
  `verify.md` (mirrored into `Markus_v3Tests/` and `Markus_v3UITests/`) pass."
  The Swift Testing seam-probe files run on any destination (they model pure
  decisions); the XCUITest files (`MacMenuBarUITests`, `MacPointerUITests`)
  require a **Mac Catalyst run destination** with a pointer device — the menu
  bar, the system open panel, scene restoration across relaunch, and a real
  hover are unreachable on the iPhone 17 simulator named in constitution.md (per
  `verify.md` → "Destination requirements"). Task-specific extras are listed
  where they apply.

## Decomposition rationale (why these tasks, and not more or fewer)

The natural decomposition follows the design's five components plus the
Catalyst project-configuration step the components depend on:

- **T-001 — Catalyst destination enablement** must come first: the menu bar,
  File → Open panel, scene restoration, pointer, and Mac icon are all Catalyst
  surfaces that only exist once the Mac (Catalyst) destination is enabled on the
  target and the build produces a Catalyst app. This is a **target/config
  change, not a new framework or deploy path** (no new dependency, no CI path) —
  it is the wave-1 root because the other tasks' XCUITest acceptance runs on the
  Catalyst destination it provides.
- **T-002 — Component A (menu bar build + enablement)** is one cohesive contract:
  the File/Edit/View structure, the ⌘-equivalents that match the firing bindings,
  responder-chain enablement, and routing each Markus item to the *same*
  `EditorActions` / `presentDocument` seam. Splitting per-menu or per-item would
  fracture "one menu structure, each item a trigger onto an existing flow"
  (C-1.*, C-2.*, S-1, S-2) across units.
- **T-003 — Component B base (File → Open adapter)** is the panel-in /
  `presentDocument(at:)`-out adapter for the *no-document-open* path (present
  panel, type-constrain, funnel the URL, inherit cancel/fail/non-md/resume-target
  semantics). One adapter, one seam (C-3.*, S-3).
- **T-004 — Component B F-001 (composed open-while-open operation)** is split out
  because it is a *distinct behavioral contract* — the load-success-gated
  composed host operation (load → conditional teardown → present) that the
  adversarial review pinned (F-001 / C-2.4 / S-4 / DC-10) — and it **depends on
  T-003**: it composes the open funnel T-003 establishes with the existing
  teardown, behind a load-success gate. Folding it into T-003 would aggregate the
  simple adapter with the higher-risk ordering guarantee that is the feature's
  correctness centrepiece.
- **T-005 — Component C (pointer/hover layer)** is the pure enhancement overlay on
  the two existing targets (C-4.*, S-5); independent of menu/open/restoration.
- **T-006 — Component D (Mac scene-restoration bridge)** is the thin bridge from
  the Mac scene-restoration entry into the existing `LaunchResumeBranch` decision
  (C-5.*, S-6); independent of the others.
- **T-007 — Component E (Mac app-icon slots)** populates the empty `idiom:mac`
  slots additively (C-6.*); a pure asset-catalog task, independent of the rest.

Not fewer: each carries a distinct behavioral contract with its own dedicated
spec test(s); the "split any task that aggregates distinct concerns" rule keeps
the F-001 ordering guarantee (T-004) separate from the plain adapter (T-003).
Not more: each component is a single cohesive contract completable in one build
session with margin.

## Wave 1 — Catalyst destination root

### T-001 — Enable the Mac (Catalyst) destination on the target

- **Description:** Enable the **Mac (Catalyst)** destination on the `Markus_v3`
  target so the project builds and launches as a Catalyst Mac app (Apple Silicon).
  This is a target/configuration change only — it adds **no new framework, no new
  dependency, and no new deploy path**. It is the root the other tasks build on:
  the menu bar (T-002), File → Open panel (T-003/T-004), scene restoration
  (T-006), pointer (T-005), and Mac icon (T-007) are all Catalyst surfaces that
  presuppose a Catalyst build. No product behavior changes in this task; running
  the existing iOS/iPad build under Catalyst should preserve open / render / edit
  / save / conflict / resume behavior unchanged (the iPad-in-a-window baseline the
  rest of the feature then makes feel native).
- **Inputs:** `design.md` Stage-2 framing + "Existing seams confirmed" (the build
  must run under Catalyst before any component lands); `requirements.md` Context
  (Catalyst build, no new capability); `declaration.md` (Catalyst Mac build);
  the Xcode project (`Markus_v3.xcodeproj`), target build settings / supported
  destinations.
- **Outputs:**
  - Modified: the `Markus_v3` target build settings / `project.pbxproj` to enable
    the Mac (Catalyst) supported destination; any signing/capability adjustment
    the Catalyst destination requires (automatic signing per constitution
    Deployment).
  - Behavior delivered: a Catalyst Mac build that builds, launches, and preserves
    the inherited iOS/iPad behavior (X-3); the run destination the XCUITest files
    require.
- **Dependencies:** none (wave-1 root).
- **Wave:** 1.
- **Acceptance:** the project builds and launches on a **Mac Catalyst run
  destination**, and the mirrored XCUITest harness (`MacMenuBarUITests`,
  `MacPointerUITests`) launches the app on that destination — the T-001-tagged
  harness setup (`MacMenuBarUITests.setUpWithError` /
  `MacPointerUITests.setUpWithError` launching on the Catalyst destination)
  succeeds. Existing iOS/iPad behavior is unchanged under the Catalyst build (no
  regression to open/render/edit/save/conflict/resume). Until this task lands the
  Catalyst-destination XCUITest cases cannot run at all.

## Wave 2 — Shell components over the Catalyst build (parallel)

### T-002 — Catalyst menu bar (Component A): File/Edit/View structure, enablement, and routing

- **Description:** Build the Catalyst menu bar (design Component A —
  `CatalystMenuBuilder`) by overriding the application menu-build hook on
  `AppDelegate`. Construct the **File** (Open… ⌘O, Save ⌘S, Close ⌘W — **no New**),
  **View** (a stable-titled **Toggle Preview** on ⌘P), and **Edit** (system-
  standard Undo/Redo/Cut/Copy/Paste/Select All, deferred entirely to the system
  text responder) structure. Each Markus item is a **trigger onto the existing
  flow**, never a second implementation: Save → `saveNow` → `triggerSave()`;
  Close → `closeEditor` → `dismissPresentedEditor()`; Toggle Preview →
  `toggleMode`; Open… → the Component-B open command (T-003). The shown ⌘
  equivalent equals the firing binding and menu-vs-shortcut invocation produce
  identical effects (C-1.4, C-1.5, FM-1). **Enablement** is driven by editor-
  session presence read through the responder chain (S-1): Save / Close / Toggle
  Preview are disabled at the browser (no installed `EditorActions` handles) and
  enabled with a document open; Open is always enabled; pressing ⌘S/⌘W/⌘P at the
  browser is a structural no-op (command unavailable, never fires into `nil` — no
  crash, browser undisturbed). Every enabled item is keyboard-reachable (WCAG 2.1
  AA full keyboard access). The exact responder that validates the document-scoped
  commands is a build choice bounded by the S-1 observable guard.
- **Inputs:** `design.md` Component A (C-1.1–C-1.5, C-2.1–C-2.3, C-2.5), seams
  S-1/S-2, X-2/X-4; `requirements.md` US-1/US-2 (AC-1.1–1.6, AC-2.1–2.4 +
  disabled-shortcut edge), FM-1, FM-4, FM-6, FM-10; ground-truth seams in
  `Markus_v3/Host/EditorActions.swift`,
  `Markus_v3/Host/EditorKeyCommandHostingController.swift`,
  `Markus_v3/Host/BrowserHostController.swift`,
  `Markus_v3/App/Markus_v3App.swift` (AppDelegate).
- **Outputs:**
  - Added: the menu-build override on `AppDelegate` (design Component A); mirrored
    Swift Testing tests in `Markus_v3Tests/` and XCUITest cases in
    `Markus_v3UITests/` (from `MenuBarRoutingTests.swift` and the menu/enablement
    cases of `MacMenuBarUITests.swift`).
  - Modified (only as needed to register/route/validate the commands):
    `BrowserHostController` / `EditorKeyCommandHostingController` (expose the
    existing handles to the menu's responder-chain validation; route Open to the
    Component-B command).
  - Behavior delivered: US-1/US-2; FM-1, FM-4, FM-6, FM-10; C-1.1–C-1.5,
    C-2.1–C-2.3, C-2.5; S-1, S-2; X-2, X-4.
- **Dependencies:** T-001 (the menu bar exists only on a Catalyst build). The
  File → Open *item* routes to Component B (T-003); the menu **structure/routing**
  is this task, the open **adapter** is T-003.
- **Wave:** 2.
- **Acceptance:** the T-002-tagged tests in `verify.md` pass — Swift Testing
  (`MenuBarRoutingTests`): `fileMenu_containsOpenSaveClose_noNew`,
  `viewMenu_containsStableTitledTogglePreview_onCmdP`, `editMenu_isSystemStandardOnly`,
  `saveMenuItem_drivesExistingSaveFlow`, `closeMenuItem_drivesExistingCloseFlow`,
  `togglePreviewMenuItem_drivesExistingToggleFlow`, `openMenuItem_routesToPresentDocument`,
  `shownShortcutEqualsFiringBinding`, `everyEnabledItemIsKeyboardReachable`,
  `documentScopedItems_disabledWithNoDocument`, `documentScopedItems_enabledWithDocument`,
  `openIsAlwaysEnabled`, `editItems_followSystemEnablement`,
  `enablementAndLiveHandleAreTheSameFact`, `shortcuts_atBrowser_areStructuralNoOps`;
  XCUITest (Catalyst destination): `test_fileMenu_containsOpenSaveClose_noNew`,
  `test_viewMenu_containsStableTitledTogglePreview`, `test_editMenu_containsSystemStandardItems`,
  `test_menuTogglePreview_matchesCmdP`, `test_menuClose_returnsToBrowser_likeCmdW`,
  `test_menuSave_showsNoNewConfirmationUI`, `test_documentScopedItems_disabledAtBrowser`,
  `test_documentScopedItems_enabledWithDocument`, `test_disabledShortcutsAtBrowser_areStructuralNoOps`.
  The File menu has Open/Save/Close and **no New**; menu and shortcut converge on
  one implementation per action.

### T-003 — File → Open adapter (Component B base): panel → presentDocument funnel

- **Description:** Build the File → Open command (design Component B —
  `MacOpenCommand`) as a picker-to-funnel **adapter**: present the system open
  panel constrained to `MarkdownDocument.readableContentTypes` (`.md` /
  `.markdown`), and hand the chosen URL to the **existing** `presentDocument(at:)`
  (scope acquire → size pre-check → coordinated read → strict UTF-8 decode →
  `installEditorSession` on success → `didOpenDocument` →
  `LastFileStore.recordLastOpened`). It introduces **no** second open, decode,
  read, or security-scoped-bookmark mechanism (FM-2); the panel's only output is a
  URL into the existing funnel (S-3). Inherited semantics, **for the no-document-
  open path**: a successfully opened file becomes the resume target (C-3.4); cancel
  leaves everything untouched (C-3.5); a failing or non-markdown file surfaces the
  existing `openPathAlert` "Couldn't open" and releases the security-scoped
  resource (C-3.6). Reachable from both the File → Open menu item (T-002) and the
  ⌘O shortcut (the same command). **Open-while-open ordering is T-004.**
- **Inputs:** `design.md` Component B (C-3.1–C-3.6), seam S-3, the OWASP security
  note, X-3; `requirements.md` US-3 (AC-3.1–3.4 + cancel / failing / non-md edge
  cases), FM-2; ground-truth `BrowserHostController.presentDocument(at:)`,
  `loadMarkdownDocument(at:)`, `MarkdownDocument.readableContentTypes`,
  `LastFileStore.recordLastOpened`.
- **Outputs:**
  - Added: the `MacOpenCommand` open adapter (design Component B); mirrored Swift
    Testing tests in `Markus_v3Tests/` (from the panel/funnel/cancel/fail/non-md/
    resume-target cases of `MacOpenCommandTests.swift`) and the open XCUITest
    cases in `Markus_v3UITests/` (from `MacMenuBarUITests.swift`).
  - Modified: `BrowserHostController` only as needed to invoke the open panel and
    funnel the URL into the existing `presentDocument(at:)` (no new open path).
  - Behavior delivered: US-3 (AC-3.1–3.4 + cancel/failing/non-md); FM-2;
    C-3.1–C-3.6; S-3.
- **Dependencies:** T-001 (the system open panel is a Catalyst surface). The
  File → Open *menu item* that invokes this command is wired in T-002.
- **Wave:** 2.
- **Acceptance:** the T-003-tagged tests in `verify.md` pass — Swift Testing
  (`MacOpenCommandTests`): `open_presentsSystemPanel`,
  `open_panelConstrainedToMarkdownTypes`, `open_chosenFile_funnelsThroughPresentDocument`,
  `open_success_recordsAsResumeTarget`, `open_canceled_leavesEverythingUntouched`,
  `open_failingFile_surfacesExistingAlertAndReleasesScope`,
  `open_nonMarkdownFile_handledByExistingGates`, `menuSave_noNewUI_failureViaExistingRouter`;
  XCUITest (Catalyst destination): `test_fileOpen_presentsSystemPanel`,
  `test_fileOpen_opensChosenMarkdownFile`, `test_openCanceled_leavesCurrentDocumentUntouched`.
  The open panel's only output is a URL into `presentDocument(at:)`; no second
  open/decode/bookmark mechanism exists.

### T-004 — Open-while-open composed host operation (Component B, F-001): load-success-gated

- **Description:** Build the **load-success-gated** open-while-open composed host
  operation (design C-2.4 / S-4 — the resolved AC-3.5 transition; **addresses
  adversarial F-001**). When File → Open is chosen with a document already open,
  the operation is **load → conditional teardown → present**: (1) load and
  validate the chosen URL first via the existing pure `loadMarkdownDocument(at:)`
  (no state mutation); (2) on `.alert`, surface the existing `openPathAlert`
  "Couldn't open" and leave the current session, detector, and document **fully
  intact** (the inherited DC-10 guarantee — identical to canceled Open); (3) only
  on `.document` success tear down the prior session (the existing teardown's
  synchronous save + detector stop) and present the new document, with the present
  sequenced **after** the teardown's dismissal completes (avoiding the double-
  present race). The prior document is never relinquished before the new document
  has successfully loaded; the result is one window, one document, no two-docs-live
  moment, no multi-document model (FM-8). This requires a *composed* host operation
  because the existing `dismissPresentedEditor()` is atomic and unconditional and
  cannot be invoked teardown-first without breaking DC-10. The concrete present-
  after-dismiss mechanism (dismiss-completion closure / non-animated present after
  teardown / a combined host method) is a build choice bounded by the observable
  guard "a failed File → Open never leaves the user worse off than a canceled one."
- **Inputs:** `design.md` *Resolved deferred question — AC-3.5* (steps 1–3),
  C-2.4, seam S-4, X-3; `requirements.md` AC-3.5 + "Open of an unreadable /
  failing file" edge case, FM-8 (DC-10 inherited); `adversarial-review.md` F-001
  (resolved/verified); ground-truth `dismissPresentedEditor()` (atomic teardown),
  `presentDocument(at:)` (DC-10 lives within one call), `loadMarkdownDocument(at:)`
  (pure validation).
- **Outputs:**
  - Added: the composed open-while-open host operation (design C-2.4 / S-4);
    mirrored Swift Testing tests in `Markus_v3Tests/` (from the `openWhileOpen_*`
    cases of `MacOpenCommandTests.swift`) and XCUITest cases in `Markus_v3UITests/`
    (the open-while-open cases of `MacMenuBarUITests.swift`).
  - Modified: `BrowserHostController` to add the composed load → conditional
    teardown → present operation (composing the existing teardown and
    `presentDocument`/`installEditorSession` behind a load-success gate); no new
    read/decode/bookmark mechanism.
  - Behavior delivered: AC-3.5 (resolved open-while-open transition); FM-8; C-2.4;
    S-4; DC-10 inherited and preserved.
- **Dependencies:** T-003 (composes the open funnel T-003 establishes with the
  existing teardown behind a load-success gate); T-001 (Catalyst build).
- **Wave:** 3.
- **Acceptance:** the T-004-tagged tests in `verify.md` pass — Swift Testing
  (`MacOpenCommandTests`): `openWhileOpen_success_replacesSingleDocument`,
  `openWhileOpen_success_loadsBeforeTeardown`, `openWhileOpen_failedNewOpen_preservesPrior`,
  `openWhileOpen_failedNewOpen_noWorseThanCancel`, `openWhileOpen_addsNoMultiDocumentState`;
  XCUITest (Catalyst destination): `test_openWhileOpen_success_replacesSingleDocument`,
  `test_openWhileOpen_failedNewOpen_preservesPriorDocument`. The success path runs
  `[.loadNew, .tearDownPrior, .presentNew]` (load first); a **failed** new open
  runs load only, leaves `activeDocument` on the **prior** file with its detector
  running, surfaces the existing alert, and is no worse than a canceled open
  (DC-10); single window, no two-docs-live.

### T-005 — Pointer / hover affordance layer (Component C)

- **Description:** Attach pointer/hover feedback (design Component C —
  `PointerAffordanceLayer`) to the two existing tap targets — the `RenderedView`
  tap-to-edit surface and the eye mode-switch control — as a **pure enhancement
  layer**. The hover region coincides with the *existing* tap/click region of each
  target (clickable area == tappable area — S-5); a click routes through the same
  action as a tap (tap-to-edit → rendered→raw; eye → seed rendered anchor → save →
  `mode = .rendered`), driving no parallel path (C-4.1, C-4.2). It changes no
  action, hit area, or existing gesture (tap-to-edit, the L→R swipe-to-raw,
  vertical scroll, the edge-pan dismiss, the toolbar buttons — C-4.3, FM-5).
  Pointer is **never the sole affordance**: every pointer-fed action is also
  reachable by tap/click and by ⌘P / View → Toggle Preview (C-4.4). With no
  pointer device the feedback is simply never triggered and nothing is hidden,
  disabled, or changed (C-4.5). It adds no new interactive element and no new
  action.
- **Inputs:** `design.md` Component C (C-4.1–C-4.5), seam S-5, X-1;
  `requirements.md` US-4 (AC-4.1–4.4 + no-pointer edge case), FM-5; ground-truth
  `Markus_v3/Views/RenderedView.swift` (tap-to-edit `.onTapGesture` /
  `.contentShape`), `Markus_v3/Views/DocumentView.swift` (the eye button).
- **Outputs:**
  - Added: the pointer/hover affordance layer over the two existing targets
    (design Component C); mirrored Swift Testing tests in `Markus_v3Tests/` (from
    `PointerAffordanceTests.swift`) and XCUITest cases in `Markus_v3UITests/`
    (from `MacPointerUITests.swift`).
  - Modified: `RenderedView.swift` (hover feedback on the tap-to-edit surface,
    hit area unchanged), `DocumentView.swift` (hover feedback on the eye control).
  - Behavior delivered: US-4; FM-5; C-4.1–C-4.5; S-5; X-1.
- **Dependencies:** T-001 (pointer/hover and the click path are exercised on the
  Catalyst destination with a pointer).
- **Wave:** 2.
- **Acceptance:** the T-005-tagged tests in `verify.md` pass — Swift Testing
  (`PointerAffordanceTests`): `tapToEditSurface_showsFeedback_clickPerformsExistingTransition`,
  `eyeControl_showsFeedback_clickPerformsExistingTransition`,
  `clickableRegionEqualsTappableRegion`, `clickActionIdenticalToTap_noGestureChanged`,
  `everyPointerFedAction_alsoReachableWithoutPointer`,
  `noPointerDevice_feedbackNeverTriggered_behaviorUnchanged`; XCUITest (Catalyst
  destination with a pointer): `test_tapToEditSurface_clickPerformsExistingTransition`,
  `test_eyeControl_clickPerformsExistingTransition`, `test_clickAndTap_produceSameTransition`,
  `test_existingGesturesStillWork_withPointerLayer`, `test_modeSwitch_reachableWithoutPointer`,
  `test_noPointerDevice_tapStillWorks_nothingHidden`. The clickable area equals the
  tappable area before and after the layer is added; click == tap.

### T-006 — Mac scene-restoration bridge (Component D)

- **Description:** Build the Mac single-window state-restoration bridge (design
  Component D — `MacRestorationBridge`) that, on relaunch, hands control to the
  **existing** resume decision: the Mac scene-restoration entry routes into
  `host.initialResumeAction` → `LaunchResumeBranch.resume(into:)` →
  `LastFileStore.resolveLastOpened()` (security-scoped bookmark, path fallback).
  The **document identity** is never stored or resolved by a new Mac-only store
  (FM-3, S-6) — the OS may persist window/scene chrome, but *which* file is chosen
  is solely the existing bookmark/path resolution. It restores a **single**
  window/document (C-5.2, FM-8), the **same** file resolved the **same** way as
  iOS/iPad resume (C-5.3). Edge cases inherit the existing fail-closed behavior: a
  moved file retargets via the bookmark; a deleted file (or first-ever launch)
  resolves nothing and lands on the browser with **no error UI** (C-5.4, C-5.5);
  a restored document enters the **unchanged** conflict/deletion/save lifecycle
  (C-5.6, FM-7). No new persistence store and no "file missing" recovery dialog.
- **Inputs:** `design.md` Component D (C-5.1–C-5.6), seam S-6, X-3;
  `requirements.md` US-5 (AC-5.1–5.3 + moved/deleted / first-launch / lifecycle
  edge cases), FM-3, FM-7, FM-8; ground-truth `Markus_v3/Resume/LaunchResumeBranch.swift`,
  `LastFileStore.resolveLastOpened()`, `SceneDelegate.scene(_:willConnectTo:options:)`,
  `host.initialResumeAction`.
- **Outputs:**
  - Added: the Mac scene-restoration bridge into the existing resume decision
    (design Component D); mirrored Swift Testing tests in `Markus_v3Tests/` (from
    the `restoration_*` cases of `MacRestorationTests.swift`) and XCUITest cases
    in `Markus_v3UITests/` (the relaunch/first-launch/moved-deleted cases of
    `MacMenuBarUITests.swift`).
  - Modified: `SceneDelegate` / the host's scene-restoration entry only as needed
    to route Mac restoration into `LaunchResumeBranch.resume(into:)` (no new
    document-identity store).
  - Behavior delivered: US-5; FM-3, FM-7, FM-8; C-5.1–C-5.6; S-6.
- **Dependencies:** T-001 (Mac window-state restoration is a Catalyst behavior).
- **Wave:** 2.
- **Acceptance:** the T-006-tagged tests in `verify.md` pass — Swift Testing
  (`MacRestorationTests`): `restoration_restoresViaExistingResumePath`,
  `restoration_singleWindow`, `restoration_consistentWithIOSResume`,
  `restoration_movedFile_retargetsViaBookmark`, `restoration_deletedFile_landsOnBrowserNoError`,
  `restoration_firstLaunch_landsOnBrowser`, `restoration_restoredDocument_entersUnchangedLifecycle`;
  XCUITest (Catalyst destination): `test_relaunch_restoresPreviouslyOpenDocument`,
  `test_firstLaunch_landsOnBrowser`, `test_movedOrDeletedPriorDocument_landsOnBrowserNoError`.
  The document choice is made solely by `LaunchResumeBranch` / `LastFileStore`
  (no new identity store); restoration restores a single window.

### T-007 — Mac app-icon slots (Component E)

- **Description:** Populate the 12 empty `"idiom":"mac"` slots in
  `Assets.xcassets/AppIcon.appiconset/Contents.json` (design Component E —
  `MacAppIconSlots`) with a sized macOS icon set (16/32/128/256/512 @1x/@2x) so
  the Dock, Finder, and app switcher show a real Markus icon, not a placeholder or
  blank (C-6.1). The change is **additive**: the existing iOS/iPad universal slots
  (referencing `Markus-app-icon.png`) are untouched and unregressed; both
  platforms show their correct icon (C-6.2, FM-9). The exact source images are a
  build choice bounded by "real Mac icon present, iOS/iPad icon unchanged."
- **Inputs:** `design.md` Component E (C-6.1, C-6.2) + the 12-Mac-slot note;
  `requirements.md` US-6 (AC-6.1, AC-6.2), FM-9; ground-truth
  `Assets.xcassets/AppIcon.appiconset/Contents.json`, `Markus-app-icon.png`.
- **Outputs:**
  - Added: the Mac-idiom icon assets and their `filename` entries in
    `AppIcon.appiconset/Contents.json`; mirrored Swift Testing tests in
    `Markus_v3Tests/` (from the `macIconSlots_*` cases of
    `MacRestorationTests.swift`).
  - Modified: `Assets.xcassets/AppIcon.appiconset/Contents.json` (Mac slots only;
    iOS/iPad entries unchanged).
  - Behavior delivered: US-6; FM-9; C-6.1, C-6.2.
- **Dependencies:** T-001 (the Mac icon slots matter for the Catalyst build). The
  asset edit itself is independent of the other components.
- **Wave:** 2.
- **Acceptance:** the T-007-tagged tests in `verify.md` pass — Swift Testing
  (`MacRestorationTests`): `macIconSlots_arePopulated`, `macIconSlots_doNotRegressIOSIcon`.
  No empty/placeholder Mac slot remains; the iOS/iPad icon is unchanged.

## Wave summary

| Wave | Tasks | Parallelism |
|------|-------|-------------|
| 1 | T-001 | root — enable the Mac (Catalyst) destination; everything else builds on it |
| 2 | T-002, T-003, T-005, T-006, T-007 | full — five independent shell components over the Catalyst build (menu bar / open adapter / pointer / restoration / icon); no ordering dependency among them; land as separate commits |
| 3 | T-004 | the F-001 composed open-while-open operation; depends on T-003's open funnel |

## Dependency graph summary

```
Wave 1 (root):
  T-001  Enable the Mac (Catalyst) destination on the target          (no deps)

Wave 2 (parallel, all depend on T-001):
  T-002  Catalyst menu bar (Component A) — structure/enablement/routing
  T-003  File → Open adapter (Component B base) — panel → presentDocument
  T-005  Pointer / hover affordance layer (Component C)
  T-006  Mac scene-restoration bridge (Component D)
  T-007  Mac app-icon slots (Component E)

Wave 3:
  T-004  Open-while-open composed host operation (Component B, F-001)  (deps: T-003, T-001)
```

The Catalyst-destination task (T-001) is the wave-1 root: menu bar, open,
pointer, restoration, and icon all presuppose a Catalyst build. They parallelize
in wave 2. The F-001 composed open-while-open operation (T-004) depends on the
File → Open adapter (T-003) because it composes that open funnel with the
existing teardown behind a load-success gate, so it sits in wave 3.

## Task → behavior trace (at-a-glance)

| Task | Component | Primary US/AC/FM | Design contracts | Primary test files |
|------|-----------|------------------|------------------|--------------------|
| T-001 | Catalyst destination | Context / X-3 (no regression) | Stage-2 framing; "Existing seams confirmed" | XCUITest harness setup (`MacMenuBarUITests`, `MacPointerUITests`) |
| T-002 | A (menu bar) | US-1/2; AC-1.*, AC-2.*; FM-1/4/6/10 | C-1.*, C-2.1–2.3, C-2.5, S-1, S-2, X-2, X-4 | `MenuBarRoutingTests.swift`, `MacMenuBarUITests.swift` (menu/enablement) |
| T-003 | B base (Open adapter) | US-3; AC-3.1–3.4 + cancel/fail/non-md; FM-2 | C-3.1–3.6, S-3 | `MacOpenCommandTests.swift` (panel/funnel), `MacMenuBarUITests.swift` (open) |
| T-004 | B F-001 (open-while-open) | AC-3.5; FM-8 (DC-10) | C-2.4, S-4 | `MacOpenCommandTests.swift` (`openWhileOpen_*`), `MacMenuBarUITests.swift` (open-while-open) |
| T-005 | C (pointer/hover) | US-4; AC-4.*; FM-5 | C-4.1–4.5, S-5, X-1 | `PointerAffordanceTests.swift`, `MacPointerUITests.swift` |
| T-006 | D (restoration) | US-5; AC-5.*; FM-3/7/8 | C-5.1–5.6, S-6, X-3 | `MacRestorationTests.swift` (restoration_*), `MacMenuBarUITests.swift` (relaunch/first-launch/moved) |
| T-007 | E (Mac icon) | US-6; AC-6.*; FM-9 | C-6.1, C-6.2 | `MacRestorationTests.swift` (macIconSlots_*) |

## Sizing assessment

**Comfortable single-feature DAG.** Seven atomic tasks across three waves — one
Catalyst-destination root, five parallel shell components, and one wave-3 task
(the F-001 composed open-while-open operation) gated on the open adapter. This is
within the ≤ 3–4 wave ceiling and fits one screen. **No new framework,
dependency, or deploy path is introduced** — every component reuses this app's
own existing action flows (`EditorActions`, `presentDocument(at:)`,
`LaunchResumeBranch` / `LastFileStore`, the eye/tap-to-edit targets) over
standard Catalyst/UIKit mechanisms (the menu-build hook, the system open panel,
`UIPointerInteraction`, scene state restoration). Enabling the Mac (Catalyst)
destination is a **target/config change, not a new framework or deploy path**, so
it does not push the DAG oversize. Each task carries a distinct behavioral
contract with its own dedicated spec test(s) and is comfortably completable in one
build session with margin; the higher-risk F-001 ordering guarantee is isolated in
its own task (T-004) rather than aggregated into the plain adapter (T-003).

Every task has at least one mapped test (see `verify.md` — authoritative task→test
mapping). No task is left uncovered.
