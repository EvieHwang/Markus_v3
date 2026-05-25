# DAG: editor-foundation-4

Three concerns, seven tasks, four waves.

Generated: 2026-05-25

---

## Tasks

### T-001 — `ScrollAnchor` value type
**Wave:** 1
**Description:** Create `Markus_v3/Models/ScrollAnchor.swift`. A `Sendable` struct with a `fractionalY: Double` property clamped to `[0, 1]` on init (including NaN/infinity guard), a `static let top = ScrollAnchor(fractionalY: 0)`, and `Equatable` conformance.
**Inputs:** design.md §1
**Outputs:** `Markus_v3/Models/ScrollAnchor.swift` (new)
**Dependencies:** none
**Acceptance condition:** `ScrollAnchorTests` suite passes — clamping, `.top`, NaN/infinity guard, equality by value. `ScrollAnchorArithmeticTests` suite passes — tap-fractional conversion, zero-content safety, rapid-switch overwrite.

---

### T-002 — `RawEditorScrollState` observable object
**Wave:** 1
**Description:** Create `Markus_v3/Editor/RawEditorScrollState.swift`. A `@MainActor final class` conforming to `ObservableObject` with a plain `var currentFractionalY: Double = 0` (no `@Published`). The class carries no UIKit references; it is the bridge between the `UIViewRepresentable` coordinator and `DocumentView`.
**Inputs:** design.md §3
**Outputs:** `Markus_v3/Editor/RawEditorScrollState.swift` (new)
**Dependencies:** none
**Acceptance condition:** `RawEditorScrollStateTests` suite passes — initial value 0, synchronous write/read, independent instances do not share state.

---

### T-003 — `ListContinuationHandler` pure value type
**Wave:** 1
**Description:** Create `Markus_v3/Editor/ListContinuationHandler.swift`. A stateless struct exposing `static func result(for text: String, cursorPosition: String.Index) -> ListContinuationResult`. Implement the `ListContinuationResult` enum (`.plainNewline`, `.continueList(prefix: String)`, `.exitList(stripPrefix: String)`). Decision tree: extract the current line, match unordered (`- `, `* `, `+ `) and ordered (`\d+. `) prefixes, apply mid-line/empty-body/cursor-position rules (design.md §8 and §List Continuation Logic). Pure Swift; no UIKit.
**Inputs:** design.md §8, §List Continuation Logic; requirements.md Stories 6, 7, 8
**Outputs:** `Markus_v3/Editor/ListContinuationHandler.swift` (new)
**Dependencies:** none
**Acceptance condition:** All `ListContinuationHandlerUnorderedTests`, `ListContinuationHandlerOrderedTests`, and `ListContinuationHandlerNonListTests` suites pass (28 unit test cases, no UIKit required).

---

### T-004 — `MarkdownEditorTextView` UITextView subclass
**Wave:** 1
**Description:** Create `Markus_v3/Editor/MarkdownEditorTextView.swift`. A `UITextView` subclass that sets `smartQuotesType = .no`, `smartDashesType = .no`, `spellCheckingType = .yes`, `autocorrectionType = .yes` in its designated initializer. Applies a monospaced body font (`UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)` or equivalent). Exposes no public scroll-control API — scroll targeting is performed by the bridge.
**Inputs:** design.md §2
**Outputs:** `Markus_v3/Editor/MarkdownEditorTextView.swift` (new)
**Dependencies:** none
**Acceptance condition:** `SmartQuoteSuppressionTests` suite passes — `smartQuotesType == .no`, `smartDashesType == .no`, `spellCheckingType == .yes`, `autocorrectionType == .yes`.

---

### T-005 — `MarkdownTextViewBridge` UIViewRepresentable
**Wave:** 2
**Description:** Create `Markus_v3/Editor/MarkdownTextViewBridge.swift`. A `UIViewRepresentable` wrapping `MarkdownEditorTextView`. The `Coordinator` is `@MainActor` and implements `UITextViewDelegate` (which also covers `UIScrollViewDelegate`). Wire up: (a) text binding — `textViewDidChange` writes `document.text` and calls `markDirty()`; (b) scroll state — `scrollViewDidScroll` writes `rawScrollState.currentFractionalY = contentOffset.y / max(1, contentSize.height - bounds.height)` on every scroll frame (not just on settle); (c) list continuation — `textView(_:shouldChangeTextIn:replacementText:)` intercepts `"\n"`, calls `ListContinuationHandler.result(for:cursorPosition:)`, applies the result via a single `textView.replace(_:withText:)` call (returns `false` to suppress the default newline — satisfies single-undo requirement); (d) pending scroll anchor — the `Coordinator` holds an `anchorApplied` flag; in `updateUIView`, if `pendingScrollAnchor != nil && !coordinator.anchorApplied`, defer the offset apply via `DispatchQueue.main.async` (call `layoutIfNeeded()` before setting `contentOffset` if needed), then clear the anchor via its binding/callback and set `anchorApplied = true`; (e) opacity-0 reveal — view starts `.opacity(0)` when `pendingScrollAnchor != nil` and cross-fades to `.opacity(1)` after anchor is applied (satisfies AC-2.5).
**Inputs:** `MarkdownEditorTextView` (T-004), `RawEditorScrollState` (T-002), `ListContinuationHandler`/`ListContinuationResult` (T-003), `ScrollAnchor` (T-001), design.md §4, §Scroll Anchor Lifecycle
**Outputs:** `Markus_v3/Editor/MarkdownTextViewBridge.swift` (new)
**Dependencies:** T-001, T-002, T-003, T-004
**Acceptance condition:** `ScrollAnchorLifecycleTests` suite passes (anchor consumed exactly once, not re-applied on second `updateUIView`). `UITextViewMigrationTests` structural tests pass (`documentStoresFullSource`, `emptyDocumentNocrash`, `unicodePreserved`).

---

### T-006 — Replace `RawEditorView` body with `MarkdownTextViewBridge`
**Wave:** 3
**Description:** Rewrite `Markus_v3/Views/RawEditorView.swift`. Replace the `TextEditor` body with `MarkdownTextViewBridge`. `RawEditorView` gains: `@Binding var pendingScrollAnchor: ScrollAnchor?` (passed to the bridge; bridge clears it after consumption); a `RawEditorScrollState` parameter from `DocumentView` (forwarded to the bridge coordinator). The opacity-0 reveal is owned by the bridge (T-005); `RawEditorView` does not need a separate `isVisible` flag. The external `View` signature with `DocumentView` is unchanged — same text binding and `AutosaveCoordinator` integration as the walking-skeleton `TextEditor` version.
**Inputs:** `MarkdownTextViewBridge` (T-005), `ScrollAnchor` (T-001), `RawEditorScrollState` (T-002), existing `RawEditorView.swift`, design.md §5
**Outputs:** `Markus_v3/Views/RawEditorView.swift` (rewritten)
**Dependencies:** T-001, T-002, T-005
**Acceptance condition:** App compiles. `UITextViewMigrationTests` full suite passes. `SmartQuoteSuppressionTests` suite continues to pass. `testAppLaunchesToDocumentBrowser` UI test passes (no crash on launch).

---

### T-007 — `DocumentView` anchor wiring + `RenderedView` tap/anchor extension
**Wave:** 4
**Description:** Extend `Markus_v3/Views/DocumentView.swift` and `Markus_v3/Views/RenderedView.swift` together — these two files form one coupled wiring unit: `DocumentView` introduces anchor state that `RenderedView` consumes in the same session.

**DocumentView changes:** Add `@StateObject private var rawScrollState = RawEditorScrollState()`; `@State private var pendingRawAnchor: ScrollAnchor?`; `@State private var pendingRenderedAnchor: ScrollAnchor?`. Eye-icon action closure: read `rawScrollState.currentFractionalY` synchronously before setting `mode = .rendered`, store as `pendingRenderedAnchor`. `RenderedView` `onTap(fractionalY:)` callback: store the reported fractional y in `pendingRawAnchor`, then set `mode = .raw`. Pass `rawScrollState` and `pendingRawAnchor` (binding) to `RawEditorView`; pass `pendingRenderedAnchor` (binding) to `RenderedView`. For programmatic mode switches: set pending anchor to `.top`. Rapid-switch correctness: each transition overwrites the pending anchor; no queue.

**RenderedView changes:** Add a `UIScrollView` proxy (`UIViewRepresentable`) that locates the underlying `UIScrollView` and exposes `contentOffset`, `contentSize`, and `setContentOffset(_:animated:)`. Tap gesture: compute `tapContentY = tap.y + scrollView.contentOffset.y` and report `tapContentY / max(1, scrollView.contentSize.height)` via an `onTap(fractionalY:)` callback before the mode switch fires. Link-tap path (`OpenURLAction` override): reports `fractionalY: 0`. Incoming anchor apply: accept `pendingRenderedAnchor: Binding<ScrollAnchor?>` from `DocumentView`; apply `scrollView.contentOffset.y = anchor.fractionalY × max(0, contentSize.height - bounds.height)` clamped, via the UIScrollView proxy after layout; clear binding after apply. Opacity-0 reveal: start `.opacity(0)` when `pendingRenderedAnchor != nil`, cross-fade to `.opacity(1)` after anchor applied (satisfies AC-3.4). Zero content height: reports y=0, no crash.
**Inputs:** `RawEditorScrollState` (T-002), `ScrollAnchor` (T-001), `RawEditorView` (T-006), existing `DocumentView.swift`, existing `RenderedView.swift`, design.md §6 `DocumentView`, §7 `RenderedView`, §Scroll Anchor Lifecycle
**Outputs:** `Markus_v3/Views/DocumentView.swift` (extended), `Markus_v3/Views/RenderedView.swift` (extended)
**Dependencies:** T-001, T-002, T-006
**Acceptance condition:** `ScrollAnchorArithmeticTests` full suite passes. `ScrollAnchorLifecycleTests` full suite passes. `UITextViewMigrationTests` full suite passes. `testAppLaunchesToDocumentBrowser` passes. When un-skipped: `testEyeIconVisibleInRawMode`, `testEyeIconTapReturnsToRendered`, `testRawToRenderedSwitchNoVisibleJump`, `testRenderedToRawSwitchNoVisibleJump`, `testRawToRenderedPreservesScrollPosition`, `testTapAtMidpointEntersRawModeNearTapPosition`, `testRapidModeSwitchingDoesNotCrash`, `testModeSwitchOnEmptyDocumentNocrash`, `testEmptyFileShowsEmptyEditorSurface` pass structurally (no crash).

---

## Wave summary

| Wave | Tasks | Can parallelize? |
|------|-------|-----------------|
| 1 | T-001, T-002, T-003, T-004 | Yes — all independent |
| 2 | T-005 | Single task |
| 3 | T-006 | Single task |
| 4 | T-007 | Single task (two files, one coupled wiring unit) |

**Total tasks:** 7
**Total waves:** 4

No sizing warning — within the 3–4 wave target.

T-007 touches two files (`DocumentView` and `RenderedView`) but they are a single coupled wiring unit: `DocumentView` introduces `pendingRenderedAnchor` and `RenderedView` consumes it. Splitting them would require T-007 to pass a binding to a view that doesn't yet accept it, forcing a stub API and a second touch of `DocumentView`. Keeping them together produces a single fully-connected, testable seam in one session.

---

## Dependency graph

```
T-001   T-002   T-003   T-004      ← Wave 1 (all independent)
  \       \       |      /
   \       \      |     /
          T-005                    ← Wave 2
            |
          T-006                    ← Wave 3
            |
          T-007                    ← Wave 4
```

More precisely:

- T-005 ← T-001, T-002, T-003, T-004
- T-006 ← T-001, T-002, T-005
- T-007 ← T-001, T-002, T-006
