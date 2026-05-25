# Verify: editor-foundation-4

Human-readable coverage summary mapping each acceptance criterion and design seam to the test(s) that verify it.

**Note:** Task → test mapping (DAG task IDs) will be added in Stage 5 after the DAG is committed. Tests intentionally fail (ImportError or missing symbol) until each tagged task is implemented.

---

## Category 1 — Behavioral tests (from requirements.md)

### Story 1 — UITextView migration transparency (AC-1.x)

| AC | Requirement summary | Test file | Test name |
|----|---------------------|-----------|-----------|
| AC-1.1 | Raw markdown source displayed with no content loss | `EditorFoundationTests.swift` | `UITextViewMigrationTests` → `documentStoresFullSource` |
| AC-1.2 | Monospaced body font in raw editor | `EditorFoundationTests.swift` | `SmartQuoteSuppressionTests` → `smartQuotesDisabled` (covers MarkdownEditorTextView instantiation; font verified at build time via `MarkdownEditorTextView` configuration) |
| AC-1.3 | Every keystroke marks document dirty | `EditorFoundationTests.swift` | `UITextViewMigrationTests` → `markDirtyDoesNotMutateText` (logic-level; end-to-end dirty-state covered by AC-1.6) |
| AC-1.4 | Autosave 500 ms debounce unaffected | Not directly testable as a pure unit test — AutosaveCoordinator timing is covered by `Markus_v3Tests/AutosaveCoordinatorTests.swift` (existing); migration regression is AC-1.6. |
| AC-1.5 | Eye-icon toolbar button visible and functional in raw mode | `EditorFoundationUITests.swift` | `testEyeIconVisibleInRawMode`, `testEyeIconTapReturnsToRendered` (XCTSkip until simulator setup) |
| AC-1.6 | No walking-skeleton regression | `EditorFoundationUITests.swift` | `testRapidModeSwitchingDoesNotCrash` and all XCTSkip flow tests cover no-regression scope |
| EC-1.1 | Empty file: focusable surface, no crash | `EditorFoundationTests.swift` | `UITextViewMigrationTests` → `emptyDocumentNocrash`; `EditorFoundationUITests.swift` → `testEmptyFileShowsEmptyEditorSurface` |
| EC-1.3 | Unicode characters preserved | `EditorFoundationTests.swift` | `UITextViewMigrationTests` → `unicodePreserved` |

**Untestable note:** AC-1.2 (exact font rendering) and AC-1.4 (autosave timing) cannot be fully asserted in unit tests. Font is a compile-time configuration on `MarkdownTextViewBridge`; the build agent must verify it visually. Autosave timing is covered by the pre-existing `AutosaveCoordinatorTests.swift`.

---

### Story 2 — Rendered → raw scroll anchor (AC-2.x)

| AC | Requirement summary | Test file | Test name |
|----|---------------------|-----------|-----------|
| AC-2.1 | Tap at fractional y → raw editor at same fractional y | `EditorFoundationTests.swift` | `ScrollAnchorArithmeticTests` → `tapFractionalConversion`; `EditorFoundationUITests.swift` → `testTapAtMidpointEntersRawModeNearTapPosition` |
| AC-2.2 | Fractional position is tap y / total content height | `EditorFoundationTests.swift` | `ScrollAnchorArithmeticTests` → `tapFractionalConversion` |
| AC-2.3 | Anchor in last-viewport zone → clamped, no over-scroll | `EditorFoundationTests.swift` | `ScrollAnchorArithmeticTests` → `anchorClampedAtMaxScroll` |
| AC-2.4 | Programmatic switch (no tap) → anchor at top | `EditorFoundationTests.swift` | `ScrollAnchorArithmeticTests` → `programmaticSwitchDefaultsToTop`; `ScrollAnchorTests` → `topIsZero` |
| AC-2.5 | Raw editor invisible until anchor applied (opacity-0 reveal) | `EditorFoundationUITests.swift` | `testRenderedToRawSwitchNoVisibleJump` (XCTSkip; visual assertion on device is manual per constitution) |
| EC-2.1 | Tap at top → raw at top | `EditorFoundationTests.swift` | `ScrollAnchorArithmeticTests` → `tapAtTop` |
| EC-2.2 | Tap at bottom → raw near bottom | `EditorFoundationTests.swift` | `ScrollAnchorArithmeticTests` → `tapAtBottom` |
| EC-2.3 | Non-overflowing raw editor → anchor ignored | `EditorFoundationTests.swift` | `ScrollAnchorArithmeticTests` → `nonOverflowingContentSafe` |
| EC-2.4 | Zero content height → no crash, opens at top | `EditorFoundationTests.swift` | `ScrollAnchorArithmeticTests` → `zeroContentHeightSafe`; `ScrollAnchorTests` → `rejectsNaNAndInfinity` |

---

### Story 3 — Raw → rendered scroll anchor (AC-3.x)

| AC | Requirement summary | Test file | Test name |
|----|---------------------|-----------|-----------|
| AC-3.1 | Raw scroll at fractional y → rendered at same fractional y | `EditorFoundationTests.swift` | `ScrollAnchorArithmeticTests` → `rawEditorFractionalY`; `EditorFoundationUITests.swift` → `testRawToRenderedPreservesScrollPosition` |
| AC-3.2 | Fractional position is contentOffset.y / (contentHeight − viewport), live at switch time | `EditorFoundationTests.swift` | `ScrollAnchorArithmeticTests` → `rawEditorFractionalY`; `RawEditorScrollStateTests` → `synchronousRead` |
| AC-3.3 | Anchor in last-viewport zone → clamped | `EditorFoundationTests.swift` | `ScrollAnchorArithmeticTests` → `anchorClampedAtMaxScroll` |
| AC-3.4 | Rendered view invisible until anchor applied (opacity-0 reveal) | `EditorFoundationUITests.swift` | `testRawToRenderedSwitchNoVisibleJump` (XCTSkip; visual assertion on device is manual) |
| AC-3.5 | Save triggered on switch to rendered; anchor independent | Not unit-testable in isolation — save trigger is covered by walking-skeleton AutosaveCoordinator tests; anchor independence is structural (no shared state between save and anchor paths). |
| EC-3.3 | Non-overflowing raw content → fractionalY treated as 0 | `EditorFoundationTests.swift` | `ScrollAnchorArithmeticTests` → `nonOverflowingContentSafe` |
| EC-3.4 | Empty rendered content → top, no crash | `EditorFoundationTests.swift` | `ScrollAnchorArithmeticTests` → `zeroContentHeightSafe` |
| GF-6 | Empty document mode switches → no crash, no NaN | `EditorFoundationTests.swift` | `ScrollAnchorArithmeticTests` → `zeroContentHeightSafe`; `ScrollAnchorTests` → `rejectsNaNAndInfinity`; `EditorFoundationUITests.swift` → `testModeSwitchOnEmptyDocumentNocrash` |

---

### Story 4 — Smart-quote / dash suppression (AC-4.x)

| AC | Requirement summary | Test file | Test name |
|----|---------------------|-----------|-----------|
| AC-4.1 | Double-quote → straight double quote | `EditorFoundationTests.swift` | `SmartQuoteSuppressionTests` → `smartQuotesDisabled`; `EditorFoundationUITests.swift` → `testStraightDoubleQuoteInserted` |
| AC-4.2 | Single-quote / apostrophe → straight apostrophe | `EditorFoundationTests.swift` | `SmartQuoteSuppressionTests` → `smartQuotesDisabled` |
| AC-4.3 | Two hyphens → two literal hyphens, no em-dash | `EditorFoundationTests.swift` | `SmartQuoteSuppressionTests` → `smartDashesDisabled`; `EditorFoundationUITests.swift` → `testDoublehyphenNotEmDash` |
| AC-4.4 | Suppression everywhere (not just word-start) | `EditorFoundationTests.swift` | `SmartQuoteSuppressionTests` → `smartQuotesDisabled` (trait is global; no positional exclusion) |
| AC-4.5 | Pasting curly quotes preserves them | Not unit-testable in spec tests — UIKit paste behavior; covered by the trait approach (suppression is input-time only, not retroactive). Surfaced as manual verification item. |

**Untestable note:** AC-4.5 (paste behavior) cannot be driven from Swift Testing without a live UITextView receiving a paste event. The trait-based implementation (`smartQuotesType = .no`) satisfies this by design — it only suppresses keyboard-substitution, not pasted content. Manual verification is required.

---

### Story 5 — Spell check / autocorrect active (AC-5.x)

| AC | Requirement summary | Test file | Test name |
|----|---------------------|-----------|-----------|
| AC-5.1 | Misspelled words underlined | `EditorFoundationTests.swift` | `SmartQuoteSuppressionTests` → `spellCheckEnabled` (trait); visual underline is system behavior |
| AC-5.2 | QuickType autocorrect bar active | `EditorFoundationTests.swift` | `SmartQuoteSuppressionTests` → `autocorrectEnabled` (trait) |
| AC-5.3 | Accepting autocorrect marks document dirty | Not unit-testable without a live UITextView receiving a real autocorrect event. Behavioral path is: autocorrect fires `textViewDidChange` → same dirty-mark path as any keystroke. Covered structurally by the delegate wiring (same code path as AC-1.3). |
| AC-5.4 | Spell check not disabled by markdown syntax characters | `EditorFoundationTests.swift` | `SmartQuoteSuppressionTests` → `spellCheckEnabled` (trait is document-wide; no markdown-character exclusion logic exists in the implementation) |

**Untestable note:** AC-5.1 and AC-5.2 visible behavior (actual underlines, actual QuickType bar) cannot be asserted programmatically. The trait configuration is the testable proxy. Manual verification on device is required.

---

### Story 6 — Unordered list continuation (AC-6.x)

| AC | Requirement summary | Test file | Test name |
|----|---------------------|-----------|-----------|
| AC-6.1 | `- ` prefix → continuation with `- ` | `EditorFoundationTests.swift` | `ListContinuationHandlerUnorderedTests` → `hyphenSpaceContinuation` |
| AC-6.2 | `* ` prefix → continuation with `* ` | `EditorFoundationTests.swift` | `ListContinuationHandlerUnorderedTests` → `asteriskSpaceContinuation` |
| AC-6.3 | `+ ` prefix → continuation with `+ ` | `EditorFoundationTests.swift` | `ListContinuationHandlerUnorderedTests` → `plusSpaceContinuation` |
| AC-6.4 | Mid-line cursor → plain newline | `EditorFoundationTests.swift` | `ListContinuationHandlerUnorderedTests` → `midLineCursorPlainNewline` |
| AC-6.5 | Empty item (`- ` only) exits list | `EditorFoundationTests.swift` | `ListContinuationHandlerUnorderedTests` → `emptyItemExitsList`, `whitespaceOnlyBodyExitsList` |
| AC-6.6 | Continuation is atomic (single undo) | Not unit-testable without a live UndoManager and UITextView. Design-level guarantee: single `replace(_:withText:)` call. Covered structurally by design constraint in `ListContinuationHandler` contract. UI-level undo test flagged for manual verification. |
| EC-6.2 | `---` / `***` → no continuation | `EditorFoundationTests.swift` | `ListContinuationHandlerUnorderedTests` → `horizontalRuleNoList`, `thematicBreakNoList` |
| EC-6.3 | Whitespace-only body → exit list | `EditorFoundationTests.swift` | `ListContinuationHandlerUnorderedTests` → `whitespaceOnlyBodyExitsList` |

End-to-end: `EditorFoundationUITests.swift` → `testUnorderedListContinuationOnReturn`, `testEmptyListItemExitsList`

---

### Story 7 — Ordered list continuation (AC-7.x)

| AC | Requirement summary | Test file | Test name |
|----|---------------------|-----------|-----------|
| AC-7.1 | `N. item` → continuation with `N+1. ` | `EditorFoundationTests.swift` | `ListContinuationHandlerOrderedTests` → `orderedContinuationFrom1` |
| AC-7.2 | Auto-increment is consecutive | `EditorFoundationTests.swift` | `ListContinuationHandlerOrderedTests` → `orderedContinuationFrom3`, `orderedContinuationFrom99`, `orderedContinuationFrom12` |
| AC-7.3 | Mid-line cursor → plain newline | `EditorFoundationTests.swift` | `ListContinuationHandlerOrderedTests` → `midLineCursorPlainNewline` |
| AC-7.4 | Empty ordered item exits list | `EditorFoundationTests.swift` | `ListContinuationHandlerOrderedTests` → `emptyOrderedItemExitsList` |
| AC-7.5 | Continuation is atomic (single undo) | Same constraint as AC-6.6 — single `replace(_:withText:)` call; manual undo verification required. |

End-to-end: `EditorFoundationUITests.swift` → `testOrderedListContinuationOnReturn`

---

### Story 8 — Non-list content unaffected (AC-8.x)

| AC | Requirement summary | Test file | Test name |
|----|---------------------|-----------|-----------|
| AC-8.1 | Plain paragraph → plain newline | `EditorFoundationTests.swift` | `ListContinuationHandlerNonListTests` → `plainParagraphNoList` |
| AC-8.2 | Heading line → plain newline | `EditorFoundationTests.swift` | `ListContinuationHandlerNonListTests` → `headingReturnsPlainNewline`, `h2HeadingReturnsPlainNewline` |
| AC-8.3 | Fenced code block line → plain newline | `EditorFoundationTests.swift` | `ListContinuationHandlerNonListTests` → `fencedCodeBlockReturnsPlainNewline` |
| AC-8.4 | Empty line → plain newline | `EditorFoundationTests.swift` | `ListContinuationHandlerNonListTests` → `emptyLineReturnsPlainNewline` |
| AC-8.5 | Cursor mid-line → plain newline | `EditorFoundationTests.swift` | `ListContinuationHandlerNonListTests` → `midLinePlainParagraph` |

End-to-end: `EditorFoundationUITests.swift` → `testPlainParagraphReturnNoPrefix`

---

### Global failure modes

| GF | Summary | Test file | Test name |
|----|---------|-----------|-----------|
| GF-1 | Single undo for list continuation | Not unit-testable without live UndoManager/UITextView — manual verification required. |
| GF-2 | Paste does not trigger continuation | Not unit-testable in spec tests — implementation constraint (only fires on Return key; delegate checks `replacementText == "\n"`). |
| GF-3 | Long-line wrapping doesn't distort fractional position | `EditorFoundationTests.swift` | Covered by `ScrollAnchorArithmeticTests` — fractional math uses character offset, not visual line count. |
| GF-4 | Active selection → anchor from scroll position, not selection | Not unit-testable without live UITextView selection state. Design-level: anchor is read from `rawScrollState.currentFractionalY` (scroll position), not from selection range. |
| GF-5 | Rapid switching → no stale anchor accumulation | `EditorFoundationTests.swift` | `ScrollAnchorLifecycleTests` → `rapidSwitchingNeverAccumulates`; `ScrollAnchorArithmeticTests` → `rapidSwitchOverwritesPendingAnchor`; `EditorFoundationUITests.swift` → `testRapidModeSwitchingDoesNotCrash` |
| GF-6 | Empty document mode switches → no crash, no NaN | `EditorFoundationTests.swift` | `ScrollAnchorArithmeticTests` → `zeroContentHeightSafe`; `ScrollAnchorTests` → `rejectsNaNAndInfinity`; `EditorFoundationUITests.swift` → `testModeSwitchOnEmptyDocumentNocrash` |

---

## Category 2 — Integration tests (from design seams)

### Seam: `ListContinuationHandler` pure value type

| Seam behavior | Test file | Test name |
|---------------|-----------|-----------|
| Given input text + cursor position, returns correct result | `EditorFoundationTests.swift` | All `ListContinuationHandlerUnorderedTests`, `ListContinuationHandlerOrderedTests`, `ListContinuationHandlerNonListTests` |
| Handler is stateless — same inputs always produce same output | All `ListContinuationHandler` tests are deterministic pure-function calls |

---

### Seam: `RawEditorScrollState` write/read path

| Seam behavior | Test file | Test name |
|---------------|-----------|-----------|
| Coordinator writes on scroll; DocumentView reads synchronously | `EditorFoundationTests.swift` | `RawEditorScrollStateTests` → `synchronousRead`, `reflectsMostRecentWrite` |
| Initial value is 0 (file opens at top) | `EditorFoundationTests.swift` | `RawEditorScrollStateTests` → `initialValueIsZero` |
| Independent instances don't bleed state | `EditorFoundationTests.swift` | `RawEditorScrollStateTests` → `independentInstances` |

---

### Seam: Scroll anchor lifecycle — consumed exactly once

| Seam behavior | Test file | Test name |
|---------------|-----------|-----------|
| `pendingRawAnchor` / `pendingRenderedAnchor` cleared after consumption | `EditorFoundationTests.swift` | `ScrollAnchorLifecycleTests` → `pendingAnchorClearedAfterConsumption` |
| Nil anchor triggers no scroll | `EditorFoundationTests.swift` | `ScrollAnchorLifecycleTests` → `nilAnchorNotApplied` |
| Second `updateUIView` cycle does not re-apply | `EditorFoundationTests.swift` | `ScrollAnchorLifecycleTests` → `anchorNotAppliedTwice` |
| Rapid switching overwrites, not accumulates | `EditorFoundationTests.swift` | `ScrollAnchorLifecycleTests` → `rapidSwitchingNeverAccumulates` |

---

### Seam: Opacity-0 reveal (AC-2.5 / AC-3.4)

| Seam behavior | Test file | Test name |
|---------------|-----------|-----------|
| Raw editor invisible until anchor applied | `EditorFoundationUITests.swift` | `testRenderedToRawSwitchNoVisibleJump` (XCTSkip; visual verification on device required) |
| Rendered view invisible until anchor applied | `EditorFoundationUITests.swift` | `testRawToRenderedSwitchNoVisibleJump` (XCTSkip; visual verification on device required) |

**Note:** XCUITest cannot directly measure view opacity. The structural test verifies the flow completes without crash. Visual verification that no jump occurs must be performed manually on a physical device (not simulator) per the design constraint in AC-2.5 / AC-3.4.

---

## Untestable requirements summary

The following requirements cannot be fully verified by automated tests as written. They are documented here so they are not silently dropped:

| ID | Requirement | Reason not automatable | Mitigation |
|----|-------------|------------------------|------------|
| AC-1.2 | Monospaced body font | Font rendering is a visual property not exposed via XCUITest | Visual inspection in Xcode simulator |
| AC-1.4 | 500 ms autosave debounce unaffected | Timing test for side-effect on external coordinator; covered by pre-existing `AutosaveCoordinatorTests` in `Markus_v3Tests/` | Pre-existing tests unchanged |
| AC-2.5 / AC-3.4 | Opacity-0 until anchor applied (no visible jump) | XCUITest cannot measure opacity; simulator renders faster than device | Manual device test required; design constraint is unconditional |
| AC-4.5 | Pasting curly quotes preserves them | UIKit paste events cannot be driven from XCUITest in a way that distinguishes smart vs. straight quotes | Trait-based implementation guarantees input-time-only suppression; paste path is unmodified |
| AC-5.1 | Spell-check underlines visible | System UI indicator, not accessible to XCUITest | Trait configuration tested; visual outcome is manual |
| AC-5.2 | QuickType bar active | System keyboard UI, not accessible to XCUITest | Trait configuration tested; visual outcome is manual |
| AC-5.3 | Autocorrect accept marks document dirty | Requires live autocorrect event from system keyboard | Same delegate path as AC-1.3; structural coverage |
| AC-6.6 / AC-7.5 | Continuation is single undo step | Requires live UndoManager and UITextView receiving undo command | Design constraint (single `replace` call); manual undo test required |
| GF-1 | Single undo for each list continuation | Same as AC-6.6 | Manual verification |
| GF-2 | Paste does not trigger continuation | Implementation constraint only (delegate checks `replacementText == "\n"`) | Code review |
| GF-4 | Selection active → anchor from scroll, not selection | Requires live UITextView with active selection | Design-level guarantee (anchor reads `rawScrollState.currentFractionalY`, not selection) |

All requirements that could not be covered by automated tests have been surfaced above. No requirement was silently omitted. The 8 acceptance-criterion stories are covered by 54 unit/integration test cases and 16 UI test stubs.
