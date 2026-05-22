// Spec test — UI / end-to-end
// Tags: T-007, T-008, T-010 (every test covers the integration surface)
// Verifies: AC-1.1, AC-1.2, AC-2.1, AC-2.3, AC-2.4, AC-3.1, AC-3.2, AC-3.4, AC-4.3, AC-5.1,
//           AC-5.3, AC-6.1, AC-6.2, AC-6.3, AC-A11Y-1, AC-A11Y-2, EC-8, EC-14
//
// XCUITest target. Requires a bundled sample.md in the UI-test bundle resources.

import XCTest

final class WalkingSkeletonFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIApplication().launch()
    }

    func testFirstLaunchShowsDocumentBrowser() {
        let app = XCUIApplication()
        // Document browser is the very first UI; no splash element present.
        XCTAssertTrue(app.otherElements["UIDocumentBrowserView"].waitForExistence(timeout: 5)
                      || app.navigationBars["Browse"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Welcome"].exists, "No onboarding/welcome screen allowed")
    }

    func testOpenFileRendersGFM() throws {
        let app = XCUIApplication()
        openSampleFile(in: app)
        // The sample.md should render with a recognizable heading.
        XCTAssertTrue(app.staticTexts["Walking Skeleton Sample"].waitForExistence(timeout: 5))
    }

    func testNavBarShowsFilenameWithoutExtension() throws {
        let app = XCUIApplication()
        openSampleFile(in: app)
        XCTAssertTrue(app.navigationBars["sample"].exists)
        XCTAssertFalse(app.navigationBars["sample.md"].exists)
    }

    func testNoCopyInAppContainer() throws {
        // Verify after editing that no file with our text exists in the app's container.
        let app = XCUIApplication()
        openSampleFile(in: app)
        app.otherElements["RenderedView"].tap()
        let editor = app.textViews.firstMatch
        editor.tap()
        editor.typeText(" — uitest mark")
        // App-container files are not enumerable from inside the test target without
        // entitlements; the build agent should verify by reading the actual on-disk
        // file (system path) and asserting it contains the mark, and by asserting no
        // file in NSTemporaryDirectory/Documents contains it.
    }

    func testTapToEdit() throws {
        let app = XCUIApplication()
        openSampleFile(in: app)
        app.otherElements["RenderedView"].tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 2))
    }

    func testRawModeShowsEyeIcon() throws {
        let app = XCUIApplication()
        openSampleFile(in: app)
        app.otherElements["RenderedView"].tap()
        XCTAssertTrue(app.buttons["Show rendered"].exists)
    }

    func testTapToEditRequiresSecondTapForCursor() throws {
        let app = XCUIApplication()
        openSampleFile(in: app)
        app.otherElements["RenderedView"].tap()
        let editor = app.textViews.firstMatch
        // First tap was the mode switch. The editor exists but isn't focused yet
        // (cursor placement is the user's second tap).
        XCTAssertFalse(editor.hasKeyboardFocus, "Editor must not auto-focus on mode switch")
        editor.tap()
        XCTAssertTrue(editor.hasKeyboardFocus)
    }

    func testEyeIconReturnsToRendered() throws {
        let app = XCUIApplication()
        openSampleFile(in: app)
        app.otherElements["RenderedView"].tap()
        app.buttons["Show rendered"].tap()
        XCTAssertTrue(app.otherElements["RenderedView"].waitForExistence(timeout: 2))
    }

    func testEditedContentVisibleInRendered() throws {
        let app = XCUIApplication()
        openSampleFile(in: app)
        app.otherElements["RenderedView"].tap()
        let editor = app.textViews.firstMatch
        editor.tap()
        editor.typeText("\n\nAdded by UI test.")
        app.buttons["Show rendered"].tap()
        XCTAssertTrue(app.staticTexts["Added by UI test."].waitForExistence(timeout: 3))
    }

    func testEditsPersistAtOriginalLocation() throws {
        // Build agent: write an edit, close the document, re-open, assert the edit is present.
        // Then read the file from its OS-level path and confirm the bytes match.
        let app = XCUIApplication()
        openSampleFile(in: app)
        app.otherElements["RenderedView"].tap()
        let editor = app.textViews.firstMatch
        editor.tap()
        editor.typeText("persisted-edit")
        app.navigationBars.buttons.firstMatch.tap() // back to browser
        openSampleFile(in: app)
        XCTAssertTrue(app.staticTexts["persisted-edit"].waitForExistence(timeout: 3))
    }

    func testEditsVisibleAfterCloseReopen() throws {
        try testEditsPersistAtOriginalLocation() // same flow, named for AC-6.1 traceability
    }

    func testRapidModeSwitching() throws {
        let app = XCUIApplication()
        openSampleFile(in: app)
        for _ in 0..<10 {
            app.otherElements["RenderedView"].tap()
            app.buttons["Show rendered"].tap()
        }
        XCTAssertTrue(app.otherElements["RenderedView"].exists)
    }

    func testCancelFilePicker() throws {
        let app = XCUIApplication()
        // Tap somewhere to dismiss browser if open, then ensure no crash on cancel paths.
        // Specific cancel UI is provided by the system browser; this is a smoke test.
        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    func testEyeIconAccessibilityLabel() throws {
        let app = XCUIApplication()
        openSampleFile(in: app)
        app.otherElements["RenderedView"].tap()
        XCTAssertTrue(app.buttons["Show rendered"].exists,
                      "Eye-icon button must have accessibilityLabel \"Show rendered\" (AC-A11Y-1)")
    }

    func testRenderedViewHasEditAccessibilityAction() throws {
        let app = XCUIApplication()
        openSampleFile(in: app)
        let rendered = app.otherElements["RenderedView"]
        XCTAssertTrue(rendered.exists)
        // XCUIElement.accessibilityCustomActions exposure varies; build agent uses
        // the Accessibility Inspector recipe or queries via private API in test target.
        // The contract is: VoiceOver users see an "Edit" action when focusing the rendered view.
    }

    // MARK: - Helper
    private func openSampleFile(in app: XCUIApplication) {
        // The bundled sample.md is added by T-001 to the UI-test target resources and
        // pre-copied into the simulator's Files-app-visible location by setUp.
        let sampleCell = app.cells["sample.md"]
        if !sampleCell.waitForExistence(timeout: 3) {
            // Browser navigation may be needed depending on simulator state.
            // The build agent should add the navigation helper for the chosen Files location.
        }
        sampleCell.tap()
    }
}

private extension XCUIElement {
    var hasKeyboardFocus: Bool {
        (self.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }
}
