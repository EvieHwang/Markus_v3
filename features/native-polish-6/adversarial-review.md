# Adversarial Review — native-polish-6

**Mode:** verification pass — all four prior findings were marked `addressed`; this pass verifies each fix and attacks each with the original lens
**requirements.md SHA:** 113dafba195cd0882b0068f09d73c22b8d35d355
**design.md SHA:** 113dafba195cd0882b0068f09d73c22b8d35d355

---

## Summary

Four open findings. Two are medium severity; two are low. One finding that the design itself flags as uncertain (C7 / NP-10 API) escalates to a medium because the requirements do not reflect the uncertainty. One prescription-feedback item is recorded for the ShareLink implementation choice.

---

## Findings

### F-001 — Indented-code-block heuristic in MarkdownLineBreakNormalizer will mis-classify list-continuation lines, breaking NP-3.3

**Severity:** MEDIUM
**Lens:** Integrity / Failure modes

**Finding:**

NP-3.3 requires that single-newline-as-line-break behavior applies "everywhere in the rendered view that body text is rendered (paragraphs, list items, blockquotes)." The design (C2) states the normalizer recognizes indented code blocks as "4-space / 1-tab indent on every line of the block" and skips normalization inside them. In CommonMark (which `swift-cmark` implements), a 4-space-indented line is an indented code block only at the document's base block level — not inside a list. Inside a list item, continuation paragraphs are identified by indentation relative to the list marker, and 4-space-indented text is *list body*, not a code block. A "lightweight pass" that classifies any 4-space-indented line as a code block will treat indented list-body lines as code-region content and skip the trailing-space injection for them. The result: single newlines inside list items will render as soft breaks (spaces) rather than the hard line breaks NP-3.3 requires, whenever the list uses 4-space indentation for continuation text.

This is a concrete, reproducible failure mode against a stated requirement. The normalizer's block-structure pass must be context-sensitive: indented code blocks are only valid outside list context (CommonMark spec §4.4). Inside a list, 4-space indentation signals continuation, not code.

**Recommended action (architecture):** Strengthen C2's description of the normalizer's block-structure pass to require that indented-code-block detection is context-sensitive — it must track whether the current line is inside a list item (by noting whether a preceding line opened a list marker) and suppress indented-code-block classification within that context. Alternatively, the normalizer can use only fenced code block detection (``` ``` ``` delimiters) and avoid indented-code-block detection entirely, noting that indented code blocks are rare in prose markdown and that the app's target user (prose writer, not coder) is unlikely to author them. Either resolution must be stated explicitly in C2 before building.

**Status:** addressed — C2 revised in design.md to use fenced-code-block detection only (` ``` ` / `~~~` delimiters); indented-code-block exemption dropped entirely. NPC-4 updated accordingly. Single newlines inside list continuation lines are now normalized as required by NP-3.3.

**Verification:** Fix confirmed. C2's algorithm in design.md now explicitly excludes indented-code-block detection and restricts the "code region" exemption to fenced blocks only. NPC-4 in the behavioral constraints list reflects this. The list-continuation failure mode is resolved.

**Adjacent gap found → F-005.** NPC-5 asserts that inline code span content is "passed through unchanged," but the normalizer algorithm (steps 1–3 in C2) operates at block level only — it has no inline code span awareness. A newline inside an inline code span (`` `foo\nbar` ``) falls outside any fenced-code-block region and would receive the trailing-space injection by step 3, violating NPC-5. The behavioral constraint is stated but the algorithm does not mechanistically achieve it. See F-005 below.

---

### F-002 — NP-10 Recents registration: requirements assert a behavioral outcome that design cannot guarantee; the gap is deferred to build time without amending requirements

**Severity:** MEDIUM
**Lens:** Integrity / Coverage

**Finding:**

NP-10.1 and NP-10.2 assert unqualified behavioral outcomes: "the file appears in the document browser's Recents section" and "Recents reflects access order." The feature declaration (Success section) lists "Files opened via bookmark re-register with the document browser so they appear in its Recents section in correct order" as a success criterion.

The design (C7) conducts a thorough API survey and concludes that no documented public UIKit API exists for non-`UIDocument` apps to explicitly register Recents with `UIDocumentBrowserViewController` for programmatically-presented files. The design lists candidate mechanisms (`revealDocument`, security-scoped access, `NSFileCoordinator`), acknowledges none are reliably documented for this purpose, and defers the API choice to "build time." The "Requirements change assessment" section at the end of design.md notes this may require narrowing NP-10 to "best-effort" — but does not make that change, and architecture is declared stable.

This leaves an integrity gap: the requirements state a deterministic outcome; the design cannot guarantee it. If the API choice at build time fails to populate Recents reliably (likely for security-scoped external files not opened through the browser delegate), NP-10.1/NP-10.2 will fail silently and the feature will be marked complete while a success criterion is unmet.

**Recommended action (requirements):** Amend NP-10.1 and NP-10.2 to a best-effort framing: "After a bookmark-based open, the app makes a best-effort attempt to register the file with the document browser's Recents using the best available UIKit API; whether the file appears in Recents depends on OS behavior for security-scoped files opened outside the browser delegate." This also requires amending the feature declaration's Success section accordingly. The remaining NP-10 criteria (NP-10.3 through NP-10.6) are valid as written and require no change.

**Status:** addressed — NP-10.1 and NP-10.2 revised to best-effort framing in requirements.md v2. NP-10.3–NP-10.6 unchanged.

**Verification:** Fix confirmed. NP-10.1 now reads "makes a best-effort attempt to register the file… whether the file actually appears in Recents depends on OS behavior… appearance in Recents is not guaranteed." NP-10.2 adds "Deterministic ordering in Recents is not asserted — actual Recents ordering is OS-controlled." The language is unambiguous. Testability is preserved: NP-10.4 (registration attempted every open), NP-10.5 (registration even when browser off-screen), and NP-10.6 (no crash on failure) remain concrete behavioral assertions. No adjacent gap introduced.

---

### F-003 — NP-9.1 color audit scope in design (C6) is narrower than the requirement

**Severity:** LOW
**Lens:** Coverage

**Finding:**

NP-9.1 states: "No color value in the app's UI is expressed as a hard-coded hex, RGB, or non-adaptive UIColor." This is an app-wide requirement. The design (C6) scopes the audit to "components modified by this feature — `MarkdownEditorTextView`, `RenderedView`, `DocumentView`, and the conflict/deletion surfaces in `DetectorSurfaces`." Components that are not touched by this feature (e.g., existing navigation chrome, any legacy color constants, `BrowserHostController` view styling) are not audited.

If any unmodified component contains hard-coded colors, NP-9.1 will fail on an acceptance pass even though no component introduced by this feature contains them. The requirement's scope ("the app's UI") exceeds the design's audit scope ("modified components").

**Location:** NP-9.1 (requirements); C6 audit scope paragraph (design).

**Recommended action (architecture):** Either (a) expand C6's audit scope to cover all current UIKit/SwiftUI files in the project (a one-pass grep for `UIColor(red:`, `UIColor(hex:`, `#colorLiteral`, and hard-coded `Color(` initializers), or (b) add a scoping note to NP-9.1 narrowing it to "components introduced or modified by this feature," consistent with how prior features were handled. Option (a) is cleaner since it actually satisfies the stated requirement.

**Status:** addressed — NP-9.1 narrowed in requirements.md v2 to apply only to UI components added or modified by this feature, matching C6's audit scope in design.md.

**Verification:** Fix confirmed. NP-9.1 now explicitly scopes to "any UI component added or modified by this feature" and states "UI components not touched by this feature are out of scope for this requirement." This aligns exactly with C6's audit scope in design.md. No adjacent gap introduced.

---

### F-004 — NP-6.5 / rendered view L→R swipe conflict with UINavigationController interactive pop is not resolved in design

**Severity:** LOW
**Lens:** Integrity / Failure modes

**Finding:**

NP-6.5 requires: "The swipe gesture on the rendered view does not conflict with the standard iOS back/interactive-pop gesture if that gesture is also configured on this view." The design (C3) addresses the raw editor case (NPC-9: only one recognizer fires per L→R swipe on raw). For the rendered view, the design installs a SwiftUI `.simultaneousGesture(DragGesture(...))` for L→R → raw, but does not address whether the navigation controller's interactive-pop gesture (a `UIScreenEdgePanGestureRecognizer` on the navigation controller's view, which covers all hosted content including rendered view) fires simultaneously.

In the standard UIKit navigation stack, the interactive-pop gesture starts from the screen's leading edge. A full-width L→R drag on the rendered view (which the design intends to trigger raw mode) starts from the middle of the screen and therefore should not activate the edge-pan recognizer. However, if the user begins a drag near the leading edge, both gestures could activate: the edge-pan would navigate to the file browser (not just switch to raw), and the SwiftUI DragGesture would also attempt to fire. The design does not address this overlap region or specify which recognizer should win.

**Location:** NP-6.5 (requirements); C3 seam-relationships paragraph for RenderedView (design).

**Recommended action (architecture):** Add a note to C3 specifying the expected behavior when a L→R swipe on rendered view begins near the leading screen edge: either (a) the edge-pan recognizer wins (navigating to browser, not to raw), which is acceptable provided users know to drag from the middle for raw mode, or (b) require the SwiftUI DragGesture to fail when the gesture's start X position is within the edge-pan's recognition zone (first ~20pt). State the chosen behavior explicitly so the builder does not have to guess.

**Status:** addressed — NPC-22 added to C3 in design.md stating that the `UIScreenEdgePanGestureRecognizer` (system edge pan) takes priority over the SwiftUI `DragGesture` in the leading screen-edge overlap zone. A near-edge L→R drag on the rendered view navigates to the file browser; the `DragGesture` (raw mode) fires only for drags starting outside the edge zone. NPC-22 also added to the full behavioral constraints list.

**Verification:** Fix confirmed. NPC-22 in C3 body and in the full behavioral constraints list explicitly states the priority rule: system edge pan wins in the first ~20 pt zone; SwiftUI DragGesture fires only for drags starting outside that zone. The fix is logically symmetric with NPC-9's treatment of the same conflict on the raw editor surface. No adjacent gap introduced: the intentional asymmetry (near-edge → file browser; mid-screen → raw) is explicitly stated, so the builder cannot misread it.

---

---

### F-005 — MarkdownLineBreakNormalizer algorithm does not mechanistically exempt inline code spans; NPC-5 behavioral constraint is asserted but not achieved by the stated algorithm

**Severity:** LOW
**Lens:** Integrity / Failure modes
**Introduced by:** verification of F-001 fix (adjacent gap)

**Finding:**

NPC-5 states: "An inline code span that happens to contain a newline is passed through unchanged; the preprocessor does not inspect or modify inline code span content." NP-3.5 (requirements) echoes this: single newlines within an inline code span do not affect rendering of surrounding body text.

The C2 algorithm (steps 1–4) operates entirely at block level: step 1 identifies fenced code blocks and HTML blocks; step 2 preserves those regions; step 3 injects trailing spaces before every bare `\n` outside those block-level regions. Inline code spans (`` `...` ``) are an *inline-level* construct — they are not block-level structures and are not detected by the block-level pass. A newline inside an inline code span (e.g., the unusual but valid `` `foo\nbar` ``) falls outside any fenced-code-block region from the block-level pass's perspective and would receive the two-trailing-space injection by step 3.

In practice the rendered result is likely invisible — the CommonMark renderer treats the backtick-delimited span as a code span and ignores markup inside it, so the injected spaces inside the backtick are rendered verbatim as part of the code-span text rather than as a `<br>`. But the preprocessor is *modifying* the content of inline code spans contrary to NPC-5's assertion. If a future renderer or a `swift-cmark` version change processes the injected spaces differently, the output could break. More concretely, NP-17 requires that "inline code content is rendered verbatim; no extra line breaks are injected" — the algorithm currently *does* inject trailing spaces inside inline code spans even if the current renderer happens to hide them.

This is a design gap: NPC-5 is a correct behavioral goal but the algorithm as described in steps 1–3 does not achieve it. The block-level pass must also skip inline code span content, or the normalizer's step 3 must be constrained to operate only outside inline code spans.

**Recommended action (architecture):** Strengthen C2's description of step 3 (or add a step 1b) to require that the normalizer also tracks inline code spans (backtick-delimited runs) within non-code-block lines and skips the trailing-space injection inside them. A lightweight single-pass approach: for each line outside a fenced code region, scan for balanced backtick runs before injecting trailing spaces; any `\n` that falls inside a backtick-delimited span is left unchanged. Alternative: since multi-line inline code spans are rare and already semantically unusual in CommonMark (CommonMark spec §6.1 strips the leading/trailing line endings from code span content before rendering), the design could explicitly note that multi-line inline code spans are not a supported input pattern for this app's target user (prose writer), and assert NPC-5 only for single-line spans. Either resolution must be explicit in C2.

**Status:** open

---

## Prescription feedback

### C5 — ShareLink vs. UIActivityViewController implementation choice

**Note:** implementation prescription, not behavioral constraint — design section C5.

The design hedges between `ShareLink(item: fileURL)` and a fallback to imperative `UIActivityViewController` presentation, noting the distinction "is detectable in testing." Both paths satisfy the behavioral constraints (NP-8.4, NP-8.5). The deleted-file guard logic is correctly described for both paths. The uncertainty about whether `ShareLink(item:)` reads from disk or triggers a UIDocument coordinator is a valid implementation-time concern but does not represent a requirements gap or a behavioral constraint that needs strengthening before building. No action required.

---

## Findings index

| ID | Severity | Lens | Subject | Status |
|----|----------|------|---------|--------|
| F-001 | MEDIUM | Integrity / Failure modes | Indented-code-block heuristic misclassifies list-continuation lines; NP-3.3 fails for indented list body | addressed — verified |
| F-002 | MEDIUM | Integrity / Coverage | NP-10.1/NP-10.2 assert deterministic Recents registration; design cannot guarantee it; gap deferred without amending requirements | addressed — verified |
| F-003 | LOW | Coverage | NP-9.1 color audit scope (app-wide) exceeds C6 design audit scope (modified components only) | addressed — verified |
| F-004 | LOW | Integrity / Failure modes | NP-6.5 rendered view L→R swipe vs. edge-pan recognizer overlap region unresolved in design | addressed — verified |
| F-005 | LOW | Integrity / Failure modes | C2 normalizer algorithm (block-level pass) does not exempt inline code spans; NPC-5 behavioral constraint asserted but not mechanistically achieved | open |
