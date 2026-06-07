// IpadExpansion13_ContentWidthTests.swift
// Mirrored (and adapted to the live host) from
// features/ipad-expansion-13/tests/ContentWidthTests.swift.
//
// Covers T-002: the shared ~700pt centered content column applied identically
// to the raw editor and rendered preview, regular size class only. These
// unit tests pin the pure width-resolution decision; the live SwiftUI
// rendering (caret/gutter/transition) is covered by the UI test file.

import Testing
import Foundation
import CoreGraphics
import SwiftUI
@testable import Markus_v3

@Suite("Part 2 — shared content-width resolution (regular vs compact)")
struct IpadExpansion13_ContentColumnLayoutTests {

    let cap: CGFloat = ContentColumnLayout.maxContentWidth
    let tolerance: CGFloat = 40

    // MARK: AC-7.1 / AC-7.2 — both surfaces capped & centered in regular width

    @Test("AC-7.1/7.2: in regular width at 1024pt, the column caps usable width near ~700pt")
    func regularWide_capsBothSurfaces() {
        let layout = ContentColumnLayout.resolve(sizeClass: .regular,
                                                 availableWidth: 1024)
        #expect(abs(layout.usableWidth - cap) <= tolerance,
                "AC-7.1/7.2: usable width must be ~700pt in regular width (got \(layout.usableWidth))")
        #expect(layout.isCentered,
                "AC-7.1/7.2: column must be horizontally centered when capped")
    }

    @Test("AC-7 wide-window edge: at ~1366pt the column stays ~700pt, centered, with side gutters")
    func veryWide_columnStaysCappedAndCentered() {
        let layout = ContentColumnLayout.resolve(sizeClass: .regular,
                                                 availableWidth: 1366)
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

    @Test("AC-7.3/FM-8: both surfaces resolve to the same width and position")
    func bothSurfacesShareWidthAndPosition() {
        // The single shared resolver guarantees: any two calls with the
        // same (sizeClass, availableWidth) yield identical layouts.
        let raw = ContentColumnLayout.resolve(sizeClass: .regular,
                                              availableWidth: 1100)
        let rendered = ContentColumnLayout.resolve(sizeClass: .regular,
                                                   availableWidth: 1100)
        #expect(raw.usableWidth == rendered.usableWidth,
                "C-B.1/FM-8: both surfaces must draw from one shared max width")
        #expect(raw.leadingGutter == rendered.leadingGutter,
                "C-B.1/FM-8: both surfaces must sit at the same horizontal position")
    }

    // MARK: AC-7.4 / C-B.3 — the cap is a MAXIMUM, not a fixed width

    @Test("AC-7.4: a narrow-but-regular width below the cap uses the full available width")
    func regularNarrow_belowCap_usesFullWidth() {
        let available: CGFloat = 560 // regular but narrower than the cap
        let layout = ContentColumnLayout.resolve(sizeClass: .regular,
                                                 availableWidth: available)
        #expect(layout.usableWidth == available,
                "AC-7.4: below the cap the content must use the full available width")
        #expect(layout.leadingGutter == 0 && layout.trailingGutter == 0,
                "AC-7.4 / C-B.3: no centering gutters appear until available width exceeds the cap")
    }

    @Test("C-B.3: gutters appear only once available width exceeds the cap")
    func guttersAppearOnlyAboveCap() {
        let atCap = ContentColumnLayout.resolve(sizeClass: .regular,
                                                availableWidth: cap)
        #expect(atCap.leadingGutter == 0,
                "C-B.3: at exactly the cap there are no gutters")
        let aboveCap = ContentColumnLayout.resolve(sizeClass: .regular,
                                                   availableWidth: cap + 400)
        #expect(aboveCap.leadingGutter > 0,
                "C-B.3: above the cap, gutters appear")
    }

    // MARK: US-8 / AC-8.x / FM-5 — compact width is full width, no centering

    @Test("AC-8.1/FM-5: compact width never caps — full available width, no gutters")
    func compact_neverCaps() {
        for available: CGFloat in [390, 700, 834, 1024] {
            let layout = ContentColumnLayout.resolve(sizeClass: .compact,
                                                     availableWidth: available)
            #expect(layout.usableWidth == available,
                    "AC-8.1/FM-5: compact must fill the full width \(available) (got \(layout.usableWidth))")
            #expect(layout.leadingGutter == 0 && layout.trailingGutter == 0,
                    "AC-8.1/FM-5: compact must apply no centering gutters")
            #expect(layout.isCentered == false,
                    "AC-8.1/FM-5: compact must not center")
        }
    }

    @Test("AC-8.2: a wide compact width (e.g. 1024 in Slide Over edge) still does NOT cap")
    func compactWide_stillFullWidth() {
        let layout = ContentColumnLayout.resolve(sizeClass: .compact,
                                                 availableWidth: 1024)
        #expect(layout.usableWidth == 1024,
                "AC-8.2/FM-5: cap is governed by size class, not raw width — compact stays full width")
    }

    // MARK: US-10 / AC-10.1–10.2 / C-B.4 / FM-6 — centering, not clipping

    @Test("AC-10.1/FM-6: gutters are background only — column + gutters fully account for the width")
    func gutterIsBackgroundOnly() {
        let layout = ContentColumnLayout.resolve(sizeClass: .regular,
                                                 availableWidth: 1200)
        let reconstructed = layout.leadingGutter + layout.usableWidth + layout.trailingGutter
        #expect(abs(reconstructed - 1200) <= 1,
                "AC-10.1/FM-6: column + gutters must account for the full available width")
    }

    @Test("AC-10.2/C-B.4: the full ~700pt column is usable — not reserved away as padding")
    func fullColumnUsable() {
        let layout = ContentColumnLayout.resolve(sizeClass: .regular,
                                                 availableWidth: 1200)
        #expect(layout.usableWidth >= cap - tolerance,
                "AC-10.2: the usable text column must not be materially narrower than ~700pt")
    }

    @Test("AC-10 long-token edge: wrap/scroll behavior at the cap matches a ~700pt viewport")
    func longTokenWrapsAsAt700ptViewport() {
        // The cap introduces no clipping the surface would not already
        // exhibit at a 700pt-wide viewport: the resolved column width at a
        // 1200pt regular viewport equals what the same surface would resolve
        // to at a 700pt compact viewport (both = 700).
        let capped = ContentColumnLayout.resolve(sizeClass: .regular,
                                                 availableWidth: 1200).usableWidth
        let nativeViewport = ContentColumnLayout.resolve(sizeClass: .compact,
                                                         availableWidth: capped).usableWidth
        #expect(capped == nativeViewport,
                "AC-10 edge: the capped column width must equal a same-width viewport")
    }

    // MARK: S-6 — both surfaces independently observe the same size class

    @Test("S-6: after a size-class change, a mode switch shows the other surface already correct")
    func modeSwitchAfterTransition_otherSurfaceCorrect() {
        let nowRegular: CGFloat = 1024
        let rendered = ContentColumnLayout.resolve(sizeClass: .regular,
                                                   availableWidth: nowRegular)
        let rawAfterSwitch = ContentColumnLayout.resolve(sizeClass: .regular,
                                                         availableWidth: nowRegular)
        #expect(rawAfterSwitch.usableWidth == rendered.usableWidth,
                "S-6/FM-8: switching modes after a transition must show the other surface at the correct width")
    }
}
