# Build Deviations — restore-system-create-7

Living log of places where the build had to deviate from `design.md` or
adapt the `tests/` spec test suite while implementing the DAG. Each entry
flows back as a candidate finding into the next `/adversarial` pass per
the build skill.

## D-1 — `LaunchResumeBranch.swift` UI-test seed helpers used `LocalDocumentsFallback`

- **Wave / task:** Wave 1 → surfaced during Wave 2 (T-004).
- **Design section contradicted / under-spec:** `design.md` "Components being removed → C7 LocalDocumentsFallback" lists only the `Create/` call sites of `LocalDocumentsFallback`. It did not anticipate that `Markus_v3/Resume/LaunchResumeBranch.swift`'s `seedSampleAndRecord` and `removeSeededSample` helpers also called `LocalDocumentsFallback.documentsDirectory()` to locate the UI-test seed file.
- **What was done instead:** Inlined the `FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)` call directly into both helpers. No new helper added; the behavior is identical (both call sites resolve to the same app-Documents URL the removed type vended). The two-line duplication is acceptable since the type is gone for good.
- **Why:** Restoring compilation is non-optional; the alternative was to retain `LocalDocumentsFallback` purely for resume-test seeding, which would have violated AC-5.4 (no call site references the removed components).
- **Behavioral impact:** None. Resume-on-launch and UI-test seeding behave identically.

## D-2 — Spec tests adapted to actual codebase API

- **Wave / task:** Wave 2 (T-004 + T-005).
- **Design section contradicted / under-spec:** `features/restore-system-create-7/tests/*.swift` were authored against an aspirational API (`LastFileStore.shared`, `LaunchResumeBranch().resolveResumeTarget()`, `DocumentOpenObserver.shared.recordOpen(url:)`, `DocumentView.initialMode(forContent:byteSize:)`, `DocumentView.initialMode(forFile:)`) that does not match the live codebase. `verify.md` explicitly notes this: *"these files are not bundled into the Xcode test target. The build implementer mirrors them into `Markus_v3Tests/` and `Markus_v3UITests/` when picking up each DAG task, adjusting accessibility identifiers and helper imports to match the live host."*
- **What was done instead:**
  - **`LastFileStore.shared` → `LastFileStore()` instance.** `LastFileStore` is a `nonisolated final class` keyed on `UserDefaults.standard` with default keys, so every `LastFileStore()` instance reads/writes the same underlying record. The spec tests' semantic of "one shared store" is preserved without adding a singleton.
  - **`LastFileStore.shared.record(url:) / .clear() / .hasRecord`** mapped to the live `recordLastOpened(_:)` API plus `UserDefaults.standard.removeObject(forKey:)` for clear and `defaults.data(forKey:) != nil` for `hasRecord`.
  - **`LaunchResumeBranch().resolveResumeTarget()`** rewritten as a call to `LastFileStore().resolveLastOpened()` — the live API surface for "what would resume into?" without the side effect of actually presenting a view controller. The behavioral assertion (a recorded URL is the resume target; an unresolvable record yields nil and is retained) is preserved.
  - **`DocumentOpenObserver.shared.recordOpen(url:)`** rewritten as a direct `LastFileStore().recordLastOpened(url)` call. Production code wires `DocumentOpenObserver.install()` to forward `host.didOpenDocument` through `LastFileStore.recordLastOpened`, so the observable behavior is identical.
  - **`DocumentView.initialMode(forContent:byteSize:)` and `DocumentView.initialMode(forFile:)`** added as static helpers on `DocumentView` exposing the same decision the `.onAppear` block applies. This is the seam DC-4 names; the helpers exist solely to let the rule be tested at the unit level (in addition to the live `.onAppear` integration path).
- **Why:** The spec tests' behavioral observables are correct (DC-1/DC-2/DC-3/DC-4/DC-5/DC-6/DC-7 contracts), only their API hooks were wrong. Rewriting the implementation to match a fictional API would have produced a worse-shaped codebase. Adapting the tests to the real shapes preserves the load-bearing assertions and the requirement-to-test trace recorded in `verify.md`.
- **Behavioral impact:** None. Every adapted test asserts the same observable as the spec original; only the call shapes used to drive and observe the system differ.

## D-3 — `RemovedComponentsTests.noResidualSymbolReferences` scope

- **Wave / task:** Wave 2 (T-004) — implementation note for the mirrored test.
- **Detail:** The spec's `grepSwiftSources(under: "Markus_v3", containingAny:)` walks every `.swift` file under `Markus_v3/` and checks for the removed symbol names. After Wave 2 T-004 deletes `CreateDocumentHandler.swift` and rewrites the create-delegate body in `BrowserHostController.swift`, no `.swift` file under `Markus_v3/` mentions any of the removed types. The mirrored test runs the same probe and is expected to pass after T-004. This is not a deviation; it is a confirmation that the test will start passing only at the right wave.
