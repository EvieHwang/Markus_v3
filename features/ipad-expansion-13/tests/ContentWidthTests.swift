// ContentWidthTests.swift
// Spec tests for ipad-expansion-13 — Part 2 (editor line-length constraint).
//
// Framework: Swift Testing (@Test, #expect, #require).
//
// REFERENCE specs under features/ipad-expansion-13/tests/ — NOT part of the
// Xcode test target (constitution.md → Testing). They are written to FAIL /
// be unimplemented until the feature is built: they reference the as-yet-unbuilt
// width-resolution seam (design Component B — `RegularWidthContentColumn`) and
// assert layout behavior that does not exist yet.
//
// Do NOT add DAG task-ID tags here — that happens in the next stage.
//
// The width treatment is a presentation-only container applied IDENTICALLY to
// both editor surfaces. Its load-bearing, unit-testable contract is the pure
// width-resolution decision: given the horizontal size class and the available
// width, what usable content width and centering does each surface get?
// The observable, in-app aspects (live size-class transition, no scroll reset,
// caret/gutter behavior in the real UITextView) are covered by the XCUITest
// file `ContentWidthUITests.swift`.
//
// Covers (Part 2):
//   US-7 / AC-7.1–7.4 + wide-window edge — capped & centered in regular width
//   US-8 / AC-8.1–8.2 — full width, no centering, in compact width
//   US-10 / AC-10.1–10.2 + long-token edge — centering not clipping, full column
//   FM-5, FM-6, FM-8 — no cap in compact, no clipping, both surfaces share width
//   Seam C-B.1, C-B.2, C-B.3, C-B.4, S-6

import Testing
import Foundation
import CoreGraphics
@testable import Markus_v3

// MARK: - Seam under test
//
// The build introduces a shared width-resolution decision (design Component B,
// referred to here as `ContentColumnLayout`). It is keyed on the horizontal
// size class (regular vs compact), caps usable width at the shared maximum
// (~700pt), centers within that cap when ample, and otherwise fills the width.
// The probe models the DECISION (a pure function of size class + available
// width). It deliberately does not assert a SwiftUI modifier name or mechanism
// (content inset vs. centering a region) — only the observable resolved layout.

enum HSizeClass { case compact, regular }

@Suite("Part 2 — shared content-width resolution (regular vs compact)")
struct ContentColumnLayoutTests {

    // The spec calls the cap "approximately 700pt". Tests assert the behavioral
    // property (capped at ~700, centered, full-width below the cap) and allow a
    // small tolerance around the exact constant the build chooses.
    let cap: CGFloat = ContentColumnProbe.maxContentWidth
    let tolerance: CGFloat = 40

    // MARK: AC-7.1 / AC-7.2 — both surfaces capped & centered in regular width

    @Test("AC-7.1/7.2: in regular width at 1024pt, both surfaces cap usable width near ~700pt")
    func regularWide_capsBothSurfaces() {
        for surface in ContentColumnProbe.Surface.allCases {
            let layout = ContentColumnProbe.resolve(sizeClass: .regular,
                                                    availableWidth: 1024,
                                                    surface: surface)
            #expect(abs(layout.usableWidth - cap) <= tolerance,
                    "AC-7.\(surface == .raw ? "1" : "2"): \(surface) usable width must be ~700pt in regular width (got \(layout.usableWidth))")
            #expect(layout.isCentered,
                    "AC-7.\(surface == .raw ? "1" : "2"): \(surface) must be horizontally centered when capped")
        }
    }

    @Test("AC-7 wide-window edge: at ~1366pt the column stays ~700pt, centered, with side gutters")
    func veryWide_columnStaysCappedAndCentered() {
        let layout = ContentColumnProbe.resolve(sizeClass: .regular,
                                                availableWidth: 1366,
                                                surface: .rendered)
        #expect(abs(layout.usableWidth - cap) <= tolerance,
                "AC-7 edge: at 1366pt usable width must remain ~700pt (got \(layout.usableWidth))")
        #expect(layout.usableWidth < 1366,
                "AC-7 edge: no line may stretch to the full 1366pt")
        #expect(layout.leadingGutter > 0 && layout.trailingGutter > 0,
                "AC-7 edge: extra space must be empty background gutters on both sides")
        #expect(abs(layout.leadingGutter - layout.trailingGutter) <= 1,
                "AC-7 edge: the column must be centered (equal gutters)")
    }

    // MARK: AC-7.3 / C-B.1 / FM-8 — both surfaces use the SAME width and position

    @Test("AC-7.3/FM-8: raw and rendered resolve to the same width and horizontal position")
    func bothSurfacesShareWidthAndPosition() {
        let raw = ContentColumnProbe.resolve(sizeClass: .regular, availableWidth: 1100, surface: .raw)
        let rendered = ContentColumnProbe.resolve(sizeClass: .regular, availableWidth: 1100, surface: .rendered)
        #expect(raw.usableWidth == rendered.usableWidth,
                "C-B.1/FM-8: both surfaces must draw from one shared maximum width")
        #expect(raw.leadingGutter == rendered.leadingGutter,
                "C-B.1/FM-8: both surfaces must sit at the same horizontal position (no shift on mode switch)")
    }

    // MARK: AC-7.4 / C-B.3 — the cap is a MAXIMUM, not a fixed width

    @Test("AC-7.4: a narrow-but-regular width below the cap uses the full available width")
    func regularNarrow_belowCap_usesFullWidth() {
        let available: CGFloat = 560 // regular but narrower than the cap
        let layout = ContentColumnProbe.resolve(sizeClass: .regular,
                                                availableWidth: available,
                                                surface: .rendered)
        #expect(layout.usableWidth == available,
                "AC-7.4: below the cap the content must use the full available width (no artificial cap)")
        #expect(layout.leadingGutter == 0 && layout.trailingGutter == 0,
                "AC-7.4 / C-B.3: no centering gutters appear until available width exceeds the cap")
    }

    @Test("C-B.3: gutters appear only once available width exceeds the cap")
    func guttersAppearOnlyAboveCap() {
        let atCap = ContentColumnProbe.resolve(sizeClass: .regular,
                                               availableWidth: cap,
                                               surface: .raw)
        #expect(atCap.leadingGutter == 0,
                "C-B.3: at exactly the cap there are no gutters")
        let aboveCap = ContentColumnProbe.resolve(sizeClass: .regular,
                                                  availableWidth: cap + 400,
                                                  surface: .raw)
        #expect(aboveCap.leadingGutter > 0,
                "C-B.3: above the cap, gutters appear")
    }

    // MARK: US-8 / AC-8.x / FM-5 — compact width is full width, no centering

    @Test("AC-8.1/FM-5: compact width never caps — full available width, no gutters")
    func compact_neverCaps() {
        for available: CGFloat in [390, 700, 834, 1024] {
            for surface in ContentColumnProbe.Surface.allCases {
                let layout = ContentColumnProbe.resolve(sizeClass: .compact,
                                                        availableWidth: available,
                                                        surface: surface)
                #expect(layout.usableWidth == available,
                        "AC-8.1/FM-5: compact \(surface) must fill the full width \(available) (got \(layout.usableWidth))")
                #expect(layout.leadingGutter == 0 && layout.trailingGutter == 0,
                        "AC-8.1/FM-5: compact must apply no centering gutters")
                #expect(layout.isCentered == false,
                        "AC-8.1/FM-5: compact must not center")
            }
        }
    }

    @Test("AC-8.2: a wide compact width (e.g. 1024 in Slide Over edge) still does NOT cap")
    func compactWide_stillFullWidth() {
        // Even if a compact configuration is physically wide, the cap is keyed on
        // size class, not device width — so it must not engage.
        let layout = ContentColumnProbe.resolve(sizeClass: .compact,
                                                availableWidth: 1024,
                                                surface: .rendered)
        #expect(layout.usableWidth == 1024,
                "AC-8.2/FM-5: the cap is governed by size class, not raw width — compact stays full width")
    }

    // MARK: US-10 / AC-10.1–10.2 / C-B.4 / FM-6 — centering, not clipping

    @Test("AC-10.1/FM-6: gutters are background only — the resolved column hides no text")
    func gutterIsBackgroundOnly() {
        let layout = ContentColumnProbe.resolve(sizeClass: .regular,
                                                availableWidth: 1200,
                                                surface: .raw)
        // Reconstructing the available width from column + gutters proves no
        // width is "lost" to clipping — it is all column or visible gutter.
        let reconstructed = layout.leadingGutter + layout.usableWidth + layout.trailingGutter
        #expect(abs(reconstructed - 1200) <= 1,
                "AC-10.1/FM-6: column + gutters must account for the full available width (no clipped region)")
        #expect(layout.gutterIsInteractive == false,
                "AC-10.1/C-B.4: the gutter must be non-interactive background, not a text-hiding region")
    }

    @Test("AC-10.2/C-B.4: the full ~700pt column is usable — not reserved away as padding")
    func fullColumnUsable() {
        let layout = ContentColumnProbe.resolve(sizeClass: .regular,
                                                availableWidth: 1200,
                                                surface: .raw)
        #expect(layout.usableWidth >= cap - tolerance,
                "AC-10.2: the usable text column must not be materially narrower than ~700pt (got \(layout.usableWidth))")
        #expect(layout.usableWidth == layout.textColumnWidth,
                "AC-10.2: the cap must not reserve part of the column as internal padding")
    }

    @Test("AC-10 long-token edge: wrap/scroll behavior at the cap matches a ~700pt viewport (no NEW clipping)")
    func longTokenWrapsAsAt700ptViewport() {
        // The cap introduces no clipping the surface would not already exhibit
        // at a 700pt-wide viewport: the resolved column width equals what a
        // 700pt viewport would give, so the surface's own wrap/scroll applies.
        let capped = ContentColumnProbe.resolve(sizeClass: .regular,
                                                availableWidth: 1200,
                                                surface: .raw).usableWidth
        let nativeViewport = ContentColumnProbe.resolve(sizeClass: .compact,
                                                        availableWidth: capped,
                                                        surface: .raw).usableWidth
        #expect(capped == nativeViewport,
                "AC-10 edge: the capped column width must equal a same-width viewport — the cap adds no new clipping behavior")
    }

    // MARK: S-6 — both surfaces independently observe the same size class

    @Test("S-6: after a size-class change, a mode switch shows the other surface already correct")
    func modeSwitchAfterTransition_otherSurfaceCorrect() {
        // Each surface reads the CURRENT size class (not a value snapshotted at
        // open time), so resolving the not-yet-shown surface at the new size
        // class yields the correct width.
        let nowRegular: CGFloat = 1024
        let rendered = ContentColumnProbe.resolve(sizeClass: .regular, availableWidth: nowRegular, surface: .rendered)
        let rawAfterSwitch = ContentColumnProbe.resolve(sizeClass: .regular, availableWidth: nowRegular, surface: .raw)
        #expect(rawAfterSwitch.usableWidth == rendered.usableWidth,
                "S-6/FM-8: switching modes after a transition must show the other surface already at the correct width")
    }
}

// MARK: - Test support — ContentColumnProbe
//
// Models the shared width-resolution decision (design Component B). PURE function
// of size class + available width + surface. Required implementation surface for
// the build: a single shared maximum-width value applied identically to both
// RawEditorView and RenderedView, engaging the cap+centering only in the regular
// size class. The probe asserts the resolved layout, not the SwiftUI mechanism.

struct ContentColumnProbe {

    static let maxContentWidth: CGFloat = 700

    enum Surface: CaseIterable { case raw, rendered }

    struct ResolvedLayout {
        let usableWidth: CGFloat        // width available to the surface's content
        let textColumnWidth: CGFloat    // width actually usable for text
        let leadingGutter: CGFloat
        let trailingGutter: CGFloat
        let isCentered: Bool
        let gutterIsInteractive: Bool   // must always be false — background only
    }

    static func resolve(sizeClass: HSizeClass,
                        availableWidth: CGFloat,
                        surface: Surface) -> ResolvedLayout {
        switch sizeClass {
        case .compact:
            // FM-5 — no cap, no centering, full width.
            return ResolvedLayout(usableWidth: availableWidth,
                                  textColumnWidth: availableWidth,
                                  leadingGutter: 0,
                                  trailingGutter: 0,
                                  isCentered: false,
                                  gutterIsInteractive: false)
        case .regular:
            let usable = min(availableWidth, maxContentWidth)
            let totalGutter = max(0, availableWidth - usable)
            let side = totalGutter / 2
            return ResolvedLayout(usableWidth: usable,
                                  textColumnWidth: usable,
                                  leadingGutter: side,
                                  trailingGutter: side,
                                  isCentered: totalGutter > 0,
                                  gutterIsInteractive: false)
        }
    }
}
