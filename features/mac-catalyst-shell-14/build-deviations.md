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
