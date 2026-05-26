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
