# Adversarial Review: resume-and-create-2

*Review based on requirements.md + design.md at commit `4fbeb2c`. Re-run of the first-pass review (`fef48d2`). Scoped to verify the six findings marked `addressed` and to attack the proposed fixes. No `Reuses pattern:` markers in design.md, so all surfaces continue to receive full-lens scrutiny.*

## Open findings

### F-007 — NSUserActivity advertising mechanism is unspecified
- **Severity:** MEDIUM
- **Lens:** Integrity / Coverage
- **Finding.** Surfaced while attacking F-003's fix. Requirements AC-1.5 explicitly names `NSUserActivity` as the primary persistence mechanism ("UserDefaults-only persistence is rejected as the primary mechanism; `NSUserActivity` is the HIG-canonical surface"). Design component #3 says `LastDocumentStore.record(url:)` "attaches it to the scene's `NSUserActivity`" but never specifies how that activity becomes the scene's activity — there is no `.userActivity(activityType:isActive:_:)` modifier anywhere in `ContentView` (component #1) to advertise the activity to SwiftUI's scene lifecycle. Design component #1 *does* install `.onContinueUserActivity("com.evehwang.Markus.openDocument")` to receive the activity, but with no advertising side, the activity is never delivered — that code path is dead.

  Concrete failure mode: build agent implements the design literally. UserDefaults-backed resume works on cold launch (because `LastDocumentStore.resolveLastDocumentURL()` reads UserDefaults directly in `viewDidAppear`). After a long-suspended state where the scene is torn down (AC-1.4), the SwiftUI scene reconstructs and `viewDidAppear` fires again — UserDefaults still works. So the *behavior* of resume is correct via UserDefaults alone. But AC-1.5 says NSUserActivity is primary, and the build agent will either (a) leave the NSUserActivity wiring as dead decoration, confusing future readers, or (b) try to advertise the activity correctly without guidance and waste time on a mechanism that contributes nothing.

  Two clean resolutions:
  - **(a) Drop NSUserActivity from this feature.** Update AC-1.5 to "UserDefaults-backed security-scoped bookmark." Note that NSUserActivity is HIG-canonical but not required for single-app, single-device resume. Remove `.onContinueUserActivity` from component #1; remove the "attach to scene's NSUserActivity" language from component #3.
  - **(b) Wire NSUserActivity properly.** Add `.userActivity("com.evehwang.Markus.openDocument", isActive: ...) { activity in activity.addUserInfoEntries(from: ["bookmark": data]) }` to `ContentView`, with a binding for the current bookmark data. Specify that `.onContinueUserActivity` is the restoration entry point and document the relationship to UserDefaults (UserDefaults as fallback when no activity is delivered).

  Recommendation: **(a)**. The feature declaration explicitly excludes Handoff and multi-scene state restoration, which are the actual reasons to use `NSUserActivity`. For local resume in a single-scene iOS app, UserDefaults is sufficient and clearer. AC-1.5's "HIG-canonical" framing was aspirational, not load-bearing.
- **Recommended action:** `t3-requirements` — soften AC-1.5 to UserDefaults-as-primary. Then `t3-architecture` — strip dead `.onContinueUserActivity` and the "attach to scene's NSUserActivity" language from components #1 and #3.
- **Location:** requirements.md AC-1.5; design.md components #1 and #3.
- **Status:** `open`

### F-008 — Close-during-dismiss interaction with walking-skeleton-1 AC-RECOVER-1 is unspecified
- **Severity:** LOW
- **Lens:** Failure modes
- **Finding.** Surfaced while attacking F-004's fix. Design component #5's close lifecycle calls `document.close { _ in cleanupIfUntouched; stopAccessingSecurityScopedResource }` from inside the nav delegate's `willShow placeholderVC` callback, in parallel with `navController.dismiss(animated: true)`. If `close` itself fails (e.g., `.savingError` from a final flush against a now-missing file or a write-permission revocation between the last edit and dismiss), `UIDocument` will post `stateChangedNotification` with savingError. Walking-skeleton-1's `SaveStatusObserver` (component #7, simplified per F-003) observes this and `DocumentView` would set `activeAlert = .saveFailed(...)` per walking-skeleton-1 AC-RECOVER-1 — but `DocumentView` is being dismissed at the same time.

  Concrete failure mode: the user makes an edit, taps back, dismiss starts, close fires a save error during dismiss, the recovery alert (with "Copy contents to clipboard" action) is set on `DocumentView`'s `activeAlert` but the view is no longer in the hierarchy. The alert never appears. The user loses their edits and gets no clipboard rescue — silent data loss in a corner-case path that AC-RECOVER-1 was explicitly designed to prevent.
- **Recommended action:** `t3-architecture` — specify in design component #5 close lifecycle whether: (a) save-failures during dismiss are re-presented on the browser (`MarkusDocumentBrowserViewController`) as the fallback host for the recovery alert, (b) close is awaited before dismiss begins (so the alert can fire on the still-live `DocumentView` and dismiss is gated by the user's response), or (c) save-failures during dismiss are accepted as silent data loss in this race window (declaring the existing alert path "best-effort"). Option (a) preserves AC-RECOVER-1 most faithfully.
- **Location:** design.md component #5 ("UIDocument open/close lifecycle" subsection, dismiss path).
- **Status:** `open`

### F-009 — Pop-vs-dismiss animation coordination unspecified; risks visible jank
- **Severity:** MEDIUM
- **Lens:** Standards compliance (HIG)
- **Finding.** Surfaced while attacking F-005's fix. Design component #2 step 6 prescribes intercepting `navigationController(_:willShow:animated:)` and calling `dismiss(animated: true)` when the target is `placeholderVC`. At that point the navigation pop has already begun — the back chevron tap (or the interactive-pop edge swipe) has committed the pop. So the design has two animations running concurrently: UIKit's default pop animation (documentVC sliding right, placeholderVC sliding in from the left) and the modal dismiss animation using the browser's `transitionController(forDocumentAt:)` reverse-zoom.

  Concrete failure mode: the user sees the placeholder VC briefly visible as the documentVC slides off, before the modal zoom-back covers it. Or the zoom-back transition's geometry conflicts with the slide. Either way, the dismiss looks "janky" relative to Apple's first-party document apps (Pages, Numbers, Keynote) — which is the explicit HIG-alignment goal of pattern (b) from F-005.

  Three plausible resolutions, each with trade-offs:
  - **(a) Cancel the pop, then dismiss.** Implement `UINavigationBarDelegate.navigationBar(_:shouldPop:)` to return `false` (cancel the pop) and trigger `dismiss(animated: true)` instead. The placeholder is never reached; the zoom-back transition runs alone. Cleanest visually. Subtle: `shouldPop` is awkward to wire under `UINavigationController`'s default delegation; may require a custom `UINavigationBar` subclass or interception via `navigationItem.backAction` (iOS 14+).
  - **(b) `dismiss(animated: false)`.** Suppress the modal dismiss animation; the pop's default slide animation provides the only visual cue. Visually consistent but loses the zoom-back transition that pattern (b) was meant to preserve.
  - **(c) Custom barbutton action that bypasses pop entirely.** Replace the native `backBarButtonItem` with a custom `UIBarButtonItem` styled with `chevron.backward` + "Documents" whose action calls `dismiss(animated: true)` directly. No pop ever happens. Loses native chevron rendering — reverts to F-005's option (a) visual divergence.

  The design must commit to one. Pattern (b) (the placeholder-VC trick) was chosen specifically to get native chevron rendering AND native edge-swipe. If we now strip the native chevron via (c), we have placeholder VC overhead for no visual gain. Option (a) is the cleanest preservation of pattern (b)'s value; option (b) is a fallback if (a) proves too fragile.
- **Recommended action:** `t3-architecture` — pick one of (a)/(b)/(c). My read: try **(a)** first; fall back to **(b)** if `shouldPop` interception proves unreliable. Document the trade-off in component #2.
- **Location:** design.md component #2 step 6 (nav delegate `willShow placeholderVC` interception).
- **Status:** `open`

## Resolved findings

### F-001 — Zero-byte mode-default ambiguity
- *Originally MEDIUM, Integrity/Coverage.* Fix verified: requirements.md AC-4.4 rewritten to trigger raw+keyboard on session provenance (`UntouchedFileTracker.shared.isUntouched(url:)`) rather than byte size. EC-23 ("opens to an empty rendered view") is now consistent — a zero-byte file resumed from a prior session is no longer in the tracker's set, so it falls through to walking-skeleton-1 EC-2's byte-size default and opens rendered. Design.md component #8 now explicitly consults `UntouchedFileTracker.isUntouched(url:)` first and falls back to byte-size logic only when not in the set. Attack on the fix: edge cases (force-quit after typed-then-deleted, force-quit before autosave fires) behave consistently with the new logic. No adjacent gap.

### F-002 — Multi-scene not explicitly disabled
- *Originally MEDIUM, Scope drift/Failure modes.* Fix verified: design.md component #9 explicitly sets `UIApplicationSupportsMultipleScenes = NO` and includes a build-agent note about flipping walking-skeleton-1's likely default. Attack on the fix: no SceneDelegate is configured (consistent with the pattern-2 choice in F-003's fix); manual iPad-simulator verification is reasonable for this scope. No adjacent gap.

### F-003 — App-entry pattern muddled
- *Originally MEDIUM, Integrity.* Fix verified: design.md component #1 adopts pattern 2 explicitly — pure SwiftUI App with `WindowGroup { ContentView() }`, no `UIApplicationDelegateAdaptor`, no SceneDelegate. `BrowserHostView` is the `UIViewControllerRepresentable` wrapper; resume orchestration lives in `MarkusDocumentBrowserViewController.viewDidAppear` first-appearance branch. Attack on the fix: the pattern itself is sound; cold-launch resume via UserDefaults works regardless of NSUserActivity. **However**, the attack surfaced a new adjacent gap — the NSUserActivity machinery referenced throughout components #1 and #3 is incompletely wired. That gap is logged as F-007 and remains `open`.

### F-004 — UIDocument async lifecycle unspecified
- *Originally MEDIUM, Coverage/Failure modes.* Fix verified: design.md component #5 has a dedicated "UIDocument open/close lifecycle" subsection covering open-before-present, failure discrimination via `documentState` (with the resume-path bookmark clearing on `.fileMissing`/`.iCloudDownloadFailed`), close-before-cleanup ordering, and the close → cleanupIfUntouched → stopAccessingSecurityScopedResource chain. Attack on the fix: the lifecycle is correctly sequenced. **However**, the attack surfaced a new adjacent gap — close fails during dismiss races with walking-skeleton-1 AC-RECOVER-1's alert presentation. That gap is logged as F-008 (LOW) and remains `open`.

### F-005 — "Back chevron + Documents" hard to render natively for a presented modal
- *Originally MEDIUM, Standards compliance (HIG).* Fix verified: design.md component #2 adopts option (b), the placeholder-VC pattern. The native `backBarButtonItem` on `documentVC` renders as "‹ Documents" identically to Apple's first-party document apps. Side benefit: `interactivePopGestureRecognizer` becomes natively available, which was folded back into AC-3.3 via RI-4. Attack on the fix: the rendering is now correct. **However**, the attack surfaced a new adjacent gap — the *animation coordination* between pop and modal dismiss is unspecified and risks visible jank. That gap is logged as F-009 (MEDIUM) and remains `open`.

### F-006 — `LastDocumentStore.record(url:)` failure path unspecified
- *Originally LOW, Failure modes.* Fix verified: design.md component #3 now explicitly catches the throw from `URL.bookmarkData(...)`, logs via `os_log` at debug level, preserves any previously persisted bookmark, and returns without persisting. Visible consequence (silent fall-through to browser on next launch) is documented and consistent with the declaration's silent-failure stance. Attack on the fix: the "preserve previous bookmark" choice means a record-failure leaves the user resuming to one-file-ago — defensible since both this and "clear on failure" are silent options and the declaration permits either. No adjacent gap.
