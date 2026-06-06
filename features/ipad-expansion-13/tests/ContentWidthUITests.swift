// ContentWidthUITests.swift
// End-to-end UI tests for ipad-expansion-13 — Part 2 (line-length constraint).
//
// Framework: XCUITest (Swift Testing has no UI-test equivalent — constitution.md).
//
// REFERENCE specs under features/ipad-expansion-13/tests/. Mirror into
// Markus_v3UITests/ for the build, adjusting accessibility identifiers.
// Written to FAIL until the feature is built: before the cap exists the rendered
// content stretches edge-to-edge (frame(maxWidth: .infinity)), so the centering /
// gutter / live-transition assertions fail.
//
// These cover the IN-APP, observable parts of Part 2 that the pure-decision unit
// tests (ContentWidthTests.swift) cannot reach:
//   US-9 / AC-9.1–9.3 — live response to size-class transitions (no reopen)
//   US-10 / AC-10.3 + C-B.4 — caret/selection stay in the column; gutter non-interactive
//   FM-7 — a transition does not reset scroll to top or discard unsaved edits
//   S-5, S-7 — presentation-only, applied to the visible surface, orthogonal to scroll/save
//
// SIZE-CLASS TRANSITIONS in XCUITest are driven via iPad multitasking (Slide Over
// / Split View drag) or device rotation. The realization of the transition gesture
// is left to the build implementer (a documented helper seam below); the spec
// fixes the observable outcome. These tests REQUIRE an iPad simulator (a regular
// width class is unreachable on iPhone). Noted in verify.md.
//
// Do NOT add DAG task-ID tags here — that happens in the next stage.

import XCTest

final class ContentWidthUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITest-SeedFixture", "long-content.md"]
        app.launch()
        XCTAssertTrue(app.otherElements["DocumentView"].waitForExistence(timeout: 10),
                      "Editor must be the active surface")
    }

    // MARK: - AC-7.1/7.2 (observable) — content is centered in regular width

    func test_renderedContent_isCenteredInRegularWidth() throws {
        // On a full-screen iPad (regular width) the rendered column must not
        // span the full window — there must be empty gutters on both sides.
        let rendered = app.otherElements["RenderedView"]
        XCTAssertTrue(rendered.waitForExistence(timeout: 5))

        // The content column is identified separately from the full surface.
        let column = app.otherElements["ContentColumn"]
        XCTAssertTrue(column.waitForExistence(timeout: 5),
                      "AC-7.2: the capped content column must be present in regular width")
        XCTAssertLessThan(column.frame.width, rendered.frame.width - 1,
                          "AC-7.2: the column must be narrower than the full surface (gutters present)")
        // Centered: leading gutter ≈ trailing gutter.
        let leading = column.frame.minX - rendered.frame.minX
        let trailing = rendered.frame.maxX - column.frame.maxX
        XCTAssertEqual(leading, trailing, accuracy: 2,
                       "AC-7.2: the column must be horizontally centered (equal gutters)")
    }

    func test_rawAndRendered_shareColumnPosition() throws {
        // AC-7.3 / FM-8 — switching modes must not shift the column.
        let renderedColumn = app.otherElements["ContentColumn"]
        XCTAssertTrue(renderedColumn.waitForExistence(timeout: 5))
        let renderedFrame = renderedColumn.frame

        app.otherElements["RenderedView"].tap() // tap-to-edit → raw
        let rawColumn = app.otherElements["ContentColumn"]
        XCTAssertTrue(rawColumn.waitForExistence(timeout: 5))
        XCTAssertEqual(rawColumn.frame.minX, renderedFrame.minX, accuracy: 2,
                       "AC-7.3/FM-8: the raw column must sit at the same x as the rendered column")
        XCTAssertEqual(rawColumn.frame.width, renderedFrame.width, accuracy: 2,
                       "AC-7.3/FM-8: both surfaces must use the same column width")
    }

    // MARK: - US-9 / AC-9.x — live size-class transition

    func test_compactToRegular_appliesCapLive() throws {
        // Begin in a compact configuration (Slide Over), then expand to regular.
        enterCompactWidth()
        let surface = app.otherElements["RenderedView"]
        XCTAssertTrue(surface.waitForExistence(timeout: 5))
        // In compact, the column spans the full (narrow) width — no gutters.
        let compactColumn = app.otherElements["ContentColumn"]
        let compactLeading = compactColumn.frame.minX - surface.frame.minX
        XCTAssertEqual(compactLeading, 0, accuracy: 2,
                       "AC-8.1: compact width must have no leading gutter")

        // Transition compact → regular WITHOUT reopening the document.
        enterRegularWidth()
        XCTAssertTrue(app.otherElements["DocumentView"].exists,
                      "AC-9.1: the document must NOT reopen on the transition")
        let regularColumn = app.otherElements["ContentColumn"]
        let regularSurface = app.otherElements["RenderedView"]
        XCTAssertLessThan(regularColumn.frame.width, regularSurface.frame.width - 1,
                          "AC-9.1: the cap+centering must apply live after compact→regular")
    }

    func test_regularToCompact_removesCapLive() throws {
        enterRegularWidth()
        let regularColumn = app.otherElements["ContentColumn"]
        XCTAssertTrue(regularColumn.waitForExistence(timeout: 5))
        let regularSurface = app.otherElements["RenderedView"]
        XCTAssertLessThan(regularColumn.frame.width, regularSurface.frame.width - 1,
                          "precondition: regular width is capped")

        enterCompactWidth()
        let compactColumn = app.otherElements["ContentColumn"]
        let compactSurface = app.otherElements["RenderedView"]
        XCTAssertEqual(compactColumn.frame.width, compactSurface.frame.width, accuracy: 2,
                       "AC-9.2: compact width must return to full-width live (cap removed)")
    }

    func test_transition_preservesScrollPositionAndEdits() throws {
        // FM-7 — a transition must not reset scroll to top or discard edits.
        enterRegularWidth()
        // Enter raw, type a marker, scroll down.
        app.otherElements["RenderedView"].tap()
        let rawEditor = app.textViews["RawEditorTextView"]
        XCTAssertTrue(rawEditor.waitForExistence(timeout: 5))
        rawEditor.tap()
        rawEditor.typeText("\nTRANSITION-MARKER-XYZ")
        rawEditor.swipeUp() // scroll away from the top

        // Transition regular → compact.
        enterCompactWidth()

        // The edit must still be present (no edit loss).
        let editorAfter = app.textViews["RawEditorTextView"]
        XCTAssertTrue(editorAfter.waitForExistence(timeout: 5))
        let text = editorAfter.value as? String ?? ""
        XCTAssertTrue(text.contains("TRANSITION-MARKER-XYZ"),
                      "FM-7: the size-class transition must not discard unsaved edits")
        // The document was not reopened (still the same editor surface).
        XCTAssertTrue(app.otherElements["DocumentView"].exists,
                      "FM-7: the transition must not require reopening the document")
    }

    func test_transition_thenModeSwitch_showsOtherSurfaceCorrect() throws {
        // AC-9.3 / S-6 — after a transition, switching modes shows the newly
        // shown surface at the correct width for the CURRENT size class.
        enterCompactWidth()
        enterRegularWidth() // now regular, rendered showing
        app.otherElements["RenderedView"].tap() // → raw
        let rawColumn = app.otherElements["ContentColumn"]
        let rawSurface = app.otherElements["RawEditorTextView"]
        XCTAssertTrue(rawColumn.waitForExistence(timeout: 5))
        XCTAssertLessThan(rawColumn.frame.width, rawSurface.frame.width - 1,
                          "AC-9.3/S-6: after a transition, the newly shown raw surface must already be capped")
    }

    // MARK: - US-10 / AC-10.3 + C-B.4 — caret & non-interactive gutter

    func test_tapInGutter_doesNotEnterTextOrMoveCaret() throws {
        // C-B.4 / FM-6 — the gutter is non-interactive background. Tapping it
        // in raw mode must not place a caret there or steal the touch.
        enterRegularWidth()
        app.otherElements["RenderedView"].tap() // → raw
        let rawEditor = app.textViews["RawEditorTextView"]
        XCTAssertTrue(rawEditor.waitForExistence(timeout: 5))
        let surface = app.otherElements["DocumentView"]

        // Tap far to the leading side, inside the gutter (outside the column).
        let gutterPoint = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.5))
        gutterPoint.tap()

        // No selection/caret should be reported in a gutter region. We assert
        // the editor did not gain a caret outside its column by checking the
        // text view's bounds still contain any caret activity (proxy: the tap
        // did not dismiss/replace the editor and no character was inserted).
        let text = rawEditor.value as? String ?? ""
        XCTAssertFalse(text.contains("\u{200B}"),
                       "C-B.4: a gutter tap must not inject content")
        XCTAssertTrue(rawEditor.exists,
                      "AC-10.3/C-B.4: a gutter tap must be inert — the editor column is unaffected")
    }

    func test_typingAtColumnEdge_caretStaysWithinColumn() throws {
        // AC-10.3 — typing toward the right edge wraps/scrolls within the
        // centered column; the caret never renders in or behind a gutter.
        enterRegularWidth()
        app.otherElements["RenderedView"].tap()
        let rawEditor = app.textViews["RawEditorTextView"]
        XCTAssertTrue(rawEditor.waitForExistence(timeout: 5))
        rawEditor.tap()
        rawEditor.typeText(String(repeating: "wordwordword ", count: 30))
        // The text view's frame must remain within the centered column.
        let column = app.otherElements["ContentColumn"]
        XCTAssertTrue(column.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(rawEditor.frame.maxX, column.frame.maxX + 2,
                                 "AC-10.3: the text/caret region must stay within the centered column's right edge")
    }

    // MARK: - Size-class transition helpers (build-step seams)
    //
    // The transition mechanism (Slide Over / Split View drag, or rotation) is
    // an implementation detail of the test harness. The spec fixes the
    // observable outcome (capped vs. full-width); the build implementer wires
    // these helpers to the concrete multitasking/rotation primitives available
    // on the target Xcode/simulator. Left as documented seams.

    private func enterCompactWidth() {
        // Reference intent: put the app in a compact horizontal size class
        // (e.g. Slide Over, or a narrow Split View pane). Implementer realizes
        // via XCUIDevice multitasking or a launch-argument-driven override.
        app.launchArguments_appendOverride("-UITest-ForceSizeClass", "compact")
    }

    private func enterRegularWidth() {
        // Reference intent: full-screen iPad / regular horizontal size class.
        app.launchArguments_appendOverride("-UITest-ForceSizeClass", "regular")
    }
}

private extension XCUIApplication {
    /// Documented seam: applies a size-class override at runtime. The build step
    /// may instead drive a real multitasking/rotation transition; what matters
    /// for the spec is that after the call the app is in the named size class
    /// WITHOUT the document being reopened (AC-9.x / FM-7).
    func launchArguments_appendOverride(_ flag: String, _ value: String) {
        // Reference-only. Implementer maps to the live transition primitive.
        _ = (flag, value)
    }
}
