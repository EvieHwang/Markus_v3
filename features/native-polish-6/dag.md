# DAG — native-polish-6

Dependency graph of build tasks for the native-polish feature. Organized into
parallel waves; tasks within a wave have no dependencies on each other and can
be executed simultaneously.

Size check: 8 tasks, 3 waves — within normal bounds for one focused build session.

---

## Task index

| ID | Wave | Description |
|----|------|-------------|
| T-001 | 1 | SF Mono font in MarkdownEditorTextView (C0) |
| T-002 | 1 | MarkdownLineBreakNormalizer new file (C2) |
| T-003 | 1 | RecentsRegistrar new file + LaunchResumeBranch wiring (C7) |
| T-004 | 2 | Dynamic Type typography in RenderedView (C1) |
| T-005 | 2 | RenderedView line-break normalization — wire C2 into RenderedView |
| T-006 | 2 | HIG semantic colors + .bar material audit (C6) |
| T-007 | 3 | Swipe gesture wiring in DocumentView / RawEditorView / RenderedView (C3) |
| T-008 | 3 | Share button + long-press text selection in DocumentView / RenderedView (C4 + C5) |

---

## Wave 1 — Foundation (no dependencies on other tasks)

### T-001 — SF Mono font in MarkdownEditorTextView

**Description:** Replace `UIFont.monospacedSystemFont(ofSize:weight:)` in
`MarkdownEditorTextView.configureAppearance()` with an explicit
`UIFont(name: "SFMono-Regular", size: 17)` (fixed prose point size, not
Dynamic Type). Set `typingAttributes` to the same font so newly typed text
inherits it. Add a fallback to `UIFont.monospacedSystemFont` if the named font
cannot be loaded.

**Inputs:**
- `Markus_v3/Editor/MarkdownEditorTextView.swift` (read + modify)
- `features/native-polish-6/design.md` C0 section (read)

**Outputs:**
- `Markus_v3/Editor/MarkdownEditorTextView.swift` (modified)

**Dependencies:** none

**Wave:** 1

**Acceptance condition:** `MarkdownEditorTextView().font?.fontName` starts with
`"SFMono-"` and `MarkdownEditorTextView().typingAttributes[.font]` cast to
`UIFont` has a font name starting with `"SFMono-"`. The font's `pointSize` is
in the range [14, 20]. Tests `rawEditorUsesSFMono`, `rawEditorFontNameIsSFMono`,
`rawEditorFontSizeIsProseSize`, `rawEditorTypingAttributesCarrySFMono`,
`rawEditorTextAssignmentRetainsSFMono`, `rawEditorDoesNotUseSFPro` all pass.

---

### T-002 — MarkdownLineBreakNormalizer (new file)

**Description:** Create `Markus_v3/Editor/MarkdownLineBreakNormalizer.swift`
with a `enum MarkdownLineBreakNormalizer` (or `struct`) containing a single
static entry point `normalize(_ input: String) -> String`. The implementation:
(1) scans for fenced code block open/close markers (` ``` ` or `~~~` with optional
info strings); (2) inside fenced regions, leaves content unchanged; (3) outside
fenced regions, for every `\n` not preceded by two or more spaces and not part
of a blank line (`\n\n`), appends two trailing spaces before the `\n`. The
function is a pure function with no state.

**Inputs:**
- `features/native-polish-6/design.md` C2 section (read)
- No existing file to modify — new file only

**Outputs:**
- `Markus_v3/Editor/MarkdownLineBreakNormalizer.swift` (created)

**Dependencies:** none

**Wave:** 1

**Acceptance condition:** All C2 seam tests pass: `fencedCodeBacktickPassThrough`,
`fencedCodeTildePassThrough`, `infoStringFencedCodePassThrough`,
`bareNewlineBecomesTwoTrailingSpaces`, `listContinuationNewlineNormalized`,
`blankLinePreserved`, `doubleNewlineStaysParagraphBreak`,
`alreadyNormalizedNotDoubleModified`, `bodyTextAfterCodeBlockNormalized`,
`emptyInputProducesEmptyOutput`, `singleLineUnchanged`,
`blockquoteNewlineNormalized`, `normalizerIsDeterministic`,
`normalizerHasNoState`. Behavioral tests `singleNewlineGetsTrailingSpaces`,
`blankLinePreservedAsParagraphBreak`, `singleNewlineInListItemNormalized`,
`singleNewlineInBlockquoteNormalized`, `fencedCodeBlockNotNormalized_backtick`,
`fencedCodeBlockNotNormalized_tilde`, `multiLineFencedCodeBlockUnchanged`,
`inlineCodeSpanNotAffectedInOutput`, `multiLineInlineCodeSpanNoCrash`,
`twoConsecutiveNewlinesUnchanged`, `alreadyNormalizedLineNotDoubleModified`,
`normalizerIsPureFunction`, `normalizerHandlesEmptyString` all pass.

---

### T-003 — RecentsRegistrar + LaunchResumeBranch wiring

**Description:** Create `Markus_v3/Resume/RecentsRegistrar.swift` with a
`RecentsRegistrar` type that accepts a weak reference to the
`UIDocumentBrowserViewController` (via `BrowserHostController`) and exposes a
`register(url:)` method. The method attempts the best available UIKit mechanism
for registering Recents (empirically determined at build time from design C7
candidates: `revealDocument(at:importIfNeeded:completion:)` or security-scoped
access touch). Failures are swallowed silently. Add an `isResumeOpen: Bool =
false` parameter to `BrowserHostController.presentDocument(at:animated:)` and
call `RecentsRegistrar.register(url:)` when `isResumeOpen == true`.
Update `LaunchResumeBranch.resume(into:)` to pass `isResumeOpen: true`.

**Inputs:**
- `Markus_v3/Resume/LaunchResumeBranch.swift` (read + modify)
- `Markus_v3/Host/BrowserHostController.swift` (read + modify)
- `features/native-polish-6/design.md` C7 section (read)
- No existing RecentsRegistrar file — new file

**Outputs:**
- `Markus_v3/Resume/RecentsRegistrar.swift` (created)
- `Markus_v3/Host/BrowserHostController.swift` (modified — new parameter)
- `Markus_v3/Resume/LaunchResumeBranch.swift` (modified — pass `isResumeOpen: true`)

**Dependencies:** none

**Wave:** 1

**Acceptance condition:** C7 seam tests pass: `recentsRegistrarCalledOnBookmarkOpen`,
`recentsRegistrarNotCalledOnBrowserDelegateOpen`, `recentsRegistrarCalledWithCorrectURL`,
`recentsRegistrarWorksWhenBrowserNotFrontmost`, `recentsRegistrarFailureIsNoop`,
`recentsRegistrarCalledEveryOpen`, `recentsRegistrarCalledPerURL`,
`mixedOpenSequenceOnlyBookmarkRegisters`. Behavioral tests
`launchResumeBranchCallsRecentsRegistrar`, `recentsRegistrationAttemptedEveryOpen`,
`recentsRegistrationWhenBrowserOffScreen`, `recentsRegistrationFailureNoCrash`,
`browserDelegateOpenNotDoubleRegistered`, `recentsRegistrationCalledInAccessOrder`,
`recentsRegistrationWhenBrowserNotFrontmost` all pass.

---

## Wave 2 — View layer changes (depend on T-002 for normalizer; T-001 and T-003 independent)

### T-004 — Dynamic Type typography in RenderedView

**Description:** Apply a `MarkdownTheme` (or `.environment` modifier) to the
`Markdown(text)` call site in `RenderedView.body` that maps body text to
SwiftUI `.font(.body)` (Dynamic Type body style) and headings to `.title`,
`.title2`, `.title3` respectively. No fixed point sizes for body text. Add a
testability hook `RenderedViewTypographyProbe` that exposes the body font and
heading font for unit tests.

**Inputs:**
- `Markus_v3/Views/RenderedView.swift` (read + modify)
- `features/native-polish-6/design.md` C1 section (read)

**Outputs:**
- `Markus_v3/Views/RenderedView.swift` (modified)

**Dependencies:** none (C1 does not require T-002)

**Wave:** 2

**Acceptance condition:** `RenderedViewTypographyProbe().bodyFont().fontDescriptor`
has a `.textStyle` attribute equal to `UIFont.TextStyle.body` OR
`probe.usesPreferredFont == true`. `probe.bodyFont().pointSize` equals
`UIFont.preferredFont(forTextStyle: .body).pointSize`. H1 heading point size
exceeds body point size. Tests `renderedViewBodyUsesBodyStyle`,
`renderedViewBodyMatchesPreferredFont`, `renderedViewHeadingLargerThanBody`,
`renderedViewConstructible`, `renderedViewAtAccessibilityXL` all pass.

---

### T-005 — Wire MarkdownLineBreakNormalizer into RenderedView

**Description:** In `RenderedView.body`, replace `Markdown(text)` with
`Markdown(MarkdownLineBreakNormalizer.normalize(text))`. The normalizer is
called every render pass (it is a pure function so this is safe). No changes
to `DocumentView`, `MarkdownDocument`, or any other file.

**Inputs:**
- `Markus_v3/Views/RenderedView.swift` (read + modify)
- `Markus_v3/Editor/MarkdownLineBreakNormalizer.swift` (read — created by T-002)
- `features/native-polish-6/design.md` C2 seam relationship section (read)

**Outputs:**
- `Markus_v3/Views/RenderedView.swift` (modified)

**Dependencies:** T-002 (normalizer must exist before wiring)

**Wave:** 2

**Acceptance condition:** `RenderedView(text: "line one\nline two", onTap: { _ in })`
passes its text through `MarkdownLineBreakNormalizer.normalize` before reaching
`Markdown(...)`. Behavioral tests `singleNewlineGetsTrailingSpaces` (observable
at the RenderedView level), `fencedCodeBlockInteriorsUnchanged`, `multiLineInlineCodeNoCrash`,
`fencedCodeBlockNotNormalized_backtick`, `fencedCodeBlockNotNormalized_tilde`,
`multiLineFencedCodeBlockUnchanged`, `singleNewlineInListItemNormalized`,
`singleNewlineInBlockquoteNormalized` all continue to pass.

---

### T-006 — HIG semantic colors + .bar material audit

**Description:** (1) Audit `MarkdownEditorTextView`, `RenderedView`,
`DocumentView`, and `DetectorSurfaces` for any hard-coded color values
(UIColor(red:green:blue:alpha:), Color(hex:), CGColor literals). Replace any
found with HIG semantic equivalents. (2) Add `.toolbarBackground(.visible, for:
.navigationBar)` (or equivalent `UINavigationBarAppearance` configuration with
`.configureWithDefaultBackground()`) to `DocumentView` to ensure the navigation
bar uses the `.bar` blur material. Add a `navigationBarUsesMaterial` testability
flag to `DocumentViewToolbarProbe`.

**Inputs:**
- `Markus_v3/Views/DocumentView.swift` (read + modify)
- `Markus_v3/Views/RenderedView.swift` (read, audit only — likely no change)
- `Markus_v3/Editor/MarkdownEditorTextView.swift` (read, audit only — likely no change)
- `Markus_v3/Views/DetectorSurfaces.swift` (read, audit only)
- `features/native-polish-6/design.md` C6 section (read)

**Outputs:**
- `Markus_v3/Views/DocumentView.swift` (modified — add `.toolbarBackground` modifier)
- Other files modified only if hard-coded colors are found during audit

**Dependencies:** none (audit scope is fixed; no new types required)

**Wave:** 2

**Acceptance condition:** `DocumentViewToolbarProbe(mode: .rendered).navigationBarUsesMaterial`
returns `true`. No `UIColor(red:`, `UIColor(hue:`, `UIColor(white:` (non-semantic),
or `Color(red:`, `Color(hex:` expressions appear in any file touched by this
feature (verified by grep on modified files). Tests `rawEditorNoHardCodedColors`,
`documentViewNavigationBarUsesMaterial`, `rawEditorNoCGColorDirectAssignment` all pass.

---

## Wave 3 — Interactive behaviors (depend on T-004 + T-005 completing RenderedView; T-007 and T-008 are independent of each other)

### T-007 — Swipe gesture wiring (C3)

**Description:** Add SwiftUI `.simultaneousGesture(DragGesture(minimumDistance: 20))`
to `RawEditorView` (R→L → rendered) and `RenderedView` (L→R → raw). Each
gesture's `onEnded` handler checks: (a) `|translationX| > |translationY| * 1.5`
(dominantly horizontal); (b) `|velocityX| > 200` and `|translationX| > 50`
(above threshold); (c) for RenderedView L→R: `startX > 20` (outside edge zone)
and `contentHorizontallyScrollable == false`. On the raw editor, pass an
`onSwipeToRendered` closure from `DocumentView`; on the rendered view, pass an
`onSwipeToRaw` closure. These closures call the existing `triggerSave()` +
`mode = .rendered` / `mode = .raw` paths. Verify that the existing
`UIScreenEdgePanGestureRecognizer` in `BrowserHostController` already satisfies
NP-5 for L→R on raw, and confirm NPC-9 (no dual-fire) with keyboard-up test.

**Inputs:**
- `Markus_v3/Views/DocumentView.swift` (read + modify)
- `Markus_v3/Views/RawEditorView.swift` (read + modify)
- `Markus_v3/Views/RenderedView.swift` (read + modify — already modified by T-004/T-005)
- `Markus_v3/Host/BrowserHostController.swift` (read — confirm existing edge-pan)
- `features/native-polish-6/design.md` C3 section (read)

**Outputs:**
- `Markus_v3/Views/DocumentView.swift` (modified — closures passed to child views)
- `Markus_v3/Views/RawEditorView.swift` (modified — DragGesture on raw editor)
- `Markus_v3/Views/RenderedView.swift` (modified — DragGesture on rendered view)

**Dependencies:** T-004, T-005 (RenderedView must be stable before adding more gesture modifiers)

**Wave:** 3

**Acceptance condition:** Behavioral tests `swipeRawToRenderedFiresModeSwitch`,
`swipeRawToRenderedTriggersSave`, `swipeRawToRenderedShowsCurrentBuffer`,
`verticalScrollDoesNotTriggerSwipe`, `shortDragDoesNotTriggerSwipe`,
`browserHostInstallsEdgePanRecognizer`, `swipeRawToBrowserTriggersSaveLogic`,
`onlyOneGestureFiresOnEdgePan`, `verticalGestureDoesNotTriggerBack`,
`swipeNoCrashWhenBrowserAbsent`, `swipeRenderedToRawFiresModeSwitch`,
`swipeRenderedToRawPreservesBuffer`, `horizontalScrollDoesNotTriggerSwipe`,
`nearEdgeDragGoesToBrowser`, `verticalScrollDoesNotTriggerSwipeOnRendered`,
`swipeWithKeyboardUpCompletesNormally`. C3 seam tests
`verticalDragRawEditorNoModeSwitch`, `verticalDragRenderedViewNoModeSwitch`,
`edgeZoneDragRenderedFiresEdgePan`, `midScreenDragRenderedFiresDragGesture`,
`rawEditorNoDualGestureFire`, `horizontalScrollablePosYieldsToScroll`,
`lowVelocityDragNoModeSwitch`, `modeSwitchGestureIsSimultaneous`,
`swipeWithKeyboardUpCompletesTransition` all pass. Edge cases
`wideCodeBlockHorizontalScrollDoesNotTriggerSwipe`, `selectionExtendingDragNoModeSwitch`,
`swipeToBrowserWhenBrowserAbsent`, `swipeWithKeyboardPresentedSucceeds` pass.

---

### T-008 — Share button + long-press text selection (C4 + C5)

**Description:** (C4) Apply `.textSelection(.enabled)` to `Markdown(...)` (or
its enclosing container) in `RenderedView`. This is a single-modifier addition;
no custom gesture recognizer. (C5) Add a `ToolbarItem(placement: .topBarTrailing)`
to `DocumentView`'s `.toolbar` block conditioned on `mode == .rendered`,
containing a `ShareLink(item: fileURL!)` button with the `square.and.arrow.up`
SF Symbol. Add a deleted-file guard: check `FileManager.default.fileExists`
before presenting; if missing, no-op. If `ShareLink` cannot guarantee disk-only
sharing, fall back to imperative `UIActivityViewController` via a
`UIViewControllerRepresentable`. Share button is absent when `mode == .raw`
(NPC-11). Guard against nil `fileURL` (NPC-12).

**Inputs:**
- `Markus_v3/Views/RenderedView.swift` (read + modify — already modified by T-004/T-005/T-007)
- `Markus_v3/Views/DocumentView.swift` (read + modify — already modified by T-006/T-007)
- `features/native-polish-6/design.md` C4 and C5 sections (read)

**Outputs:**
- `Markus_v3/Views/RenderedView.swift` (modified — `.textSelection(.enabled)`)
- `Markus_v3/Views/DocumentView.swift` (modified — share `ToolbarItem`)

**Dependencies:** T-004, T-005 (RenderedView stable), T-006 (DocumentView toolbar block established)

**Wave:** 3

**Acceptance condition:** Behavioral tests `renderedViewHasTextSelectionEnabled`,
`longPressUsesSystemMenu`, `longPressOnEmptyDocumentNoCrash`,
`renderedViewWithTextSelectionConstructible`, `renderedModeHasShareButton`,
`rawModeDoesNotHaveShareButton`, `tappingSharePresentsActivityViewController`,
`shareUsesFileURL`, `shareWithDeletedFileNoCrash`, `shareWithNilURLNoCrash`,
`unsavedEditsPreservedAfterShare`. C5 seam tests `shareButtonPresentInRenderedMode`,
`shareButtonAbsentInRawMode`, `modeSwitchRemovesShareButton`,
`modeSwitchAddsShareButton`, `shareButtonInTopBarTrailing`,
`shareButtonTapPresentsActivityVC`, `shareButtonTapWithDeletedFileNoop`,
`shareButtonTapWithNilURL`. Edge cases `longPressOnEmptyRenderedDocNoCrash`,
`shareWithExternallyDeletedFileNoCrash`, `shareUsesLastSavedFileNotBuffer` pass.

---

## Dependency graph summary

```
Wave 1 (parallel):
  T-001  (no deps)
  T-002  (no deps)
  T-003  (no deps)

Wave 2 (parallel, after Wave 1):
  T-004  (no deps within Wave 1)
  T-005  (depends on T-002)
  T-006  (no deps within Wave 1)

Wave 3 (parallel, after Wave 2):
  T-007  (depends on T-004, T-005)
  T-008  (depends on T-004, T-005, T-006)
```

All tasks have at least one test in BehavioralTests.swift or SeamTests.swift. ✓
