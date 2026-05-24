# Adversarial Review: editor-foundation-4

Review SHA — requirements.md: 164a6c6ba0c088bdb3933fb54a341d3dbc61b649 design.md: 80315aa4dfbd4e3edcd08054729b48c87939cccc
Mode: fresh review

---

## Findings

### F-001 — Stale scroll anchor when mode switch fires during momentum scroll
**Severity:** MEDIUM
**Lens:** Integrity / Failure modes
**Finding:** AC-3.2 requires the fractional position to be read "at the moment the mode switch is triggered." The design (§3 `MarkdownTextViewBridge`) writes the `scrollAnchorBinding` only on `scrollViewDidEndDecelerating` and `scrollViewDidEndDragging(_:willDecelerate:)` (i.e., after scroll movement settles). If the user initiates a momentum scroll in the raw editor and then immediately taps the eye-icon toolbar button before deceleration completes, `DocumentView`'s `pendingRenderedAnchor` is populated from the binding's last-settled value — not the live `contentOffset` at tap time. The resulting rendered view opens at a position that may differ substantially from where the user was actually reading. This violates AC-3.2 directly and is reproducible on any long document with a fast fling-and-tap interaction.
**Recommended action (architecture):** Remove reliance on the binding's cached value for the mode-switch path. Instead, have `RawEditorView` (or `MarkdownTextViewBridge`) expose a synchronous read of the current fractional position that `DocumentView` calls at the moment it triggers the mode switch, before setting `mode = .rendered`. The binding can still be used for other purposes (e.g., keeping `DocumentView` loosely in sync), but the anchor used for the pending transition must be read live. A simple `var currentFractionalY: Double { get }` on `MarkdownTextViewBridge` or `RawEditorView`, read inside the eye-icon action closure before the mode flip, satisfies AC-3.2 without structural change.
**Status:** open

---

### F-002 — AC-2.5 / AC-3.4 not definitively satisfied by design
**Severity:** MEDIUM
**Lens:** Coverage / Standards compliance (Apple HIG)
**Finding:** AC-2.5 states "the scroll anchor is applied before the raw editor is visible to the user — there is no visible jump from the top to the target position after the view appears." AC-3.4 states the identical requirement for the rendered direction. The design (§Scroll Anchor Lifecycle, §Requirements implications) uses `DispatchQueue.main.async` to defer the `setContentOffset` call and explicitly acknowledges that "if in practice a one-frame flash is observed during implementation (device-dependent layout timing), the correct fix is to hold the view invisible (`.opacity(0)`) until the anchor callback fires." The design marks this fix as "a permissible implementation refinement, not a requirements change" and leaves the decision to the build agent.

This leaves the behavioral requirement unsatisfied at the design level: a build agent who does not observe the flash on the simulator (common — simulators render faster than devices) will ship code that violates AC-2.5 / AC-3.4 on physical hardware. Apple HIG requires transitions to be smooth and predictable; a top-to-target jump on every mode switch on device is a first-class UX regression.
**Recommended action (architecture):** The design should prescribe the `.opacity(0)` / reveal-after-apply pattern unconditionally, not conditionally. Concretely: both `RawEditorView` and `RenderedView` should start with `opacity 0` whenever they are presented with a non-nil pending anchor, reveal themselves (opacity 1, optionally with a short cross-fade) only after the anchor has been applied and cleared. This is deterministic and device-independent. The `DispatchQueue.main.async` approach alone is insufficient to guarantee the requirement on all hardware.
**Status:** addressed — AC-2.5 and AC-3.4 in requirements.md now explicitly mandate the opacity-0-until-anchor-applied behavior unconditionally. Design must prescribe this pattern, not leave it conditional.

---

## Prescription feedback

### §Scroll Anchor Lifecycle — deferred apply via `DispatchQueue.main.async`
Implementation prescription, not behavioral constraint. The design mandates `DispatchQueue.main.async` as the mechanism. On devices with different layout timing (or under future SwiftUI scheduler changes), this single-hop may not guarantee that `contentSize` is finalized when the offset is applied. The design section "Build agent must know" reinforces this as the correct approach, but the behavior of `contentSize` being ready after one async hop is an iOS-version-dependent implementation detail. If the build agent encounters layout issues, `layoutIfNeeded()` before the offset set, or a `GeometryReader`-based trigger, may be more reliable. This does not affect the behavioral requirement (no visible jump) — that is captured by F-002. Noted here so the agent is not surprised if the single-hop is insufficient on a specific iOS version. (Design §Scroll Anchor Lifecycle, §Build agent must know)

### §6 `RenderedView` — `ScrollViewReader` option for fractional anchor application
Implementation prescription, not behavioral constraint. The design says `RenderedView` applies the incoming scroll anchor "using `ScrollViewReader` or the `UIScrollView` proxy's `setContentOffset` after layout." `ScrollViewReader.scrollTo(_:anchor:)` requires a named view ID and an `UnitPoint` anchor — it cannot apply an arbitrary fractional content offset. For fractional positioning, the UIScrollView proxy path is the only viable option. The `ScrollViewReader` mention is misleading and should be removed to prevent the build agent from attempting a path that cannot satisfy the behavioral requirement. The UIScrollView proxy approach is correct. (Design §6 `RenderedView` tap reporting)
