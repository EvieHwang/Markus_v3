# Verify — mac-catalyst-shell-14

Coverage map from `requirements.md` (US-*, AC-*, FM-*, edge cases) and `design.md`
(component contracts C-1.*/C-2.*/C-3.*/C-4.*/C-5.*/C-6.*, behavioral seams
S-1..S-6, cross-cutting X-1..X-4) to the reference spec tests under
`features/mac-catalyst-shell-14/tests/`.

These spec tests are **reference / human-readable** — they are NOT part of the
Xcode test target (constitution.md → Testing). The build implementer mirrors them
into `Markus_v3Tests/` (Swift Testing) and `Markus_v3UITests/` (XCUITest) when
picking up each task, adjusting symbol / identifier / menu-title names to match the
live host.

The **Task ID column is intentionally absent** at this stage: the DAG does not yet
exist. `/dag` applies the authoritative task → test mapping in the next stage (as it
did for feature 13). Tests are written to **fail / be unimplemented** until the
feature is built: the Swift Testing files reference the as-yet-unbuilt seams
(`CatalystMenuBuilder`, `MacOpenCommand` funnel, the composed open-while-open host
operation, `MacRestorationBridge`, the populated Mac icon slots, the
`PointerAffordanceLayer`), and the XCUITest files assert Catalyst behavior (a real
menu bar, the system open panel, scene restoration, pointer hover) that does not
exist before the build.

## Test files

| File | Framework | Concern |
|------|-----------|---------|
| `MenuBarRoutingTests.swift` | Swift Testing | Part 1 structure + enablement + routing seams: File has Open/Save/Close (no New); View has a stable-titled Toggle Preview on ⌘P; Edit defers to the system responder; each menu item drives the SAME EditorActions / presentDocument flow as its shortcut; shown ⌘ equivalents equal the firing bindings; full keyboard access; document-scoped items disabled with no document / enabled with one (S-1); Open always enabled; disabled-shortcut-at-browser is a structural no-op. |
| `MacOpenCommandTests.swift` | Swift Testing | Part 2 seam + the **F-001-resolved** open-while-open ordering: Open presents the system panel constrained to `MarkdownDocument.readableContentTypes`; a chosen URL funnels through `presentDocument(at:)` (S-3) with no second mechanism; opened file becomes the resume target; cancel / failing / non-md edges; **load-success-gated** open-while-open (load → conditional teardown → present; a failed new open leaves the prior document fully intact — DC-10; no two-docs-live; single window) (S-4). |
| `PointerAffordanceTests.swift` | Swift Testing | Part 3 seam: pointer feedback on the tap-to-edit surface and the eye control; the hover region coincides with the existing tap region and the clickable area equals the tappable area (S-5); a click routes through the same action as a tap; pointer is never the sole affordance; no-pointer device hides/disables/changes nothing. |
| `MacRestorationTests.swift` | Swift Testing | Part 4 + Part 5 seams: restoration defers the document choice solely to `LaunchResumeBranch` / `LastFileStore` (S-6) — same file, same resolution as iOS/iPad resume; single window; moved/deleted fails closed to the browser with no error UI; first launch lands on the browser; restored doc enters the unchanged conflict/lifecycle; Mac icon slots populated with no empty/placeholder, iOS/iPad icon unregressed. |
| `MacMenuBarUITests.swift` | XCUITest | Part 1/2/4 end-to-end on a **Mac Catalyst** destination: the real menu bar's File/Edit/View structure and ⌘ equivalents; menu actions match the shortcuts; enablement at browser vs. editor; disabled-shortcut no-op; File → Open via the system panel; **open-while-open success replaces the single window AND a failed new open preserves the prior document (the F-001 case)**; cancel leaves the current doc untouched; relaunch restores the prior document (single window); first-launch and moved/deleted land on the browser with no error UI. |
| `MacPointerUITests.swift` | XCUITest | Part 3 end-to-end on a **Mac Catalyst** destination with a pointer: hover + click on the tap-to-edit surface and the eye control performs the identical existing transition; click == tap; existing gestures still work with the layer attached; the mode switch is reachable without a pointer; no-pointer device hides nothing and tap still works. |

## Coverage matrix

### Part 1 — Mac menu bar (US-1 / US-2)

| Requirement | Test(s) |
|-------------|---------|
| AC-1.1 (File = Open/Save/Close, ⌘ equivalents, no New) | `MenuBarRoutingTests.fileMenu_containsOpenSaveClose_noNew`; `MacMenuBarUITests.test_fileMenu_containsOpenSaveClose_noNew` |
| AC-1.2 / FM-10 (View = Toggle Preview on ⌘P, stable title) | `MenuBarRoutingTests.viewMenu_containsStableTitledTogglePreview_onCmdP`; `MacMenuBarUITests.test_viewMenu_containsStableTitledTogglePreview` |
| AC-1.3 / AC-2.4 (Edit = system-standard items, defers to responder) | `MenuBarRoutingTests.editMenu_isSystemStandardOnly`, `...editItems_followSystemEnablement`; `MacMenuBarUITests.test_editMenu_containsSystemStandardItems` |
| AC-1.4 / FM-1 (menu Save drives saveNow→triggerSave) | `MenuBarRoutingTests.saveMenuItem_drivesExistingSaveFlow`; `MacMenuBarUITests.test_menuSave_showsNoNewConfirmationUI` |
| AC-1.4 / FM-1 (menu Close drives closeEditor→dismiss) | `MenuBarRoutingTests.closeMenuItem_drivesExistingCloseFlow`; `MacMenuBarUITests.test_menuClose_returnsToBrowser_likeCmdW` |
| AC-1.4 / FM-1 (menu Toggle Preview drives toggleMode) | `MenuBarRoutingTests.togglePreviewMenuItem_drivesExistingToggleFlow`; `MacMenuBarUITests.test_menuTogglePreview_matchesCmdP` |
| AC-1.4 / S-2 (menu Open routes to presentDocument) | `MenuBarRoutingTests.openMenuItem_routesToPresentDocument`; `MacOpenCommandTests.open_chosenFile_funnelsThroughPresentDocument` |
| AC-1.5 (shown shortcut == firing binding; menu == shortcut) | `MenuBarRoutingTests.shownShortcutEqualsFiringBinding`, `...saveMenuItem_drivesExistingSaveFlow`, `...closeMenuItem_drivesExistingCloseFlow`, `...togglePreviewMenuItem_drivesExistingToggleFlow`; `MacMenuBarUITests.test_menuTogglePreview_matchesCmdP` |
| AC-1.6 (full keyboard access; no pointer-only action) | `MenuBarRoutingTests.everyEnabledItemIsKeyboardReachable` |
| AC-2.1 / S-1 / FM-6 (doc-scoped disabled with no document) | `MenuBarRoutingTests.documentScopedItems_disabledWithNoDocument`, `...enablementAndLiveHandleAreTheSameFact`; `MacMenuBarUITests.test_documentScopedItems_disabledAtBrowser` |
| AC-2.2 (doc-scoped enabled with a document) | `MenuBarRoutingTests.documentScopedItems_enabledWithDocument`, `...enablementAndLiveHandleAreTheSameFact`; `MacMenuBarUITests.test_documentScopedItems_enabledWithDocument` |
| AC-2.3 (Open always enabled) | `MenuBarRoutingTests.openIsAlwaysEnabled`; `MacMenuBarUITests.test_documentScopedItems_disabledAtBrowser` (Open enabled assertion) |
| AC-2.4 (Edit items follow system enablement) | `MenuBarRoutingTests.editItems_followSystemEnablement` |
| Disabled-shortcut edge / C-2.5 / FM-6 (⌘S/⌘W/⌘P at browser = no-op) | `MenuBarRoutingTests.shortcuts_atBrowser_areStructuralNoOps`; `MacMenuBarUITests.test_disabledShortcutsAtBrowser_areStructuralNoOps` |

### Part 2 — File → Open and open-while-open (US-3 / AC-3.5)

| Requirement | Test(s) |
|-------------|---------|
| AC-3.1 (Open presents the system panel) | `MacOpenCommandTests.open_presentsSystemPanel`; `MacMenuBarUITests.test_fileOpen_presentsSystemPanel` |
| AC-3.2 (panel constrained to readableContentTypes) | `MacOpenCommandTests.open_panelConstrainedToMarkdownTypes` |
| AC-3.3 / S-3 / FM-2 (chosen file funnels through presentDocument) | `MacOpenCommandTests.open_chosenFile_funnelsThroughPresentDocument`; `MacMenuBarUITests.test_fileOpen_opensChosenMarkdownFile` |
| AC-3.4 (opened file becomes the resume target) | `MacOpenCommandTests.open_success_recordsAsResumeTarget` |
| AC-3.5 / FM-8 (open replaces the single current document) | `MacOpenCommandTests.openWhileOpen_success_replacesSingleDocument`, `...openWhileOpen_addsNoMultiDocumentState`; `MacMenuBarUITests.test_openWhileOpen_success_replacesSingleDocument` |
| **Open-while-open ordering (C-2.4 / S-4 — F-001): load-first** | `MacOpenCommandTests.openWhileOpen_success_loadsBeforeTeardown` |
| **Failed new open preserves prior (DC-10 — the F-001 case)** | `MacOpenCommandTests.openWhileOpen_failedNewOpen_preservesPrior`, `...openWhileOpen_failedNewOpen_noWorseThanCancel`; `MacMenuBarUITests.test_openWhileOpen_failedNewOpen_preservesPriorDocument` |
| Open cancel edge (nothing opens, current untouched) | `MacOpenCommandTests.open_canceled_leavesEverythingUntouched`; `MacMenuBarUITests.test_openCanceled_leavesCurrentDocumentUntouched` |
| Open failing edge / FM-2 (existing alert, scope released, prior preserved) | `MacOpenCommandTests.open_failingFile_surfacesExistingAlertAndReleasesScope`, `...openWhileOpen_failedNewOpen_preservesPrior` |
| Open non-md edge (existing gates, no new handling) | `MacOpenCommandTests.open_nonMarkdownFile_handledByExistingGates` |
| FM-7 (File → Save adds no new save/conflict UI) | `MacOpenCommandTests.menuSave_noNewUI_failureViaExistingRouter`; `MacMenuBarUITests.test_menuSave_showsNoNewConfirmationUI` |

### Part 3 — Pointer / hover feedback (US-4)

| Requirement | Test(s) |
|-------------|---------|
| AC-4.1 (tap-to-edit feedback; click = existing rendered→raw) | `PointerAffordanceTests.tapToEditSurface_showsFeedback_clickPerformsExistingTransition`; `MacPointerUITests.test_tapToEditSurface_clickPerformsExistingTransition` |
| AC-4.2 (eye control feedback; click = existing transition) | `PointerAffordanceTests.eyeControl_showsFeedback_clickPerformsExistingTransition`; `MacPointerUITests.test_eyeControl_clickPerformsExistingTransition` |
| AC-4.3 / FM-5 (no action/hit-area/gesture change; click == tap) | `PointerAffordanceTests.clickActionIdenticalToTap_noGestureChanged`; `MacPointerUITests.test_clickAndTap_produceSameTransition`, `...test_existingGesturesStillWork_withPointerLayer` |
| AC-4.4 / FM-5 (pointer never the sole affordance) | `PointerAffordanceTests.everyPointerFedAction_alsoReachableWithoutPointer`; `MacPointerUITests.test_modeSwitch_reachableWithoutPointer` |
| No-pointer edge / C-4.5 (never triggered; nothing hidden/disabled) | `PointerAffordanceTests.noPointerDevice_feedbackNeverTriggered_behaviorUnchanged`; `MacPointerUITests.test_noPointerDevice_tapStillWorks_nothingHidden` |

### Part 4 — Single-window state restoration (US-5)

| Requirement | Test(s) |
|-------------|---------|
| AC-5.1 / S-6 / FM-3 (restores via existing resume path; no new identity store) | `MacRestorationTests.restoration_restoresViaExistingResumePath`; `MacMenuBarUITests.test_relaunch_restoresPreviouslyOpenDocument` |
| AC-5.2 / FM-8 (single window/document, no tabs) | `MacRestorationTests.restoration_singleWindow`; `MacMenuBarUITests.test_relaunch_restoresPreviouslyOpenDocument` (windows == 1) |
| AC-5.3 (same file & resolution as iOS/iPad resume) | `MacRestorationTests.restoration_consistentWithIOSResume` |
| Moved/deleted edge / C-5.4 (bookmark retarget; else browser, no error) | `MacRestorationTests.restoration_movedFile_retargetsViaBookmark`, `...restoration_deletedFile_landsOnBrowserNoError`; `MacMenuBarUITests.test_movedOrDeletedPriorDocument_landsOnBrowserNoError` |
| First-launch edge / C-5.5 (resolves nothing → browser; no placeholder) | `MacRestorationTests.restoration_firstLaunch_landsOnBrowser`; `MacMenuBarUITests.test_firstLaunch_landsOnBrowser` |
| Lifecycle edge / C-5.6 / FM-7 (restored doc enters unchanged lifecycle) | `MacRestorationTests.restoration_restoredDocument_entersUnchangedLifecycle` |

### Part 5 — Mac app-icon assets (US-6)

| Requirement | Test(s) |
|-------------|---------|
| AC-6.1 / C-6.1 (Mac slots populated; no empty/placeholder) | `MacRestorationTests.macIconSlots_arePopulated` |
| AC-6.2 / C-6.2 / FM-9 (iOS/iPad icon not regressed; Mac slots additive) | `MacRestorationTests.macIconSlots_doNotRegressIOSIcon` |

### Failure modes → tests

| FM | Test(s) |
|----|---------|
| FM-1 (no parallel save/close/toggle/open implementation) | `MenuBarRoutingTests.saveMenuItem_drivesExistingSaveFlow`, `...closeMenuItem_drivesExistingCloseFlow`, `...togglePreviewMenuItem_drivesExistingToggleFlow`, `...openMenuItem_routesToPresentDocument` |
| FM-2 (no second open/decode/read/bookmark mechanism) | `MacOpenCommandTests.open_chosenFile_funnelsThroughPresentDocument`, `...open_failingFile_surfacesExistingAlertAndReleasesScope`, `...open_nonMarkdownFile_handledByExistingGates` |
| FM-3 (no new identity store / file-missing recovery dialog) | `MacRestorationTests.restoration_restoresViaExistingResumePath`, `...restoration_movedFile_retargetsViaBookmark`, `...restoration_deletedFile_landsOnBrowserNoError`; `MacMenuBarUITests.test_movedOrDeletedPriorDocument_landsOnBrowserNoError` |
| FM-4 (no File → New / ⌘N) | `MenuBarRoutingTests.fileMenu_containsOpenSaveClose_noNew`; `MacMenuBarUITests.test_fileMenu_containsOpenSaveClose_noNew` |
| FM-5 (pointer never sole / no hit-area or gesture change / nothing hidden) | `PointerAffordanceTests.clickActionIdenticalToTap_noGestureChanged`, `...everyPointerFedAction_alsoReachableWithoutPointer`, `...noPointerDevice_feedbackNeverTriggered_behaviorUnchanged`; `MacPointerUITests.test_existingGesturesStillWork_withPointerLayer` |
| FM-6 (no nil-handle invocation; disabled when no document; no crash) | `MenuBarRoutingTests.documentScopedItems_disabledWithNoDocument`, `...shortcuts_atBrowser_areStructuralNoOps`; `MacMenuBarUITests.test_disabledShortcutsAtBrowser_areStructuralNoOps` |
| FM-7 (no conflict/deletion/save UI change) | `MacOpenCommandTests.menuSave_noNewUI_failureViaExistingRouter`; `MacRestorationTests.restoration_restoredDocument_entersUnchangedLifecycle`; `MacMenuBarUITests.test_menuSave_showsNoNewConfirmationUI` |
| FM-8 (single window; no multi-document model; no two-docs-live) | `MacOpenCommandTests.openWhileOpen_success_replacesSingleDocument`, `...openWhileOpen_addsNoMultiDocumentState`; `MacRestorationTests.restoration_singleWindow`; `MacMenuBarUITests.test_openWhileOpen_success_replacesSingleDocument` |
| FM-9 (no iOS/iPad icon regression) | `MacRestorationTests.macIconSlots_doNotRegressIOSIcon` |
| FM-10 (toggle stays on ⌘P; ⌘/ not wired) | `MenuBarRoutingTests.viewMenu_containsStableTitledTogglePreview_onCmdP` |

### Design seams → tests

| Seam / contract | Test(s) |
|-----------------|---------|
| S-1 (enablement tracks editor-session presence via the responder chain; disabled-shortcut is structural) | `MenuBarRoutingTests.documentScopedItems_disabledWithNoDocument`, `...documentScopedItems_enabledWithDocument`, `...enablementAndLiveHandleAreTheSameFact`, `...shortcuts_atBrowser_areStructuralNoOps`; `MacMenuBarUITests.test_documentScopedItems_disabledAtBrowser`, `...test_documentScopedItems_enabledWithDocument` |
| S-2 (menu actions reach the same EditorActions / presentDocument seams) | `MenuBarRoutingTests.saveMenuItem_drivesExistingSaveFlow`, `...closeMenuItem_drivesExistingCloseFlow`, `...togglePreviewMenuItem_drivesExistingToggleFlow`, `...openMenuItem_routesToPresentDocument` |
| S-3 (open panel's only output is a URL into the existing funnel) | `MacOpenCommandTests.open_chosenFile_funnelsThroughPresentDocument` (`panelOutputWasURLOnly`) |
| S-4 (open-while-open load-success-gated; prior relinquished only after new load succeeds; failed open never tears down prior — DC-10) | `MacOpenCommandTests.openWhileOpen_success_loadsBeforeTeardown`, `...openWhileOpen_failedNewOpen_preservesPrior`, `...openWhileOpen_failedNewOpen_noWorseThanCancel`; `MacMenuBarUITests.test_openWhileOpen_failedNewOpen_preservesPriorDocument` |
| S-5 (pointer feedback layered over existing hit regions; clickable == tappable) | `PointerAffordanceTests.clickableRegionEqualsTappableRegion`, `...clickActionIdenticalToTap_noGestureChanged` |
| S-6 (restoration entry hands control to the existing resume decision; no new persisted identity) | `MacRestorationTests.restoration_restoresViaExistingResumePath`, `...restoration_consistentWithIOSResume`, `...restoration_deletedFile_landsOnBrowserNoError` |
| C-2.4 (open-while-open replaces single document, load-success-gated) | `MacOpenCommandTests.openWhileOpen_success_replacesSingleDocument`, `...openWhileOpen_addsNoMultiDocumentState`, `...openWhileOpen_failedNewOpen_preservesPrior` |
| C-3.x (Component B adapter: panel → presentDocument; success/cancel/failure semantics inherited) | `MacOpenCommandTests` (all of `MacOpenPanelTests`, `MacOpenEdgeCaseTests`) |
| C-4.x (Component C: feedback on both targets; click == tap; never sole; inert with no pointer) | `PointerAffordanceTests` (all suites); `MacPointerUITests` (all cases) |
| C-5.x (Component D: defers to resume; single window; fail-closed; unchanged lifecycle) | `MacRestorationTests` (all of `MacRestorationTests`, `MacRestorationEdgeTests`) |
| C-6.x (Component E: populated Mac slots; iOS/iPad additive) | `MacRestorationTests.macIconSlots_arePopulated`, `...macIconSlots_doNotRegressIOSIcon` |
| X-1 / X-2 (no new product surface; out-of-scope structurally excluded) | `MenuBarRoutingTests.fileMenu_containsOpenSaveClose_noNew` (no New), `...editMenu_isSystemStandardOnly` (no custom Edit), `...viewMenu_containsStableTitledTogglePreview_onCmdP` (⌘P not ⌘/); `MacOpenCommandTests.openWhileOpen_addsNoMultiDocumentState` (no multi-document) |
| X-3 (existing behavior preserved unchanged) | `MacOpenCommandTests.menuSave_noNewUI_failureViaExistingRouter`; `MacRestorationTests.restoration_restoredDocument_entersUnchangedLifecycle` |
| X-4 (one implementation per action across all entry points) | `MenuBarRoutingTests.saveMenuItem_drivesExistingSaveFlow` (menu == ⌘S), `...closeMenuItem_drivesExistingCloseFlow` (menu == ⌘W), `...togglePreviewMenuItem_drivesExistingToggleFlow` (menu == ⌘P); `MacOpenCommandTests.open_chosenFile_funnelsThroughPresentDocument` (open == browser pick) |

## Notes on technique

- **Observable / seam framing.** Every test asserts an observable: which existing
  flow ran (`saveNow`→`triggerSave`, `closeEditor`→`dismiss`, `toggleMode`,
  `presentDocument`), an item's enabled state and shown ⌘ equivalent, a resolved
  resume outcome, the populated state of an icon slot, the equality of a hover
  region and the existing tap region, or — for the highest-value case — the
  teardown/present **ordering** and whether the prior document survived a failed
  open. No test asserts a call signature, a `UIMenu` construction shape, a
  `UIPointerInteraction` constructor, or a private attribute. "Routes to the
  existing flow" (FM-1) is tested as downstream-effect equivalence (the menu item
  and its shortcut produce the same observable result), not by inspecting which
  method object was referenced.
- **The F-001 ordering is the centrepiece.** `MacOpenCommandTests` pins the
  load-success-gated ordering three ways: the success path runs
  `[.loadNew, .tearDownPrior, .presentNew]` (load first); a **failed** new open
  runs `[.loadNew]` only, leaves `activeDocument` on the **prior** file, keeps the
  prior detector running, and surfaces the existing "Couldn't open" alert
  (`openWhileOpen_failedNewOpen_preservesPrior`); and an explicit equivalence test
  asserts a failed open is no worse than a canceled one
  (`openWhileOpen_failedNewOpen_noWorseThanCancel`). The XCUITest mirror
  (`test_openWhileOpen_failedNewOpen_preservesPriorDocument`) asserts the user is
  **not** dropped to the browser. This is the DC-10 guarantee the adversarial
  review flagged and the resolved design pins.
- **Unit vs. UI split (matching feature 13's precedent).** The pure decisions —
  the menu structure / enablement / routing equivalence, the open funnel + the
  open-while-open ordering, the resume outcome, the icon-slot state, the
  hover-region-equals-tap-region invariant — are unit-tested with Swift Testing
  probes that model each seam. The genuinely in-app Catalyst behaviors a unit test
  cannot reach — a real menu bar, the system open panel, scene restoration across a
  relaunch, a real pointer hover/click — are XCUITest cases. This mirrors feature
  13's split (unit seam tests in `KeyCommandRoutingTests` / `ContentWidthTests` +
  end-to-end `KeyboardShortcutsUITests` / `ContentWidthUITests`), at the **same
  executability level**: no heavier harness than the precedent is introduced.
- **Catalyst UI-level behaviors.** Per the brief, menu-bar presence, pointer/hover,
  and scene restoration are Catalyst/UI behaviors. They are expressed end-to-end in
  the two XCUITest files exactly as feature 13 expressed its hardware-keyboard and
  size-class behaviors — with the driving primitives (the macOS menu bar via
  `menuBars`, the open panel via the file-dialog element tree, relaunch via
  `terminate()`/`launch()`, pointer hover) left as **documented helper seams**, the
  same stance feature 13 took for `holdKey` and the size-class transition. The spec
  fixes the observable outcome; the build implementer maps each helper to the
  concrete primitive available on the target Xcode version.
- **Destination requirements.** The menu-bar, File → Open panel, restoration, and
  pointer cases require a **Mac Catalyst run destination** — the menu bar, the
  open panel, and a pointer device are unreachable on the iPhone 17 simulator named
  in constitution.md. The Swift Testing probe files run on any destination (they
  model pure decisions); the two XCUITest files run on the Catalyst Mac
  destination. The build implementer adds that destination when running these
  cases.
- **Reference-only / fail-until-built.** These files are not bundled into the Xcode
  test target. They reference the unbuilt `CatalystMenuBuilder`, `MacOpenCommand`
  funnel, composed open-while-open host operation, `MacRestorationBridge`,
  populated Mac icon slots, and `PointerAffordanceLayer`, and assert Catalyst
  behavior absent before the build — so they fail / are unimplemented until the
  feature lands.
- **Task IDs deferred.** Per the brief, no DAG task-ID tags are applied here. `/dag`
  adds the authoritative task → test mapping in the next stage (as it did for
  feature 13's verify.md).

## Untestable requirements

None. Every US-* / AC-* / FM-* line and every design seam (S-1..S-6, C-1.* through
C-6.*, X-1..X-4) is covered by at least one reference test above. The aspects the
brief flagged as potentially hard — Catalyst menu-bar presence, pointer/hover, and
scene restoration — are all testable in this project's harness following feature
13's precedent: their observable contracts are pinned by Swift Testing seam probes,
and their genuinely in-app behavior is exercised end-to-end by XCUITest on a Mac
Catalyst destination, with the driving primitives left as documented seams (the
same level of executability feature 13's reference tests use). No requirement was
dropped or covered only weakly.
