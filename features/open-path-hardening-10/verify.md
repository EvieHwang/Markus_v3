# Verify — open-path-hardening-10

Coverage map from `requirements.md` (BR-1 through BR-16) and `design.md` (DC-1 through DC-11) to the spec tests under `features/open-path-hardening-10/tests/`.

Task ID column is intentionally absent — the DAG does not yet exist. `/dag` (Stage 5) will populate task tagging in a later pass.

## Test files

| File | Framework | Concern |
|------|-----------|---------|
| `HappyPathOpenTests.swift` | Swift Testing | BR-1 well-formed UTF-8 opens unchanged; BR-6 empty file; BR-9 BOM-prefixed UTF-8; DC-3 BOM retained in buffer and suppressed at render; DC-1 success path emits no alert. |
| `NonUTF8DecodePolicyTests.swift` | Swift Testing | BR-2 non-UTF-8 → encoding alert (policy (b)); BR-10 UTF-16 BOM; BR-11 mixed encoding (valid prefix, invalid tail); DC-2 no `U+FFFD` in any presented buffer. |
| `SizeCeilingTests.swift` | Swift Testing | BR-4 size ceiling enforcement; BR-7 exactly-at-ceiling vs one-over; DC-5 20 MiB inclusive boundary; BR-4.2 pre-read gate (no full read for oversized files); DC-4 size precedes decode. |
| `LoadFailureMappingTests.swift` | Swift Testing | BR-3 every load failure surfaces; BR-8 file becomes unreadable mid-load; BR-13 symlink to missing target; BR-14 non-regular URL; DC-8 deterministic OS-error → alert variant mapping with generic fallback; DC-7 alert texts are distinguishable. |
| `AlertHostAndScopeTests.swift` | Swift Testing | DC-6/DC-6a alerts hosted on `BrowserHostController` root view (cold-launch / browser-idle coverage); DC-9 security-scoped resource released on every terminal path; BR-15 idempotent repeat failures; DC-10 prior document survives failed second pick; BR-5.1 reuse of `ActiveAlert` channel (no new surface type). |
| `ResumeGateTests.swift` | Swift Testing | BR-16 resume path uses the same gate; DC-11 ordering contract — bookmark-fallback resolves URL before this feature's pipeline observes it. |
| `OpenPathSilentNoOpUITests.swift` | XCUITest | End-to-end: DC-1 silent-no-op is unreachable. Cold-launch → pick each problem-file class → assert an alert is on screen and dismissable, returning the user to a pickable browser. |

## Coverage matrix

### Behavioral requirements → tests

| BR | Test(s) |
|----|---------|
| BR-1.1 (well-formed UTF-8 opens, no alert/banner/label) | `HappyPathOpenTests.wellFormedUTF8OpensWithNoAlert`, `OpenPathSilentNoOpUITests.test_wellFormedFile_opensWithoutAlert` |
| BR-1.2 (buffer equals on-disk content after normalization) | `HappyPathOpenTests.bufferMatchesOnDiskAfterNormalization` |
| BR-1.3 (BOM-prefixed file opens; BOM retained in buffer, suppressed at render) | `HappyPathOpenTests.bomPrefixedFileOpensAndRetainsBomBytes`, `HappyPathOpenTests.bomIsNotRenderedAsVisibleCharacter`, `HappyPathOpenTests.noEditSaveOfBomFileIsByteIdentical` |
| BR-1.4 (no measurable latency regression on the happy path) | `HappyPathOpenTests.happyPathLatencyIsWithinBudget` |
| BR-2.1 (non-UTF-8 → exactly one surface, design-fixed; choice (b) pinned) | `NonUTF8DecodePolicyTests.nonUTF8LatinFileSurfacesEncodingAlertAndPresentsNoDocument` |
| BR-2.2 (non-UTF-8 never silent no-op) | `NonUTF8DecodePolicyTests.everyNonUTF8InputProducesAnAlertNotASilentReturn` |
| BR-2.3 (n/a — policy (a) not chosen) | Not applicable: DC-2 pins policy (b). The negative is asserted by `NonUTF8DecodePolicyTests.noPresentedBufferContainsReplacementCharacter`. |
| BR-2.4 (dismissable encoding error; no zombie scope; pickable state after dismiss) | `NonUTF8DecodePolicyTests.encodingAlertIsDismissableAndReturnsToPickableBrowser`, `AlertHostAndScopeTests.scopeIsReleasedOnEveryTerminalPath` |
| BR-2.5 (reuses existing `ActiveAlert` channel; no novel surface) | `AlertHostAndScopeTests.failureSurfacesReuseActiveAlertChannel` |
| BR-3.1 (every load failure → alert before browser idle) | `LoadFailureMappingTests.everyNamedFailureCaseSurfacesAnAlert`, `OpenPathSilentNoOpUITests.test_everyFailureClass_showsAlertNoSilentReturn` |
| BR-3.2 (alert text distinguishes the named cases) | `LoadFailureMappingTests.alertTextsAreDistinguishablePerCase` |
| BR-3.3 (dismiss → clean state, scope released, no stale doc) | `AlertHostAndScopeTests.scopeIsReleasedOnEveryTerminalPath`, `LoadFailureMappingTests.dismissReturnsToPickableBrowser` |
| BR-3.4 (failure on second pick does not tear down prior document) | `AlertHostAndScopeTests.priorDocumentSurvivesFailedSecondPick` |
| BR-3.5 (load seam may return nil/throw, but every caller-observed nil → alert) | `LoadFailureMappingTests.callerConvertsEveryFailureToAlert` |
| BR-3.6 (success path shows zero alerts; cross-check BR-1.1) | `HappyPathOpenTests.wellFormedUTF8OpensWithNoAlert` |
| BR-4.1 (oversized → too-large surface; no document) | `SizeCeilingTests.oversizedFileSurfacesTooLargeAlertAndPresentsNoDocument` |
| BR-4.2 (pre-read gate; no measurable memory spike) | `SizeCeilingTests.oversizedFileIsRejectedWithoutFullRead` |
| BR-4.3 (single fixed ceiling, documented in design) | `SizeCeilingTests.ceilingIsAFixedConstantHonoringDesignValue` |
| BR-4.4 (reuses `Conflict & lifecycle UI`) | `AlertHostAndScopeTests.failureSurfacesReuseActiveAlertChannel` |
| BR-4.5 (rejection releases scope) | `AlertHostAndScopeTests.scopeIsReleasedOnEveryTerminalPath` (size case included) |
| BR-4.6 (at-boundary inclusive; +1 strict reject) | `SizeCeilingTests.exactlyAtCeilingIsAccepted`, `SizeCeilingTests.oneByteOverCeilingIsRejected` |
| BR-5.1 (constraint — design review, not behavioral) | Verified by design review + `AlertHostAndScopeTests.failureSurfacesReuseActiveAlertChannel` as the behavioral cross-check. |
| BR-6 (empty file) | `HappyPathOpenTests.emptyFileOpensWithEmptyBuffer` |
| BR-7 (exactly-at-ceiling and one-over) | `SizeCeilingTests.exactlyAtCeilingIsAccepted`, `SizeCeilingTests.oneByteOverCeilingIsRejected` |
| BR-8 (unreadable mid-load) | `LoadFailureMappingTests.fileVanishingMidLoadProducesMovedOrPermissionAlert` |
| BR-9 (BOM-prefixed UTF-8 is not classified non-UTF-8) | `HappyPathOpenTests.bomPrefixedFileOpensAndRetainsBomBytes` |
| BR-10 (UTF-16 BOM) | `NonUTF8DecodePolicyTests.utf16BomFileSurfacesEncodingAlert` |
| BR-11 (mixed encoding — valid prefix, invalid tail) | `NonUTF8DecodePolicyTests.mixedEncodingFileSurfacesEncodingAlertAndPresentsNoTruncatedDocument` |
| BR-12 (iCloud not-yet-downloaded — out of scope; existing surface owns it) | Asserted by absence: `LoadFailureMappingTests.iCloudDownloadFailedIsNotReplacedByThisFeaturesSurfaces` |
| BR-13 (symlink follows to target; missing target → moved/removed) | `LoadFailureMappingTests.symlinkToMissingTargetSurfacesMovedRemovedAlert` |
| BR-14 (directory / non-regular URL → load-failure surface, not crash) | `LoadFailureMappingTests.directoryURLSurfacesAFailureAlertNotACrash` |
| BR-15 (repeated failures are idempotent; no stacked modals, no scope leak) | `AlertHostAndScopeTests.repeatedFailuresOnSameUrlAreIdempotentAndDoNotLeakScope` |
| BR-16 (resume path uses the same load gate) | `ResumeGateTests.resumeUrlGoesThroughTheSameOpenGate`, `ResumeGateTests.oversizedResumeTargetSurfacesTooLargeAlert`, `ResumeGateTests.nonUTF8ResumeTargetSurfacesEncodingAlert`, `ResumeGateTests.vanishedResumeTargetSurfacesMovedRemovedOrIsRescuedByBookmarkFallback` |

### Design seams → tests

| DC | Test(s) |
|----|---------|
| DC-1 (every terminal state is doc or alert; no silent return) | `LoadFailureMappingTests.everyNamedFailureCaseSurfacesAnAlert`, `OpenPathSilentNoOpUITests.test_everyFailureClass_showsAlertNoSilentReturn` |
| DC-2 (decode policy (b): encoding alert, no lossy buffer) | `NonUTF8DecodePolicyTests.nonUTF8LatinFileSurfacesEncodingAlertAndPresentsNoDocument`, `NonUTF8DecodePolicyTests.noPresentedBufferContainsReplacementCharacter` |
| DC-3 (BOM retained, suppressed at render, round-trips on no-edit save) | `HappyPathOpenTests.bomPrefixedFileOpensAndRetainsBomBytes`, `HappyPathOpenTests.bomIsNotRenderedAsVisibleCharacter`, `HappyPathOpenTests.noEditSaveOfBomFileIsByteIdentical` |
| DC-4 (size first, then read errors, then decode) | `SizeCeilingTests.sizeCheckPrecedesDecodeForOversizedBinaryFiles` |
| DC-5 (ceiling = 20 MiB inclusive) | `SizeCeilingTests.exactlyAtCeilingIsAccepted`, `SizeCeilingTests.oneByteOverCeilingIsRejected`, `SizeCeilingTests.ceilingIsAFixedConstantHonoringDesignValue` |
| DC-6 (four failure cases through `ActiveAlert`; no new UI grammar) | `AlertHostAndScopeTests.failureSurfacesReuseActiveAlertChannel`, `AlertHostAndScopeTests.allFourFailureCasesAreActiveAlertCases` |
| DC-6a (alert host is `BrowserHostController` root view, on screen during browser-idle) | `AlertHostAndScopeTests.coldLaunchFailedPickShowsAlertWithNoDocumentPresented`, `OpenPathSilentNoOpUITests.test_coldLaunchFailedPick_showsAlertOnBrowserHost` |
| DC-7 (alert texts are distinguishable enough to act) | `LoadFailureMappingTests.alertTextsAreDistinguishablePerCase` |
| DC-8 (deterministic OS-error → variant; generic fallback) | `LoadFailureMappingTests.permissionDeniedErrorMapsToPermissionAlert`, `LoadFailureMappingTests.noSuchFileErrorMapsToMovedRemovedAlert`, `LoadFailureMappingTests.unknownReadErrorMapsToGenericAlert` |
| DC-9 (scope released on every terminal path) | `AlertHostAndScopeTests.scopeIsReleasedOnEveryTerminalPath`, `AlertHostAndScopeTests.repeatedFailuresOnSameUrlAreIdempotentAndDoNotLeakScope` |
| DC-10 (failed later pick does not tear down prior document) | `AlertHostAndScopeTests.priorDocumentSurvivesFailedSecondPick` |
| DC-11 (resume uses the same gate; bookmark fallback resolves first) | `ResumeGateTests.resumeUrlGoesThroughTheSameOpenGate`, `ResumeGateTests.bookmarkFallbackResolvesBeforeOpenPipelineObservesUrl` |

## Notes on technique

- **Behavioral framing.** Every test asserts an observable: an alert is presented, a buffer is non-nil/equals bytes, a security-scope count returns to baseline, a file is or is not present, an alert text is or is not the encoding text. No test asserts call signatures, private storage, or constructor argument lists. The seam contracts (DC-*) are exercised via their public side effects on `BrowserHostController` / `MarkdownDocument` / `ActiveAlert`.
- **Reference-only.** Per `constitution.md`, these files are reference / human-readable specs. The build implementer mirrors them into `Markus_v3Tests/` (Swift Testing) and `Markus_v3UITests/` (XCUITest) when picking up matching DAG tasks. They are not bundled into the Xcode test target as-is.
- **Failing-by-default.** The tests reference symbols that do not yet exist on `BrowserHostController` (an open-path `ActiveAlert` accessor, a public size-ceiling constant, a public scope-acquire count for test introspection). They will fail to compile or skip until the build introduces those seams — that failure is the gate the build agent uses to confirm the right module is being touched.
- **Generated-fixtures over checked-in binaries.** Oversized fixtures (20 MiB + 1) are synthesized in `setUp` rather than committed, so the repo stays small. Tests that require a 500 MB file are tagged with a `largeFixture` trait so they can be skipped in fast runs but exercised on the device.
- **OS-error injection.** `LoadFailureMappingTests` injects errors through a lightweight protocol-shaped seam (a file-reader the test substitutes) rather than mocking `URL` itself. The behavioral assertion is on the resulting `ActiveAlert` case, not on which line of the pipeline threw.

## Untestable requirements

None. All BR-* lines are testable as written. BR-5.1 is a design-review constraint (no novel UI surface invented) and is verified by the design review + the behavioral cross-check `failureSurfacesReuseActiveAlertChannel`, which asserts each failure surface arrives as an `ActiveAlert` case rather than a new view type.

## Status

Tests written under `features/open-path-hardening-10/tests/`. Reference seams these tests bind to but that the build still has to introduce:

- `ActiveAlert.permissionDenied`, `.fileMovedOrRemoved`, `.couldNotReadFile`, `.tooLarge` — three new cases on the existing enum (DC-6).
- `OpenPathSizeCeiling` — namespace exposing `maxBytes` and `admits(byteSize:)` (DC-5).
- `OpenPathLoadPipeline` — namespace exposing `classify(byteSize:bytesForDecodeProbe:) -> .ok | .tooLarge | .invalidEncoding` and `failureResult(for:) -> OpenPathLoadResult` (DC-4, DC-8, BR-3.5).
- `OpenPathLoadResult` — two-case enum `.document(MarkdownDocument)` / `.alert(ActiveAlert)`; type-level proof of "no silent-nil outcome" (BR-3.5).
- `OpenPathFailureMapper.alert(for: Error) -> ActiveAlert` — the deterministic OS-error → variant table from DC-8.
- `OpenPathAlertCopy.message(for: ActiveAlert) -> String` — the user-facing text exposed for DC-7 distinguishability assertions.
- `OpenPathScopeAudit.acquiredCount(for: URL) -> Int` — test-only introspection for DC-9 / BR-15.
- `BrowserHostController.openPathAlert: ActiveAlert?` and `BrowserHostController.activeDocument: MarkdownDocument?` — host-level seams for the integration tests (DC-6a, DC-10).

These are the seams the build agent introduces in early DAG waves; the tests will compile-fail until they exist, which is the expected gate.
