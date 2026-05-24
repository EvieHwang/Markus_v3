# Design: editor-foundation-4

## Ground-truth check (resolved before drafting)

- **Walking skeleton seams consulted:** `RawEditorView`, `RenderedView`, `DocumentView`, `DocumentMode` — all read from `features/walking-skeleton-1/design.md` before drafting.
- **Concurrency:** Swift 6 strict concurrency on; all UIKit-bridging seams run `@MainActor` unless otherwise noted. `UIViewRepresentable` callbacks (`makeUIView`, `updateUIView`, `makeCoordinator`) run on the main actor by protocol contract.
- **UIViewRepresentable + scroll position:** `UIScrollView.contentOffset` is a UIKit value; it cannot be read reliably from SwiftUI until the underlying `UIView` tree has been laid out. The design solves this via a deferred-apply pattern (see §Scroll Anchor Lifecycle).
- **Pattern reuse from constitution.md:** constitution.md contains no iOS-specific patterns (it holds Python/React entries only). Patterns established by this feature are the first iOS-layer patterns and should be registered in constitution.md after the feature ships.
- **Walking skeleton pattern citations in this document:** walking-skeleton-1 established the initial iOS patterns. References below use the form `Extends seam: [seam name]` or `Replaces seam: [seam name]` against the seam table in walking-skeleton-1/design.md.

---

## High-level shape

This feature has three tightly coupled concerns that share a single migration seam: the `TextEditor`→`UITextView` bridge. All three are delivered together because they each require direct `UITextView` access and separating them would require a second migration pass.

**Concern 1 — UITextView migration.** `RawEditorView` is replaced wholesale. The new implementation wraps a `MarkdownEditorTextView` (a `UITextView` subclass) via a `UIViewRepresentable` type called `MarkdownTextViewBridge`. The SwiftUI surface of `RawEditorView` is unchanged from the perspective of its caller, `DocumentView`.

**Concern 2 — Scroll-anchor preservation.** A lightweight value type, `ScrollAnchor`, carries a `fractionalY: Double` (clamped `0…1`) between mode transitions. `DocumentView` owns the live anchor value. `MarkdownTextViewBridge` exposes a write-only scroll target so the anchor can be applied to the `UITextView` after layout. `RenderedView` exposes a matching scroll target for the rendered → raw → rendered round-trip.

**Concern 3 — Native editing polish.** `MarkdownEditorTextView` overrides `UITextInputTraits` to suppress smart quotes/dashes and enables spell check/autocorrect. A `UITextViewDelegate` implemented in `MarkdownTextViewBridge.Coordinator` intercepts Return key presses for list continuation.

---

## Components

### 1. `ScrollAnchor` — `ScrollAnchor.swift` (new)

A value type that represents the fractional vertical scroll position used across mode transitions.

**Behavioral constraints:**
- The value is always in `[0.0, 1.0]`. Values outside this range are clamped on write; callers need not guard.
- A `ScrollAnchor` with `fractionalY == 0` represents "top of document" and is the safe default for all edge cases (empty document, unknown tap position, programmatic mode switch with no tap).
- The type carries no UIKit or SwiftUI types — it is a pure value that either side of the bridge can hold without concurrency concern.

**Public interface (named because this is the contract between `DocumentView` and both editor surfaces):**
```swift
struct ScrollAnchor: Sendable {
    static let top = ScrollAnchor(fractionalY: 0)
    var fractionalY: Double  // always clamped [0, 1]
    init(fractionalY: Double)
}
```

The interface is named explicitly because `DocumentView`, `MarkdownTextViewBridge`, and `RenderedView` all pass this type across their shared boundary — it is the integration contract, not an implementation detail.

---

### 2. `MarkdownEditorTextView` — `MarkdownEditorTextView.swift` (new)

A `UITextView` subclass responsible for the text input traits and physical scroll-position read.

**Behavioral constraints:**
- Smart quotes and smart dashes are suppressed at all times. A user typing `"`, `'`, or `--` receives the literal character(s) typed, never a typographic substitute. This applies everywhere in the document, not only at word boundaries.
- Spell check and autocorrect are active. Misspelled words receive the system underline indicator; the QuickType bar offers completions.
- Accepting an autocorrect suggestion constitutes a normal text-change event; the document is marked dirty and the autosave timer is reset exactly as any other keystroke would.
- The subclass exposes a read of its current fractional scroll position: `contentOffset.y / max(1, contentSize.height - bounds.height)`, where the denominator floor of 1 prevents division-by-zero on empty or non-overflowing documents.
- The subclass exposes no public `scrollTo` method. Scroll targeting is performed externally by `MarkdownTextViewBridge` after layout (see §Scroll Anchor Lifecycle).

---

### 3. `MarkdownTextViewBridge` — `MarkdownTextViewBridge.swift` (new)

A `UIViewRepresentable` that bridges `MarkdownEditorTextView` into SwiftUI.

**Behavioral constraints:**
- Text edits flow out through a binding to `document.text`. Every character-level change updates the binding value, which triggers `document.markDirty()` and the autosave debounce in `AutosaveCoordinator` — identical to the pre-migration `TextEditor` behavior.
- The bridge renders a monospaced body font, matching the pre-migration appearance.
- Scroll position flows out to `DocumentView` through a `Binding<ScrollAnchor>`. The bridge writes this binding whenever the scroll view settles (on `scrollViewDidEndDecelerating` and `scrollViewDidEndDragging(_:willDecelerate:)` when not decelerating). This keeps `DocumentView`'s anchor fresh for the raw → rendered transition without requiring continuous polling.
- An incoming `pendingScrollAnchor: ScrollAnchor?` (optional) is consumed exactly once after the `UITextView` is laid out. See §Scroll Anchor Lifecycle.
- The bridge does not expose its `UITextView` instance directly to SwiftUI callers; all behavioral surface passes through the binding and the anchor.

**Coordinator responsibilities:**
- Implements `UITextViewDelegate`.
- On `textViewDidChange`: writes the updated text to the binding; calls `markDirty()` and notifies `AutosaveCoordinator`.
- On `scrollViewDidEndDecelerating` / `scrollViewDidEndDragging(_:willDecelerate:)` with `!decelerate`: computes the current fractional position from `MarkdownEditorTextView` and writes `scrollAnchorBinding`.
- Intercepts Return key presses for list continuation (see §List Continuation Logic).

**Swift 6 / concurrency boundary.** `UIViewRepresentable` protocol methods run on `@MainActor`. All `Coordinator` delegate callbacks are called by UIKit on the main thread; the `@MainActor` annotation on the coordinator class satisfies Swift 6's isolation requirement. No data crosses an actor boundary inside this bridge — the bindings are `@MainActor`-bound SwiftUI state.

Extends seam: Raw editor (was `TextEditor`, becomes `MarkdownTextViewBridge` + `MarkdownEditorTextView`).

---

### 4. `RawEditorView` — `RawEditorView.swift` (replaced)

`RawEditorView` remains a SwiftUI `View`; its signature from `DocumentView`'s perspective is unchanged. Internally, it replaces the `TextEditor` body with `MarkdownTextViewBridge`.

**Behavioral constraints:**
- The view's external contract with `DocumentView` is identical to the walking-skeleton version: it takes a `MarkdownDocument` binding and integrates with `AutosaveCoordinator`.
- An empty file produces an empty, focusable, layout-stable editing surface with no crash and no placeholder.
- Files at or above the 500 KB threshold open directly in raw mode and are fully editable (existing walking-skeleton guarantee preserved).

`RawEditorView` owns the `pendingScrollAnchor` state slot for this view's instance — it passes it down to `MarkdownTextViewBridge` and clears it after the bridge has consumed it (see §Scroll Anchor Lifecycle).

Replaces seam: Raw editor (walking-skeleton-1 `TextEditor` body, same SwiftUI surface).

---

### 5. `DocumentView` scroll-anchor ownership — `DocumentView.swift` (extended)

`DocumentView` gains two new state values:

- `@State private var pendingRawAnchor: ScrollAnchor?` — set by `RenderedView`'s tap handler before mode switches to `.raw`. Passed to `RawEditorView`, which forwards it to `MarkdownTextViewBridge` and clears it after one use.
- `@State private var pendingRenderedAnchor: ScrollAnchor?` — set by `RawEditorView`'s mode-switch path before mode switches to `.rendered`. Passed to `RenderedView`, which applies it on appear and clears it after one use.

**Behavioral constraints:**
- `DocumentView` never reads the UITextView's internal state directly; it reads a `ScrollAnchor` value produced by `MarkdownTextViewBridge`.
- If a mode switch occurs while both `pendingRawAnchor` and `pendingRenderedAnchor` are non-nil (rapid switching), each transition reads the current-at-the-moment-of-switch anchor and overwrites the pending value. No accumulation of stale anchors is possible.
- On a programmatic mode switch (no tap, no scroll), `DocumentView` sets the pending anchor to `.top` (`fractionalY: 0`), satisfying AC-2.4 / AC-3.3 defaults.

**Tap location to anchor conversion.** When `RenderedView` reports a tap, it provides the tap's y-position within the scroll view's content area. `DocumentView` converts this to a `ScrollAnchor` by dividing `tapContentY / max(1, totalContentHeight)`, clamping to `[0, 1]`. This conversion is a pure arithmetic operation on main-actor state; no UIKit object is retained across the conversion.

Extends seam: Mode switcher (adds anchor state; tap-to-edit and eye-icon paths remain).

---

### 6. `RenderedView` tap reporting — `RenderedView.swift` (extended)

`RenderedView` gains the ability to report the tap's content-area y-position upward before triggering the mode switch.

**Behavioral constraints:**
- The tap gesture callback computes the tap's y-offset within the scroll content (not the viewport) at the moment of the tap and passes it to `DocumentView` via a callback closure before setting `mode = .raw`.
- If the scroll content height is zero (empty document), the reported y-offset is 0 and the anchor defaults to `.top` with no crash.
- `RenderedView` also accepts a `pendingScrollAnchor: ScrollAnchor?` from `DocumentView` for the raw → rendered return path. It applies this anchor on first layout/appear and clears it. See §Scroll Anchor Lifecycle.
- The pre-existing `OpenURLAction` override (link tap → raw mode) uses `fractionalY: 0` as the anchor (no tap location is meaningful for a link activation), satisfying AC-2.4.

`RenderedView` must access the underlying `UIScrollView` to read content offset and content height. This is done via a `UIViewRepresentable` coordinator that wraps `RenderedView`'s scroll view, or — preferably — by reading `GeometryReader`-derived values if MarkdownUI exposes them. If neither is clean, a `UIScrollView` subclass proxy registered via `UIViewRepresentable` is acceptable. The build agent chooses the cleanest available approach; the behavioral contract (fractional y from content area at tap time) is what matters.

Extends seam: Rendered view (adds tap-location reporting and incoming scroll anchor application).

---

### 7. `ListContinuationHandler` — `ListContinuationHandler.swift` (new)

A stateless value type (or a namespace of static functions) that encapsulates the list-continuation decision logic. It is called by `MarkdownTextViewBridge.Coordinator` on Return key press.

**Behavioral constraints:**
- Given the current text and cursor position, the handler determines whether the current line matches a list prefix pattern, and if so, what to insert.
- Unordered prefix patterns recognized: `- `, `* `, `+ ` (prefix followed by exactly one space, at the start of the line, with the cursor at or after the last non-whitespace character on the line).
- Ordered prefix pattern recognized: one or more digit characters followed by `. `, at the start of the line, with the cursor at or after the last non-whitespace character on the line.
- "Empty item exits list" rule: if the entire line content after the prefix is empty (only whitespace or nothing), Return removes the prefix and inserts a plain newline instead of continuing the list.
- "Mid-line" rule: if the cursor is before the last non-whitespace character on the line, Return inserts a plain newline and does not trigger continuation.
- For ordered lists, auto-increment increments the parsed integer by 1. Parsing and incrementing are on plain positive integers only; leading zeros and the `)` delimiter are not handled.
- The handler returns a value indicating either "insert plain newline" or "insert newline + `<prefix>`". It does not mutate the text view directly — the coordinator applies the returned instruction so that all mutations happen in one place.
- The insert is applied via `UITextView.replace(_:withText:)` (or equivalent) as a single replacement, satisfying the atomic-undo requirement (AC-6.6, AC-7.5). The coordinator does not call `insertText` followed by a second `insertText`; it makes one replacement that includes both the newline and the prefix.

**Public interface (named because it is the seam between the keyboard event and the text mutation):**
```swift
enum ListContinuationResult {
    case plainNewline
    case continueList(prefix: String)  // prefix to insert after "\n"
    case exitList(stripPrefix: String) // remove stripPrefix and insert "\n"
}

struct ListContinuationHandler {
    static func result(for text: String, cursorPosition: String.Index) -> ListContinuationResult
}
```

Named explicitly because it is unit-tested in isolation (the handler's decision logic is pure and can be exercised with `Swift Testing` `#expect` without a live `UITextView`).

---

## Scroll Anchor Lifecycle

This section resolves the three key architectural questions raised in the task brief.

### How the tap location travels from RenderedView to RawEditorView

The tap event and the mode switch happen in the same gesture callback, on the main actor. The lifecycle is:

1. User taps `RenderedView`. The tap gesture handler fires on `@MainActor`.
2. `RenderedView` computes `tapContentY` and reports it via its `onTap(contentY:)` closure parameter.
3. `DocumentView.onTap(contentY:)` converts to `ScrollAnchor(fractionalY: tapContentY / max(1, totalContentHeight))` and stores it in `pendingRawAnchor`.
4. `DocumentView` sets `mode = .raw`.
5. SwiftUI replaces `RenderedView` with `RawEditorView` in the same render pass (or the next, before the screen is committed). `RawEditorView` receives `pendingRawAnchor` as a prop.
6. `RawEditorView` passes `pendingRawAnchor` to `MarkdownTextViewBridge` as `pendingScrollAnchor`.
7. See §Deferred apply below.

Steps 3–4 happen within the same synchronous closure on the main actor, so the anchor is always set before the mode flip is visible.

### How the scroll anchor survives the SwiftUI view lifecycle (UITextView not yet laid out)

The `UITextView` cannot receive a `setContentOffset` call until its layout pass has completed — calling it in `makeUIView` or even `updateUIView` may target zero-height content and produce no visible scroll.

**Deferred-apply pattern:**

- `MarkdownTextViewBridge` holds a `pendingScrollAnchor: ScrollAnchor?` input and an `@State private var anchorApplied: Bool` inside the `Coordinator`.
- In `makeUIView`: the text view is created and configured; no scroll is applied yet.
- In `updateUIView`: if `pendingScrollAnchor != nil && !coordinator.anchorApplied`, the bridge schedules the scroll with `DispatchQueue.main.async`. The async hop ensures UIKit has completed layout before the offset is set. After the apply, `coordinator.anchorApplied = true` and the parent is notified to clear `pendingScrollAnchor` (via a `Binding<ScrollAnchor?>` or a callback closure).
- Because `updateUIView` runs synchronously on the main actor, and the async hop runs on the same main queue, no data races are possible; the `anchorApplied` flag is main-actor-isolated.
- The text view scrolls to `contentSize.height * fractionalY`, clamped so the offset does not place the bottom of the visible area past the end of content (satisfying AC-2.3 / EC-2.2 / EC-2.3).
- On an empty document (`contentSize.height == 0` or `bounds.height >= contentSize.height`), the fractional computation produces offset 0 or is skipped; no crash, no NaN (satisfying GF-6).

The same deferred-apply pattern applies in `RenderedView` for the raw → rendered direction, using `ScrollViewReader` or the `UIScrollView` proxy's `setContentOffset` after layout.

### Exposing scroll position to SwiftUI without violating Swift 6 strict concurrency

The `MarkdownEditorTextView` instance lives on the main actor (UIKit's contract). The `Coordinator` class is `@MainActor`. The scroll-position binding in `MarkdownTextViewBridge` is a SwiftUI `Binding<ScrollAnchor>`, which is also main-actor-bound.

The read path: `scrollViewDidEndDecelerating` fires on the main thread → `Coordinator` (main actor) reads `textView.contentOffset` and `textView.contentSize` → computes `fractionalY` as a `Double` → writes `scrollAnchorBinding.wrappedValue = ScrollAnchor(fractionalY:)`.

`ScrollAnchor` is `Sendable` (it is a struct of a `Double` with no reference types). No value crosses an actor boundary — the entire path is main-actor-isolated. This satisfies Swift 6 strict concurrency with no `nonisolated` escape hatches.

---

## Seam Summary

| Seam (from declaration.md Shape) | Walking-skeleton realization | editor-foundation-4 change |
|---|---|---|
| Raw editor | `RawEditorView` with `TextEditor` | **Replaced:** `RawEditorView` now hosts `MarkdownTextViewBridge` + `MarkdownEditorTextView` |
| Mode switcher | `@State mode` in `DocumentView`; no scroll anchor | **Extended:** `DocumentView` gains `pendingRawAnchor` / `pendingRenderedAnchor`; mode-switch path reads and writes anchors |
| Rendered view | `RenderedView` with `ScrollView` + `Markdown`; tap sets `mode = .raw` | **Extended:** tap handler reports content-y before mode switch; view accepts incoming anchor for apply-on-appear |
| Document model | `MarkdownDocument` | No change |
| Document browser entry | `DocumentGroup` | No change |
| File access layer | `ReferenceFileDocument` | No change |
| Conflict & lifecycle UI | `DocumentError` surface | No change |

---

## List Continuation Logic (detailed)

Called from `MarkdownTextViewBridge.Coordinator.textView(_:shouldChangeTextIn:replacementText:)` when `replacementText == "\n"`.

Decision tree:
1. Extract the current line from the full text using the cursor position.
2. Match the line against unordered prefix patterns `^([-*+]) ` and ordered pattern `^(\d+)\. `.
3. If no match → return `ListContinuationResult.plainNewline`.
4. If match:
   a. Compute the content after the prefix on the current line.
   b. If the content is empty or all whitespace → return `.exitList(stripPrefix:)`.
   c. If the cursor position is before the last non-whitespace character → return `.plainNewline`.
   d. Otherwise → return `.continueList(prefix:)` with the appropriate next prefix.
5. For ordered continuation, the next prefix is `"\(parsedInteger + 1). "`.

The coordinator intercepts the newline before it is inserted (returning `false` from `shouldChangeTextIn`) and calls `textView.replace(textView.textRange(from:to:), withText: insertionString)` where `insertionString` is either `"\n"` (plain) or `"\n" + continuationPrefix` — one atomic replacement, satisfying the single-undo requirement.

For `.exitList`: the coordinator replaces the range covering the current line's prefix plus the (empty) content and the cursor's newline with a plain `"\n"`.

---

## File layout changes

New files:
```
Markus_v3/
  Editor/
    MarkdownEditorTextView.swift
    MarkdownTextViewBridge.swift
    ListContinuationHandler.swift
  Models/
    ScrollAnchor.swift
  Views/
    RawEditorView.swift          (rewritten; same path)
    RenderedView.swift           (extended; same path)
    DocumentView.swift           (extended; same path)
```

Test files (new unit tests):
```
Markus_v3Tests/
  ListContinuationHandlerTests.swift
  ScrollAnchorTests.swift
```

The `Editor/` group is new. All other paths retain their walking-skeleton locations.

---

## Build agent must know

- **Deferred scroll apply is mandatory.** Do not attempt to set `contentOffset` in `makeUIView`. Do not attempt to set it in `updateUIView` without the `DispatchQueue.main.async` hop. The hop is safe and correct; it is not a race — it defers until the current run-loop turn (which includes layout) has completed.
- **One replacement, not two inserts, for list continuation.** Using two `insertText` calls will produce two undo steps, violating AC-6.6 and AC-7.5. Always use a single `replace(_:withText:)` or equivalent.
- **Smart-quote suppression is a UITextInputTraits flag, not a delegate method.** Set `smartQuotesType = .no` and `smartDashesType = .no` directly on the `UITextView` subclass in `makeUIView` (or on the subclass itself). Do not attempt to intercept and replace characters after the fact.
- **`UITextViewDelegate` and `UIScrollViewDelegate` are the same object.** `UITextView.delegate` covers both text and scroll events; the `Coordinator` implements both protocols in one class.
- **`ScrollAnchor` must be consumed exactly once.** After `MarkdownTextViewBridge` applies a pending anchor, it clears `pendingScrollAnchor` via its binding/callback. If it does not clear it, `updateUIView` will re-apply the scroll on every subsequent SwiftUI update, fighting the user's scroll position.
- **Rapid mode switching (GF-5).** Each transition computes the anchor fresh from the current scroll state at the moment of the switch. There is no queue of pending anchors; `DocumentView` overwrites `pendingRawAnchor` / `pendingRenderedAnchor` on every transition. Rapid switching cannot accumulate state.
- **All UI work runs on `@MainActor`.** Swift 6 strict concurrency is on. Every class introduced in this feature that touches UIKit (`MarkdownEditorTextView`, `MarkdownTextViewBridge.Coordinator`) is `@MainActor`. `ScrollAnchor` is `Sendable` and carries no actor annotation.
- **No regression in walking-skeleton guarantees.** The `RawEditorView` surface contract with `DocumentView` is unchanged; `AutosaveCoordinator` is triggered from `MarkdownTextViewBridge.Coordinator.textViewDidChange` exactly as `TextEditor`'s `onChange` triggered it before.

---

## Requirements implications

No requirements changes flagged. The requirements are stable and the architecture satisfies all acceptance criteria without contradiction.

One clarification worth noting (not a change): AC-2.5 ("scroll anchor applied before the raw editor is visible") is satisfied by the deferred-apply pattern's timing. The `DispatchQueue.main.async` hop fires within the same run-loop drain that renders the incoming view, so the first committed frame is already scrolled to the target position. If in practice a one-frame flash is observed during implementation (device-dependent layout timing), the correct fix is to hold the view invisible (`.opacity(0)`) until the anchor callback fires and then animate in — this is a permissible implementation refinement, not a requirements change.

---

Architecture stable — no requirements changes flagged
