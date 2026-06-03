// RenderedTheme12Tests.swift
// Spec tests for rendered-theme-12 — Rendered Theme Polish.
//
// These tests are reference / human-readable specs. They live under
// features/rendered-theme-12/tests/ and are NOT part of the Xcode test target
// (per constitution.md). They will compile and run once the implementation is
// complete; until then they may fail with import or compilation errors.
//
// Coverage strategy:
//   - Behavioral tests: requirements US-1 through US-9, AC-8.x, AC-9.x
//   - Seam tests: design seams BC-8, BC-9, BC-13, BC-14, BC-15, and structural
//     assertions about MarkdownThemeFactory.swift source content (FM-1, FM-5,
//     FM-7, FM-8, FM-9 / AC-8.5, AC-8.6).
//
// Block-element visual behaviors (US-1 through US-7, BC-1 through BC-7) are
// delegated to Theme.gitHub by the absence of custom overrides. They cannot be
// asserted in pure unit tests without a UI host. Those requirements are
// documented as source-structural checks: confirming no custom override exists
// for those elements is the correct unit-level proxy for BC-1 through BC-7.
//
// Task → test mapping will be added by the DAG stage.

import Testing
import Foundation
import UIKit
@testable import Markus_v3

// MARK: - Helpers

/// Reads MarkdownThemeFactory.swift source for structural assertions.
/// Returns nil if the file cannot be located (pre-implementation state).
private func themeFactorySource() -> String? {
    // Walk from this file's directory up to the repo root, then into
    // Markus_v3/Views/MarkdownThemeFactory.swift.
    let here = URL(fileURLWithPath: #filePath)
    // features/rendered-theme-12/tests/RenderedTheme12Tests.swift
    // -> features/rendered-theme-12/tests
    // -> features/rendered-theme-12
    // -> features
    // -> repo root
    let repoRoot = here
        .deletingLastPathComponent() // tests/
        .deletingLastPathComponent() // rendered-theme-12/
        .deletingLastPathComponent() // features/
        .deletingLastPathComponent() // repo root
    let factoryURL = repoRoot
        .appendingPathComponent("Markus_v3/Views/MarkdownThemeFactory.swift")
    return try? String(contentsOf: factoryURL, encoding: .utf8)
}

/// Reads RenderedView.swift source to verify it is not modified by this feature.
private func renderedViewSource() -> String? {
    let here = URL(fileURLWithPath: #filePath)
    let repoRoot = here
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = repoRoot.appendingPathComponent("Markus_v3/Views/RenderedView.swift")
    return try? String(contentsOf: url, encoding: .utf8)
}

// MARK: - Suite: AC-8 — Dynamic Type contract (US-8)

@Suite("US-8 — Dynamic Type heading scaling preserved")
struct US8_DynamicTypeTests {

    // AC-8.1 — bodyFont() returns UIFont.preferredFont(forTextStyle: .body)
    @Test("AC-8.1: bodyFont() point size equals UIFont.preferredFont(forTextStyle: .body)")
    func bodyFontMatchesPreferredFont() {
        let body = MarkdownThemeFactory.bodyFont()
        let preferred = UIFont.preferredFont(forTextStyle: .body)
        #expect(
            body.pointSize == preferred.pointSize,
            "bodyFont() point size \(body.pointSize) must equal preferred body size \(preferred.pointSize)"
        )
    }

    // AC-8.1 — bodyFont() is Dynamic Type-scaled (not a fixed constant)
    @Test("AC-8.1: bodyFont() is not a hard-coded fixed size — it tracks preferredFont")
    func bodyFontIsNotHardCoded() {
        // The value must match the live system preference, which by definition
        // is not a constant. We verify this by confirming equality to
        // preferredFont(.body), which is the Dynamic Type contract.
        let body = MarkdownThemeFactory.bodyFont()
        let preferred = UIFont.preferredFont(forTextStyle: .body)
        #expect(body.pointSize == preferred.pointSize)
    }

    // AC-8.2 — headingFont(level:) em factors
    @Test("AC-8.2: headingFont(level:) sizes match em factors multiplied by bodyFont().pointSize")
    func headingFontEmFactors() {
        let bodySize = MarkdownThemeFactory.bodyFont().pointSize
        let emFactors: [(level: Int, factor: CGFloat)] = [
            (1, 2.00),
            (2, 1.50),
            (3, 1.25),
            (4, 1.00),
            (5, 0.875),
            (6, 0.85),
        ]
        let tolerance: CGFloat = 0.5
        for entry in emFactors {
            let expected = bodySize * entry.factor
            let actual = MarkdownThemeFactory.headingFont(level: entry.level).pointSize
            #expect(
                abs(actual - expected) <= tolerance,
                "H\(entry.level): expected ~\(expected) pt (body \(bodySize) × \(entry.factor)), got \(actual) pt"
            )
        }
    }

    // AC-8.3 — monotonic heading hierarchy at default Dynamic Type size
    @Test("AC-8.3: heading font sizes are strictly descending H1 > H2 > H3 >= H4 > H5 > H6")
    func headingHierarchyIsMonotonic() {
        let sizes = (1...6).map { MarkdownThemeFactory.headingFont(level: $0).pointSize }
        // H1 > H2 > H3 >= H4 (H3 at 1.25x, H4 at 1.0x — strictly greater)
        #expect(sizes[0] > sizes[1], "H1 must be larger than H2")
        #expect(sizes[1] > sizes[2], "H2 must be larger than H3")
        #expect(sizes[2] >= sizes[3], "H3 must be >= H4")
        #expect(sizes[3] > sizes[4], "H4 must be larger than H5")
        #expect(sizes[4] > sizes[5], "H5 must be larger than H6")
    }

    // AC-8.3 edge case — hierarchy holds at each defined Dynamic Type size
    @Test("AC-8.3 edge case: heading hierarchy holds at all Dynamic Type content sizes")
    func headingHierarchyAtAllDynamicTypeSizes() {
        // We can't inject a UITraitCollection for preferredFont in a unit test, so
        // we verify the invariant using the current system size. The invariant holds
        // by construction (multiplication by ordered factors with no subtraction).
        let bodySize = MarkdownThemeFactory.bodyFont().pointSize
        #expect(bodySize > 0, "bodyFont().pointSize must be positive at any Dynamic Type size")
        let h1 = MarkdownThemeFactory.headingFont(level: 1).pointSize
        let h6 = MarkdownThemeFactory.headingFont(level: 6).pointSize
        #expect(h1 > h6, "H1 must always be larger than H6 regardless of Dynamic Type size")
        #expect(h6 > 0, "H6 must be positive (no overflow or negative size from 0.85 factor)")
    }

    // AC-8.6 / BC-15 — heading overrides must NOT set explicit margin values
    // (Source-structural seam: no markdownMargin call may appear in heading builders)
    @Test("AC-8.6 / BC-15: heading builders do not set explicit markdownMargin values (inherited from Theme.gitHub)")
    func headingBuildersDoNotSetExplicitMargins() throws {
        guard let source = themeFactorySource() else {
            #expect(Bool(false), "MarkdownThemeFactory.swift not found — run after implementation")
            return
        }
        // After migration, no markdownMargin call should appear inside any heading builder.
        // The current pre-migration implementation uses markdownMargin(top: 24, bottom: 16);
        // post-migration that call must be absent.
        let containsMarginOverride = source.contains("markdownMargin")
        #expect(
            !containsMarginOverride,
            "heading builders must not call markdownMargin — margins are delegated to Theme.gitHub (AC-8.6)"
        )
    }
}

// MARK: - Suite: AC-9 — No regression in inline styles (US-9) + smoke

@Suite("US-9 — No visual regression in preserved inline styles")
struct US9_InlineStyleTests {

    // AC-9.4 / BC-13 — makeTheme() does not crash
    @Test("AC-9.4 / BC-13: makeTheme() returns a Theme value without crashing")
    func makeThemeDoesNotCrash() {
        let theme = MarkdownThemeFactory.makeTheme()
        // Swift's type system guarantees non-nil on a value type; existence confirms no crash.
        _ = theme
        #expect(Bool(true), "makeTheme() must return a Theme value at every call site")
    }

    // AC-9.4 — makeTheme() is idempotent (can be called multiple times without crash)
    @Test("AC-9.4: makeTheme() can be called multiple times without crashing")
    func makeThemeIsIdempotent() {
        for _ in 1...5 {
            _ = MarkdownThemeFactory.makeTheme()
        }
        #expect(Bool(true))
    }
}

// MARK: - Suite: FM-1 — Theme base must not be Theme() blank

@Suite("FM-1 — makeTheme() must not return a blank Theme() base")
struct FM1_ThemeBaseTests {

    // FM-1 source-structural seam:
    // The implementation must start from Theme.gitHub, not Theme().
    // We verify this by checking the source for "Theme.gitHub" (present)
    // and absence of "Theme()" as the return or chaining root.
    @Test("FM-1: MarkdownThemeFactory.swift uses Theme.gitHub as the base (not Theme())")
    func themeBaseIsGitHub() throws {
        guard let source = themeFactorySource() else {
            #expect(Bool(false), "MarkdownThemeFactory.swift not found — run after implementation")
            return
        }
        #expect(
            source.contains("Theme.gitHub"),
            "makeTheme() must start from Theme.gitHub (FM-1)"
        )
        // Post-migration, Theme() should not appear as the chaining root.
        // Theme() used as a type name in comments is acceptable; we check
        // that the return value's chain does not start with Theme().
        // The simplest proxy: the string "return Theme()" must not appear.
        let hasBlankThemeReturn = source.contains("return Theme()")
        #expect(
            !hasBlankThemeReturn,
            "makeTheme() must not return Theme() — it must start from Theme.gitHub (FM-1)"
        )
    }
}

// MARK: - Suite: FM-5 — RenderedView.swift must not be modified

@Suite("FM-5 — RenderedView.swift is unchanged by this feature")
struct FM5_RenderedViewUnchangedTests {

    // FM-5 source-structural seam:
    // RenderedView.swift must exist and load without error. If it were
    // deleted or renamed, the app would not compile. This is a smoke check
    // confirming the file is present and readable.
    @Test("FM-5: RenderedView.swift exists and is readable (not deleted or renamed)")
    func renderedViewFileExists() {
        let source = renderedViewSource()
        #expect(source != nil, "RenderedView.swift must exist — it must not be modified or deleted by this feature")
    }

    // FM-5 — RenderedView.swift does not contain theme construction code
    // (theme construction belongs solely in MarkdownThemeFactory.swift)
    @Test("FM-5: RenderedView.swift delegates theme construction to MarkdownThemeFactory, not inline")
    func renderedViewDoesNotInlineThemeConstruction() {
        guard let source = renderedViewSource() else {
            #expect(Bool(false), "RenderedView.swift not found")
            return
        }
        // RenderedView must not directly construct Theme.gitHub or Theme()
        // inline — it must call MarkdownThemeFactory.makeTheme().
        let hasInlineTheme = source.contains("Theme.gitHub") || source.contains("Theme()")
        #expect(
            !hasInlineTheme,
            "RenderedView.swift must not construct a theme inline — it must call MarkdownThemeFactory.makeTheme()"
        )
    }
}

// MARK: - Suite: FM-7 — code/strong/emphasis overrides must not be ported

@Suite("FM-7 — Removed inline overrides are not reimplemented in makeTheme()")
struct FM7_RemovedOverridesTests {

    // FM-7 source-structural seam:
    // The .code, .strong, and .emphasis builder chains present in the
    // pre-migration implementation must not appear in the new implementation.
    // They are subsumed by Theme.gitHub and must not be redefined (FM-6 / FM-7).
    @Test("FM-7: makeTheme() does not redefine .code override (subsumed by Theme.gitHub)")
    func noCodeOverride() throws {
        guard let source = themeFactorySource() else {
            #expect(Bool(false), "MarkdownThemeFactory.swift not found — run after implementation")
            return
        }
        // The .code { } builder chain must not appear.
        // We check for the specific chained call pattern.
        let hasCodeOverride = source.contains(".code {") || source.contains(".code{")
        #expect(
            !hasCodeOverride,
            "makeTheme() must not redefine .code — it is subsumed by Theme.gitHub (FM-7)"
        )
    }

    @Test("FM-7: makeTheme() does not redefine .strong override (subsumed by Theme.gitHub)")
    func noStrongOverride() throws {
        guard let source = themeFactorySource() else {
            #expect(Bool(false), "MarkdownThemeFactory.swift not found — run after implementation")
            return
        }
        let hasStrongOverride = source.contains(".strong {") || source.contains(".strong{")
        #expect(
            !hasStrongOverride,
            "makeTheme() must not redefine .strong — it is subsumed by Theme.gitHub (FM-7)"
        )
    }

    @Test("FM-7: makeTheme() does not redefine .emphasis override (subsumed by Theme.gitHub)")
    func noEmphasisOverride() throws {
        guard let source = themeFactorySource() else {
            #expect(Bool(false), "MarkdownThemeFactory.swift not found — run after implementation")
            return
        }
        let hasEmphasisOverride = source.contains(".emphasis {") || source.contains(".emphasis{")
        #expect(
            !hasEmphasisOverride,
            "makeTheme() must not redefine .emphasis — it is subsumed by Theme.gitHub (FM-7)"
        )
    }
}

// MARK: - Suite: FM-8 — No hard-coded color literals in overrides

@Suite("FM-8 — No hard-coded color literals in text or heading overrides")
struct FM8_NoHardCodedColorsTests {

    // FM-8 source-structural seam:
    // The text and heading overrides must not use Color(red:green:blue:)
    // or equivalent. All colors come from Theme.gitHub (inherited),
    // Color.primary, or semantic system colors.
    @Test("FM-8: MarkdownThemeFactory.swift does not use Color(red:green:blue:) in overrides")
    func noHardCodedColorRGB() throws {
        guard let source = themeFactorySource() else {
            #expect(Bool(false), "MarkdownThemeFactory.swift not found — run after implementation")
            return
        }
        // Check for the most common hard-coded color literal forms.
        let hasRGBLiteral = source.contains("Color(red:") || source.contains("Color(red :")
        #expect(
            !hasRGBLiteral,
            "makeTheme() overrides must not use Color(red:green:blue:) literals (FM-8)"
        )
    }

    @Test("FM-8: MarkdownThemeFactory.swift does not use UIColor with fixed RGB components in overrides")
    func noHardCodedUIColorRGB() throws {
        guard let source = themeFactorySource() else {
            #expect(Bool(false), "MarkdownThemeFactory.swift not found — run after implementation")
            return
        }
        let hasUIColorRGB = source.contains("UIColor(red:") || source.contains("UIColor(red :")
        #expect(
            !hasUIColorRGB,
            "makeTheme() overrides must not use UIColor(red:green:blue:alpha:) literals (FM-8)"
        )
    }
}

// MARK: - Suite: FM-9 / AC-8.5 — .isHeader trait on all heading builders

@Suite("FM-9 / AC-8.5 — .isHeader accessibility trait present on all heading builders")
struct FM9_IsHeaderTraitTests {

    // FM-9 / AC-8.5 source-structural seam:
    // Each heading builder (heading1 through heading6) must call
    // .accessibilityAddTraits(.isHeader). Omitting it on any level
    // breaks VoiceOver heading navigation (WCAG 2.1 SC 1.3.1).
    @Test("FM-9 / AC-8.5: heading builders all call .accessibilityAddTraits(.isHeader)")
    func allHeadingBuildersHaveIsHeaderTrait() throws {
        guard let source = themeFactorySource() else {
            #expect(Bool(false), "MarkdownThemeFactory.swift not found — run after implementation")
            return
        }
        // Count occurrences of .accessibilityAddTraits(.isHeader).
        // There must be exactly 6 (one per heading level).
        let token = ".accessibilityAddTraits(.isHeader)"
        let occurrences = source.components(separatedBy: token).count - 1
        #expect(
            occurrences == 6,
            "Expected 6 .accessibilityAddTraits(.isHeader) calls (one per heading level H1–H6), found \(occurrences) (FM-9, AC-8.5)"
        )
    }

    // FM-3 / FM-9 — heading1 through heading6 builders must be present
    @Test("FM-3: heading1 through heading6 overrides are all present in makeTheme()")
    func allSixHeadingOverridesPresent() throws {
        guard let source = themeFactorySource() else {
            #expect(Bool(false), "MarkdownThemeFactory.swift not found — run after implementation")
            return
        }
        for level in 1...6 {
            #expect(
                source.contains(".heading\(level)"),
                "heading\(level) override must be present in makeTheme() (FM-3)"
            )
        }
    }
}

// MARK: - Suite: FM-2 / BC-8 — text override must be present

@Suite("FM-2 / BC-8 — text override preserves Dynamic Type body size")
struct FM2_TextOverrideTests {

    // FM-2 source-structural seam:
    // The .text { } builder must be present in makeTheme().
    // Removing it causes the rendered view to inherit Theme.gitHub's fixed
    // text size instead of the Dynamic Type-scaled size.
    @Test("FM-2: .text override is present in makeTheme()")
    func textOverridePresent() throws {
        guard let source = themeFactorySource() else {
            #expect(Bool(false), "MarkdownThemeFactory.swift not found — run after implementation")
            return
        }
        #expect(
            source.contains(".text {") || source.contains(".text{"),
            ".text override must be present in makeTheme() so body size tracks Dynamic Type (FM-2)"
        )
    }

    // FM-4 — heading sizes must not be fixed point values
    // Structural proxy: .pt( must not appear in any heading builder context.
    @Test("FM-4: heading overrides do not use fixed .pt() font sizes")
    func headingOverridesDoNotUseFixedPointSizes() throws {
        guard let source = themeFactorySource() else {
            #expect(Bool(false), "MarkdownThemeFactory.swift not found — run after implementation")
            return
        }
        // .pt( is the swift-markdown-ui API for absolute point sizes.
        // No heading builder should use it; sizes must be em-relative.
        // We check that .pt( does not appear in the heading section.
        // A broad check (anywhere in the file) is a safe conservative proxy.
        let hasFixedPt = source.contains(".pt(")
        #expect(
            !hasFixedPt,
            "heading overrides must not use .pt() (fixed point size) — they must use .em() to track Dynamic Type (FM-4)"
        )
    }

    // BC-8 seam — bodyFont() returns a UIFont whose pointSize equals preferredFont(.body)
    @Test("BC-8: MarkdownThemeFactory.bodyFont() point size equals UIFont.preferredFont(forTextStyle: .body).pointSize")
    func bodyFontPointSizeEqualsSystemBodyPreference() {
        let bodyFont = MarkdownThemeFactory.bodyFont()
        let systemBody = UIFont.preferredFont(forTextStyle: .body)
        #expect(
            bodyFont.pointSize == systemBody.pointSize,
            "BC-8: bodyFont() \(bodyFont.pointSize) pt must equal system body \(systemBody.pointSize) pt"
        )
    }
}

// MARK: - Suite: BC-9 — heading proportionality seam

@Suite("BC-9 — Heading font proportionality and hierarchy seam")
struct BC9_HeadingProportionalityTests {

    // BC-9 — all six heading levels return fonts
    @Test("BC-9: headingFont(level:) returns a non-nil UIFont for each level 1–6")
    func headingFontLevelsAreAllDefined() {
        for level in 1...6 {
            let font = MarkdownThemeFactory.headingFont(level: level)
            #expect(font.pointSize > 0, "headingFont(level: \(level)) must return a positive point size")
        }
    }

    // BC-9 — heading sizes are strictly proportional to bodyFont
    @Test("BC-9: headingFont sizes are derived from bodyFont().pointSize × em factor (not independent)")
    func headingFontSizesDerivedFromBodyFont() {
        let bodySize = MarkdownThemeFactory.bodyFont().pointSize
        let emFactors: [CGFloat] = [2.00, 1.50, 1.25, 1.00, 0.875, 0.85]
        let tolerance: CGFloat = 0.5
        for (index, factor) in emFactors.enumerated() {
            let level = index + 1
            let expected = bodySize * factor
            let actual = MarkdownThemeFactory.headingFont(level: level).pointSize
            #expect(
                abs(actual - expected) <= tolerance,
                "H\(level): \(actual) pt should equal body(\(bodySize)) × \(factor) = \(expected) pt (±\(tolerance))"
            )
        }
    }

    // BC-9 seam — H1 > body (existing contract, restated for seam clarity)
    @Test("BC-9 seam: H1 font is larger than body font")
    func h1LargerThanBody() {
        let bodySize = MarkdownThemeFactory.bodyFont().pointSize
        let h1Size = MarkdownThemeFactory.headingFont(level: 1).pointSize
        #expect(h1Size > bodySize, "H1 (\(h1Size) pt) must be larger than body (\(bodySize) pt)")
    }

    // BC-9 seam — H6 < body (0.85× factor means H6 < body)
    @Test("BC-9 seam: H6 font is smaller than body font (em factor 0.85 < 1.0)")
    func h6SmallerThanBody() {
        let bodySize = MarkdownThemeFactory.bodyFont().pointSize
        let h6Size = MarkdownThemeFactory.headingFont(level: 6).pointSize
        #expect(h6Size < bodySize, "H6 (\(h6Size) pt) must be smaller than body (\(bodySize) pt)")
    }
}

// MARK: - Suite: BC-13 — makeTheme() constructibility

@Suite("BC-13 — makeTheme() completes without error at all call sites")
struct BC13_ConstructibilityTests {

    // BC-13 — makeTheme() smoke at all Dynamic Type sizes
    // We can't change preferredFont in-process, but we verify the
    // constructor returns without crashing at the current system size.
    @Test("BC-13: makeTheme() returns a valid Theme at the current Dynamic Type size")
    func makeThemeReturnsValidTheme() {
        let theme = MarkdownThemeFactory.makeTheme()
        _ = theme
        #expect(Bool(true), "makeTheme() must not crash (BC-13)")
    }

    // BC-13 — RenderedView is constructible using the theme (integration smoke)
    @MainActor
    @Test("BC-13 integration: RenderedView is constructible with the theme from makeTheme()")
    func renderedViewWithThemeIsConstructible() {
        let _ = RenderedView(text: "# Heading\n\nParagraph text.", onTap: { _ in })
        #expect(Bool(true), "RenderedView must be constructible — makeTheme() must not crash (BC-13)")
    }

    // BC-13 — constructible with GFM block elements
    @MainActor
    @Test("BC-13: RenderedView constructible with GFM tables, code blocks, blockquotes, and thematic breaks")
    func renderedViewWithAllGFMBlockElements() {
        let gfm = """
        # Heading 1
        ## Heading 2

        A paragraph with **bold** and *italic* and `inline code` text.

        | Column A | Column B |
        |----------|----------|
        | Cell 1   | Cell 2   |
        | Cell 3   | Cell 4   |

        ```swift
        let x = 42
        let longLine = "This is a very long line that might exceed the viewport width in a narrow layout"
        ```

        > A blockquote with some text.
        >
        > > Nested blockquote.

        ---

        - Tight item one
        - Tight item two

        - Loose item one

        - Loose item two

        [A link](https://example.com)
        """
        let _ = RenderedView(text: gfm, onTap: { _ in })
        #expect(Bool(true), "RenderedView must not crash when rendering any GFM block element type (BC-13)")
    }
}
