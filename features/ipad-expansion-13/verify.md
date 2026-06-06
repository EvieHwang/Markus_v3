# Verify — ipad-expansion-13

Coverage map from `requirements.md` (US-*, AC-*, FM-*, edge cases) and `design.md`
(Component contracts C-A.*/C-B.*, behavioral seams S-1..S-7, cross-cutting X-*) to
the reference spec tests under `features/ipad-expansion-13/tests/`.

These spec tests are **reference / human-readable** — they are NOT part of the
Xcode test target (constitution.md → Testing). The build implementer mirrors them
into `Markus_v3Tests/` (Swift Testing) and `Markus_v3UITests/` (XCUITest) when
picking up each task, adjusting symbol/identifier names to match the live host.

The **Task ID column is intentionally a placeholder** in this stage — the DAG does
not exist yet. The next stage (`/dag`) populates the authoritative task→test
mapping by tagging each test with the task that must make it pass. Tests are written
to **fail / be unimplemented** until then: the Swift Testing files reference the
as-yet-unbuilt seams (`EditorKeyCommandProvider` routing, the shared content-width
resolution), and the XCUITest files assert behavior (⌘P/⌘W/⌘S firing, a centered
column, live size-class transition) that does not exist before the build.

## Test files

| File | Framework | Concern |
|------|-----------|---------|
| `KeyCommandRoutingTests.swift` | Swift Testing | Part 1 seam + behavior: the three commands (⌘P/⌘W/⌘S) route to the **existing** toggle/save/close flows (no parallel path); ⌘P not swallowed by the text view; ⌘W saves synchronously before dismiss; ⌘S uses `triggerSave()`→`markDirty()` with no new UI; provider vends exactly three titled commands; no-op without a keyboard; registration is inert. |
| `ContentWidthTests.swift` | Swift Testing | Part 2 seam: the shared width-resolution **decision** (capped ~700pt + centered in regular width; full-width, no gutters in compact; cap is a maximum not a fixed width; both surfaces share width/position; gutter accounts for all available width / no clipping). |
| `KeyboardShortcutsUITests.swift` | XCUITest | Part 1 end-to-end on an iPad simulator with a hardware keyboard: ⌘P toggles (incl. keyboard-up no-swallow), ⌘S saves with no new UI, ⌘W returns to browser preserving edits, discoverability overlay lists exactly the three action titles, no-keyboard no-op, registration leaves existing gestures intact. |
| `ContentWidthUITests.swift` | XCUITest | Part 2 end-to-end on an iPad simulator: column centered in regular width, raw/rendered share column position, **live** compact↔regular transition without reopen, no scroll reset / no edit loss on transition, mode-switch-after-transition correctness, non-interactive gutter, caret stays in the column. |

## Coverage matrix

### Part 1 — keyboard shortcuts (US-1/2/4/5/6)

| Requirement | Test(s) | Task ID |
|-------------|---------|---------|
| AC-1.1 (⌘P rendered→raw = tap-to-edit transition) | `KeyCommandRoutingTests.cmdP_renderedToRaw_usesExistingTransition`; `KeyboardShortcutsUITests.test_cmdP_togglesRenderedToRawToRendered` | _next stage_ |
| AC-1.2 (⌘P raw→rendered = eye-button transition, save triggered) | `KeyCommandRoutingTests.cmdP_rawToRendered_usesExistingTransition`; `KeyboardShortcutsUITests.test_cmdP_togglesRenderedToRawToRendered` | _next stage_ |
| AC-1.3 (repeated ⌘P alternates, no drift, one path each) | `KeyCommandRoutingTests.cmdP_repeatedTogglesAlternate`; `KeyboardShortcutsUITests.test_cmdP_repeatedAlternatesNoDrift` | _next stage_ |
| AC-1.4 (VoiceOver announcement preserved; initial assign silent) | `KeyCommandRoutingTests.cmdP_postsModeAnnouncement`, `...initialModeAppear_postsNoAnnouncement` | _next stage_ |
| ⌘P edge (keyboard up: toggles, inserts no character) / FM-3 | `KeyCommandRoutingTests.cmdP_withTextViewFirstResponder_notSwallowed`; `KeyboardShortcutsUITests.test_cmdP_withKeyboardUp_togglesAndInsertsNoCharacter` | _next stage_ |
| AC-2.1 (⌘W via onBack→dismissPresentedEditor; browser visible; detector stopped) | `KeyCommandRoutingTests.cmdW_invokesExistingReturnFlow`; `KeyboardShortcutsUITests.test_cmdW_returnsToBrowser_inRenderedMode` | _next stage_ |
| AC-2.2 (synchronous save before dismiss; edits preserved; no discard prompt) | `KeyCommandRoutingTests.cmdW_savesSynchronouslyBeforeDismiss`; `KeyboardShortcutsUITests.test_cmdW_preservesUnsavedEdits` | _next stage_ |
| AC-2.3 (⌘W honored in both modes) | `KeyCommandRoutingTests.cmdW_honoredInBothModes`; `KeyboardShortcutsUITests.test_cmdW_returnsToBrowser_inRawMode` | _next stage_ |
| ⌘W edge (at browser: structural no-op, no crash) | `KeyCommandRoutingTests.cmdW_atBrowser_isNoOp` | _next stage_ |
| AC-4.1 (⌘S = triggerSave→markDirty; no new mechanism) | `KeyCommandRoutingTests.cmdS_invokesExistingSaveFlow` | _next stage_ |
| AC-4.2 (no new toast/dialog/indicator; failure via existing router) | `KeyCommandRoutingTests.cmdS_noNewConfirmationUI`, `...cmdS_failureUsesExistingAlertPath`; `KeyboardShortcutsUITests.test_cmdS_savesWithNoNewConfirmationUI` | _next stage_ |
| AC-4.3 (⌘S honored both modes; harmless in rendered) | `KeyCommandRoutingTests.cmdS_honoredInBothModes`; `KeyboardShortcutsUITests.test_cmdS_inRenderedMode_isHarmless` | _next stage_ |
| ⌘S edge (clean buffer: no corrupt/conflict/error) | `KeyCommandRoutingTests.cmdS_cleanBuffer_isHarmless`; `KeyboardShortcutsUITests.test_cmdS_inRenderedMode_isHarmless` | _next stage_ |
| AC-5.1 (exactly three titled commands ⌘P/⌘W/⌘S) | `KeyCommandRoutingTests.providerVendsExactlyThreeTitledCommands`; `KeyboardShortcutsUITests.test_discoverabilityOverlay_listsThreeCommands` | _next stage_ |
| AC-5.2 (titles distinct, action-describing, mode-stable) | `KeyCommandRoutingTests.titlesAreDistinctAndActionDescribing`, `...cmdPTitleStableAcrossModes`; `KeyboardShortcutsUITests.test_discoverabilityOverlay_titleStableAcrossModes` | _next stage_ |
| US-5 overlay edge (no editor command at browser) | `KeyCommandRoutingTests.cmdW_atBrowser_isNoOp` (provider absent at browser); `KeyboardShortcutsUITests.test_discoverabilityOverlay_listsThreeCommands` (no 'New Document' entry) | _next stage_ |
| AC-6.1 (no behavior change without a keyboard) | `KeyCommandRoutingTests.noKeyboard_noCommandFires`; `KeyboardShortcutsUITests.test_noHardwareKeyboard_shortcutsAreNoOp` | _next stage_ |
| AC-6.2 (registration never crashes / alters layout / disables gestures) | `KeyCommandRoutingTests.registration_isInert`; `KeyboardShortcutsUITests.test_registration_doesNotDisableExistingGestures` | _next stage_ |

### Part 2 — width constraint (US-7/8/9/10)

| Requirement | Test(s) | Task ID |
|-------------|---------|---------|
| AC-7.1 (raw editor capped & centered in regular) | `ContentWidthTests.regularWide_capsBothSurfaces` (raw); `ContentWidthUITests.test_renderedContent_isCenteredInRegularWidth` (sibling surface) | _next stage_ |
| AC-7.2 (rendered preview capped & centered in regular) | `ContentWidthTests.regularWide_capsBothSurfaces` (rendered); `ContentWidthUITests.test_renderedContent_isCenteredInRegularWidth` | _next stage_ |
| AC-7.3 (consistent width across modes) / FM-8 / C-B.1 | `ContentWidthTests.bothSurfacesShareWidthAndPosition`, `...modeSwitchAfterTransition_otherSurfaceCorrect`; `ContentWidthUITests.test_rawAndRendered_shareColumnPosition` | _next stage_ |
| AC-7.4 (full width usable below the cap — maximum not fixed) | `ContentWidthTests.regularNarrow_belowCap_usesFullWidth` | _next stage_ |
| AC-7 wide-window edge (~1366pt stays ~700 centered) | `ContentWidthTests.veryWide_columnStaysCappedAndCentered` | _next stage_ |
| AC-8.1 (compact = full width, no cap/centering) / FM-5 | `ContentWidthTests.compact_neverCaps` | _next stage_ |
| AC-8.2 (no regression to current iPhone layout) | `ContentWidthTests.compactWide_stillFullWidth` (cap keyed on size class, not width) | _next stage_ |
| AC-9.1 (compact→regular applies cap live, no reopen / no state loss) | `ContentWidthUITests.test_compactToRegular_appliesCapLive`, `...test_transition_preservesScrollPositionAndEdits` | _next stage_ |
| AC-9.2 (regular→compact removes cap live) | `ContentWidthUITests.test_regularToCompact_removesCapLive` | _next stage_ |
| AC-9.3 (applies to visible surface; survives mode switch) / S-6 | `ContentWidthTests.modeSwitchAfterTransition_otherSurfaceCorrect`; `ContentWidthUITests.test_transition_thenModeSwitch_showsOtherSurfaceCorrect` | _next stage_ |
| AC-10.1 (centering, not clipping; gutter background only) / FM-6 | `ContentWidthTests.gutterIsBackgroundOnly` | _next stage_ |
| AC-10.2 (full ~700pt column usable, not reserved as padding) | `ContentWidthTests.fullColumnUsable` | _next stage_ |
| AC-10.3 (caret/selection/scroll within the centered column) | `ContentWidthUITests.test_tapInGutter_doesNotEnterTextOrMoveCaret`, `...test_typingAtColumnEdge_caretStaysWithinColumn` | _next stage_ |
| AC-10 long-token edge (no NEW clipping vs a 700pt viewport) | `ContentWidthTests.longTokenWrapsAsAt700ptViewport` | _next stage_ |

### Failure modes → tests

| FM | Test(s) | Task ID |
|----|---------|---------|
| FM-1 (no parallel save/toggle/close implementation) | `KeyCommandRoutingTests.cmdP_renderedToRaw_usesExistingTransition`, `...cmdP_repeatedTogglesAlternate`, `...cmdW_invokesExistingReturnFlow`, `...cmdS_invokesExistingSaveFlow` | _next stage_ |
| FM-2 (no new confirmation/prompt/toast beyond existing) | `KeyCommandRoutingTests.cmdW_savesSynchronouslyBeforeDismiss` (no discard prompt), `...cmdS_noNewConfirmationUI`, `...cmdS_failureUsesExistingAlertPath`; `KeyboardShortcutsUITests.test_cmdS_savesWithNoNewConfirmationUI`, `...test_cmdW_preservesUnsavedEdits` | _next stage_ |
| FM-3 (⌘P not swallowed / no literal char) | `KeyCommandRoutingTests.cmdP_withTextViewFirstResponder_notSwallowed`; `KeyboardShortcutsUITests.test_cmdP_withKeyboardUp_togglesAndInsertsNoCharacter` | _next stage_ |
| FM-4 (registration: no crash/layout change/gesture disable) | `KeyCommandRoutingTests.registration_isInert`; `KeyboardShortcutsUITests.test_registration_doesNotDisableExistingGestures`, `...test_noHardwareKeyboard_shortcutsAreNoOp` | _next stage_ |
| FM-5 (no cap in compact) | `ContentWidthTests.compact_neverCaps`, `...compactWide_stillFullWidth` | _next stage_ |
| FM-6 (no clip/hide/push into a gutter) | `ContentWidthTests.gutterIsBackgroundOnly`, `...fullColumnUsable`; `ContentWidthUITests.test_tapInGutter_doesNotEnterTextOrMoveCaret` | _next stage_ |
| FM-7 (transition: no reopen, no scroll reset, no edit loss) | `ContentWidthUITests.test_transition_preservesScrollPositionAndEdits`, `...test_compactToRegular_appliesCapLive` | _next stage_ |
| FM-8 (both surfaces share max width — no desync on mode switch) | `ContentWidthTests.bothSurfacesShareWidthAndPosition`, `...modeSwitchAfterTransition_otherSurfaceCorrect`; `ContentWidthUITests.test_rawAndRendered_shareColumnPosition` | _next stage_ |
| FM-9 (no new model/storage/copy/naming from ⌘S) | `KeyCommandRoutingTests.cmdS_invokesExistingSaveFlow` (`newSaveMechanismIntroduced == false`) | _next stage_ |

### Design seams → tests

| Seam / contract | Test(s) | Task ID |
|-----------------|---------|---------|
| C-A.1 / S-2 / S-3 (each command triggers an existing action, never a second impl) | `KeyCommandRoutingTests.cmdP_*`, `cmdW_invokesExistingReturnFlow`, `cmdS_invokesExistingSaveFlow` | _next stage_ |
| C-A.2 (⌘P reproduces transition incl. direction + anchor + announcement) | `KeyCommandRoutingTests.cmdP_renderedToRaw_usesExistingTransition`, `...cmdP_rawToRendered_usesExistingTransition`, `...cmdP_postsModeAnnouncement` | _next stage_ |
| C-A.3 (⌘W reproduces back-button/return effect, sync save) | `KeyCommandRoutingTests.cmdW_invokesExistingReturnFlow`, `...cmdW_savesSynchronouslyBeforeDismiss` | _next stage_ |
| C-A.5 (⌘S reproduces save flow exactly, harmless on clean buffer) | `KeyCommandRoutingTests.cmdS_invokesExistingSaveFlow`, `...cmdS_cleanBuffer_isHarmless` | _next stage_ |
| C-A.6 (three commands enumerable with stable action titles) | `KeyCommandRoutingTests.providerVendsExactlyThreeTitledCommands`, `...titlesAreDistinctAndActionDescribing`, `...cmdPTitleStableAcrossModes`; `KeyboardShortcutsUITests.test_discoverabilityOverlay_*` | _next stage_ |
| C-A.7 (registration inert without a keyboard, never disturbs UI) | `KeyCommandRoutingTests.noKeyboard_noCommandFires`, `...registration_isInert` | _next stage_ |
| S-1 (provider lifetime bound to editor session; absent at browser) | `KeyCommandRoutingTests.cmdW_atBrowser_isNoOp` | _next stage_ |
| S-4 (chord claimed above the UITextView before it becomes text) | `KeyCommandRoutingTests.cmdP_withTextViewFirstResponder_notSwallowed`; `KeyboardShortcutsUITests.test_cmdP_withKeyboardUp_togglesAndInsertsNoCharacter` | _next stage_ |
| C-B.1 (single shared max width across both surfaces) | `ContentWidthTests.bothSurfacesShareWidthAndPosition`; `ContentWidthUITests.test_rawAndRendered_shareColumnPosition` | _next stage_ |
| C-B.2 (cap engages in regular, disengages in compact, live on transition) | `ContentWidthTests.regularWide_capsBothSurfaces`, `...compact_neverCaps`; `ContentWidthUITests.test_compactToRegular_appliesCapLive`, `...test_regularToCompact_removesCapLive` | _next stage_ |
| C-B.3 (cap is a maximum, not a fixed width) | `ContentWidthTests.regularNarrow_belowCap_usesFullWidth`, `...guttersAppearOnlyAboveCap`, `...veryWide_columnStaysCappedAndCentered` | _next stage_ |
| C-B.4 (non-interactive gutter; full column usable; no clipping; caret in column) | `ContentWidthTests.gutterIsBackgroundOnly`, `...fullColumnUsable`, `...longTokenWrapsAsAt700ptViewport`; `ContentWidthUITests.test_tapInGutter_doesNotEnterTextOrMoveCaret`, `...test_typingAtColumnEdge_caretStaysWithinColumn` | _next stage_ |
| S-5 (cap reads size class live; re-lays out in place on transition) | `ContentWidthUITests.test_compactToRegular_appliesCapLive`, `...test_regularToCompact_removesCapLive`, `...test_transition_preservesScrollPositionAndEdits` | _next stage_ |
| S-6 (both surfaces observe same size class; mode switch after transition correct) | `ContentWidthTests.modeSwitchAfterTransition_otherSurfaceCorrect`; `ContentWidthUITests.test_transition_thenModeSwitch_showsOtherSurfaceCorrect` | _next stage_ |
| S-7 (width treatment presentation-only; orthogonal to scroll & save) | `ContentWidthUITests.test_transition_preservesScrollPositionAndEdits` | _next stage_ |
| X-2 (out-of-scope structurally excluded — exactly three commands, no ⌘N) | `KeyCommandRoutingTests.providerVendsExactlyThreeTitledCommands` (count == 3, inputs == p/w/s); `KeyboardShortcutsUITests.test_discoverabilityOverlay_listsThreeCommands` (no 'New Document') | _next stage_ |

## Notes on technique

- **Observable / seam framing.** Every test asserts an observable: a resulting
  `DocumentMode`, which existing flow ran, whether a save/dismiss occurred, whether
  a character was inserted, a resolved column width / gutter, a UI element's frame
  or presence. No test asserts a call signature, constructor argument list, or
  private attribute, per the Stage 4 brief. The "routes to the existing flow"
  contract (FM-1) is tested as a downstream-effect equivalence (the shortcut and
  its existing UI counterpart produce the same observable result), not by inspecting
  which method object was referenced.
- **Unit vs. UI split.** The pure decisions (toggle-direction selection, the
  width-resolution math) are unit-tested with Swift Testing probes that model the
  seam. The genuinely in-app behaviors that a unit test cannot reach — a real
  ⌘-chord delivered by a hardware keyboard, the discoverability overlay, a live
  size-class transition, caret/gutter behavior in the real `UITextView` — are
  XCUITest cases. This mirrors the `restore-system-create-7` and `native-polish-6`
  split (unit seam tests + an end-to-end UITest file).
- **Simulator requirements.** The discoverability-overlay and regular-width cases
  require an **iPad simulator** with a connected hardware keyboard (a regular
  horizontal size class and a hardware-keyboard chord source are unreachable on the
  iPhone 17 destination named in constitution.md). The build implementer runs the
  Part 1 keyboard cases and all Part 2 cases on an iPad destination; the
  constitution's iPhone-17 destination still covers the compact-width path
  (`compact_neverCaps`) and the no-keyboard no-op (`test_noHardwareKeyboard_*`).
- **Documented test seams.** Two XCUITest helpers (`holdKey` for the ⌘-hold overlay,
  and `enterCompactWidth`/`enterRegularWidth` for the size-class transition) are
  left as documented reference seams: the spec fixes the observable outcome and the
  build implementer maps each to the concrete XCUITest/multitasking primitive
  available on the target Xcode version. This matches the design's stance that the
  exact responder, the width-realization mechanism, and the size signal are build
  choices bounded by the behavioral guards.
- **Reference-only / fail-until-built.** These files are not bundled into the Xcode
  test target. They reference the unbuilt `EditorKeyCommandProvider` routing and the
  unbuilt shared width resolution, and assert behavior absent before the build — so
  they fail / are unimplemented until each tagged task lands, as required.
- **Task IDs deferred.** The Task ID column reads "_next stage_" throughout;
  `/dag` populates the authoritative task→test mapping after the DAG is committed.

## Untestable requirements

None. Every US-*/AC-*/FM-* line and every design seam (C-A.*, C-B.*, S-1..S-7,
X-2) is covered by at least one reference test above. The two aspects the brief
flagged as potentially hard are both testable in this project's harness:
**⌘ keyboard input and the discoverability overlay** via XCUITest
(`typeKey(_:modifierFlags:)` and a ⌘-hold), and **size-class transitions** via an
iPad simulator (Slide Over / Split View / rotation). No requirement was dropped or
covered only weakly.
