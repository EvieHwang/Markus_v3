# Verify — native-polish-6

Coverage summary mapping each requirement and design seam to the tests that verify it.

**Task→test mapping column is intentionally blank — Stage 5 (/dag) fills it.**

---

## Legend

- **File B** = `features/native-polish-6/tests/BehavioralTests.swift`
- **File S** = `features/native-polish-6/tests/SeamTests.swift`
- **Suite** = the `@Suite` name containing the test
- **Test** = the `@Test` display name

---

## Behavioral requirements coverage

### NP-1 — SF Mono font in raw editor

| Criterion | Test(s) | Suite | Task ID |
|-----------|---------|-------|---------|
| NP-1.1 SF Mono font family on text view | `rawEditorUsesSFMono`, `rawEditorFontNameIsSFMono` | B: `NP-1 — SF Mono font in raw editor` | |
| NP-1.2 Fixed prose-appropriate size | `rawEditorFontSizeIsProseSize` | B: `NP-1 — SF Mono font in raw editor` | |
| NP-1.3 Applied to all text (initial, typed, pasted) | `rawEditorTypingAttributesCarrySFMono`, `rawEditorTextAssignmentRetainsSFMono` | B: `NP-1 — SF Mono font in raw editor` | |
| NP-1.4 Not SF Pro | `rawEditorDoesNotUseSFPro` | B: `NP-1 — SF Mono font in raw editor` | |

### NP-2 — System default font (Dynamic Type) in rendered view

| Criterion | Test(s) | Suite | Task ID |
|-----------|---------|-------|---------|
| NP-2.1 Dynamic Type body style, scales with preferred size | `renderedViewBodyUsesBodyStyle`, `renderedViewBodyMatchesPreferredFont` | B: `NP-2 — Dynamic Type body style in rendered view` | |
| NP-2.2 Size changes with Settings (requires XCUITest; unit test is structural proxy) | `renderedViewBodyMatchesPreferredFont` | B: `NP-2 — Dynamic Type body style in rendered view` | |
| NP-2.3 No hard-coded fixed size for body text | `renderedViewBodyUsesBodyStyle`, `renderedViewBodyMatchesPreferredFont` | B: `NP-2 — Dynamic Type body style in rendered view` | |
| NP-2.4 Headings scale proportionally | `renderedViewHeadingLargerThanBody` | B: `NP-2 — Dynamic Type body style in rendered view` | |

### NP-3 — Single-newline line break in rendered view

| Criterion | Test(s) | Suite | Task ID |
|-----------|---------|-------|---------|
| NP-3.1 Single `\n` produces hard line break | `singleNewlineGetsTrailingSpaces`, `bareNewlineBecomesTwoTrailingSpaces` (S) | B: `NP-3 — MarkdownLineBreakNormalizer`, S: `C2 Seam` | |
| NP-3.2 `\n\n` produces paragraph break | `blankLinePreservedAsParagraphBreak`, `blankLinePreserved` (S), `doubleNewlineStaysParagraphBreak` (S) | B: `NP-3`, S: `C2 Seam` | |
| NP-3.3 Applies inside list items and blockquotes | `singleNewlineInListItemNormalized`, `singleNewlineInBlockquoteNormalized`, `listContinuationNewlineNormalized` (S), `blockquoteNewlineNormalized` (S) | B: `NP-3`, S: `C2 Seam` | |
| NP-3.4 Fenced code blocks NOT normalized | `fencedCodeBlockNotNormalized_backtick`, `fencedCodeBlockNotNormalized_tilde`, `multiLineFencedCodeBlockUnchanged`, `fencedCodeBacktickPassThrough` (S), `fencedCodeTildePassThrough` (S), `infoStringFencedCodePassThrough` (S) | B: `NP-3`, S: `C2 Seam` | |
| NP-3.5 Inline code spans NOT normalized *(known gap F-005 — see note below)* | `inlineCodeSpanNotAffectedInOutput`, `multiLineInlineCodeSpanNoCrash` | B: `NP-3 — MarkdownLineBreakNormalizer` | |

> **F-005 known gap:** NP-3.5 / NP-17 assert that inline code span content is passed through unchanged. The C2 normalizer operates at block level only and does not mechanistically exempt inline code spans (open finding F-005 from adversarial review). Tests verify that the rendered output is correct (the CommonMark renderer ignores injected trailing spaces inside backtick spans at current swift-cmark versions); they do not assert byte identity of inline span interiors. If a future renderer version exposes the injected spaces differently, these tests will detect the regression.

### NP-4 — Swipe R→L on raw editor transitions to rendered view

| Criterion | Test(s) | Suite | Task ID |
|-----------|---------|-------|---------|
| NP-4.1 R→L swipe triggers transition to rendered | `swipeRawToRenderedFiresModeSwitch` | B: `NP-4 — R→L swipe on raw editor` | |
| NP-4.2 Transition is animated (requires XCUITest) | *(XCUITest — not unit-testable)* | — | |
| NP-4.3 Unsaved edits preserved (save triggered) | `swipeRawToRenderedTriggersSave` | B: `NP-4 — R→L swipe on raw editor` | |
| NP-4.4 Rendered view shows current buffer | `swipeRawToRenderedShowsCurrentBuffer` | B: `NP-4 — R→L swipe on raw editor` | |
| NP-4.5 No conflict with text selection gesture | `shortDragDoesNotTriggerSwipe`, `lowVelocityDragNoModeSwitch` (S) | B: `NP-4`, S: `C3 Seam` | |
| NP-4.6 No conflict with vertical scroll | `verticalScrollDoesNotTriggerSwipe`, `verticalDragRawEditorNoModeSwitch` (S) | B: `NP-4`, S: `C3 Seam` | |

### NP-5 — Swipe L→R on raw editor transitions to file browser

| Criterion | Test(s) | Suite | Task ID |
|-----------|---------|-------|---------|
| NP-5.1 L→R swipe navigates to file browser | `browserHostInstallsEdgePanRecognizer`, `swipeRawToBrowserTriggersSaveLogic` | B: `NP-5 — L→R swipe on raw editor` | |
| NP-5.2 Animated transition (requires XCUITest) | *(XCUITest — not unit-testable)* | — | |
| NP-5.3 Save logic fires on swipe-to-browser | `swipeRawToBrowserTriggersSaveLogic` | B: `NP-5 — L→R swipe on raw editor` | |
| NP-5.4 No conflict with system interactive-pop gesture (NPC-9) | `onlyOneGestureFiresOnEdgePan`, `rawEditorNoDualGestureFire` (S) | B: `NP-5`, S: `C3 Seam` | |
| NP-5.5 No conflict with text selection | `shortDragDoesNotTriggerSwipe`, `lowVelocityDragNoModeSwitch` (S) | B: `NP-4`, S: `C3 Seam` | |
| NP-5.6 No conflict with vertical scroll | `verticalGestureDoesNotTriggerBack`, `verticalDragRawEditorNoModeSwitch` (S) | B: `NP-5`, S: `C3 Seam` | |

### NP-6 — Swipe L→R on rendered view transitions to raw editor

| Criterion | Test(s) | Suite | Task ID |
|-----------|---------|-------|---------|
| NP-6.1 L→R swipe triggers transition to raw | `swipeRenderedToRawFiresModeSwitch`, `midScreenDragRenderedFiresDragGesture` (S) | B: `NP-6`, S: `C3 Seam` | |
| NP-6.2 Animated transition (requires XCUITest) | *(XCUITest — not unit-testable)* | — | |
| NP-6.3 Document state unchanged by swipe | `swipeRenderedToRawPreservesBuffer` | B: `NP-6 — L→R swipe on rendered view` | |
| NP-6.4 No conflict with horizontal content scroll (NPC-19) | `horizontalScrollDoesNotTriggerSwipe`, `wideCodeBlockHorizontalScrollDoesNotTriggerSwipe` (B edge cases), `horizontalScrollablePosYieldsToScroll` (S) | B: `NP-6`, B: edge cases, S: `C3 Seam` | |
| NP-6.5 No conflict with edge-pan gesture (NPC-22) | `nearEdgeDragGoesToBrowser`, `edgeZoneDragRenderedFiresEdgePan` (S) | B: `NP-6`, S: `C3 Seam` | |

### NP-7 — Long press in rendered view raises system text menu

| Criterion | Test(s) | Suite | Task ID |
|-----------|---------|-------|---------|
| NP-7.1 System text menu appears on long press | `renderedViewHasTextSelectionEnabled` | B: `NP-7 — Long press in rendered view` | |
| NP-7.2 Menu contains Copy and Select All (requires XCUITest) | *(XCUITest — not unit-testable)* | — | |
| NP-7.3 Copy action copies to pasteboard (requires XCUITest) | *(XCUITest — not unit-testable)* | — | |
| NP-7.4 Select All selects all text (requires XCUITest) | *(XCUITest — not unit-testable)* | — | |
| NP-7.5 No conflict with link long-press (system behavior via .textSelection) | *(Inherent in .textSelection(.enabled) — no extra test needed)* | — | |
| NP-7.6 Empty document: no crash on long press | `longPressOnEmptyDocumentNoCrash`, `longPressOnEmptyRenderedDocNoCrash` (B edge cases) | B: `NP-7`, B: edge cases | |
| NP-7.7 System control used, not custom action sheet | `longPressUsesSystemMenu` | B: `NP-7 — Long press in rendered view` | |

### NP-8 — Share button in rendered view navigation bar

| Criterion | Test(s) | Suite | Task ID |
|-----------|---------|-------|---------|
| NP-8.1 Share button uses `square.and.arrow.up` SF Symbol | `renderedModeHasShareButton`, `shareButtonPresentInRenderedMode` (S), `shareButtonSFSymbol` check (S) | B: `NP-8`, S: `C5 Seam` | |
| NP-8.2 Tapping share presents UIActivityViewController | `tappingSharePresentsActivityViewController`, `shareButtonTapPresentsActivityVC` (S) | B: `NP-8`, S: `C5 Seam` | |
| NP-8.3 Activity list is OS-provided (structural contract, no unit test needed) | *(OS behavior — no test needed)* | — | |
| NP-8.4 Share uses last-saved disk file, not in-memory buffer | `shareUsesFileURL`, `shareButtonTapPresentsActivityVC` (S) | B: `NP-8`, S: `C5 Seam` | |
| NP-8.5 Unsaved edits remain intact after share | `unsavedEditsPreservedAfterShare` | B: `NP-8 — Share button` | |
| NP-8.6 Deleted file: no crash | `shareWithDeletedFileNoCrash`, `shareWithExternallyDeletedFileNoCrash` (B edge cases), `shareButtonTapWithDeletedFileNoop` (S) | B: `NP-8`, B: edge cases, S: `C5 Seam` | |
| NP-8.7 Share button absent in raw editor | `rawModeDoesNotHaveShareButton`, `shareButtonAbsentInRawMode` (S) | B: `NP-8`, S: `C5 Seam` | |
| NP-8.8 iPad popover anchoring (UIActivityViewController standard behavior) | *(Standard UIKit behavior when placed in ToolbarItem — no extra test needed)* | — | |

### NP-9 — HIG semantic colors and `.bar` material

| Criterion | Test(s) | Suite | Task ID |
|-----------|---------|-------|---------|
| NP-9.1 No hard-coded colors in modified components | `rawEditorNoHardCodedColors`, `rawEditorNoCGColorDirectAssignment` | B: `NP-9 — HIG semantic colors` | |
| NP-9.2 Toolbars/nav bars use `.bar` material | `documentViewNavigationBarUsesMaterial` | B: `NP-9 — HIG semantic colors` | |
| NP-9.3 Correct in Dark Mode (requires XCUITest) | *(XCUITest — visual appearance not unit-testable)* | — | |
| NP-9.4 Correct with Increase Contrast (system semantic colors have built-in HC variants) | *(Satisfied structurally by using semantic colors; no dedicated unit test)* | — | |
| NP-9.5 Nav bar in raw and rendered views uses `.bar` material | `documentViewNavigationBarUsesMaterial` | B: `NP-9 — HIG semantic colors` | |

### NP-10 — Recents registration after bookmark-based open

| Criterion | Test(s) | Suite | Task ID |
|-----------|---------|-------|---------|
| NP-10.1 Best-effort registration attempt on bookmark-based open | `launchResumeBranchCallsRecentsRegistrar`, `recentsRegistrarCalledOnBookmarkOpen` (S) | B: `NP-10`, S: `C7 Seam` | |
| NP-10.2 Registration called in access order | `recentsRegistrationCalledInAccessOrder`, `recentsRegistrarCalledPerURL` (S) | B: `NP-10`, S: `C7 Seam` | |
| NP-10.3 Browser-delegate opens not double-registered | `browserDelegateOpenNotDoubleRegistered`, `recentsRegistrarNotCalledOnBrowserDelegateOpen` (S), `mixedOpenSequenceOnlyBookmarkRegisters` (S) | B: `NP-10`, S: `C7 Seam` | |
| NP-10.4 Registration on every bookmark-based open | `recentsRegistrationAttemptedEveryOpen`, `recentsRegistrarCalledEveryOpen` (S) | B: `NP-10`, S: `C7 Seam` | |
| NP-10.5 Registration when browser is off-screen | `recentsRegistrationWhenBrowserOffScreen`, `recentsRegistrarWorksWhenBrowserNotFrontmost` (S) | B: `NP-10`, S: `C7 Seam` | |
| NP-10.6 Registration failure: no crash, no user error, file still opens | `recentsRegistrationFailureNoCrash`, `recentsRegistrarFailureIsNoop` (S) | B: `NP-10`, S: `C7 Seam` | |

---

## Edge cases NP-11 through NP-21

| Edge case | Test(s) | Suite | Task ID |
|-----------|---------|-------|---------|
| NP-11 Horizontal scroll in rendered view | `wideCodeBlockHorizontalScrollDoesNotTriggerSwipe` | B: `NP-11 through NP-21 — Edge cases` | |
| NP-12 Selection-extending drag on raw editor | `selectionExtendingDragNoModeSwitch` | B: `NP-11 through NP-21 — Edge cases` | |
| NP-13 Share sheet uses disk copy despite unsaved edits | `shareUsesLastSavedFileNotBuffer` | B: `NP-11 through NP-21 — Edge cases` | |
| NP-14 Share with deleted file: no crash | `shareWithExternallyDeletedFileNoCrash` | B: `NP-11 through NP-21 — Edge cases` | |
| NP-15 Long press on empty rendered content: no crash | `longPressOnEmptyRenderedDocNoCrash` | B: `NP-11 through NP-21 — Edge cases` | |
| NP-16 Fenced code block newlines not normalized | `fencedCodeBlockInteriorsUnchanged` | B: `NP-11 through NP-21 — Edge cases` | |
| NP-17 Inline code span no crash *(F-005 known gap)* | `multiLineInlineCodeNoCrash` | B: `NP-11 through NP-21 — Edge cases` | |
| NP-18 Recents registration when browser off-screen | `recentsRegistrationWhenBrowserNotFrontmost` | B: `NP-11 through NP-21 — Edge cases` | |
| NP-19 Swipe L→R when browser not in stack: no crash | `swipeToBrowserWhenBrowserAbsent` | B: `NP-11 through NP-21 — Edge cases` | |
| NP-20 Swipe with keyboard up: no deadlock | `swipeWithKeyboardPresentedSucceeds`, `swipeWithKeyboardUpCompletesTransition` (S) | B: edge cases, S: `C3 Seam` | |
| NP-21 Dynamic Type Accessibility XL: no clip | `renderedViewAtAccessibilityXLNoClip` | B: `NP-11 through NP-21 — Edge cases` | |

---

## Design seam coverage

### C2 Seam — MarkdownLineBreakNormalizer input/output contract

| Behavior | Test(s) | Task ID |
|----------|---------|---------|
| Fenced code block (backtick) passes through unchanged | `fencedCodeBacktickPassThrough` | |
| Fenced code block (tilde) passes through unchanged | `fencedCodeTildePassThrough` | |
| Fenced code block with info string passes through unchanged | `infoStringFencedCodePassThrough` | |
| Bare newline in body text → two trailing spaces + `\n` | `bareNewlineBecomesTwoTrailingSpaces` | |
| List continuation line single `\n` normalized | `listContinuationNewlineNormalized` | |
| Blank line (`\n\n`) preserved as paragraph break, not line break | `blankLinePreserved`, `doubleNewlineStaysParagraphBreak` | |
| Already-normalized line not double-modified | `alreadyNormalizedNotDoubleModified` | |
| Body text after code block is normalized normally | `bodyTextAfterCodeBlockNormalized` | |
| Empty input → empty output | `emptyInputProducesEmptyOutput` | |
| Single-line input (no `\n`) is returned unchanged | `singleLineUnchanged` | |
| Blockquote `\n` normalized (NP-3.3) | `blockquoteNewlineNormalized` | |
| Pure function (deterministic across calls) | `normalizerIsDeterministic`, `normalizerHasNoState` | |

### C3 Seam — SwipeNavigationCoordinator: gesture conflict resolution

| Behavior | Test(s) | Task ID |
|----------|---------|---------|
| Vertical drag on raw editor does not trigger mode switch | `verticalDragRawEditorNoModeSwitch` | |
| Vertical drag on rendered view does not trigger mode switch | `verticalDragRenderedViewNoModeSwitch` | |
| L→R drag in edge zone on rendered view fires edge pan, not DragGesture (NPC-22) | `edgeZoneDragRenderedFiresEdgePan` | |
| L→R drag outside edge zone on rendered view fires DragGesture for raw mode | `midScreenDragRenderedFiresDragGesture` | |
| On raw editor, L→R edge pan and SwiftUI DragGesture do not both fire (NPC-9) | `rawEditorNoDualGestureFire` | |
| Horizontal content scroll yields to scroll, not mode switch (NPC-19) | `horizontalScrollablePosYieldsToScroll` | |
| Low-velocity drag below threshold does not trigger mode switch (NPC-20) | `lowVelocityDragNoModeSwitch` | |
| DragGesture is `.simultaneousGesture` (scroll also receives events) | `modeSwitchGestureIsSimultaneous` | |
| Keyboard-up swipe completes mode switch without deadlock (NPC-8) | `swipeWithKeyboardUpCompletesTransition` | |

### C5 Seam — Share button presence conditioned on DocumentView mode

| Behavior | Test(s) | Task ID |
|----------|---------|---------|
| Share button present in rendered mode | `shareButtonPresentInRenderedMode` | |
| Share button absent in raw mode (NPC-11) | `shareButtonAbsentInRawMode` | |
| Mode switch rendered→raw removes share button | `modeSwitchRemovesShareButton` | |
| Mode switch raw→rendered adds share button | `modeSwitchAddsShareButton` | |
| Share button in `.topBarTrailing` placement | `shareButtonInTopBarTrailing` | |
| Share tap with existing file presents UIActivityViewController | `shareButtonTapPresentsActivityVC` | |
| Share tap with deleted file is a safe no-op | `shareButtonTapWithDeletedFileNoop` | |
| Share tap with nil URL is a safe no-op (NPC-12) | `shareButtonTapWithNilURL` | |

### C7 Seam — RecentsRegistrar: called on bookmark-based open, not browser-delegate open

| Behavior | Test(s) | Task ID |
|----------|---------|---------|
| `RecentsRegistrar.register` called for bookmark-based open | `recentsRegistrarCalledOnBookmarkOpen` | |
| `RecentsRegistrar.register` NOT called for browser-delegate open (NPC-17) | `recentsRegistrarNotCalledOnBrowserDelegateOpen` | |
| Register called with the exact URL being opened | `recentsRegistrarCalledWithCorrectURL` | |
| Register works when browser is not the frontmost VC (NPC-15) | `recentsRegistrarWorksWhenBrowserNotFrontmost` | |
| Registration failure is a silent no-op; document still opens (NPC-16) | `recentsRegistrarFailureIsNoop` | |
| Register called on every bookmark-based open of the same file (NP-10.4) | `recentsRegistrarCalledEveryOpen` | |
| Register called once per open for each URL | `recentsRegistrarCalledPerURL` | |
| Mixed open sequence: only bookmark opens register | `mixedOpenSequenceOnlyBookmarkRegisters` | |

---

## Requirements requiring XCUITest (not unit-testable)

The following acceptance criteria require end-to-end UI testing via `XCUITest` and cannot be meaningfully verified in Swift Testing unit tests. These are documented here so they are not lost when the XCUITest suite is written.

| Criterion | Reason |
|-----------|--------|
| NP-4.2 Animated transition (R→L raw→rendered) | Requires observing UIKit animation in simulator |
| NP-5.2 Animated transition (L→R raw→browser) | Requires observing UIKit animation in simulator |
| NP-6.2 Animated transition (L→R rendered→raw) | Requires observing UIKit animation in simulator |
| NP-7.2 System text menu contains Copy and Select All | Requires interacting with system UI callout |
| NP-7.3 Copy action populates pasteboard | Requires live UIKit text selection interaction |
| NP-7.4 Select All selects all text | Requires live UIKit text selection interaction |
| NP-9.3 UI correct in Dark Mode | Requires visual snapshot or UITraitCollection overrides in XCUITest |
| NP-9.4 UI correct with Increase Contrast | Requires accessibility settings override in XCUITest |
| NP-2.2 Rendered view body size changes with Settings text size | Requires Dynamic Type override in XCUITest |
| NP-21 No layout clipping at Accessibility XL (visual) | Requires screenshot/snapshot comparison in XCUITest |

---

## Known gaps (open adversarial findings)

| Finding | Severity | Impact on tests |
|---------|----------|-----------------|
| F-005 (open) | LOW | NP-3.5 / NP-17 tests verify rendered output only, not byte identity of inline code span interiors. The normalizer injects trailing spaces inside inline code spans at the byte level; the CommonMark renderer currently ignores them. Tests are annotated with `@available(*, deprecated, message:)` marker and inline comments. If a future swift-cmark version processes injected spaces differently, the tests will catch the regression. |
