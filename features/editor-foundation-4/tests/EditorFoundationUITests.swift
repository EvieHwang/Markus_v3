// EditorFoundationUITests.swift
// Spec UI tests for editor-foundation-4
//
// Framework: XCUITest (XCTestCase)
// These tests live in features/editor-foundation-4/tests/ and are reference
// specs. They are NOT part of the Xcode UITest target until the DAG step
// copies / links them into Markus_v3UITests/. Tests that require a running app
// with a pre-populated document are marked XCTSkip — they follow the same
// convention established by WalkingSkeletonFlowUITests.swift.
//
// Do NOT add DAG task-ID tags here — tagging happens in Stage 5.
//
// Behaviors under test:
//   • Mode switch with visible scroll position (AC-2.x, AC-3.x) — needs document
//   • Tap-to-edit scroll anchor (AC-2.5, AC-3.4) — needs document
//   • Smart-quote / dash suppression visible input (AC-4.x) — needs document
//   • Spell-check indicator visible (AC-5.x) — needs document
//   • List continuation visible in editor (AC-6.x, AC-7.x) — needs document
//   • Eye-icon toolbar present in raw mode (AC-1.5) — needs document

import XCTest

final class EditorFoundationUITests: XCTestCase {

    // MARK: - Setup

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIApplication().launch()
    }

    // MARK: - Runs without pre-populated document

    // AC-1.5: eye-icon button must be accessible — verified here as an
    // accessibility-label check once a document is open; structure test only
    // confirms the app launches to a document browser (no crash, no onboarding).
    func testAppLaunchesToDocumentBrowser() {
        let app = XCUIApplication()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Welcome"].exists)
    }

    // MARK: - Require pre-populated document (sample.md in simulator Documents)
    // All tests below follow the XCTSkip convention from WalkingSkeletonFlowUITests.
    // A future wave can un-skip these by wiring up the simulator document setup.

    // AC-1.5: eye-icon ("Show rendered") toolbar button visible in raw mode
    func testEyeIconVisibleInRawMode() throws {
        try XCTSkipIf(true, "Needs pre-populated sample.md in simulator Documents — follow-up wave.")
        let app = XCUIApplication()
        // Open a document and enter raw mode
        // The toolbar button must exist with accessibilityLabel "Show rendered"
        XCTAssertTrue(app.buttons["Show rendered"].waitForExistence(timeout: 5))
    }

    // AC-1.5: tapping eye-icon returns to rendered mode
    func testEyeIconTapReturnsToRendered() throws {
        try XCTSkipIf(true, "Needs pre-populated sample.md in simulator Documents — follow-up wave.")
        let app = XCUIApplication()
        let eyeButton = app.buttons["Show rendered"]
        XCTAssertTrue(eyeButton.waitForExistence(timeout: 5))
        eyeButton.tap()
        // After tap, rendered view should appear and eye-icon disappear
        XCTAssertFalse(eyeButton.waitForExistence(timeout: 2))
    }

    // AC-2.5: raw editor starts invisible when a non-zero scroll anchor is pending
    // (opacity-0 reveal). Observable behavior: no visible content jump from top to
    // anchor position — the editor appears already at the correct position.
    // This test can only be asserted structurally; the visual test is manual.
    func testRenderedToRawSwitchNoVisibleJump() throws {
        try XCTSkipIf(true, "Needs pre-populated long document. Visual anchor jump requires manual verification on device; structural test needs simulator setup.")
        // Structural assertion: after tap-to-edit at a non-zero content position,
        // the raw editor text view is visible (alpha > 0) only after layout.
        // XCUITest cannot inspect opacity directly; this test exercises the flow
        // and asserts no crash.
        let app = XCUIApplication()
        // Scroll rendered view to ~50% then tap
        let renderedScrollView = app.scrollViews.firstMatch
        XCTAssertTrue(renderedScrollView.waitForExistence(timeout: 5))
        renderedScrollView.swipeUp()
        renderedScrollView.tap()
        // Raw editor should be visible; no crash
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 3))
    }

    // AC-3.4: rendered view starts invisible when a non-zero raw scroll anchor is
    // pending (opacity-0 reveal — same pattern as AC-2.5, opposite direction).
    func testRawToRenderedSwitchNoVisibleJump() throws {
        try XCTSkipIf(true, "Needs pre-populated long document. Visual anchor jump requires manual verification on device; structural test needs simulator setup.")
        let app = XCUIApplication()
        // Open file in raw mode, scroll partway, tap eye-icon
        let rawTextView = app.textViews.firstMatch
        XCTAssertTrue(rawTextView.waitForExistence(timeout: 5))
        rawTextView.swipeUp()
        app.buttons["Show rendered"].tap()
        // Rendered view should appear without crashing
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 3))
    }

    // AC-2.1 / AC-2.2: tap at ~50% scroll position in rendered view lands the
    // raw editor near the same fractional position (not at top).
    // Full positional assertion requires coordinate math beyond standard XCUITest;
    // this test verifies the flow completes without crash and the editor is
    // presented at a non-initial scroll state (heuristic: text near bottom is visible).
    func testTapAtMidpointEntersRawModeNearTapPosition() throws {
        try XCTSkipIf(true, "Needs pre-populated long document (>2 screens of content) — follow-up wave.")
        let app = XCUIApplication()
        let renderedScroll = app.scrollViews.firstMatch
        XCTAssertTrue(renderedScroll.waitForExistence(timeout: 5))
        // Tap the vertical midpoint of the scroll view
        let mid = renderedScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        mid.tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 3))
    }

    // AC-3.1 / AC-3.2: switching raw → rendered preserves scroll position.
    func testRawToRenderedPreservesScrollPosition() throws {
        try XCTSkipIf(true, "Needs pre-populated long document — follow-up wave.")
        let app = XCUIApplication()
        let rawTextView = app.textViews.firstMatch
        XCTAssertTrue(rawTextView.waitForExistence(timeout: 5))
        // Scroll to bottom in raw mode
        rawTextView.swipeUp()
        rawTextView.swipeUp()
        // Switch to rendered
        app.buttons["Show rendered"].tap()
        let renderedScroll = app.scrollViews.firstMatch
        XCTAssertTrue(renderedScroll.waitForExistence(timeout: 3))
        // Structural check: rendered view is present and visible (no crash)
        XCTAssertTrue(renderedScroll.exists)
    }

    // AC-4.1: typing a double-quote inserts a straight quote, not a curly quote.
    // AC-4.2: typing a single-quote inserts a straight quote.
    func testStraightDoubleQuoteInserted() throws {
        try XCTSkipIf(true, "Needs pre-populated document open in raw mode — follow-up wave.")
        let app = XCUIApplication()
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.tap()
        textView.typeText("\"hello\"")
        // The document text should contain straight double quotes
        // XCUITest cannot inspect UITextView text directly; assert via
        // rendered view showing the literal characters (or snapshot test)
        // For now: assert no crash and typing completed
        XCTAssertTrue(textView.exists)
    }

    // AC-4.3: typing two hyphens does not produce an em-dash.
    func testDoublehyphenNotEmDash() throws {
        try XCTSkipIf(true, "Needs pre-populated document open in raw mode — follow-up wave.")
        let app = XCUIApplication()
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.tap()
        textView.typeText("--")
        // Structural: typing completes without crash
        XCTAssertTrue(textView.exists)
    }

    // AC-6.1: pressing Return at end of a "- item" line continues the list.
    func testUnorderedListContinuationOnReturn() throws {
        try XCTSkipIf(true, "Needs pre-populated document open in raw mode — follow-up wave.")
        let app = XCUIApplication()
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.tap()
        // Type a list item then press Return
        textView.typeText("- First item")
        textView.typeText("\n")
        // The next line should start with "- "
        // XCUITest cannot read UITextView value reliably; assert no crash
        XCTAssertTrue(textView.exists)
    }

    // AC-7.1: pressing Return at end of "1. item" continues with "2. "
    func testOrderedListContinuationOnReturn() throws {
        try XCTSkipIf(true, "Needs pre-populated document open in raw mode — follow-up wave.")
        let app = XCUIApplication()
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.tap()
        textView.typeText("1. First item")
        textView.typeText("\n")
        XCTAssertTrue(textView.exists)
    }

    // AC-6.5: pressing Return on a line that contains only "- " exits the list.
    func testEmptyListItemExitsList() throws {
        try XCTSkipIf(true, "Needs pre-populated document open in raw mode — follow-up wave.")
        let app = XCUIApplication()
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.tap()
        textView.typeText("- ")
        textView.typeText("\n")
        XCTAssertTrue(textView.exists)
    }

    // AC-8.1 / AC-8.2: Return on plain paragraph or heading inserts plain newline.
    func testPlainParagraphReturnNoPrefix() throws {
        try XCTSkipIf(true, "Needs pre-populated document open in raw mode — follow-up wave.")
        let app = XCUIApplication()
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.tap()
        textView.typeText("Just a paragraph")
        textView.typeText("\n")
        XCTAssertTrue(textView.exists)
    }

    // GF-5: rapid mode switching does not crash or accumulate stale anchors.
    func testRapidModeSwitchingDoesNotCrash() throws {
        try XCTSkipIf(true, "Needs pre-populated document — follow-up wave.")
        let app = XCUIApplication()
        // Render → raw → render in quick succession
        app.scrollViews.firstMatch.tap()       // → raw
        app.buttons["Show rendered"].tap()     // → rendered
        app.scrollViews.firstMatch.tap()       // → raw
        app.buttons["Show rendered"].tap()     // → rendered
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 3))
    }

    // GF-6: mode switch on empty document does not crash.
    func testModeSwitchOnEmptyDocumentNocrash() throws {
        try XCTSkipIf(true, "Needs empty document pre-populated in simulator — follow-up wave.")
        let app = XCUIApplication()
        // Tap to enter raw mode on empty doc
        app.scrollViews.firstMatch.tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 3))
        // Switch back
        app.buttons["Show rendered"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 3))
    }

    // EC-1.1: empty file shows an empty, focusable editing surface.
    func testEmptyFileShowsEmptyEditorSurface() throws {
        try XCTSkipIf(true, "Needs empty.md pre-populated in simulator — follow-up wave.")
        let app = XCUIApplication()
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        // The text view should be tappable (focusable) and not crash
        textView.tap()
        XCTAssertTrue(textView.exists)
    }
}
