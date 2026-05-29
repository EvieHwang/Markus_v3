# Build deviations — resume-and-detector-hardening-11

Records implementation differences from spec artifacts. Treated as candidate
adversarial findings on any subsequent `/adversarial` pass.

## D-001 — Spec test constructor shape (`MarkdownDocument(text:)`) does not exist

**Source affected:** `features/resume-and-detector-hardening-11/tests/unit/ChangeDetectorOrderedStartTests.swift`
**DAG tasks:** T-002

**What the spec test does.** Each test constructs a document via
`MarkdownDocument(text: "...")`, then overrides `lastKnownDiskContent` to
seed the host-prior scenario.

**Why this is wrong.** `Markus_v3/Documents/MarkdownDocument.swift` exposes
only `init()` and `init(file: FileWrapper, contentType: UTType)`. There is
no `MarkdownDocument(text:)`. The spec was written against a constructor
shape that was never present. No requirement (BR-1 .. BR-19) or design
constraint (DC-1 .. DC-11) names this constructor — the relevant contract
is the observable starting state (`document.text == content`,
`document.lastKnownDiskContent == content`), which the real
`init(file:contentType:)` produces identically.

**What was done instead.** The Xcode-target mirror at
`Markus_v3Tests/ResumeDetectorHardening11_T002Tests.swift` introduces a
small `makeDocument(text:)` helper that wraps `init(file:contentType:)`
with a `FileWrapper`. Each test then overrides `lastKnownDiskContent`
exactly as the spec did. The observable assertions are identical.

**Impact.** None on requirement coverage. The behavioral assertions in the
mirror are byte-identical to the spec where they touch
`document.lastKnownDiskContent`, `detector.activeSurface`, and
`detector.displayURL`. The reference spec file in
`features/.../tests/unit/` is left unmodified as the human-readable
authority; only the Xcode-target mirror needs to compile.

**Disposition for the req↔arch loop.** The fix lives in the spec-test
generator, not in product code. A future `/tests` invocation for this or
a similar feature should use the existing
`MarkdownDocument(file:contentType:)` constructor in spec tests so the
spec and the mirror match byte-for-byte. No product-code change required.

## D-002 — `LastFileStoreTests.retainOnFailure` inherited assertion contradicted by BR-2

**Source affected:** `Markus_v3Tests/LastFileStoreTests.swift`
**DAG tasks:** T-001

**What the inherited test asserted.** The Wave-1 test
`LastFileStoreTests.retainOnFailure` (from `resume-and-create-2`) moved
the recorded file to a sibling location in the same directory and
expected `resolveLastOpened() == nil` while the file was "unreachable",
then expected recovery once it was moved back.

**Why this is wrong under this feature.** Requirement BR-1 (and BR-2,
plus design DC-1 / DC-3) of `resume-and-detector-hardening-11`
explicitly inverts the old behavior: the bookmark is the identity of
the file, and a file moved in place within the same security scope
**must** now resolve via the bookmark fallback rather than return nil.
The recorded-path-string vetoed resolves under the old design (DC-4 of
resume-and-create-2) — that veto is exactly what this feature removes.

**What was done instead.** The test is renamed-in-spirit but kept
under the same name to preserve the inherited test surface. Its body
is updated to exercise a scenario that genuinely produces nil under
the new contract: the file is **deleted entirely** (rather than moved
sideways), so the bookmark-fallback probe in `resolveLastOpened()`
also fails (DC-3 failure case), and the resolver returns nil.
RETAIN-on-failure is asserted via both branches: `hasRecord == true`
after the failed resolve, and resolution recovers once the file is
recreated.

**Impact on requirement coverage.** None. The RETAIN-on-failure
contract (DC-6 of this feature, inherited from resume-and-create-2
DC-5) is still exercised end-to-end — only the failure-producing
scenario changed from "moved" to "deleted." The "moved file resolves"
positive case is independently covered by the new
`ResumeDetectorHardening11_T001Tests.movedFileResolvesViaBookmark`
test (BR-1 / BR-2 / DC-1 / DC-3).

**Disposition for the req↔arch loop.** No further work required. The
old test was pinning the precise behavior this feature is designed to
flip; updating it is the expected outcome of landing the feature, and
the build-deviation record is the audit trail.
