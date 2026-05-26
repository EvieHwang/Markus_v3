# Build deviations — external-change-5

Deviations from design.md (and notes on how acceptance was verified) recorded
during `/build`. Per the constitution, requirements are immutable; design is a
recommendation. Each entry notes the design section, what was done instead, and why.

## D-001 — Tests verified by inspection, not execution (whole build)

**Context:** The build ran in a Linux cloud sandbox with no Swift/Xcode toolchain
(`xcodebuild` is macOS-only; the spec tests are Swift Testing + XCUITest). The
DAG/`/next` step "run the tests tagged to this task and confirm they fail, then pass"
could not be executed here.

**What was done:** Each task's source was implemented to match the spec-test
contracts exactly, verified by close reading of the assertions in
`tests/unit/ExternalChangeTests.swift` and `tests/ui/ExternalChangeUITests.swift`.
The pure-logic suites (Waves 1–2: `ContentEqualityGate`, `LastKnownDiskState`,
`ConflictResolution`, `ChangeClassifier`, `SettleGate`, `ApplyEdgeRevalidation`,
`SaveSuspensionLatch`, `ForegroundReconciler`) are deterministic value-level
functions whose behavior was checked input-by-input against each `#expect`.

**Why / impact:** Final `xcodebuild test` on macOS (or `⌘U`) is required to confirm
compilation and green tests before merge. This is called out in the PR. No
requirement or test was modified to accommodate this.

## D-002 — Detector exposes published surface state, not a raw outcome callback

**Design section:** §Components 1 ("exposes one outbound channel to the editor: a
stream of classified outcomes").

**What was done:** `ChangeDetector` is a `@MainActor ObservableObject` that applies
`absorb` internally (DC-12) and publishes `activeSurface` (`.conflict` / `.deletion`)
plus `displayURL`. The editor binds to that published state rather than mapping a raw
outcome stream itself.

**Why:** SwiftUI surfaces are driven by observable state, not callbacks; publishing
the latched surface is the idiomatic realization of "the editor maps outcomes to
surfaces." Behavior is identical — exactly one surface at a time (DC-5), absorb is
silent (DC-12). The four-outcome classifier (`ExternalChangeOutcome`) remains the
contract; only the delivery mechanism to the UI differs.

## D-003 — Test-injection seam writes to real disk

**Design section:** §High-level shape (coordinated reads).

**What was done:** The UI-test injectors (`injectExternalChange` etc.) land bytes on
the real followed file (and move/remove it) and then route through the same
`handleDidChange`/`handleDidMove`/`handleDidDelete` coordinated-read path the live
`NSFilePresenter` callbacks use, rather than feeding a synthetic situation straight
into the classifier.

**Why:** It exercises the real classify→apply path (including settle re-evaluation
that re-reads disk), so the deterministic UI fixtures match production behavior
instead of bypassing it. Confined to `-uitest-*` launch flags / debug affordances
gated by `-uitest-open-seed-file`; absent in normal runs.

## D-005 — UI-test element/affordance queries broadened to match working precedent (final-verification fix)

**Context:** D-001 noted the build ran without a Swift toolchain, so tests were
verified by inspection only. When the test suite was finally executed on macOS
(`xcodebuild test -scheme Markus_v3 -destination 'platform=iOS Simulator,name=iPhone 17'`),
all 17 executable `ExternalChangeUITests` failed on the same precondition:
`openSeededFile` queried `app.otherElements["RenderedView"]`, which never resolves
the SwiftUI `RenderedView` (a `ScrollView`, not an `.other` element type). The
already-working `ResumeAndCreateUITests` use the broader `descendants(matching:.any)`
query; the `ExternalChange` author used the type-restricted form and made the same
false assumption about UIDocumentBrowserViewController's create affordance.

**Test files affected:** `Markus_v3UITests/ExternalChangeUITests.swift` (the
in-target copy). The spec file in `features/external-change-5/tests/ui/` is left as
the original written contract; the in-target copy is the executable copy the agent
adapts when the seam binding needs adjustment, mirroring D-004.

**What was wrong:**
- `app.otherElements["RenderedView"]` (used by `openSeededFile`, `enterRawEditor`,
  three other call sites) — false assumption: a SwiftUI `ScrollView` with
  `.accessibilityIdentifier("RenderedView")` is not exposed as `.other` to XCUITest.
- `app.buttons["CreateDocument"]` (in `testNormalCreateTypeSaveProducesNoConflictSurfaces`)
  — false assumption: the identifier is "Create Document" (with a space) and the
  affordance can also be a cell, not just a button, across iOS versions.
- `app.otherElements["UIDocumentBrowserView"] || navigationBars["Browse"]`
  (browser-visible check) — false assumption: those are the only two stable
  candidates. `UIDocumentBrowserViewController` exposes itself differently across
  iOS versions; the working resume test probes four candidates.

**What was corrected:**
- Added a `renderedView(in:)` helper that uses
  `app.descendants(matching:.any).matching(identifier:"RenderedView").firstMatch`
  (the exact pattern from `ResumeAndCreateUITests`) and routed all RenderedView
  queries through it.
- Added `tapCreateDocument(in:)` and `browserIsVisible(_:timeout:)` helpers that
  mirror the working precedent in `ResumeAndCreateUITests`.

**Why these are clear test errors, not implementation bugs:** the same SwiftUI
`RenderedView` and the same `UIDocumentBrowserViewController` create flow are
exercised by the already-green `ResumeAndCreateUITests`. The implementation is
correct; the new test queries chose too-narrow forms. Behavioral assertions and
identifiers (`ConflictKeepMine`, `DeletionBannerSaveAs`, etc.) are unchanged. No
requirement, no DC, and no production code was modified.

**Verification:** 16 of 17 executable `ExternalChangeUITests` now pass; 5 remain
intentionally skipped (`XCTSkip`) per verify.md's untestable section. The 17th
(`testDiscardMineDismissesSheet`) was a flake under the full-suite SIGTERM pressure
— passes 3/3 in isolation.

## D-004 — Unit-test outcome mirror replaced by a type alias to the real outcome

**Design / test section:** `tests/unit/ExternalChangeTests.swift` declared a local
`enum ExternalChangeOutcomeKind` mirror with a header note that "the build agent
maps these public seam names onto the real detector symbols when the tasks are
implemented; the contract under test is the outcome, not the wiring."

**What was done:** In the copied Xcode-target test
(`Markus_v3Tests/ExternalChangeTests.swift`) the local mirror was replaced with
`typealias ExternalChangeOutcomeKind = ExternalChangeOutcome` so the assertions bind
to the real four-case enum vended by `ChangeClassifier` / `ApplyEdgeRevalidation` /
`ChangeDetector`. No assertion changed. The mirror's `.suppressed` case was unused by
any assertion (suppression is observed via `SettleGate.isSuppressed` returning Bool),
so dropping it is inert.

**Why:** This is the exact seam-binding the spec-test header anticipates; it lets the
tests assert against the production type rather than a parallel mirror. Mirrors the
`editor-foundation-4` precedent where copied spec tests were adapted to real
initializers.
