# Verify — Rendered Theme Polish (rendered-theme-12)

Spec tests: `features/rendered-theme-12/tests/RenderedTheme12Tests.swift`

> **Note:** Task → test mapping will be added by the DAG stage. Placeholder rows are marked `(DAG TBD)` below.

---

## Coverage Summary

### Coverage strategy

Block-element visual behaviors (US-1 through US-7, BC-1 through BC-7) are
fulfilled by `Theme.gitHub` through the *absence* of custom overrides.
They cannot be asserted in pure unit tests without a UI host. The unit-level
proxy for each of these requirements is a source-structural assertion: verifying
that `MarkdownThemeFactory.swift` uses `Theme.gitHub` as its base (FM-1) and
does not contain a custom override for those elements (FM-6). Those checks appear
in the **FM-1** and **FM-7** suites.

Where a requirement is not testable in a unit test, the reason is stated
explicitly in the "Untestable / Source-structural only" section below.

---

## Requirements Coverage

### US-1 — Table rendering (AC-1.1 / AC-1.2 / AC-1.3)

| AC | Test | Type |
|----|------|------|
| AC-1.1 (cell padding) | Covered by BC-13 constructibility + FM-1 source check (no custom tableCell override — padding comes from Theme.gitHub) | Source-structural |
| AC-1.2 (alternating row backgrounds) | Same proxy: no tableRow override in source; Theme.gitHub provides it | Source-structural |
| AC-1.3 (table border) | Same proxy | Source-structural |
| Edge case — empty table body | `BC13_ConstructibilityTests / renderedViewWithAllGFMBlockElements` — GFM with a table included | Behavioral smoke |
| Edge case — single-column table | Not separately tested; subsumed by FM-1 proof that Theme.gitHub is the base | Source-structural |

**Note:** Cell-level visual measurements (exact padding values, color tokens) require a
UI rendering host and cannot be asserted in unit tests. The FM-1 source-structural
check is the appropriate unit-level gate.

---

### US-2 — Code block rendering (AC-2.1 / AC-2.2 / AC-2.3)

| AC | Test | Type |
|----|------|------|
| AC-2.1 (background fill) | FM-1 source check + no codeBlock override in source | Source-structural |
| AC-2.2 (rounded corners) | Same proxy | Source-structural |
| AC-2.3 (horizontal scroll) | `BC13_ConstructibilityTests / renderedViewWithAllGFMBlockElements` — fenced code block with a long line included | Behavioral smoke |
| Edge case — empty fenced block | `BC13_ConstructibilityTests / renderedViewWithAllGFMBlockElements` | Behavioral smoke |

---

### US-3 — Blockquote rendering (AC-3.1 / AC-3.2)

| AC | Test | Type |
|----|------|------|
| AC-3.1 (left-border accent) | FM-1 source check + no blockquote override in source | Source-structural |
| AC-3.2 (background tint) | Same proxy | Source-structural |
| Edge case — nested blockquote | `BC13_ConstructibilityTests / renderedViewWithAllGFMBlockElements` — nested blockquote included | Behavioral smoke |

---

### US-4 — Paragraph spacing (AC-4.1 / AC-4.2)

| AC | Test | Type |
|----|------|------|
| AC-4.1 (bottom margin) | FM-1 source check + no paragraph override in source | Source-structural |
| AC-4.2 (line spacing) | Same proxy | Source-structural |
| Edge case — single-line paragraph | `BC13_ConstructibilityTests / renderedViewWithAllGFMBlockElements` | Behavioral smoke |

---

### US-5 — Link color (AC-5.1 / AC-5.2)

| AC | Test | Type |
|----|------|------|
| AC-5.1 (light-mode link color) | FM-1 source check + no link override in source; color comes from Theme.gitHub | Source-structural |
| AC-5.2 (dark-mode link color) | Same proxy | Source-structural |
| Edge case — link with custom title | `BC13_ConstructibilityTests / renderedViewWithAllGFMBlockElements` — link included | Behavioral smoke |

---

### US-6 — Thematic break rendering (AC-6.1 / AC-6.2)

| AC | Test | Type |
|----|------|------|
| AC-6.1 (styled divider) | FM-1 source check + no thematicBreak override in source | Source-structural |
| AC-6.2 (top and bottom margins) | Same proxy | Source-structural |

The thematic break (`---`) is included in `renderedViewWithAllGFMBlockElements`.

---

### US-7 — List item spacing (AC-7.1 / AC-7.2)

| AC | Test | Type |
|----|------|------|
| AC-7.1 (loose list spacing) | FM-1 source check; `renderedViewWithAllGFMBlockElements` includes a loose list | Source-structural + Behavioral smoke |
| AC-7.2 (tight list) | `renderedViewWithAllGFMBlockElements` includes a tight list | Behavioral smoke |

---

### US-8 — Dynamic Type heading scaling preserved

| AC | Test(s) | Suite |
|----|---------|-------|
| AC-8.1 (bodyFont matches preferredFont) | `bodyFontMatchesPreferredFont`, `bodyFontIsNotHardCoded`, `bodyFontPointSizeEqualsSystemBodyPreference` | US8_DynamicTypeTests, FM2_TextOverrideTests |
| AC-8.2 (em factors) | `headingFontEmFactors`, `headingFontSizesDerivedFromBodyFont` | US8_DynamicTypeTests, BC9_HeadingProportionalityTests |
| AC-8.3 (monotonic hierarchy) | `headingHierarchyIsMonotonic`, `headingHierarchyAtAllDynamicTypeSizes`, `h1LargerThanBody`, `h6SmallerThanBody` | US8_DynamicTypeTests, BC9_HeadingProportionalityTests |
| AC-8.4 (reflects change on next appearance) | Architecture-level guarantee: `RenderedView` reads `@Environment(\.dynamicTypeSize)`, causing body re-evaluation on change. Not unit-testable without a UI host. | Untestable in isolation — see note below |
| AC-8.5 (`.isHeader` on all heading levels) | `allHeadingBuildersHaveIsHeaderTrait`, `allSixHeadingOverridesPresent` | FM9_IsHeaderTraitTests |
| AC-8.6 (no explicit heading margins) | `headingBuildersDoNotSetExplicitMargins` | US8_DynamicTypeTests |
| Edge case — Accessibility XXXLarge | `headingHierarchyAtAllDynamicTypeSizes` | US8_DynamicTypeTests |

---

### US-9 — No visual regression in preserved inline styles

| AC | Test(s) | Suite |
|----|---------|-------|
| AC-9.1 (inline code monospaced) | FM-7 source check: no .code override; Theme.gitHub provides monospaced inline code | FM7_RemovedOverridesTests |
| AC-9.2 (bold heavier than body) | FM-7 source check: no .strong override; Theme.gitHub provides semibold weight | FM7_RemovedOverridesTests |
| AC-9.3 (italic distinct from body) | FM-7 source check: no .emphasis override; Theme.gitHub provides italic style | FM7_RemovedOverridesTests |
| AC-9.4 (makeTheme() does not crash) | `makeThemeDoesNotCrash`, `makeThemeIsIdempotent`, `makeThemeReturnsValidTheme` | US9_InlineStyleTests, BC13_ConstructibilityTests |

---

### Failure Modes (FM-1 through FM-9)

| FM | Test(s) | Suite |
|----|---------|-------|
| FM-1 (not Theme() base) | `themeBaseIsGitHub` | FM1_ThemeBaseTests |
| FM-2 (text override not removed) | `textOverridePresent` | FM2_TextOverrideTests |
| FM-3 (heading overrides not removed) | `allSixHeadingOverridesPresent` | FM9_IsHeaderTraitTests |
| FM-4 (no fixed pt sizes in headings) | `headingOverridesDoNotUseFixedPointSizes` | FM2_TextOverrideTests |
| FM-5 (RenderedView.swift not modified) | `renderedViewFileExists`, `renderedViewDoesNotInlineThemeConstruction` | FM5_RenderedViewUnchangedTests |
| FM-6 (no reimplemented block elements) | Covered by FM-1 + FM-7 collectively: Theme.gitHub is the base and no removed override is re-added | FM1_ThemeBaseTests, FM7_RemovedOverridesTests |
| FM-7 (code/strong/emphasis not ported) | `noCodeOverride`, `noStrongOverride`, `noEmphasisOverride` | FM7_RemovedOverridesTests |
| FM-8 (no hard-coded color literals) | `noHardCodedColorRGB`, `noHardCodedUIColorRGB` | FM8_NoHardCodedColorsTests |
| FM-9 (.isHeader not silently removed) | `allHeadingBuildersHaveIsHeaderTrait` | FM9_IsHeaderTraitTests |

---

## Design Behavioral Constraints Coverage

| BC | Test(s) | Suite |
|----|---------|-------|
| BC-1 (tables structured) | FM-1 source + `renderedViewWithAllGFMBlockElements` | FM1_ThemeBaseTests, BC13_ConstructibilityTests |
| BC-2 (code blocks distinct) | FM-1 source + `renderedViewWithAllGFMBlockElements` | FM1_ThemeBaseTests, BC13_ConstructibilityTests |
| BC-3 (blockquotes styled) | FM-1 source + `renderedViewWithAllGFMBlockElements` | FM1_ThemeBaseTests, BC13_ConstructibilityTests |
| BC-4 (paragraph spacing) | FM-1 source proxy | FM1_ThemeBaseTests |
| BC-5 (links distinct from body) | FM-1 source proxy | FM1_ThemeBaseTests |
| BC-6 (thematic breaks styled) | FM-1 source + `renderedViewWithAllGFMBlockElements` | FM1_ThemeBaseTests, BC13_ConstructibilityTests |
| BC-7 (loose vs. tight list spacing) | FM-1 source + `renderedViewWithAllGFMBlockElements` | FM1_ThemeBaseTests, BC13_ConstructibilityTests |
| BC-8 (body font = system body pref.) | `bodyFontMatchesPreferredFont`, `bodyFontPointSizeEqualsSystemBodyPreference` | US8_DynamicTypeTests, FM2_TextOverrideTests |
| BC-9 (heading proportionality and hierarchy) | Full BC9_HeadingProportionalityTests suite + US8_DynamicTypeTests | Both |
| BC-10 (inline code monospaced) | FM-7 no-.code-override proxy | FM7_RemovedOverridesTests |
| BC-11 (bold heavier than body) | FM-7 no-.strong-override proxy | FM7_RemovedOverridesTests |
| BC-12 (italic distinct from body) | FM-7 no-.emphasis-override proxy | FM7_RemovedOverridesTests |
| BC-13 (makeTheme() completes without error) | All BC13_ConstructibilityTests | BC13_ConstructibilityTests |
| BC-14 (no hard-coded color literals) | `noHardCodedColorRGB`, `noHardCodedUIColorRGB` | FM8_NoHardCodedColorsTests |
| BC-15 (heading margins inherited from Theme.gitHub) | `headingBuildersDoNotSetExplicitMargins` | US8_DynamicTypeTests |

---

## Untestable Requirements (unit tests only)

The following requirements are architectural-level guarantees that cannot be
asserted without a UI rendering host (UIKit view hierarchy or snapshot testing).
They are covered by the source-structural checks above as the best available
unit-level proxy.

| Requirement | Why not unit-testable | Proxy coverage |
|------------|----------------------|----------------|
| AC-1.1 exact padding (6 pt vertical / 13 pt horizontal) | Requires measuring rendered cell geometry in a live UIKit layout pass | FM-1 source check (Theme.gitHub is the base; its tableCell definition provides the values) |
| AC-1.2 alternating row background color values | Requires resolving a Color in a rendered view | FM-1 source check |
| AC-1.3 visible header border | Requires snapshot or UI test | FM-1 source check |
| AC-2.1 exact background color token | Requires rendering in a trait collection context | FM-1 source check |
| AC-2.2 exact corner radius | Requires a rendered view | FM-1 source check |
| AC-3.1 left-border accent color/width | Requires a rendered view | FM-1 source check |
| AC-3.2 blockquote tint color | Requires a rendered view | FM-1 source check |
| AC-4.1 exact bottom margin value | Requires layout measurement | FM-1 source check |
| AC-4.2 exact line-height ratio (> 1.0) | Requires typesetting | FM-1 source check |
| AC-5.1 exact link color in light mode (#0969DA) | Requires Color resolution in UITraitCollection.light | FM-1 source check (no link override; Theme.gitHub owns the color) |
| AC-5.2 exact link color in dark mode (#58A6FF) | Requires Color resolution in UITraitCollection.dark | Same |
| AC-6.1 distinguishable divider vs. paragraph spacing | Requires visual comparison | FM-1 source check |
| AC-6.2 exact thematic break margins | Requires layout | FM-1 source check |
| AC-7.1 loose list spacing > tight list spacing | Requires typesetting measurement | `renderedViewWithAllGFMBlockElements` smoke (no crash) |
| AC-8.4 Dynamic Type change reflected on next appearance | Requires live UIKit environment to inject a trait collection change and observe re-render | Architecture guarantee: `RenderedView` reads `@Environment(\.dynamicTypeSize)` |
| AC-9.1 inline code visually uses monospaced typeface | Requires rendering font inspection in UIKit | FM-7 source check (no .code override; Theme.gitHub owns inline code) |
| AC-9.2 bold weight visually heavier than body | Requires font weight comparison in rendered output | FM-7 source check (no .strong override) |
| AC-9.3 italic style visually differs from upright | Requires font descriptor inspection in rendered output | FM-7 source check (no .emphasis override) |

---

## Test Suite Index

| Suite | Tests | Requirements covered |
|-------|-------|---------------------|
| `US8_DynamicTypeTests` | 5 | AC-8.1, AC-8.2, AC-8.3, AC-8.6, BC-15 |
| `US9_InlineStyleTests` | 2 | AC-9.4, BC-13 |
| `FM1_ThemeBaseTests` | 1 | FM-1, BC-1 through BC-7 (proxy) |
| `FM2_TextOverrideTests` | 4 | FM-2, FM-4, BC-8, AC-8.1 |
| `FM5_RenderedViewUnchangedTests` | 2 | FM-5 |
| `FM7_RemovedOverridesTests` | 3 | FM-7, FM-6, AC-9.1, AC-9.2, AC-9.3, BC-10, BC-11, BC-12 |
| `FM8_NoHardCodedColorsTests` | 2 | FM-8, BC-14 |
| `FM9_IsHeaderTraitTests` | 2 | FM-9, AC-8.5, FM-3 |
| `BC9_HeadingProportionalityTests` | 4 | BC-9, AC-8.2, AC-8.3 |
| `BC13_ConstructibilityTests` | 3 | BC-13, AC-9.4, US-1 through US-7 (smoke) |

---

## DAG Task → Test Mapping

*(Placeholder — will be added by the DAG stage.)*
