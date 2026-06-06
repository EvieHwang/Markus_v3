# DAG — ipad-expansion-13

Dependency graph of build tasks for the iPad-expansion feature (three hardware
keyboard shortcuts wired to existing actions via an editor-session-scoped
key-command provider; a ~700pt centered max content width on the raw editor and
rendered preview, regular size class only, live on size-class transition).

**Two tasks, one wave.** The feature's two parts are genuinely independent: Part 1
adds a responder that *routes* ⌘P/⌘W/⌘S to existing flows; Part 2 adds a
presentation-only width container to the two editor surfaces. They share no data
and no ordering constraint — neither depends on the other — so they run in
parallel in a single wave. They incidentally touch overlapping files
(`DocumentView`, `RawEditorView`, `RenderedView`, the host), so the build agent
should land them as two separate commits and resolve any trivial textual overlap
in `DocumentView` at integration; the *logical* dependency is none.

Sources: `requirements.md` (US-*, AC-*, FM-*, edge cases), `design.md`
(Components A/B, seams S-1..S-7, cross-cutting X-*), `verify.md`
(test→task mapping), `tests/` (reference spec tests).

## Conventions

- **Inputs**: spec files and source files the task reads.
- **Outputs**: source files modified/added; behavior delivered (AC-/FM-/C-/S- refs).
- **Acceptance**: an objectively checkable condition for marking the task
  `complete` in `state.md`. The default is "the tests tagged to this task in
  `verify.md` (mirrored into `Markus_v3Tests/` and `Markus_v3UITests/`) pass." The
  Swift Testing unit tests run on the constitution's iPhone-17 destination
  (`xcodebuild test -scheme Markus_v3 -destination 'platform=iOS Simulator,name=iPhone 17'`);
  the regular-width / discoverability-overlay / hardware-keyboard XCUITest cases
  require an **iPad simulator** with a connected hardware keyboard (per
  `verify.md` → "Simulator requirements"). Task-specific extras are listed where
  they apply.

## Why two tasks (and not more, or fewer)

- **Not one task.** Part 1 (key-command routing) and Part 2 (content width) are
  distinct concerns with distinct behavioral contracts and separate spec-test
  pairs. The brief's "split any task that aggregates distinct concerns" rule
  separates them; a single task would aggregate keyboard-input routing and layout
  width into one unit.
- **Not more tasks.** Each part is a *single cohesive contract* that resists a
  clean further split:
  - Part 1's three commands are vended by **one** responder reachable above the
    raw `UITextView`, each routed to an existing flow. Splitting per shortcut (or
    splitting "vend the provider" from "route the commands") would create partial
    providers and split one responder's lifetime/placement contract across units —
    obscuring "exactly three commands, one provider, each routed to an existing
    flow" (AC-5.1 / C-A.1 / C-A.6 / S-1). It is one session's work with margin.
  - Part 2's width is a **single shared** value applied identically to both
    surfaces. Splitting raw vs. rendered would risk two independent width
    derivations and a desynchronized column, violating the shared-width contract
    (FM-8 / C-B.1). Applying one shared treatment to both surfaces is one session's
    work with margin.

## Wave 1 — both feature parts (parallel)

### T-001 — Editor key-command provider: ⌘P / ⌘W / ⌘S routed to existing flows

- **Description:** Introduce the editor-session-scoped key-command provider
  (design Component A — `EditorKeyCommandProvider`) reachable on the responder
  chain **above** the raw `UITextView` and **inside** the presented editor
  session, vending exactly three `UIKeyCommand`s (⌘P / ⌘W / ⌘S), each carrying a
  stable, action-describing discoverability title ("Toggle Preview", "Close",
  "Save"). Each command is a *trigger onto an existing action*, never a second
  implementation:
  - **⌘P** invokes the existing mode-toggle (`DocumentView`'s `switchTo` /
    eye-button / `switchToRenderedFromSwipe` logic), owned by `DocumentView` and
    merely *invoked* by the provider (S-2) — rendered→raw seeds the raw anchor and
    sets `mode = .raw`; raw→rendered seeds the rendered anchor from the raw
    fraction, triggers a save, sets `mode = .rendered`, and posts the same
    VoiceOver announcement. Repeated ⌘P alternates with no drift and no second
    path. Because the chord is claimed above the raw `UITextView`, ⌘P with the
    keyboard up toggles and inserts no literal character.
  - **⌘W** invokes the existing `onBack` → `BrowserHostController.dismissPresentedEditor()`
    (synchronous save → detector stop → session teardown → dismiss), owned by the
    host and exposed to the provider unchanged (S-3); unsaved edits are preserved,
    no discard prompt is added, honored in both modes.
  - **⌘S** invokes the existing `DocumentView.triggerSave()` → `document.markDirty()`
    (S-2); no toast/dialog/indicator; a failure surfaces only through the existing
    `SaveFailedAlertRouter` / `ActiveAlert.saveFailed` path; honored in both modes;
    a harmless no-op on a clean buffer.
  Registration is inert without a hardware keyboard and disturbs no existing
  gesture or layout. The provider exists only while an editor session is
  presented, so editor commands are structurally absent at the browser (the ⌘W
  browser edge case is structural, not a runtime guard). The exact responder
  (presented `UIHostingController` / a custom `UIResponder` / the host /
  `SceneDelegate`) is a build choice bounded by the "above the text view, inside
  the session" behavioral guard.
- **Inputs:** `design.md` Component A (C-A.1–C-A.7), "Resolved deferred question",
  seams S-1/S-2/S-3/S-4, X-1/X-2; `requirements.md` US-1/US-2/US-4/US-5/US-6
  (AC-1.1–1.4, AC-2.1–2.3, AC-4.1–4.3, AC-5.1–5.2, AC-6.1–6.2 + ⌘P/⌘W/⌘S edge
  cases), FM-1, FM-2, FM-3, FM-4, FM-9; ground-truth seams in
  `Markus_v3/Views/DocumentView.swift`, `RawEditorView.swift`, `RenderedView.swift`,
  `Markus_v3/Host/BrowserHostController.swift`, `SceneDelegate.swift`,
  `Markus_v3/Models/DocumentMode.swift`.
- **Outputs:**
  - Added: the key-command provider responder (design Component A), installed by
    the host for the presented editor session; mirrored Swift Testing tests in
    `Markus_v3Tests/` and XCUITest cases in `Markus_v3UITests/` (from
    `KeyCommandRoutingTests.swift` and `KeyboardShortcutsUITests.swift`).
  - Modified (only at the level needed to register/route the commands):
    `DocumentView` (exposes toggle + save as invocable handles to the provider —
    S-2); `BrowserHostController` / `SceneDelegate` (install the provider above the
    raw text view for the session; expose the existing `onBack` close — S-3).
  - Behavior delivered: US-1/US-2/US-4/US-5/US-6; FM-1, FM-2, FM-3, FM-4, FM-9;
    C-A.1–C-A.7; S-1, S-2, S-3, S-4; X-1, X-2 (exactly three commands, no ⌘N).
- **Dependencies:** none.
- **Wave:** 1.
- **Acceptance:** the T-001-tagged tests in `verify.md` pass — Swift Testing:
  `cmdP_renderedToRaw_usesExistingTransition`, `cmdP_rawToRendered_usesExistingTransition`,
  `cmdP_repeatedTogglesAlternate`, `cmdP_postsModeAnnouncement`,
  `initialModeAppear_postsNoAnnouncement`, `cmdP_withTextViewFirstResponder_notSwallowed`,
  `cmdW_invokesExistingReturnFlow`, `cmdW_savesSynchronouslyBeforeDismiss`,
  `cmdW_honoredInBothModes`, `cmdW_atBrowser_isNoOp`, `cmdS_invokesExistingSaveFlow`,
  `cmdS_noNewConfirmationUI`, `cmdS_failureUsesExistingAlertPath`,
  `cmdS_honoredInBothModes`, `cmdS_cleanBuffer_isHarmless`,
  `providerVendsExactlyThreeTitledCommands`, `titlesAreDistinctAndActionDescribing`,
  `cmdPTitleStableAcrossModes`, `noKeyboard_noCommandFires`, `registration_isInert`;
  XCUITest (iPad sim + hardware keyboard): `test_cmdP_togglesRenderedToRawToRendered`,
  `test_cmdP_repeatedAlternatesNoDrift`, `test_cmdP_withKeyboardUp_togglesAndInsertsNoCharacter`,
  `test_cmdS_savesWithNoNewConfirmationUI`, `test_cmdS_inRenderedMode_isHarmless`,
  `test_cmdW_returnsToBrowser_inRenderedMode`, `test_cmdW_returnsToBrowser_inRawMode`,
  `test_cmdW_preservesUnsavedEdits`, `test_discoverabilityOverlay_listsThreeCommands`,
  `test_discoverabilityOverlay_titleStableAcrossModes`, `test_noHardwareKeyboard_shortcutsAreNoOp`,
  `test_registration_doesNotDisableExistingGestures`. The provider vends exactly
  three commands (count == 3, inputs == {p, w, s}); no ⌘N / "New Document" entry
  exists.

### T-002 — Shared ~700pt centered content column on both editor surfaces (regular width only)

- **Description:** Introduce the shared content-width treatment (design Component
  B — `RegularWidthContentColumn`), a presentation-only container applied
  identically to `RawEditorView`'s text surface and `RenderedView`'s content. It
  derives one **shared** maximum content width (~700pt) and centers content within
  it **only** when the horizontal size class is regular; in the compact size class
  it applies no cap and no centering (iPhone / Slide Over byte-for-byte unchanged,
  modulo Part 1's inert registration). The cap is a **maximum, not a fixed width**:
  below the cap content fills the available width with no gutters; above the cap,
  equal background gutters appear on both sides; at very wide widths (~1366pt) the
  column stays ~700pt centered. Both surfaces draw from the one shared width and
  the same horizontal position, so switching modes does not shift the column
  (C-B.1 / FM-8). The gutter is non-interactive background only — the full ~700pt
  column is usable, nothing is clipped, long lines wrap as at a 700pt viewport, and
  in the raw editor the caret/selection/scroll stay within the centered column. The
  treatment reads the size class **live** and re-lays out in place on a size-class
  transition without reopening the document, resetting scroll, or discarding edits;
  each surface observes the size class itself, so a mode switch after a transition
  shows the other surface already correct (S-5/S-6/S-7). Replaces `RenderedView`'s
  current `.frame(maxWidth: .infinity, alignment: .leading)` for regular width. The
  realization mechanism (text-view content inset / container width vs. centering a
  capped region) is a build choice bounded by the observable C-B.4 guard; the size
  signal used to detect "ample vs. not" is a build choice bounded by C-B.2. A
  `ContentColumn` accessibility identifier on the capped column lets the UI tests
  locate it.
- **Inputs:** `design.md` Component B (C-B.1–C-B.4), seams S-5/S-6/S-7, X-1/X-3,
  the Component-B raw-editor seam note; `requirements.md` US-7/US-8/US-9/US-10
  (AC-7.1–7.4, AC-8.1–8.2, AC-9.1–9.3, AC-10.1–10.3 + wide-window / long-token
  edge cases), FM-5, FM-6, FM-7, FM-8; ground-truth seams in
  `Markus_v3/Views/RenderedView.swift` and `RawEditorView.swift`
  (`MarkdownTextViewBridge`).
- **Outputs:**
  - Added: the shared width-resolution treatment (design Component B); mirrored
    Swift Testing tests in `Markus_v3Tests/` and XCUITest cases in
    `Markus_v3UITests/` (from `ContentWidthTests.swift` and
    `ContentWidthUITests.swift`); a `ContentColumn` accessibility identifier on the
    capped column.
  - Modified: `RenderedView.swift` (capped+centered column in regular width;
    full-width in compact, replacing `maxWidth: .infinity`), `RawEditorView.swift`
    (same shared cap+centering on the text surface, caret/gutter behavior
    preserved).
  - Behavior delivered: US-7/US-8/US-9/US-10; FM-5, FM-6, FM-7, FM-8; C-B.1–C-B.4;
    S-5, S-6, S-7.
- **Dependencies:** none.
- **Wave:** 1.
- **Acceptance:** the T-002-tagged tests in `verify.md` pass — Swift Testing:
  `regularWide_capsBothSurfaces`, `veryWide_columnStaysCappedAndCentered`,
  `bothSurfacesShareWidthAndPosition`, `regularNarrow_belowCap_usesFullWidth`,
  `guttersAppearOnlyAboveCap`, `compact_neverCaps`, `compactWide_stillFullWidth`,
  `gutterIsBackgroundOnly`, `fullColumnUsable`, `longTokenWrapsAsAt700ptViewport`,
  `modeSwitchAfterTransition_otherSurfaceCorrect`; XCUITest (iPad sim, regular
  width): `test_renderedContent_isCenteredInRegularWidth`,
  `test_rawAndRendered_shareColumnPosition`, `test_compactToRegular_appliesCapLive`,
  `test_regularToCompact_removesCapLive`, `test_transition_preservesScrollPositionAndEdits`,
  `test_transition_thenModeSwitch_showsOtherSurfaceCorrect`,
  `test_tapInGutter_doesNotEnterTextOrMoveCaret`,
  `test_typingAtColumnEdge_caretStaysWithinColumn`. The raw and rendered columns
  resolve to the same width and x-position; compact width applies no cap.

## Wave summary

| Wave | Tasks | Parallelism |
|------|-------|-------------|
| 1 | T-001, T-002 | full — two independent concerns (key-command routing vs. content-width layout), no ordering dependency; land as two commits |

## Dependency graph summary

```
Wave 1 (parallel):
  T-001  Editor key-command provider — ⌘P/⌘W/⌘S routed to existing flows   (no deps)
  T-002  Shared ~700pt centered content column on both surfaces            (no deps)
```

The two parts (keyboard shortcuts and width constraint) are fully independent:
T-001 and T-002 share no inputs and no behavioral contract, so they sit in a
single parallel wave — reflecting the real (absent) dependency structure rather
than serializing artificially.

## Task → behavior trace (at-a-glance)

| Task | Primary US/AC/FM | Design contracts | Primary test files |
|------|------------------|------------------|--------------------|
| T-001 | US-1/2/4/5/6; AC-1.*, AC-2.*, AC-4.*, AC-5.*, AC-6.*; FM-1/2/3/4/9 | C-A.1–C-A.7, S-1, S-2, S-3, S-4, X-1, X-2 | `KeyCommandRoutingTests.swift`, `KeyboardShortcutsUITests.swift` |
| T-002 | US-7/8/9/10; AC-7.*, AC-8.*, AC-9.*, AC-10.*; FM-5/6/7/8 | C-B.1–C-B.4, S-5, S-6, S-7, X-1, X-3 | `ContentWidthTests.swift`, `ContentWidthUITests.swift` |

## Sizing assessment

Two atomic tasks in a single parallel wave. No new framework, dependency, or
deploy path is introduced — both parts use existing UIKit/SwiftUI mechanisms
(`UIKeyCommand` on the responder chain; size-class-conditional SwiftUI layout) and
route through this app's own existing action flows and surfaces. The DAG fits one
screen and has one wave (well within the 3–4 wave ceiling). This is small but
genuinely a two-task DAG (not a one-liner): each task carries a distinct
behavioral contract with its own dedicated unit + UI spec-test pair, and the
"split any task that aggregates distinct concerns" rule is what separates them.
Each task is comfortably completable in one build session with margin.

Every task has at least one mapped test (see `verify.md` — authoritative task→test
mapping).
