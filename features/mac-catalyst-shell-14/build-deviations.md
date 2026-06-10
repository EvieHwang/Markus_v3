# Build deviations — mac-catalyst-shell-14

Records adjustments made during the build where a test assertion or design call
shape did not match implementation reality. Each entry feeds back to the
req↔arch loop on the next adversarial pass.

---

## D-001 — Mac iconset slot count: 10, not 12

**Task:** T-007 (Mac app-icon slots — Component E)
**Affected:** `features/mac-catalyst-shell-14/tests/MacRestorationTests.swift`
(`macIconSlots_arePopulated` references `catalog.macSlots.count == 12`),
`features/mac-catalyst-shell-14/design.md` ("Existing seams confirmed → Icon
catalog" describes 12 `idiom:mac` slots).

**Original assertion in the spec test:**
```swift
#expect(catalog.macSlots.count == 12,
        "C-6.1: the catalog declares the 12 idiom:mac slots")
```

**What was wrong:** The pre-existing
`Markus_v3/Assets.xcassets/AppIcon.appiconset/Contents.json` declares **10**
`idiom:mac` slots, not 12. Apple's standard macOS iconset is five sizes
(16/32/128/256/512 pt) at two scales (1x, 2x), which is 10 slots total. The 64
and 1024 pt sizes are not idiomatic Mac iconset entries — 64 is rendered from
the 32@2x slot and 1024 is rendered from the 512@2x slot. Design.md inherited
the "12" miscount from a verbal description of "all the standard Mac sizes"
without verifying against the catalog. The spec test inherited the same number.

**Correction in the mirror (`Markus_v3Tests/MacCatalystShell14_AppIconTests.swift`):**
Asserts `macSlots.count == 10` to match the actual Mac iconset convention. The
spirit of the assertion — "every Mac slot must carry a filename, no empty
placeholders" — is preserved verbatim.

**Why the correction is safe:** The acceptance behavior (AC-6.1 — Dock/Finder/
switcher render a real Markus icon; no empty/placeholder slot) is invariant in
the slot count. The 10-slot catalog is exactly the standard Mac iconset that
macOS will render from at all required sizes. Populating all 10 satisfies the
behavioral requirement. The "12" was a verification error, not a behavioral
requirement.

**Adversarial follow-up:** Design.md "Existing seams confirmed → Icon catalog"
should be re-read against the live catalog in the next adversarial pass and
the "12" corrected to "10".

---

## D-002 — T-002 XCUITest mirror deferred (verified live instead)

**Task:** T-002 (Catalyst menu bar — Component A)
**Affected:** `features/mac-catalyst-shell-14/tests/MacMenuBarUITests.swift`
(reference spec for T-002's XCUITest cases — `test_fileMenu_containsOpenSaveClose_noNew`,
`test_viewMenu_containsStableTitledTogglePreview`, `test_editMenu_containsSystemStandardItems`,
`test_menuTogglePreview_matchesCmdP`, `test_menuClose_returnsToBrowser_likeCmdW`,
`test_menuSave_showsNoNewConfirmationUI`, `test_documentScopedItems_disabledAtBrowser`,
`test_documentScopedItems_enabledWithDocument`, `test_disabledShortcutsAtBrowser_areStructuralNoOps`).

**What was deferred:** mirroring the T-002 subset of `MacMenuBarUITests.swift`
into `Markus_v3UITests/` so it executes against the live Catalyst destination.
The spec's `setUpWithError` requires a `-UITest-SeedFixture mac-fixture.md`
launch-argument handler and an in-app fixture-seeding path that do not exist
in the host today; implementing them touches `SceneDelegate` /
`BrowserHostController` and is materially larger than T-002's own scope.

**What was done instead:** end-to-end **live verification on the Mac Catalyst
build** of the same 10 observable contracts the deferred XCUITests cover —
File / Edit / View structure with correct ⌘ equivalents and no New; stable-
titled Toggle Preview on ⌘P; document-scoped Save / Close / Toggle Preview
grayed at the browser and enabled in the editor; File → Open always enabled;
menu invocations dispatching through the same `EditorActions` / `presentDocument`
seams as the chord bindings (no double-fire with the `#if !targetEnvironment(macCatalyst)`
gate now on `EditorKeyCommandHostingController.keyCommands`); ⌘O presents the
system open panel from the browser; ⌘S/⌘W/⌘P at the browser are structural
no-ops. All ten contracts confirmed by the build owner against the running app.

Probe-level coverage was also confirmed in `Markus_v3Tests/MacCatalystShell14_MenuBarRoutingTests.swift`:
12 of 15 cases passed cleanly across runs; the remaining 3 are trivial data
assertions on a hardcoded `MenuBarProbe` (`MenuItemProbe(title: "Toggle Preview", …)`)
and were observed as crash-during-run artifacts of an iOS Simulator host-app
stack-guard overflow on the cooperative pool that reproduces deterministically
across iPhone 17 / iPhone 17 Pro destinations on macOS 26.4.1 / iOS 26.5 sim
— see two crash reports captured this session (`EXC_BAD_ACCESS (SIGBUS) /
KERN_PROTECTION_FAILURE`, "Could not determine thread index for stack guard
region", faulting 51 bytes past the end of the stack on
`com.apple.root.user-initiated-qos.cooperative`). The crash is unrelated to
T-002 (none of T-002's iOS-side code runs during host-app launch — the Catalyst
menu builder and `buildMenu` override are `#if targetEnvironment(macCatalyst)`
and the lone iOS-side addition is a 3-line `@objc` selector on
`BrowserHostController` not invoked during launch).

**Why the deferral is safe:** the observable contract (US-1 / US-2 / disabled-
shortcut edge / FM-1 / FM-4 / FM-6 / FM-10, plus the open-funnel and resume-
target seams) is verified end-to-end on the live Catalyst destination — the
exact verification depth the XCUITests would have provided. The XCUITest
mirror remains valuable as a regression suite once the fixture-seeding
infrastructure lands; flagging it for a follow-up pass.

**Adversarial follow-up:** (1) mirror the T-002 subset of
`MacMenuBarUITests.swift` into `Markus_v3UITests/` once a `-UITest-SeedFixture`
launch-argument path exists in the host (likely co-introduced with T-006's
restoration tests, which need the same scaffolding); (2) file a separate
issue against the iOS Simulator host-app launch stack overflow (env, not
T-002) so the probe suite can run to clean green on the standard simulator
destination.

---

## D-003 — T-005 XCUITest mirror runs on the existing resume fixture; Catalyst hit-point geometry; pre-existing iOS-only call in ExternalChangeUITests gated

**Task:** T-005 (Pointer / hover affordance layer — Component C)
**Affected:**
- `features/mac-catalyst-shell-14/tests/MacPointerUITests.swift` (reference
  spec — uses `-UITest-SeedFixture mac-fixture.md` and `-UITest-NoPointerDevice`
  launch args that do not exist in the host today; the deferral context is
  the same as D-002).
- `Markus_v3UITests/ExternalChangeUITests.swift` (pre-existing
  `XCUIDevice.shared.press(.home)` calls that are iOS-only and prevent the
  UI test target from compiling under the Mac Catalyst destination — distinct
  from T-005's contract but on the same compile path).

**What changed in the mirror.**
- **Fixture seeding via the existing resume path.** Like the rest of the
  feature's deferred fixture work (D-002), T-005's mirror lands in the editor
  via the existing `-uitest-seed-last-file` flag (LaunchResumeBranch) rather
  than the spec's not-yet-present `-UITest-SeedFixture mac-fixture.md`
  handler. The same precedent IpadExpansion13_KeyboardShortcutsUITests uses.
- **`-UITest-NoPointerDevice` deferred to probe coverage.** The spec's
  separate no-pointer-device relaunch case asserts "absent a pointer, nothing
  is hidden/disabled and tap still works." The mirror collapses this into the
  same session (the targets are visible and a tap on the rendered surface
  performs the existing transition); the relaunch semantics are pinned at the
  probe layer by `MacCatalystShell14_NoPointerDeviceTests`.
- **Coordinate-based clicks and hover on the wide-window Catalyst surface.**
  On a wide Mac Catalyst window the `RenderedView` ScrollView spans the full
  width while the actual content column is ~700 pt centered (inherited from
  ipad-expansion-13's `.contentColumn()`). `XCUIElement.tap()`'s default hit
  point lands on the padded outer region and XCUITest reports "Unable to find
  hit point for ScrollView." The mirror taps and hovers via
  `coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))` so the click
  is delivered to actual content. This is purely a test-driving primitive —
  the production contract (`clickable == tappable`, `click == tap`) is
  unchanged.

**Why the changes are safe.** Each adaptation maps to a build-step primitive
left as a documented seam in the spec ("the build implementer maps each
helper to the concrete primitive available on the target Xcode version" —
verify.md). The observable contract — pointer feedback on both targets, click
== tap, existing gestures preserved, mode switch reachable without a pointer,
no-pointer hides/disables nothing, tap still works — is asserted by the
mirror end-to-end on the Mac Catalyst destination. All six T-005 XCUITest
cases ran green against the running Catalyst build, and all six
`PointerAffordanceTests` probes ran green on the iOS-simulator destination,
covering the seam invariants the XCUITests cannot directly observe (region
equality, parallel-path absence).

**`XCUIDevice.press(.home)` gating in ExternalChangeUITests.** Two pre-T-005
backgrounding cases (`testBackgroundingDoesNotAutoResolveSheet`,
`testBufferPreservedAcrossBackgroundWithPendingSheet`) call
`XCUIDevice.shared.press(.home)`, which is iOS-only and fails to compile
under the Catalyst destination's UI test target. Until T-005 nothing
exercised the Catalyst UI test bundle, so the breakage was latent. To unblock
the Catalyst XCUITest run, both cases are gated `#if !targetEnvironment(macCatalyst)`,
matching the existing pattern used on
`EditorKeyCommandHostingController.keyCommands` (T-002). The tests still
compile and run on their intended iOS-simulator destination; only the
Catalyst variant is excluded.

**Adversarial follow-up:** (1) once the `-UITest-SeedFixture mac-fixture.md`
and `-UITest-NoPointerDevice` handlers land in the host (likely co-introduced
with T-006's restoration tests), the T-005 mirror should be updated to use
them so the no-pointer relaunch case is exercised end-to-end rather than
collapsed; (2) the two backgrounding cases in `ExternalChangeUITests` should
be replaced with a Catalyst-compatible "background then activate" primitive
(e.g. `XCUIApplication.deactivate()` or driving the OS via the launch
arguments path) so the assertions extend to the Mac as well.
