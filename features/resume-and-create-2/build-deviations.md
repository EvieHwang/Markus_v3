# Build deviations — resume-and-create-2

Records concrete deviations from `design.md` and the test-file shape in
`features/resume-and-create-2/tests/` made during the build. The canonical
behavioral spec (`requirements.md`) is unchanged.

---

## D-001 — Unit-test file split per component (Wave 1)

**What changed.** The canonical unit-test spec at
`features/resume-and-create-2/tests/unit/ResumeAndCreateTests.swift` bundles
four suites (`NameProbeTests`, `LocalDocumentsFallbackTests`,
`CreateTargetResolverTests`, `LastFileStoreTests`) into one file. Because the
file is copied/adapted into the `Markus_v3Tests` Xcode target (the synchronized
folder pattern used for actual test execution; the `features/` tree is *not* a
target), shipping it as a single file in Wave 1 would force a compile error:
`CreateTargetResolverTests` references `CreateTargetResolver` and
`LastDirectoryProviding`, which land in Wave 2 (T-004).

**What we did instead.** Split the file into one Swift Testing file per
component in `Markus_v3Tests/`:

- `Markus_v3Tests/LastFileStoreTests.swift` (T-001, Wave 1)
- `Markus_v3Tests/NameProbeTests.swift` (T-002, Wave 1)
- `Markus_v3Tests/LocalDocumentsFallbackTests.swift` (T-003, Wave 1)
- `Markus_v3Tests/CreateTargetResolverTests.swift` (T-004, Wave 2 — added in
  Wave 2)

The canonical spec file at `features/resume-and-create-2/tests/unit/...` is
left intact; it remains the human-readable reference for the contracts each
suite verifies. The split is organizational only — every test method, every
assertion, every `@Test` label, and every requirement coverage is preserved.

**Why.** Each wave can land its tests without referencing later-wave symbols,
so the per-wave `xcodebuild test` runs that `/next` performs are not blocked
by unrelated compile errors. This is the same precedent the
`editor-foundation-4` build set when it adapted spec tests into the Xcode
target (`build-deviations.md` D-001/D-002 there) — adopting the same shape
here keeps the test-target layout consistent across features.

**Impact on verify.md.** None. `verify.md` names test methods (e.g.
`LastFileStoreTests` → `recordAndResolve`), not files. The methods exist
under the same suite names with the same behavior, just in per-component
files.
