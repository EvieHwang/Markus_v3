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
