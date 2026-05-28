// MarkdownThemeFactoryAccessibilityTests.swift
// Spec tests for accessibility-8 — Component 2: Heading traits in MarkdownThemeFactory.
//
// Framework: Swift Testing (unit level, per constitution.md).
// These live under features/accessibility-8/tests/ as reference / human-readable
// specs; they are NOT part of the Xcode test target. The DAG step adds task-ID
// labels by updating verify.md — do not add task annotations here.
//
// Coverage:
//   AC-2.1  Each heading level produces a font distinct from body (trait-level
//            proxy — the unit-testable surface of MarkdownThemeFactory).
//   AC-2.3  Body text does not carry heading-scale properties.
//   AC-2.4  Heading trait assignment does not alter visual font metrics.
//
// LIMITATION (AC-2.1 heading trait — .isHeader):
//   Whether `.accessibilityAddTraits(.isHeader)` on `configuration.label`
//   actually propagates through MarkdownUI's opaque container to the leaf
//   element VoiceOver focuses cannot be verified from a Swift Testing unit
//   test without rendering the view hierarchy into a live window.
//   MarkdownThemeFactory.makeTheme() returns a MarkdownUI.Theme value whose
//   heading builder closures accept and return opaque types; inspecting the
//   resulting SwiftUI modifier chain from a unit test is not possible without
//   ViewInspector or a full hosting context.
//
//   Resolution: AC-2.2 and AC-2.5 in the requirements explicitly require
//   end-to-end behavioral verification via XCUITest (AccessibilityHeadingRotorUITests).
//   The unit tests here focus on the *typography contract* that headingFont(level:)
//   exposes — the same testable surface used by NativePolish6_TypographyAndMaterialTests.
//   That surface is sufficient to confirm the factory is called and produces distinct
//   heading levels; whether the trait propagates to VoiceOver is an XCUITest concern.

import Testing
import UIKit
@testable import Markus_v3

@Suite("accessibility-8 / Component 2 — MarkdownThemeFactory heading typography")
struct MarkdownThemeFactoryAccessibilityTests {

    // MARK: - AC-2.1 proxy: distinct font per heading level

    // Each heading level must produce a distinct point size relative to body.
    // This confirms the six heading builders are configured with different em
    // factors (H1=2.0, H2=1.5, H3=1.25, H4=1.0, H5=0.875, H6=0.85), which
    // is a necessary (though not sufficient) condition for AC-2.1.

    @Test("H1 heading font is larger than the body font")
    func h1LargerThanBody() {
        let body = MarkdownThemeFactory.bodyFont().pointSize
        let h1 = MarkdownThemeFactory.headingFont(level: 1).pointSize
        #expect(h1 > body,
                "H1 (\(h1)pt) must be larger than body (\(body)pt) — em factor 2.0")
    }

    @Test("H2 heading font is larger than the body font")
    func h2LargerThanBody() {
        let body = MarkdownThemeFactory.bodyFont().pointSize
        let h2 = MarkdownThemeFactory.headingFont(level: 2).pointSize
        #expect(h2 > body,
                "H2 (\(h2)pt) must be larger than body (\(body)pt) — em factor 1.5")
    }

    @Test("H3 heading font is larger than or equal to the body font")
    func h3AtLeastBody() {
        let body = MarkdownThemeFactory.bodyFont().pointSize
        let h3 = MarkdownThemeFactory.headingFont(level: 3).pointSize
        #expect(h3 >= body,
                "H3 (\(h3)pt) must be ≥ body (\(body)pt) — em factor 1.25")
    }

    @Test("H4 heading font equals the body font (em factor 1.0)")
    func h4EqualsBody() {
        let body = MarkdownThemeFactory.bodyFont().pointSize
        let h4 = MarkdownThemeFactory.headingFont(level: 4).pointSize
        // H4 em factor is 1.0, so its computed size equals the body size.
        #expect(h4 == body,
                "H4 (\(h4)pt) must equal body (\(body)pt) — em factor 1.0")
    }

    @Test("H5 heading font is smaller than body (em factor 0.875)")
    func h5SmallerThanBody() {
        let body = MarkdownThemeFactory.bodyFont().pointSize
        let h5 = MarkdownThemeFactory.headingFont(level: 5).pointSize
        #expect(h5 < body,
                "H5 (\(h5)pt) must be smaller than body (\(body)pt) — em factor 0.875")
    }

    @Test("H6 heading font is smaller than H5 (em factor 0.85 < 0.875)")
    func h6SmallerThanH5() {
        let h5 = MarkdownThemeFactory.headingFont(level: 5).pointSize
        let h6 = MarkdownThemeFactory.headingFont(level: 6).pointSize
        #expect(h6 < h5,
                "H6 (\(h6)pt) must be smaller than H5 (\(h5)pt) — em factors 0.85 vs 0.875")
    }

    // MARK: - AC-2.1 proxy: all six levels produce distinct sizes

    @Test("H1 through H6 produce distinct point sizes in descending order")
    func headingLevelsDescend() {
        let sizes = (1...6).map { MarkdownThemeFactory.headingFont(level: $0).pointSize }
        // H1 > H2 > H3 — strict descent for the top three
        #expect(sizes[0] > sizes[1], "H1 must be larger than H2")
        #expect(sizes[1] > sizes[2], "H2 must be larger than H3")
        // H4 is body-scale; H3 >= H4
        #expect(sizes[2] >= sizes[3], "H3 must be >= H4")
        // H5 and H6 are sub-body; H4 > H5 > H6
        #expect(sizes[3] > sizes[4], "H4 must be larger than H5")
        #expect(sizes[4] > sizes[5], "H5 must be larger than H6")
    }

    // MARK: - AC-2.3: body font is not heading-scale

    @Test("Body font point size is smaller than H1 and H2")
    func bodyFontIsNotHeadingScale() {
        let body = MarkdownThemeFactory.bodyFont().pointSize
        let h1 = MarkdownThemeFactory.headingFont(level: 1).pointSize
        let h2 = MarkdownThemeFactory.headingFont(level: 2).pointSize
        #expect(body < h1, "Body must not be H1-scale — verifies AC-2.3 at the factory seam")
        #expect(body < h2, "Body must not be H2-scale — verifies AC-2.3 at the factory seam")
    }

    // MARK: - AC-2.4: headingFont is derived from the current body size (typography unchanged)

    @Test("headingFont(level:) sizes are proportional to the current body Dynamic Type size")
    func headingFontIsProportionalToBody() {
        let bodySize = MarkdownThemeFactory.bodyFont().pointSize
        // H1 uses em factor 2.0; verify the proportionality holds.
        let h1 = MarkdownThemeFactory.headingFont(level: 1).pointSize
        let expectedH1 = bodySize * 2.0
        #expect(abs(h1 - expectedH1) < 0.5,
                "H1 font size \(h1)pt should be body × 2.0 = \(expectedH1)pt (AC-2.4: no visual regression)")
        // H2 uses em factor 1.5
        let h2 = MarkdownThemeFactory.headingFont(level: 2).pointSize
        let expectedH2 = bodySize * 1.5
        #expect(abs(h2 - expectedH2) < 0.5,
                "H2 font size \(h2)pt should be body × 1.5 = \(expectedH2)pt (AC-2.4)")
    }

    // MARK: - makeTheme() smoke: factory produces a theme without crashing

    @Test("makeTheme() returns a Theme without crashing")
    func makeThemeDoesNotCrash() {
        let theme = MarkdownThemeFactory.makeTheme()
        // Theme is a value type; non-crash is the contract.
        _ = theme
        #expect(Bool(true), "makeTheme() must return a Theme without crashing (smoke test)")
    }
}
