# Adversarial Review — iPad Expansion (ipad-expansion-13)

Reviewing requirements.md and design.md at commit `097b06528f60e51fc525225e04e0dabfab8de2ec` — FRESH REVIEW pass.

Mode: fresh review. Greenfield key-command + size-class wiring; design reported no `Reuses pattern:` marker, so security/failure-mode lenses are full-spectrum (not HIGH-only) per the Stage-3 contract.

Source ground truth verified against `Markus_v3/Views/DocumentView.swift`, `RawEditorView.swift`, `RenderedView.swift`, `Markus_v3/Host/BrowserHostController.swift`, `SceneDelegate.swift`, `Markus_v3/Models/DocumentMode.swift`.

---

## Open findings

### F-001 — ⌘N from inside a presented editor has no defined invocation/replacement path

- **Severity:** MEDIUM
- **Lens:** Failure modes / coverage
- **Scope trace:** AC-3.2 ("⌘N works while a document is already open in the editor (raw or rendered) ... returning the user into the newly created document by the existing open path") and US-3. This is declared behavior, not an implementation prescription — it passes the scope check.
- **Finding:** The new-document flow is the system create flow `documentBrowser(_:didRequestDocumentCreationWithHandler:)`, which is a **delegate callback the OS invokes when the user taps the browser's create control on `UIDocumentBrowserViewController`**. In the running app the editor is presented as a full-screen `UINavigationController` modal *on top of* the host (`installEditorSession`: `present(nav, animated:)` with `modalPresentationStyle = .fullScreen`). Two concrete failure modes the design does not resolve:
  1. **No invocation handle.** There is no public API to programmatically trigger `didRequestDocumentCreationWithHandler`. The design (C-A.4 / S-1) asserts "⌘N reaches the host so the system create flow runs" but does not name what the provider calls to start creation from inside the editor. As written, the only thing the provider can reach is the host; the host has no method that begins a system create. So ⌘N-from-editor risks being a silent no-op — a coverage gap against AC-3.2, not just an implementation detail.
  2. **Double-present conflict on completion.** Even if creation is triggered, the success path runs `presentDocument(at:)` → `installEditorSession` → `present(nav, …)` on the host. The host already has `presentedViewController` set to the current editor nav. Calling `present` on a controller that is already presenting either no-ops with a runtime warning or fails to show the new document. AC-3.2's "returning the user into the newly created document" requires the current editor to be dismissed first; the design specifies no such teardown for the ⌘N path (it specifies it only for ⌘W via `dismissPresentedEditor()`).
- **Why it matters (named risk area):** This is the "⌘N over a dirty doc" risk called out for this feature. If the current document is dirty and ⌘N is handled by tearing the editor down the way ⌘W does, edits must be saved synchronously first; if ⌘N is handled by stacking a new presentation, the system warns/fails. Either way the design has to state which, and neither is specified.
- **Recommended action (architecture):** In design.md, specify the ⌘N-from-editor sequence explicitly: (a) the concrete host entry point the provider invokes to begin a system create while the editor is presented (and whether that is even reachable, or whether ⌘N must first dismiss the editor via the same synchronous-save `dismissPresentedEditor()` path and then surface the browser's create), and (b) how the resulting `presentDocument` avoids the double-present (dismiss-then-present ordering). Tie the chosen sequence back to AC-3.2 and FM-1 (no parallel create path) and AC-2.2-style save-before-teardown so a dirty doc is not lost.
- **Status:** open

---

## Prescription feedback

These concern HOW the design realizes a behavior (call shapes, responder identity, modifier choices) rather than WHAT the feature requires. Recorded, not filed as findings.

- **Responder identity for the key-command provider** (design Component A / Resolved deferred question / S-1, S-4). The design names "the presented `UIHostingController` (or an equivalent responder the `BrowserHostController` installs)." Whether the commands live on the `UIHostingController`, a custom `UIResponder` subclass inserted in the chain, or `BrowserHostController`/`SceneDelegate` is an implementation prescription, not a behavioral constraint — implementation prescription, not behavioral constraint. (Note: the *behavioral* claim it backs — that a command above the `UITextView` on the chain is reached before the text view consumes the chord — is sound and verified against `installEditorSession`, where `host` is the nav's root above `MarkdownTextViewBridge`.)
- **Width realization mechanism** (design Component B seam note / C-B.4). "Constrain the text view's content inset/container width" vs. "center the text view within a capped region" is explicitly left to the build step and bounded by the observable C-B.4 guard. This is correctly framed as an implementation choice — implementation prescription, not behavioral constraint.
- **`@Environment(\.horizontalSizeClass)` as the size signal** (design C-B.2). The named environment key is an implementation prescription; the load-bearing constraint is the behavioral one ("capped+centered when space is ample, full-width when not") — implementation prescription, not behavioral constraint.

---

## Cleared risk areas (checked, no finding)

- **⌘W data loss.** Verified `dismissPresentedEditor()` calls `currentSaveBridge?.saveSynchronously()` before `dismiss`. ⌘W routes through `onBack` → `dismissPresentedEditor()`, so unsaved edits are written first (AC-2.2). No discard path is introduced. Sound.
- **⌘P swallowed by `UITextView`.** Verified the raw surface is `MarkdownTextViewBridge` (a plain `UITextView`) nested below the presented `UIHostingController` on the responder chain. A plain text view does not bind ⌘P, so the OS chain-walk reaches a provider installed at/above the hosting controller before the text view treats the chord as input (FM-3 / S-4). Design responder reasoning is accurate.
- **⌘P / toggle-direction ownership.** Design correctly forbids the provider from reading `mode`/seeding anchors itself (S-2), keeping `DocumentView` (which owns `mode`, `rawScrollState`, `switchTo`, `switchToRenderedFromSwipe`, `triggerSave`, `postModeAnnouncement`) the single authority. No parallel toggle path. Sound (FM-1, AC-1.x).
- **⌘S clean-buffer / no new UI.** `triggerSave()` → `document.markDirty()`; failures already route through `SaveFailedAlertRouter` / `ActiveAlert.saveFailed` in `DocumentView`. ⌘S reuses this unchanged (AC-4.x, FM-2). Sound.
- **Discoverability overlay (Apple HIG).** Requirements AC-5.1/5.2 and design C-A.6 specify distinct, action-describing, mode-stable titles ("Toggle Preview", "Close", "New Document", "Save") supplied via each command's discoverability title. HIG discoverability requirement is met at spec level.
- **Width cap vs. large Dynamic Type (WCAG / accessibility).** The ~700pt cap is a `maxWidth`, not a fixed text width; at large Dynamic Type, glyphs grow and lines wrap more within the column — no truncation is forced. `RenderedView` already re-renders on `@Environment(\.dynamicTypeSize)`. No concrete clipping/truncation failure mode. No finding.
- **Width cap live update on size-class transition (rotation / Slide Over).** S-5/S-6/S-7 read the size class live per-surface and keep the treatment presentation-only (no scroll reset, no edit loss). `RenderedView` currently uses `.frame(maxWidth: .infinity, alignment: .leading)`; replacing the max with a capped value in regular width is a clean in-place change. Behaviorally specified (US-9, FM-7). No finding.
- **Gutter intercepting touches / caret hidden (FM-6).** C-B.4 mandates a non-interactive background gutter, full usable column, caret/selection within the column. Behaviorally pinned. No finding.

---

## Summary

- Open findings: 1 MEDIUM (F-001), 0 HIGH, 0 LOW.
- `## Prescription feedback`: non-empty (3 entries).
- No finding carries the "Scope drift" lens; no declaration tension surfaced. Every declared behavior traces cleanly to declaration.md / feature declaration / requirements.md, and the design adds no new Shape component (consistent with the feature declaration's "adds no new component").
