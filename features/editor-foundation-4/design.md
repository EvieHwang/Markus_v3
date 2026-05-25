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

### 3. `RawEditorScrollState` — `RawEditorScrollState.swift` (new)

A lightweight `@MainActor` observable object that vends the live fractional scroll position of the raw editor to `DocumentView`. *Addresses adversarial F-003.*

**Behavioral constraints:**
- `DocumentView` creates this object as `@StateObject var rawScrollState = RawEditorScrollState()` and owns its lifetime.
- `DocumentView` passes the instance down to `RawEditorView`, which passes it to `MarkdownTextViewBridge`.
- The bridge's `Coordinator` holds a strong reference to `rawScrollState` and writes `rawScrollState.currentFractionalY` from `scrollViewDidScroll` on every scroll event (not just on settle). This ensures the value always reflects the live `contentOffset` at any given moment, including during an active momentum scroll.
- `DocumentView`'s eye-icon action closure reads `rawScrollState.currentFractionalY` synchronously to produce the `ScrollAnchor` for the pending rendered transition. This read is guaranteed to be on the main actor and reflects the live scroll position at the instant the mode switch fires, satisfying AC-3.2.
- Because `RawEditorScrollState` is an `ObservableObject` owned by `DocumentView`, `DocumentView` holds a stable Swift reference to it for the full lifetime of the open document. No UIKit reference escapes out of the `UIViewRepresentable` layer; only the `Double` value is surfaced.

**Public interface (named because it is the reference mechanism between `DocumentView` and the bridge coordinator):**
```swift
@MainActor
final class RawEditorScrollState: ObservableObject {
    var currentFractionalY: Double = 0
}
```

The `@Published` attribute is intentionally omitted on `currentFractionalY` — `DocumentView` reads the value synchronously at mode-switch time; it does not need SwiftUI to re-render on every scroll tick. Writing the value from `scrollViewDidScroll` without triggering a re-render keeps the scroll path free of unnecessary SwiftUI invalidation.

---

### 4. `MarkdownTextViewBridge` — `MarkdownTextViewBridge.swift` (new)

A `UIViewRepresentable` that bridges `MarkdownEditorTextView` into SwiftUI.

**Behavioral constraints:**
- Text edits flow out through a binding to `document.text`. Every character-level change updates the binding value, which triggers `document.markDirty()` and the autosave debounce in `AutosaveCoordinator` — identical to the pre-migration `TextEditor` behavior.
- The bridge renders a monospaced body font, matching the pre-migration appearance.
- Scroll position flows out to `DocumentView` through `RawEditorScrollState` (see §3 above). The bridge's `Coordinator` writes `rawScrollState.currentFractionalY` from `scrollViewDidScroll` on every scroll event, keeping the value current at all times including during momentum scrolls. `DocumentView` reads `rawScrollState.currentFractionalY` synchronously inside the eye-icon action closure before setting `mode = .rendered`. This satisfies AC-3.2 without `DocumentView` holding any UIKit reference. *Addresses adversarial F-001 and F-003.*
- An incoming `pendingScrollAnchor: ScrollAnchor?` (optional) is consumed exactly once after the `UITextView` is laid out. See §Scroll Anchor Lifecycle.
- The bridge does not expose its `UITextView` instance directly to SwiftUI callers; all behavioral surface passes through the text binding, the pending anchor, and `RawEditorScrollState`.

**Coordinator responsibilities:**
- Implements `UITextViewDelegate`.
- On `textViewDidChange`: writes the updated text to the binding; calls `markDirty()` and notifies `AutosaveCoordinator`.
- On `scrollViewDidScroll`: computes `contentOffset.y / max(1, contentSize.height - bounds.height)` and writes the result to `rawScrollState.currentFractionalY`. This fires on every scroll frame (including during momentum), not just on settle — ensuring the value is always live.
- Intercepts Return key presses for list continuation (see §List Continuation Logic).

**Swift 6 / concurrency boundary.** `UIViewRepresentable` protocol methods run on `@MainActor`. All `Coordinator` delegate callbacks are called by UIKit on the main thread; the `@MainActor` annotation on the coordinator class satisfies Swift 6's isolation requirement. No data crosses an actor boundary inside this bridge — the bindings are `@MainActor`-bound SwiftUI state.

Extends seam: Raw editor (was `TextEditor`, becomes `MarkdownTextViewBridge` + `MarkdownEditorTextView`).

---

### 5. `RawEditorView` — `RawEditorView.swift` (replaced)

`RawEditorView` remains a SwiftUI `View`; its signature from `DocumentView`'s perspective is unchanged. Internally, it replaces the `TextEditor` body with `MarkdownTextViewBridge`.

**Behavioral constraints:**
- The view's external contract with `DocumentView` is identical to the walking-skeleton version: it takes a `MarkdownDocument` binding and integrates with `AutosaveCoordinator`.
- An empty file produces an empty, focusable, layout-stable editing surface with no crash and no placeholder.
- Files at or above the 500 KB threshold open directly in raw mode and are fully editable (existing walking-skeleton guarantee preserved).

`RawEditorView` owns the `pendingScrollAnchor` state slot for this view's instance — it passes it down to `MarkdownTextViewBridge` and clears it after the bridge has consumed it (see §Scroll Anchor Lifecycle). `RawEditorView` also receives the `RawEditorScrollState` instance from `DocumentView` and forwards it to `MarkdownTextViewBridge`, so the coordinator can write live scroll updates without any UIKit reference escaping upward.

Replaces seam: Raw editor (walking-skeleton-1 `TextEditor` body, same SwiftUI surface).

---

### 6. `DocumentView` scroll-anchor ownership — `DocumentView.swift` (extended)

`DocumentView` gains three new state values:

- `@StateObject private var rawScrollState = RawEditorScrollState()` — the shared scroll-state object whose `currentFractionalY` is continuously updated by the bridge coordinator via `scrollViewDidScroll`. `DocumentView` reads this synchronously inside the eye-icon action closure. *Addresses adversarial F-003.*
- `@State private var pendingRawAnchor: ScrollAnchor?` — set by `RenderedView`'s tap handler before mode switches to `.raw`. Passed to `RawEditorView`, which forwards it to `MarkdownTextViewBridge` and clears it after one use.
- `@State private var pendingRenderedAnchor: ScrollAnchor?` — set by the eye-icon action closure before mode switches to `.rendered`. Passed to `RenderedView`, which applies it on appear and clears it after one use.

**Behavioral constraints:**
- `DocumentView` never reads the UITextView's internal state directly; it reads `rawScrollState.currentFractionalY` (a `Double` updated on the main actor by the bridge coordinator) and wraps it in a `ScrollAnchor`.
- **Raw → rendered mode switch:** When the user taps the eye-icon toolbar button, `DocumentView` reads `rawScrollState.currentFractionalY` synchronously inside the action closure before setting `mode = .rendered`. Because the coordinator writes this value from `scrollViewDidScroll` on every scroll frame, the value always reflects the live `contentOffset` at the exact moment the mode switch fires — regardless of whether a momentum scroll is still in progress. *Addresses adversarial F-001 and F-003.*
- If a mode switch occurs while both `pendingRawAnchor` and `pendingRenderedAnchor` are non-nil (rapid switching), each transition reads the current-at-the-moment-of-switch anchor and overwrites the pending value. No accumulation of stale anchors is possible.
- On a programmatic mode switch (no tap, no scroll), `DocumentView` sets the pending anchor to `.top` (`fractionalY: 0`), satisfying AC-2.4 / AC-3.3 defaults.

**Tap location to anchor conversion.** When `RenderedView` reports a tap, it provides the tap's y-position within the scroll view's content area. `DocumentView` converts this to a `ScrollAnchor` by dividing `tapContentY / max(1, totalContentHeight)`, clamping to `[0, 1]`. This conversion is a pure arithmetic operation on main-actor state; no UIKit object is retained across the conversion.

Extends seam: Mode switcher (adds anchor state; tap-to-edit and eye-icon paths remain).

---

### 7. `RenderedView` tap reporting — `RenderedView.swift` (extended)

`RenderedView` gains the ability to report the tap's content-area y-position upward before triggering the mode switch.

**Behavioral constraints:**
- The tap gesture callback computes the tap's y-offset within the scroll content (not the viewport) at the moment of the tap and passes it to `DocumentView` via a callback closure before setting `mode = .raw`.
- If the scroll content height is zero (empty document), the reported y-offset is 0 and the anchor defaults to `.top` with no crash.
- `RenderedView` also accepts a `pendingScrollAnchor: ScrollAnchor?` from `DocumentView` for the raw → rendered return path. It applies this anchor on first layout/appear and clears it. See §Scroll Anchor Lifecycle.
- The pre-existing `OpenURLAction` override (link tap → raw mode) uses `fractionalY: 0` as the anchor (no tap location is meaningful for a link activation), satisfying AC-2.4.

`RenderedView` must access the underlying `UIScrollView` to both read the tap's content-area y-position and to apply an incoming fractional anchor. `ScrollViewReader` cannot satisfy either need — it only scrolls to named view IDs and has no API for fractional offsets. The required approach is a `UIScrollView` proxy: a `UIViewRepresentable` that locates the `UIScrollView` driving the `RenderedView` scroll container and exposes `contentOffset`, `contentSize`, and `setContentOffset(_:animated:)` directly. The behavioral contract is: (1) the fractional y reported on tap is `tapContentY / max(1, totalContentHeight)` from the live `UIScrollView` state at tap time; (2) the anchor is applied by setting `scrollView.contentOffset.y = fractionalY × max(0, contentSize.height - bounds.height)`, clamped to `[0, contentSize.height - bounds.height]`, after layout is complete and before the first visible frame (opacity-0 reveal in force). *Addresses prescription feedback §6 ScrollViewReader.*

Extends seam: Rendered view (adds tap-location reporting and incoming scroll anchor application).

---

### 8. `ListContinuationHandler` — `ListContinuationHandler.swift` (new)

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

### How the raw → rendered mode switch reads a live scroll position

When the eye-icon is tapped, the action closure fires synchronously on the main actor. The correct position is the raw editor's live `contentOffset` at that instant — not a cached settled-scroll value. The mechanism that delivers this live value to `DocumentView` is `RawEditorScrollState` (§3). *Addresses adversarial F-001 and F-003.*

The lifecycle is:

1. **Continuous background write.** While the raw editor is displayed, `MarkdownTextViewBridge.Coordinator` writes `rawScrollState.currentFractionalY` from `scrollViewDidScroll` on every scroll frame — including during momentum scrolls. At any instant, `rawScrollState.currentFractionalY` reflects the true live `contentOffset.y / max(1, contentSize.height - bounds.height)`.
2. User taps the eye-icon toolbar button. The action closure fires on `@MainActor`.
3. `DocumentView` reads `rawScrollState.currentFractionalY` synchronously inside the action closure. Because step 1 fires on every scroll frame (not just on settle), this read always reflects the live scroll position at the exact moment the tap fires — satisfying AC-3.2 even when a momentum scroll is still in progress.
4. `DocumentView` stores `ScrollAnchor(fractionalY: rawScrollState.currentFractionalY)` in `pendingRenderedAnchor`.
5. `DocumentView` sets `mode = .rendered`.
6. SwiftUI replaces `RawEditorView` with `RenderedView`. `RenderedView` receives `pendingRenderedAnchor` as a prop.
7. See §Deferred apply below.

`DocumentView` holds `rawScrollState` as `@StateObject` — a stable Swift reference for the document's lifetime. No UIKit object escapes the `UIViewRepresentable` layer; only the `Double` value is surfaced. This is the concrete reference mechanism specified to close the implementation gap identified in F-003: `DocumentView` cannot hold a reference to a `UIViewRepresentable` value type, but it can hold a reference to the `ObservableObject` that the bridge's coordinator writes into. *Addresses adversarial F-003.*

### How the scroll anchor survives the SwiftUI view lifecycle (UITextView not yet laid out)

The `UITextView` cannot receive a `setContentOffset` call until its layout pass has completed — calling it before `contentSize` is finalized may target zero-height content and produce no visible scroll.

**Deferred-apply pattern (behavioral constraint, not API prescription):**

The behavioral requirement is: **the scroll offset must be applied before the first frame the user sees**. How the build agent achieves this is an implementation choice; the constraint is the outcome. Viable approaches include a post-layout callback via `DispatchQueue.main.async`, a `GeometryReader`-triggered apply, or calling `layoutIfNeeded()` before setting `contentOffset`. The build agent selects the most reliable option for the iOS version targeted; if a single async hop proves insufficient (e.g., `contentSize` is not yet final), the agent adds `layoutIfNeeded()` before the offset set or uses a geometry-change trigger.

The pattern structure, regardless of mechanism:

- `MarkdownTextViewBridge` holds a `pendingScrollAnchor: ScrollAnchor?` input and an `anchorApplied` flag inside the `Coordinator`.
- In `makeUIView`: the text view is created and configured; no scroll is applied yet.
- In `updateUIView`: if `pendingScrollAnchor != nil && !coordinator.anchorApplied`, the bridge defers the scroll apply until after UIKit has completed layout for this update cycle.
- After the apply, `coordinator.anchorApplied = true` and the parent is notified to clear `pendingScrollAnchor` (via a `Binding<ScrollAnchor?>` or a callback closure).
- The `anchorApplied` flag is main-actor-isolated (all UIKit work runs on `@MainActor`); no data races are possible.
- The text view scrolls to `contentSize.height * fractionalY`, clamped so the offset does not place the bottom of the visible area past the end of content (satisfying AC-2.3 / EC-2.2 / EC-2.3).
- On an empty document (`contentSize.height == 0` or `bounds.height >= contentSize.height`), the fractional computation produces offset 0 or is skipped; no crash, no NaN (satisfying GF-6).

**Opacity-0 reveal (unconditional, required by AC-2.5 and AC-3.4):**

Whenever a non-nil pending anchor is present, the incoming view (`RawEditorView` or `RenderedView`) must start with `opacity 0` and become visible only after the anchor has been applied and the first correctly-positioned frame is ready. A cross-fade reveal (short animation to `opacity 1`) is acceptable; an abrupt top-to-target jump is not. This is unconditional — it applies on all hardware, not only when a flash is observed in testing. The build agent must not skip this pattern because the simulator renders faster than a physical device. This directly satisfies AC-2.5 and AC-3.4 as a design-level constraint, not a conditional implementation note.

The deferred-apply pattern applies in `RenderedView` for the raw → rendered direction, using the `UIScrollView` proxy's `setContentOffset` after layout (see §7 below). `ScrollViewReader` is not used for this purpose — it only scrolls to named view IDs and cannot apply an arbitrary fractional content offset.

### Exposing scroll position to SwiftUI without violating Swift 6 strict concurrency

The `MarkdownEditorTextView` instance lives on the main actor (UIKit's contract). The `Coordinator` class is `@MainActor`. `RawEditorScrollState` is a `@MainActor final class` — it is entirely main-actor-isolated.

The write path: `scrollViewDidScroll` fires on the main thread → `Coordinator` (`@MainActor`) reads `textView.contentOffset` and `textView.contentSize` → computes `fractionalY` as a `Double` → writes `rawScrollState.currentFractionalY`. No `@Published` annotation is placed on `currentFractionalY`; this avoids triggering a SwiftUI re-render on every scroll tick while still keeping the value current for the synchronous read in step 3 of the mode-switch lifecycle.

The read path: `DocumentView`'s eye-icon action closure runs on `@MainActor` → reads `rawScrollState.currentFractionalY` (a plain `Double` property on a `@MainActor` object) → wraps it in `ScrollAnchor(fractionalY:)`.

`ScrollAnchor` is `Sendable` (it is a struct of a `Double` with no reference types). No value crosses an actor boundary — the entire path is main-actor-isolated. This satisfies Swift 6 strict concurrency with no `nonisolated` escape hatches. *Addresses adversarial F-003.*

---

## Seam Summary

| Seam (from declaration.md Shape) | Walking-skeleton realization | editor-foundation-4 change |
|---|---|---|
| Raw editor | `RawEditorView` with `TextEditor` | **Replaced:** `RawEditorView` now hosts `MarkdownTextViewBridge` + `MarkdownEditorTextView` |
| Mode switcher | `@State mode` in `DocumentView`; no scroll anchor | **Extended:** `DocumentView` gains `pendingRawAnchor` / `pendingRenderedAnchor` and `@StateObject rawScrollState: RawEditorScrollState`; mode-switch path reads `rawScrollState.currentFractionalY` live at switch time |
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
    RawEditorScrollState.swift
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

- **Deferred scroll apply is mandatory.** Do not attempt to set `contentOffset` in `makeUIView`. Do not apply it in `updateUIView` before `contentSize` is finalized. The behavioral requirement is that the offset is applied after UIKit has completed layout for the current update cycle and before the first frame the user sees. A `DispatchQueue.main.async` hop is the common approach; if `contentSize` is not yet final after the hop (device-dependent), call `layoutIfNeeded()` before setting `contentOffset`, or use a geometry-change trigger. The mechanism is an implementation choice; the outcome (offset applied before the first visible frame) is the requirement. *Addresses prescription feedback §Scroll Anchor Lifecycle.*
- **One replacement, not two inserts, for list continuation.** Using two `insertText` calls will produce two undo steps, violating AC-6.6 and AC-7.5. Always use a single `replace(_:withText:)` or equivalent.
- **Smart-quote suppression is a UITextInputTraits flag, not a delegate method.** Set `smartQuotesType = .no` and `smartDashesType = .no` directly on the `UITextView` subclass in `makeUIView` (or on the subclass itself). Do not attempt to intercept and replace characters after the fact.
- **`UITextViewDelegate` and `UIScrollViewDelegate` are the same object.** `UITextView.delegate` covers both text and scroll events; the `Coordinator` implements both protocols in one class.
- **Opacity-0 reveal is unconditional, not optional.** Whenever a non-nil pending anchor is present, the incoming view starts with `opacity 0` and reveals itself only after the anchor is applied. Do not skip this because the simulator shows no flash — physical devices render differently. This pattern is required by AC-2.5 and AC-3.4 and must not be left as a conditional refinement.
- **`ScrollAnchor` must be consumed exactly once.** After `MarkdownTextViewBridge` applies a pending anchor, it clears `pendingScrollAnchor` via its binding/callback. If it does not clear it, `updateUIView` will re-apply the scroll on every subsequent SwiftUI update, fighting the user's scroll position.
- **Rapid mode switching (GF-5).** Each transition computes the anchor fresh from the current scroll state at the moment of the switch. There is no queue of pending anchors; `DocumentView` overwrites `pendingRawAnchor` / `pendingRenderedAnchor` on every transition. Rapid switching cannot accumulate state.
- **`RawEditorScrollState` is the reference mechanism for live scroll reads.** `DocumentView` holds it as `@StateObject`; `MarkdownTextViewBridge` receives it as a parameter and passes it to `Coordinator`. `Coordinator` writes `rawScrollState.currentFractionalY` from `scrollViewDidScroll` — not from the settle callbacks. `DocumentView` reads it synchronously inside the eye-icon action closure. Never attempt to expose `currentFractionalY` as a property directly on the `UIViewRepresentable` struct — value types cannot be referenced from outside the SwiftUI render tree. *Addresses adversarial F-003.*
- **All UI work runs on `@MainActor`.** Swift 6 strict concurrency is on. Every class introduced in this feature that touches UIKit (`MarkdownEditorTextView`, `MarkdownTextViewBridge.Coordinator`, `RawEditorScrollState`) is `@MainActor`. `ScrollAnchor` is `Sendable` and carries no actor annotation.
- **No regression in walking-skeleton guarantees.** The `RawEditorView` surface contract with `DocumentView` is unchanged; `AutosaveCoordinator` is triggered from `MarkdownTextViewBridge.Coordinator.textViewDidChange` exactly as `TextEditor`'s `onChange` triggered it before.

---

## Requirements implications

No requirements changes flagged. The requirements are stable and the architecture satisfies all acceptance criteria without contradiction.

AC-2.5 and AC-3.4 mandate the opacity-0-until-anchor-applied behavior unconditionally — this is a design-level requirement, not an optional implementation refinement. The architecture enforces it as a structural constraint: both `RawEditorView` and `RenderedView` start with `opacity 0` whenever they are presented with a non-nil pending anchor, and reveal themselves (opacity 1, optionally with a short cross-fade) only after the anchor has been applied and cleared. This is not conditional on observing a flash during simulator testing; physical devices render differently and the pattern must be in place from the first implementation. *Addresses prescription feedback §Scroll Anchor Lifecycle (behavioral constraint, not API prescription); also directly satisfies AC-2.5 and AC-3.4.*

The `RawEditorScrollState` mechanism (§3) gives `DocumentView` a stable, main-actor-isolated reference from which to read the live fractional position at mode-switch time. This closes the implementation gap identified in F-003 without any requirement change — AC-3.2 already required the live value; the architecture now specifies unambiguously how that value is delivered. *Addresses adversarial F-003.*

---

Architecture stable — no requirements changes flagged
