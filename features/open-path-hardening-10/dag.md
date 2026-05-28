# DAG: open-path-hardening-10

Five tasks across three waves convert the open path from "any failure → silent
return `nil`" into a gated pipeline whose every terminal state is either a
presented document or a presented `ActiveAlert`. Wave 1 introduces leaf seams
(the four new alert cases + their copy, and the size-ceiling constant). Wave 2
adds the decode/BOM rules on `MarkdownDocument` and the pure classification +
failure-mapping logic. Wave 3 integrates the pipeline into
`BrowserHostController`, binds the alert to its root host view, and pulls the
resume path through the same gate.

Source artifacts:
- `features/open-path-hardening-10/requirements.md` (BR-1 … BR-16)
- `features/open-path-hardening-10/design.md` (DC-1 … DC-11)
- `features/open-path-hardening-10/verify.md` (Status §"reference seams … to introduce")

---

## Size check

5 tasks across 3 waves. Fits one screen. No new framework / dependency / deploy
path is introduced — every component is a Swift extension of an existing
in-repo seam (`ActiveAlert`, `MarkdownDocument`, `BrowserHostController`). No
split required.

---

## Tasks

### T-001 — Extend `ActiveAlert` with the four open-path failure cases + user-facing copy

**Wave:** 1

**Description:**
Add four cases to the existing `ActiveAlert` enum so the open-path failure
surfaces ride the same `.alert(item:)` channel `external-change-5` and
`save-bridge-hardening-9` already use (DC-6, BR-5.1): `.permissionDenied`,
`.fileMovedOrRemoved`, `.couldNotReadFile`, `.tooLarge`. The encoding-error
surface reuses the existing `.invalidEncoding` case (DC-2) — do not introduce
a parallel case. Expose `OpenPathAlertCopy.message(for: ActiveAlert) -> String`
returning the user-facing text per DC-7 wording, with each of the five cases
(four new + `.invalidEncoding`) returning a string distinguishable from the
others. All strings pass through `String(localized:)`. No new view component,
banner, toast, or sheet is introduced.

**Files touched:**
- `Markus_v3/Views/ActiveAlert.swift` (or wherever `ActiveAlert` currently lives)
- `Markus_v3/OpenPath/OpenPathAlertCopy.swift` (new)

**Inputs:**
- `design.md` DC-6, DC-7
- `requirements.md` BR-2.5, BR-3.2, BR-5.1

**Outputs:**
- `ActiveAlert` with cases `.permissionDenied`, `.fileMovedOrRemoved`,
  `.couldNotReadFile`, `.tooLarge` added (existing cases preserved).
- `OpenPathAlertCopy.message(for:)` returning five distinguishable strings.

**Dependencies:** none

**Acceptance condition:**
`xcodebuild test` passes for the mirrored test bodies of
`AlertHostAndScopeTests.allFourFailureCasesAreActiveAlertCases` and
`LoadFailureMappingTests.alertTextsAreDistinguishablePerCase`. The
`ActiveAlert` source file contains exactly the four new cases (no parallel
banner/sheet type added). `OpenPathAlertCopy.message(for:)` returns a
non-empty string for each of `.permissionDenied`, `.fileMovedOrRemoved`,
`.couldNotReadFile`, `.tooLarge`, and `.invalidEncoding`, and all five
strings are pairwise distinct.

---

### T-002 — Introduce `OpenPathSizeCeiling` with the 20 MiB inclusive constant

**Wave:** 1

**Description:**
Add an `OpenPathSizeCeiling` namespace (caseless enum or struct) exposing
`maxBytes: Int = 20 * 1024 * 1024` (= 20 971 520) and
`admits(byteSize: Int) -> Bool` returning `byteSize <= maxBytes` per DC-5's
inclusive boundary. The constant is design-fixed and not user-configurable
(OOS-6). No file I/O happens in this task — it is a pure constant + predicate
that downstream classification (T-004) and integration (T-005) consume.

**Files touched:**
- `Markus_v3/OpenPath/OpenPathSizeCeiling.swift` (new)

**Inputs:**
- `design.md` DC-5
- `requirements.md` BR-4.3, BR-4.6, BR-7

**Outputs:**
- `OpenPathSizeCeiling.maxBytes = 20_971_520`
- `OpenPathSizeCeiling.admits(byteSize:) -> Bool` with inclusive semantics.

**Dependencies:** none

**Acceptance condition:**
`xcodebuild test` passes for the mirrored test bodies of
`SizeCeilingTests.ceilingIsAFixedConstantHonoringDesignValue`,
`SizeCeilingTests.exactlyAtCeilingIsAccepted`, and
`SizeCeilingTests.oneByteOverCeilingIsRejected`. `maxBytes` equals exactly
`20_971_520`; `admits(byteSize: 20_971_520)` returns `true`;
`admits(byteSize: 20_971_521)` returns `false`.

---

### T-003 — `MarkdownDocument` strict UTF-8 decode with BOM retention + render-time suppression

**Wave:** 2

**Description:**
Adjust the `MarkdownDocument` load path so non-UTF-8 bytes throw the existing
`DocumentError.invalidEncoding` (no lossy decode, no `U+FFFD` substitution
ever reaches the buffer — DC-2). For a file whose first three bytes are
`EF BB BF` followed by valid UTF-8, retain those three bytes in the in-memory
buffer (BR-1.3, DC-3) so a no-edit save round-trips byte-identically. Update
the rendered/raw view path so a leading `U+FEFF` is not displayed as a visible
character (suppression at render — DC-3). Do not touch the save side
(OOS-4): the buffer is what the existing save writes; because the BOM is in
the buffer, the existing save round-trips it without code change. An empty
file (zero bytes) continues to open as an empty buffer (BR-6).

**Files touched:**
- `Markus_v3/Document/MarkdownDocument.swift`
- `Markus_v3/Views/RenderedView.swift` and/or
  `Markus_v3/Editor/MarkdownEditorTextView.swift` (whichever surface presents
  the buffer's leading character — BOM suppression at render only)

**Inputs:**
- `design.md` DC-2, DC-3
- `requirements.md` BR-1.2, BR-1.3, BR-2.1, BR-2.2, BR-6, BR-9, BR-10, BR-11

**Outputs:**
- `MarkdownDocument` init throws `.invalidEncoding` for any byte sequence that
  is not strict UTF-8 (no `U+FFFD` substitution).
- For BOM-prefixed UTF-8 input, the in-memory buffer's first three bytes when
  encoded back to UTF-8 are `EF BB BF`.
- The rendered output does not show the BOM as a visible character.

**Dependencies:** none (decode and render-suppression are internal to
`MarkdownDocument` + its presenting views; they do not depend on T-001 or
T-002).

**Acceptance condition:**
`xcodebuild test` passes for the mirrored test bodies of
`HappyPathOpenTests.bufferMatchesOnDiskAfterNormalization`,
`HappyPathOpenTests.bomPrefixedFileOpensAndRetainsBomBytes`,
`HappyPathOpenTests.bomIsNotRenderedAsVisibleCharacter`,
`HappyPathOpenTests.noEditSaveOfBomFileIsByteIdentical`,
`HappyPathOpenTests.emptyFileOpensWithEmptyBuffer`,
`HappyPathOpenTests.happyPathLatencyIsWithinBudget`,
`NonUTF8DecodePolicyTests.noPresentedBufferContainsReplacementCharacter`.
No presented buffer contains `U+FFFD` on any non-UTF-8 input under test;
a BOM-prefixed file's buffer encodes back with leading `EF BB BF`.

---

### T-004 — Open-path classification + failure mapper + load-result enum

**Wave:** 2

**Description:**
Introduce the pure (non-`@MainActor`, no I/O on the hot path) classification
seams the integration in T-005 consumes:

- `OpenPathLoadResult` — two-case enum `.document(MarkdownDocument)` /
  `.alert(ActiveAlert)` per verify.md §Status. Type-level proof of "no
  silent-nil outcome" (BR-3.5).
- `OpenPathLoadPipeline.classify(byteSize:bytesForDecodeProbe:) ->
  .ok | .tooLarge | .invalidEncoding` — the size-first, then decode ordering
  contract from DC-4. Returns `.tooLarge` when `byteSize > maxBytes` without
  ever inspecting `bytesForDecodeProbe`; returns `.invalidEncoding` only when
  size is admitted but the bytes do not decode as strict UTF-8; returns `.ok`
  otherwise.
- `OpenPathLoadPipeline.failureResult(for: Error) -> OpenPathLoadResult` — a
  thin shim around `OpenPathFailureMapper.alert(for:)` returning
  `.alert(...)`.
- `OpenPathFailureMapper.alert(for: Error) -> ActiveAlert` — the
  deterministic OS-error → `ActiveAlert` table from DC-8:
  - `NSFileNoSuchFileError` / `NSFileReadNoSuchFileError` / POSIX `ENOENT`
    → `.fileMovedOrRemoved`
  - `NSFileReadNoPermissionError` / POSIX `EACCES`, `EPERM` →
    `.permissionDenied`
  - `DocumentError.invalidEncoding` → `.invalidEncoding`
  - Any other `Cocoa` / POSIX file-read error (including
    `NSFileReadUnknownError`, `EIO`, framework-internal) →
    `.couldNotReadFile`

No file I/O lives in this task. The integration that wires the pipeline to
the live security-scoped read is T-005.

**Files touched:**
- `Markus_v3/OpenPath/OpenPathLoadResult.swift` (new)
- `Markus_v3/OpenPath/OpenPathLoadPipeline.swift` (new)
- `Markus_v3/OpenPath/OpenPathFailureMapper.swift` (new)

**Inputs:**
- `design.md` DC-1, DC-2, DC-4, DC-8
- `requirements.md` BR-3.1, BR-3.2, BR-3.5, BR-4.1, BR-4.2

**Outputs:**
- `OpenPathLoadResult` enum with `.document` / `.alert` cases.
- `OpenPathLoadPipeline.classify(byteSize:bytesForDecodeProbe:)` honoring
  size-first ordering.
- `OpenPathFailureMapper.alert(for:)` returning the DC-8 table values
  deterministically; unrecognized errors fall through to `.couldNotReadFile`.

**Dependencies:** T-001 (`ActiveAlert` cases referenced), T-002
(`OpenPathSizeCeiling.maxBytes` referenced), T-003
(`DocumentError.invalidEncoding` semantics relied on by the mapper).

**Acceptance condition:**
`xcodebuild test` passes for the mirrored test bodies of
`LoadFailureMappingTests.permissionDeniedErrorMapsToPermissionAlert`,
`LoadFailureMappingTests.noSuchFileErrorMapsToMovedRemovedAlert`,
`LoadFailureMappingTests.unknownReadErrorMapsToGenericAlert`,
`LoadFailureMappingTests.callerConvertsEveryFailureToAlert`,
`SizeCeilingTests.sizeCheckPrecedesDecodeForOversizedBinaryFiles`,
`SizeCeilingTests.oversizedFileIsRejectedWithoutFullRead`,
`NonUTF8DecodePolicyTests.nonUTF8LatinFileSurfacesEncodingAlertAndPresentsNoDocument`,
`NonUTF8DecodePolicyTests.utf16BomFileSurfacesEncodingAlert`,
`NonUTF8DecodePolicyTests.mixedEncodingFileSurfacesEncodingAlertAndPresentsNoTruncatedDocument`,
`NonUTF8DecodePolicyTests.everyNonUTF8InputProducesAnAlertNotASilentReturn`.
`classify` never reads `bytesForDecodeProbe` when `byteSize > maxBytes`
(observable via test fixture that passes an empty `Data` for the decode
probe and still gets `.tooLarge`).

---

### T-005 — Integrate the pipeline into `BrowserHostController` (alert host, scope, resume gate, prior-document safety)

**Wave:** 3

**Description:**
Replace `BrowserHostController.loadMarkdownDocument`'s catch-into-`nil` with
the four-stage gated pipeline from design §High-level shape:
(1) scope-acquire, (2) attribute-only size pre-check via
`OpenPathSizeCeiling.admits(byteSize:)`, (3) coordinated bytes read,
(4) strict UTF-8 decode via the `MarkdownDocument` init from T-003. Every
non-success terminal calls `OpenPathFailureMapper.alert(for:)` (T-004),
writes the result to a new `BrowserHostController.openPathAlert: ActiveAlert?`,
and releases the security-scoped resource it acquired (DC-9, BR-3.3, BR-4.5,
BR-15). Bind a `.alert(item: $openPathAlert)` modifier to the
`BrowserHostController` root host view so the alert is on screen in every
browser-idle state including cold launch with no document yet presented
(DC-6a, F-002). The existing `DocumentView.activeAlert` channel is left
unchanged for running-document surfaces. A failure on a second pick must not
tear down the previously-presented document (DC-10, BR-3.4): the new alert
state lives on the host, not the editor; explicitly assert the host does not
clear `activeDocument` on a failed second pick. Expose
`BrowserHostController.activeDocument: MarkdownDocument?` (read-only) and the
test-only `OpenPathScopeAudit.acquiredCount(for: URL) -> Int` introspection
required by verify.md §Status. The resume entry point (BR-16, DC-11) calls
into the same pipeline; the bookmark-fallback resolution upstream
(`resume-and-detector-hardening-11`) is assumed to have run before the URL
reaches the pipeline (ordering contract in DC-11). A directory or non-regular
URL that reaches the pipeline must produce a `.couldNotReadFile` alert rather
than crash on read (BR-14). A symlink whose target is missing surfaces
`.fileMovedOrRemoved` (BR-13). iCloud-not-yet-downloaded continues to use
the existing `iCloudDownloadFailed` surface — this feature does not replace it
(BR-12).

**Files touched:**
- `Markus_v3/Browser/BrowserHostController.swift`
- `Markus_v3/Views/BrowserHostView.swift` (or wherever the
  `BrowserHostController`'s root SwiftUI host view lives) — add the
  `.alert(item:)` modifier
- `Markus_v3/OpenPath/OpenPathScopeAudit.swift` (new — test-only
  introspection)

**Inputs:**
- `design.md` DC-1, DC-4, DC-6a, DC-9, DC-10, DC-11
- `requirements.md` BR-3.1, BR-3.3, BR-3.4, BR-3.5, BR-3.6, BR-4.1, BR-4.5,
  BR-8, BR-12, BR-13, BR-14, BR-15, BR-16

**Outputs:**
- `BrowserHostController.loadMarkdownDocument` (or successor) routed through
  the four-stage pipeline; never returns `nil` to the caller without first
  writing an `ActiveAlert` to `openPathAlert`.
- `.alert(item: $openPathAlert)` modifier bound to the host root view, on
  screen during the entire browser-idle lifetime.
- Security-scoped resource released on every terminal path; per-URL
  acquired-count observable via `OpenPathScopeAudit` returns to baseline
  after N failed taps.
- Resume entry point uses the same pipeline.

**Dependencies:** T-001, T-002, T-003, T-004 (consumes every Wave 1 / Wave 2
seam).

**Acceptance condition:**
`xcodebuild test` passes for the mirrored test bodies of
`AlertHostAndScopeTests.failureSurfacesReuseActiveAlertChannel`,
`AlertHostAndScopeTests.coldLaunchFailedPickShowsAlertWithNoDocumentPresented`,
`AlertHostAndScopeTests.scopeIsReleasedOnEveryTerminalPath`,
`AlertHostAndScopeTests.repeatedFailuresOnSameUrlAreIdempotentAndDoNotLeakScope`,
`AlertHostAndScopeTests.priorDocumentSurvivesFailedSecondPick`,
`LoadFailureMappingTests.everyNamedFailureCaseSurfacesAnAlert`,
`LoadFailureMappingTests.dismissReturnsToPickableBrowser`,
`LoadFailureMappingTests.fileVanishingMidLoadProducesMovedOrPermissionAlert`,
`LoadFailureMappingTests.symlinkToMissingTargetSurfacesMovedRemovedAlert`,
`LoadFailureMappingTests.directoryURLSurfacesAFailureAlertNotACrash`,
`LoadFailureMappingTests.iCloudDownloadFailedIsNotReplacedByThisFeaturesSurfaces`,
`NonUTF8DecodePolicyTests.encodingAlertIsDismissableAndReturnsToPickableBrowser`,
`SizeCeilingTests.oversizedFileSurfacesTooLargeAlertAndPresentsNoDocument`,
`HappyPathOpenTests.wellFormedUTF8OpensWithNoAlert`,
`ResumeGateTests.resumeUrlGoesThroughTheSameOpenGate`,
`ResumeGateTests.oversizedResumeTargetSurfacesTooLargeAlert`,
`ResumeGateTests.nonUTF8ResumeTargetSurfacesEncodingAlert`,
`ResumeGateTests.vanishedResumeTargetSurfacesMovedRemovedOrIsRescuedByBookmarkFallback`,
`ResumeGateTests.bookmarkFallbackResolvesBeforeOpenPipelineObservesUrl`,
`OpenPathSilentNoOpUITests.test_wellFormedFile_opensWithoutAlert`,
`OpenPathSilentNoOpUITests.test_everyFailureClass_showsAlertNoSilentReturn`,
`OpenPathSilentNoOpUITests.test_coldLaunchFailedPick_showsAlertOnBrowserHost`.
`OpenPathScopeAudit.acquiredCount(for:)` returns to baseline after a
sequence of N failed taps on the same URL.

---

## Wave summary

| Wave | Tasks | Rationale |
|------|-------|-----------|
| 1 | T-001, T-002 | Leaf seams with no in-feature dependencies — the four new `ActiveAlert` cases + copy, and the 20 MiB ceiling constant. Independent and parallelizable. |
| 2 | T-003, T-004 | T-003 hardens `MarkdownDocument`'s decode + BOM rule (independent of T-001/T-002 but logically belongs alongside the classifier). T-004 builds the pure classification + failure-mapping logic on top of the Wave 1 seams and the `DocumentError.invalidEncoding` semantics from T-003. T-003 and T-004 touch disjoint files and can run in parallel. |
| 3 | T-005 | The integration task — wires the pipeline into `BrowserHostController`, binds the alert to the host root view, threads scope acquire/release, preserves prior-document state, and pulls the resume entry through the same gate. Depends on every Wave 1 / Wave 2 seam. |
