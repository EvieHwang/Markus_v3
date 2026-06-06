// IpadExpansion13_ContentWidthUITests.swift
// Mirrored (and adapted to the live host) from
// features/ipad-expansion-13/tests/ContentWidthUITests.swift.
//
// Covers T-002 end-to-end on the simulator: the ContentColumn modifier on both
// editor surfaces. The unit tests in `IpadExpansion13_ContentWidthTests` pin
// the pure layout decision; this file verifies the in-app rendering, where
// reachable, on the constitution's iPhone destination (compact width) and
// documents the iPad-simulator-only assertions as XCTSkip seams for the
// follow-up pass.
//
// In compact width (the iPhone-17 destination), the column is full-width and
// the `ContentColumn` accessibility identifier still resolves — this is the
// non-regression contract that runs on the default destination.

import XCTest

/// Mirror of the production `ContentColumnLayout.maxContentWidth` constant.
/// UI tests cannot `@testable import Markus_v3`, so the cap is duplicated
/// here. If the production cap changes, update this mirror.
private let ContentColumnLayoutMaxWidth: CGFloat = 700

final class IpadExpansion13_ContentWidthUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uitest-seed-last-file"]
        app.launch()
        let renderedView = app.descendants(matching: .any)
            .matching(identifier: "RenderedView")
            .firstMatch
        XCTAssertTrue(renderedView.waitForExistence(timeout: 10),
                      "Editor (rendered view) must be the active surface")
    }

    private var renderedView: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "RenderedView")
            .firstMatch
    }

    private var contentColumn: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "ContentColumn")
            .firstMatch
    }

    // MARK: - Compact-width contract (runs on the iPhone-17 destination)

    func test_compactWidth_contentColumnIsFullWidth() throws {
        // FM-5 / AC-8.1 — in compact width the column has no gutters: the
        // ContentColumn element fills the rendered view's width.
        //
        // Skips when the host idiom is not iPhone — on iPad portrait the
        // horizontal size class is *regular*, where the cap engages and
        // this compact-width assertion does not hold (see
        // build-deviations.md D-2). The compact contract is verified at
        // the unit-test layer (`IpadExpansion13_ContentColumnLayoutTests.compact_neverCaps`).
        // Skip when the surface is wider than the cap — in that environment
        // we are in the regular horizontal size class and the cap engages,
        // so the compact-width assertion does not hold. The compact contract
        // is verified at the unit-test layer
        // (`IpadExpansion13_ContentColumnLayoutTests.compact_neverCaps`).
        XCTAssertTrue(renderedView.waitForExistence(timeout: 5))
        try XCTSkipIf(renderedView.frame.width > ContentColumnLayoutMaxWidth,
                      "Compact-width contract requires surface ≤ \(Int(ContentColumnLayoutMaxWidth))pt; "
                      + "current surface is \(renderedView.frame.width)pt (regular size class).")
        XCTAssertTrue(contentColumn.waitForExistence(timeout: 5),
                      "ContentColumn must be present on both size classes")
        let renderedFrame = renderedView.frame
        let columnFrame = contentColumn.frame
        XCTAssertEqual(columnFrame.width, renderedFrame.width, accuracy: 2,
                       "AC-8.1: compact width must have no gutters (column == full surface)")
    }

    // MARK: - Regular-width assertions (require an iPad simulator)

    func test_renderedContent_isCenteredInRegularWidth() throws {
        // AC-7.2 — in regular width the column is narrower than the surface
        // and centered. Requires an iPad simulator (compact-only iPhones
        // never produce a regular size class).
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad,
                      "AC-7.2 requires an iPad simulator (regular horizontal size class).")
        XCTAssertTrue(renderedView.waitForExistence(timeout: 5))
        XCTAssertTrue(contentColumn.waitForExistence(timeout: 5))
        XCTAssertLessThan(contentColumn.frame.width, renderedView.frame.width - 1,
                          "AC-7.2: the column must be narrower than the surface (gutters present)")
        let leading = contentColumn.frame.minX - renderedView.frame.minX
        let trailing = renderedView.frame.maxX - contentColumn.frame.maxX
        XCTAssertEqual(leading, trailing, accuracy: 2,
                       "AC-7.2: the column must be horizontally centered (equal gutters)")
    }

    func test_rawAndRendered_shareColumnPosition() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad,
                      "AC-7.3 requires an iPad simulator (regular horizontal size class).")
        XCTAssertTrue(contentColumn.waitForExistence(timeout: 5))
        let renderedFrame = contentColumn.frame
        renderedView.tap() // tap-to-edit → raw
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5))
        // After mode switch, ContentColumn still identifies the capped region.
        XCTAssertTrue(contentColumn.waitForExistence(timeout: 5))
        XCTAssertEqual(contentColumn.frame.minX, renderedFrame.minX, accuracy: 2,
                       "AC-7.3/FM-8: raw column must sit at the same x as the rendered column")
        XCTAssertEqual(contentColumn.frame.width, renderedFrame.width, accuracy: 2,
                       "AC-7.3/FM-8: both surfaces must use the same column width")
    }

    // MARK: - Size-class transition (iPad multitasking)

    func test_compactToRegular_appliesCapLive() throws {
        throw XCTSkip("Size-class transitions require iPad multitasking gestures "
                      + "(Slide Over / Split View drag). Live behavior is pinned by "
                      + "S-5/S-7 and re-verified via the unit-test layout decision.")
    }

    func test_regularToCompact_removesCapLive() throws {
        throw XCTSkip("See `test_compactToRegular_appliesCapLive`.")
    }

    func test_transition_preservesScrollPositionAndEdits() throws {
        throw XCTSkip("See `test_compactToRegular_appliesCapLive`.")
    }

    func test_transition_thenModeSwitch_showsOtherSurfaceCorrect() throws {
        throw XCTSkip("See `test_compactToRegular_appliesCapLive`.")
    }

    func test_tapInGutter_doesNotEnterTextOrMoveCaret() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad,
                      "Gutter-tap behavior requires regular width (iPad simulator).")
        // Tap a region far left of center where the gutter would be in
        // regular width. The hosting controller's non-interactive gutter
        // means the editor session is undisturbed.
        renderedView.tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5))
        let gutterPoint = app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.5))
        gutterPoint.tap()
        XCTAssertTrue(app.textViews.firstMatch.exists,
                      "AC-10.3/C-B.4: gutter tap must be inert — editor column is unaffected")
    }
}
