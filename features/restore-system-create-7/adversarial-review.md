*Adversarial review — fresh mode. requirements.md @ 2fd2cfb2d7c8febfe0723e772b7801adcd077ef0, design.md @ 6551527b504dc61d18d8a7b0794371fe68eebd27.*

## Findings

### F-001 — "Don't override the create delegate" may disable the "+" affordance entirely
- **Severity:** HIGH
- **Lens:** integrity / feasibility
- **Subject trace:** declaration Success #1 ("Markus does not override `documentBrowser(_:didRequestDocumentCreationWithHandler:)`"), AC-1.3, DC-1.
- **Finding:** Both the declaration and DC-1 frame the desired behavior as "let `UIDocumentBrowserViewController` run its default create affordance" by simply *not* implementing the creation-delegate callback. In actual `UIDocumentBrowserViewController` semantics, `allowsDocumentCreation = true` together with an *implemented* `documentBrowser(_:didRequestDocumentCreationWithHandler:)` is what makes the "+" affordance functional — the delegate must call the completion handler with a **template URL** the system then copies into the user-chosen location, applying the system's inline rename. With no override present, there is no template to copy and no "create what?" answer; the documented contract is that the app supplies the template via this delegate method. Files.app, Pages, etc. all implement this method — they do not omit it. The spec's mental model ("the system handles creation end-to-end if we just don't override") does not match the framework's actual contract.
- **Concrete failure mode:** After C4 removal as written, tapping "+" in the browser either does nothing (no template provided), surfaces a system error, or — depending on iOS version behavior with an unimplemented delegate — the "+" affordance is hidden entirely. AC-1.1 ("a new `.md` file appears in the folder currently shown by the browser") cannot be satisfied with the delegate fully un-implemented; the **observable** the requirement asks for (file lands in browsed folder via system rename UI) actually requires *retaining* the delegate method, but reducing it to: "complete the handler with a template URL in an app-managed temp location, and let the system copy/place/rename." That is the iOS-default path. The current spec conflates "don't override the location choice" (correct, achievable) with "don't implement the delegate at all" (incorrect — disables create).
- **Recommended action (requirements + architecture):**
  - Reframe AC-1.3 / DC-1 from "the method is not overridden" to a behavioral observable: "the new file lands in the folder currently shown by the browser, via the system's inline rename, with no Markus-supplied target directory or naming logic." The method is implemented, but minimally: provide a template URL (e.g. an empty `.md` in the app temp dir), call the completion handler, and let the system place + rename. No `CreateTargetResolver`-style directory choice; no `NameProbe`-style collision logic.
  - Update declaration Success #1 wording accordingly ("Markus does not choose the create location or name" rather than "Markus does not override the delegate method").
  - Confirm with a one-line build-time spike before locking the DAG: in the target iOS / Xcode version, verify that omitting the delegate vs. implementing it with a minimal template behaves as the spec expects. If iOS does provide a "no-template default" path for un-implemented delegates, the original spec stands; if it does not (the expected case), revise per above.
- **Status:** addressed

---

## Prescription feedback

These items concern HOW the design implements behavior rather than WHAT the feature requires.

- **DC-4 empty-content check mechanism** (`document.text.isEmpty` vs. `document.initialByteSize == 0`, with a tiebreak) — implementation prescription, not behavioral constraint. The behavioral constraint (zero-content document opens in raw mode with keyboard up regardless of provenance) is sound. Design section: DC-4 / "Seam relationships → DC-4."
- **`DocumentView.init(initialMode:)` parameter retention vs. removal** — implementation prescription. The behavioral constraint (no `initialMode` is threaded from a create path) holds either way. Design section: "Components being removed → The `initialMode` threading."
- **`Markus_v3/Create/` directory deletion and Xcode group reference cleanup** — implementation/hygiene prescription. The behavioral constraint (C4–C7 not referenced from any call site, AC-5.4) is what matters. Design section: "Build-time considerations."

---

## Summary

One HIGH integrity/feasibility finding (F-001): the spec's premise that simply *omitting* the `documentBrowser(_:didRequestDocumentCreationWithHandler:)` override yields the iOS-default create flow does not match `UIDocumentBrowserViewController`'s actual contract — the delegate must be implemented and supply a template URL for "+" to function; what the spec wants is for that implementation to be minimal (no Markus-chosen directory, no Markus-chosen name), not absent. Reframe the contract behaviorally and confirm with a small build-time spike before the DAG locks. All other lenses (coverage of EC-3 abandoned-rename, scope of the AC-4 content-based initial-mode rule, failure modes for read-only folders, integrity of preserved C0–C3/C8, HIG/accessibility standards) come up clean — the spec correctly delegates abandoned-rename to the system, the AC-4 content rule is a legitimate replacement for the removed `initialMode` threading and traces to declaration "prefer the Apple way," and the preserved components have no hidden coupling to the removed ones beyond what the design already calls out.
