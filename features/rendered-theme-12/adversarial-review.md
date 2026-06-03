# Adversarial Review — Rendered Theme Polish (rendered-theme-12)

requirements.md @ f5b9ada4ea17f01d684224fc605a7c53ee44b1a2 · design.md @ e7b7223e11ba07020508629734470daa2364b5a3 · fresh review

---

## Open Findings

### F-001 — `.isHeader` trait preservation has no acceptance criterion
**Severity:** MEDIUM
**Lens:** Coverage

**Finding:**
Requirements out-of-scope section states "accessibilityAddTraits(.isHeader) is already present on heading builders and must be preserved." The design's component table likewise notes "each heading retains `.isHeader` accessibility trait." However, no acceptance criterion (US-8 or elsewhere) and no failure mode (FM-1 through FM-8) captures this constraint. A developer who replaces the heading builder blocks during migration without including `.accessibilityAddTraits(.isHeader)` would violate this stated requirement, but no stated AC would fail. The constitution requires WCAG 2.1 AA compliance; headings that lose `.isHeader` break VoiceOver heading navigation, which is a WCAG 1.3.1 (Info and Relationships) failure.

**Recommended action:** requirements — add an acceptance criterion under US-8 (or a new user story) requiring that `.isHeader` is present on each heading builder, and add a corresponding FM entry (e.g., FM-9) stating that removing `.isHeader` from any heading builder is a violation.

**Status:** addressed — AC-8.5 and FM-9 added to requirements.md.

---

### F-002 — Heading margin behavior after migration is unspecified
**Severity:** LOW
**Lens:** Coverage

**Finding:**
The current `makeTheme()` implementation sets `markdownMargin(top: 24, bottom: 16)` on every heading builder (H1–H6). The design's behavioral constraints (BC-9) specify only heading font size and hierarchy. The design's code sketch shows only `.text { ... }` and `.heading1 { ... }` without addressing whether the explicit margin calls are retained or dropped. If retained, heading margins stay at 24/16 pt regardless of what `Theme.gitHub` provides. If dropped, heading margins change to whatever `Theme.gitHub` defines. Both are valid under the current spec — but the visual result differs, and neither requirements nor design names the correct outcome. The "no visual regression" requirement (US-9) covers inline styles only and does not extend to heading margins.

**Recommended action:** requirements — add a sentence to US-8 or US-9 specifying whether heading margins are (a) preserved at their current values, (b) delegated to `Theme.gitHub`, or (c) left as an implementation choice. If (c) is acceptable, that should be stated explicitly so a reviewer knows ambiguity is intentional.

**Status:** addressed — AC-8.6 added to requirements.md, specifying that heading margins are delegated entirely to Theme.gitHub (no markdownMargin overrides in heading builders).

---

## Prescription Feedback

The following design-section details are implementation prescriptions rather than behavioral constraints. They are recorded here for awareness but do not constitute findings because their subjects cannot be traced to declared behavioral requirements.

| Note | Design section |
|------|---------------|
| The chaining pattern (`Theme.gitHub.text { }.heading1 { }...`) is the specific API call sequence. The behavioral requirement (BC-1 through BC-13) is that the rendered output matches `Theme.gitHub` styling for unoverridden elements — the exact call syntax is an implementation detail. | "Architectural Approach: Theme.gitHub Chaining" |
| `FontProperties(family: .system(), size: baseSize)` is the specific constructor and argument for the `text` override. The behavioral requirement (BC-8, AC-8.1) is that the body point size equals `UIFont.preferredFont(forTextStyle: .body).pointSize`; the exact API shape is an implementation detail. | "Components and Responsibilities" — `text` override row |
| The `RenderedViewTypographyProbe` type name and the specific test file `NativePolish6_TypographyAndMaterialTests.swift` are implementation prescriptions. The behavioral requirement is that `bodyFont()` and `headingFont(level:)` remain public static methods with their current contracts (AC-8.1, AC-8.2). | "Tests That Must Continue to Pass" |

---

## Passing Lenses

**Integrity:** Every US (1–9) has a corresponding behavioral constraint in the design (BC-1 through BC-13). Every FM (1–8) in requirements maps to a named constraint or "What This Architecture Does Not Do" item in design. No requirements gap identified beyond F-001 and F-002 above.

**Security:** No security surface. The feature changes a pure visual theme value; no user input is parsed, no network calls are made, no file system access is added. No OWASP findings applicable.

**Standards compliance:** WCAG 2.1 AA contrast for link colors (AC-5.1, AC-5.2) is delegated to `Theme.gitHub`, which targets the same GitHub blue values used by GitHub's own accessible interfaces. The delegation is reasonable given the library is a consumer-grade dependency with its own accessibility posture. F-001 above covers the only concrete WCAG gap introduced by the migration.

**Scope drift:** None. Requirements, design, and declaration all name `MarkdownThemeFactory.swift` as the sole file changed. The design explicitly lists what it does not do. No new types, protocols, or behaviors are introduced beyond the stated theme-base substitution.

**Failure modes:** FM-1 through FM-8 in requirements are well-formed and non-overlapping. The design's "What This Architecture Does Not Do" section reinforces FM-5 and FM-6. No additional concrete failure mode identified beyond those already named.
