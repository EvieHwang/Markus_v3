# Adversarial Review: accessibility-8

**Mode:** fresh review
**requirements.md SHA:** bff4f7e87e3eb63e56dc64530eb34ffe8866a86f
**design.md SHA:** 1fdc0943e99f928ebfc8418981504ba4b87afd02

---

## Summary

Five findings surfaced. Two are HIGH (a real runtime race condition that would cause spurious VoiceOver announcements on every cold launch into raw mode, and a silent failure mode where heading traits may not propagate through MarkdownUI's view hierarchy). One MEDIUM concerns an unaddressed VoiceOver focus-restoration behavior declared required in the spec but given no implementation mechanism. Two LOW findings address a missing acceptance criterion and a borderline label. Zero security findings. No scope drift.

---

## Findings

### F-001

**Severity:** HIGH
**Lens:** Failure modes
**Finding:** The design's guard for suppressing the on-launch announcement (BC-5.3 / AC-5.5) relies on SwiftUI batching two sequential `@State` mutations in `onAppear` (`mode = resolved` then `didInitMode = true`) such that `.onChange(of: mode)` fires only after both are committed. The design acknowledges this ordering dependency ("to be certain the guard works, the ordering in `onAppear` must be preserved") but treats it as safe because "SwiftUI batches `@State` mutations." SwiftUI does coalesce state writes within a synchronous execution context, but `.onChange` observers are dispatched after the render cycle, not inline. If the SwiftUI runtime flushes the `mode` write and schedules the `.onChange` callback before processing `didInitMode = true` — which can occur when `mode` changes from its initial `.rendered` default to `.raw` during `onAppear`, because the change triggers a render cycle before the same block's second write is committed — the guard reads `false` and an unwanted "Editing mode" announcement fires on every cold launch for files that open in raw mode (empty files, large files). The declaration states that VoiceOver announcements fire on mode switches; an announcement on initial load is an incorrect user experience that the spec explicitly prohibits (AC-5.5, EC-5.4). No test currently covers this scenario (an empty-file cold launch with VoiceOver enabled), so the regression would be silent.
**Recommended action:** `architecture` — replace the `didInitMode` flag pattern with a direct guard: set `didInitMode = true` before writing `mode`, or post the announcement inside the triggering paths (`switchTo`, `switchToRawFromSwipe`, toolbar handler) rather than in a generic `.onChange` observer. The per-path approach avoids any timing dependency on SwiftUI's state-batching semantics.
**Status:** open

---

### F-002

**Severity:** HIGH
**Lens:** Coverage
**Finding:** BC-2.1 and AC-2.1 require that each heading view's accessibility traits include `.isHeader` so VoiceOver's heading rotor can navigate them. The design prescribes calling `.accessibilityAddTraits(.isHeader)` on `configuration.label` in each MarkdownUI heading builder. However, MarkdownUI's heading builder `configuration.label` is a `MarkdownContentView` — an opaque SwiftUI view that MarkdownUI renders as a layout container. SwiftUI accessibility modifiers applied to a container view are not guaranteed to propagate down to the leaf text elements that VoiceOver encounters as individual accessibility elements; if MarkdownUI marks the container as an `accessibilityElement(children: .contain)` group internally, the `.isHeader` trait lands on the container rather than on the `Text` node the rotor indexes. There is no acceptance criterion that verifies the trait is present on the element VoiceOver actually focuses (rather than a parent). AC-2.2 requires "swiping down with the rotor set to Headings moves focus sequentially," but a test that merely checks `accessibilityTraits.contains(.isHeader)` on the view returned by the builder would pass even if the trait is on the wrong node. The behavioral requirement (heading rotor works) is declared but there is no acceptance criterion that catches a MarkdownUI-internal trait propagation failure.
**Recommended action:** `requirements` — add an acceptance criterion that can only be satisfied if VoiceOver's heading rotor actually finds and navigates the elements (an XCUITest asserting `XCUIElementQuery` for heading elements returns expected count and order), not just that the modifier was applied. Also note in the design that if the trait does not propagate, the fallback is to wrap `configuration.label` in a `.accessibilityElement(children: .combine)` container with the trait, accepting that MarkdownUI's sub-element navigation is collapsed.
**Status:** open

---

### F-003

**Severity:** MEDIUM
**Lens:** Coverage
**Finding:** EC-4.2 declares a required behavior: "VoiceOver focus returns to the document without a crash or stuck-focus state" after the deletion banner is dismissed programmatically while VoiceOver focus is on the banner. Neither the requirements nor the design provide any mechanism to achieve this. The design for Component 4 adds only `.accessibilityLabel` and `.accessibilityHint` modifiers to existing buttons; it makes no provision for posting a `UIAccessibility.post(notification: .layoutChanged, ...)` or `.screenChanged` notification after banner dismissal to move VoiceOver focus back to the document. Without such a notification, VoiceOver focus is unspecified after the banner's view is removed from the hierarchy — iOS will move focus somewhere, but not necessarily to the document. The behavior is declared in the requirements (EC-4.2) but neither the requirements' acceptance criteria nor the design give it a home.
**Recommended action:** `architecture` — add an explicit step in Component 4's change description: after `detector.dismissDeletionBanner()` removes the banner from the view hierarchy, post `UIAccessibility.post(notification: .layoutChanged, argument: nil)` (or `.screenChanged` with the document view as argument) so VoiceOver focus returns to a defined location. Alternatively, promote EC-4.2 to an acceptance criterion with a testable condition, forcing the design to address it.
**Status:** open

---

### F-004

**Severity:** LOW
**Lens:** Standards compliance
**Finding:** AC-4.6 requires a `.accessibilityLabel` on the "Dismiss" deletion-banner button that "communicates dismissing the file-deleted notice." The design sets `.accessibilityLabel("Dismiss")` — the string "Dismiss" alone. WCAG 2.4.6 (Headings and Labels, AA) states that labels should be descriptive. "Dismiss" without context does not identify what is being dismissed; a VoiceOver user hearing only "Dismiss, button" cannot distinguish this from the alert's "Dismiss" button (AC-4.6 accepts "Dismiss" as a valid example, but the deletion banner and the save-failed alert both expose a "Dismiss" label). WCAG 4.1.2 (Name, Role, Value) is technically satisfied by any non-empty name, but 2.4.6 expects the label to be descriptive enough to identify the control's purpose. The requirements example ("Dismiss") and the design value ("Dismiss") are consistent with each other but both leave the WCAG 2.4.6 criterion marginally met. The constitution cites WCAG 2.1 AA, which includes 2.4.6.
**Recommended action:** `requirements` — update AC-4.6 to require a label that identifies what is being dismissed (e.g., "Dismiss deleted-file notice") and update the design string accordingly.
**Status:** open

---

### F-005

**Severity:** LOW
**Lens:** Integrity
**Finding:** AC-3.1 specifies the post-resize font size as "`UIFont.preferredFont(forTextStyle: .body).pointSize - 2` at the new category." BC-3.1 in the design matches this exactly. However, neither document addresses the edge case where `UIFont.preferredFont(forTextStyle: .body).pointSize - 2` is zero or negative — which cannot occur at any current Apple-supported Dynamic Type category (the smallest body size is 14pt, yielding 12pt), but the formula is expressed as an open subtraction with no floor. AC-3.1 relies on the formula string rather than specifying a minimum rendered size. If a future Dynamic Type category or a third-party Dynamic Type override produces a body size ≤ 2pt, the raw editor would render with a zero or negative font size, which UIKit handles by substituting the system default but which could appear as a silent visual regression. The constitution standard (WCAG 1.4.4) requires text to scale to 200% without loss of functionality; a floor of 1pt or an explicit guard would make this requirement unconditionally safe.
**Recommended action:** `requirements` — add a constraint to AC-3.1 (or a new AC-3.6) specifying that the computed font size has a floor of 1pt, consistent with UIKit's own font-size minimum.
**Status:** open

---

## Prescription feedback

The following items concern *how* the design implements things rather than *what* the feature requires. They are not findings; they are flagged for the implementer's awareness.

**Design §Component 3 (MarkdownEditorTextView):** Setting `self.font` on a `UITextView` causes UIKit to reset `typingAttributes` to a dictionary derived from the new font. The subsequent `self.typingAttributes[.font] = monoFont` line in `configureAppearance()` is therefore redundant (the font key is already set by the `font` setter). No behavioral regression results, but the design prescribes both writes as if the second is a necessary guard. *Implementation prescription, not behavioral constraint.*

**Design §Component 1, BC-1.4:** States "`UIApplication.shared.open` handles http/https, mailto, and custom-scheme URLs." SwiftUI's `openURL` environment action does not call `UIApplication.shared.open` directly — it goes through the SwiftUI environment delegation chain before reaching the UIKit layer. The claim is factually imprecise as a description of SwiftUI's mechanism, though the behavioral outcome (OS handles the URL) is correct. *Implementation prescription, not behavioral constraint.*

**Design §Component 5, `.onChange(of: mode)` ordering note:** The design instructs placing the new `.onChange` modifier "after the existing `.onChange(of: scenePhase)` modifier." Modifier ordering in SwiftUI affects rendering aesthetics but not the functional behavior of unrelated `.onChange` observers. This is a style guideline, not a behavioral constraint. *Implementation prescription, not behavioral constraint.*
