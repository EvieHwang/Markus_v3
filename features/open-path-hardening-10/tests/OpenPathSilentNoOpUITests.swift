// OpenPathSilentNoOpUITests.swift
// End-to-end UI tests for open-path-hardening-10 (DC-1, DC-6a; BR-3.1)
//
// Framework: XCUITest (per constitution.md — Swift Testing has no UI-test
// equivalent yet on iOS 26 / Xcode 26). These are reference / human-readable
// specs; the build mirrors them into Markus_v3UITests/ when picking up the
// matching DAG task.
//
// The behavioral contract under E2E test:
//   - DC-1: every open attempt terminates in either a presented document or
//           a presented alert; no silent no-op.
//   - DC-6a: the alert host is the BrowserHostController root view, so the
//            alert is on screen even when no document has ever been
//            presented in this session (cold launch).
//   - BR-3.1: every load-failure class surfaces an alert before control
//             returns to the browser idle state.
//
// Launch-arguments contract (the build vends these to seed the simulator
// with the right problem-file in the document browser):
//   -uitest-stage-problem-file <kind>
//     where <kind> ∈ {nonUTF8, utf16BOM, mixedEncoding, oversized,
//                     permissionDenied, movedMidPick, validUTF8}
//
// Each stage writes a fixture into the app's document container before the
// browser is shown, so the test can tap it and observe the resulting alert
// (or, for validUTF8, the resulting editor).

import XCTest

final class OpenPathSilentNoOpUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // DC-1 / BR-1.1 — A well-formed UTF-8 file opens without an alert.
    // The editor surface (the rendered/raw mode toggle) is on screen; the
    // browser's alert is not.
    func test_wellFormedFile_opensWithoutAlert() {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-stage-problem-file", "validUTF8"]
        app.launch()

        // Tap the staged file in the browser.
        let file = app.collectionViews.cells.containing(.staticText, identifier: "validUTF8.md").firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 5))
        file.tap()

        // Editor surface appears; no alert.
        let editor = app.otherElements["DocumentView.root"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    // DC-1 / DC-6a / BR-3.1 — On a cold launch, picking a non-UTF-8 file
    // produces an alert on the browser host (NOT on a DocumentView that
    // does not yet exist). The user is never left staring at "nothing
    // happened."
    func test_coldLaunchFailedPick_showsAlertOnBrowserHost() {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-stage-problem-file", "nonUTF8"]
        app.launch()

        let file = app.collectionViews.cells.containing(.staticText, identifier: "not-utf8.md").firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 5))
        file.tap()

        // Alert is on screen, presented on the browser host (no document
        // editor was created).
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5),
                      "DC-6a: cold-launch failed pick must present an alert "
                    + "on the browser host, not silently return.")
        // No DocumentView was instantiated.
        XCTAssertFalse(app.otherElements["DocumentView.root"].exists)

        // Dismiss → browser is pickable again.
        alert.buttons["Dismiss"].tap()
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertTrue(file.exists, "BR-2.4: after dismiss, the browser is in "
                                 + "a pickable state.")
    }

    // DC-1 / BR-3.1 — Every problem-file class produces an alert (no silent
    // return), and each is dismissable, returning the user to a pickable
    // browser.
    func test_everyFailureClass_showsAlertNoSilentReturn() {
        let cases: [(String, String, String)] = [
            // (stage-kind, expected-cell-name, expected-substring-in-alert)
            ("nonUTF8",          "not-utf8.md",        "UTF-8"),
            ("utf16BOM",         "utf16.md",           "UTF-8"),
            ("mixedEncoding",    "mixed.md",           "UTF-8"),
            ("oversized",        "huge.md",            "large"),
            ("permissionDenied", "no-perm.md",         "permission"),
            ("movedMidPick",     "vanished.md",        "no longer"),
        ]

        for (kind, cellName, expectedSubstring) in cases {
            let app = XCUIApplication()
            app.launchArguments += ["-uitest-stage-problem-file", kind]
            app.launch()

            let file = app.collectionViews.cells.containing(.staticText, identifier: cellName).firstMatch
            XCTAssertTrue(file.waitForExistence(timeout: 5),
                          "Stage \(kind): fixture cell must exist.")
            file.tap()

            let alert = app.alerts.firstMatch
            XCTAssertTrue(alert.waitForExistence(timeout: 5),
                          "BR-3.1: failure class \(kind) must produce an alert.")
            // DC-7 — alert text names the failure class.
            let alertText = alert.staticTexts.allElementsBoundByIndex
                .map { $0.label }
                .joined(separator: " ")
            XCTAssertTrue(alertText.localizedCaseInsensitiveContains(expectedSubstring),
                          "DC-7: alert for \(kind) must mention \(expectedSubstring) "
                        + "(got: \(alertText)).")

            // Dismiss → browser is pickable.
            alert.buttons["Dismiss"].tap()
            XCTAssertFalse(app.alerts.firstMatch.exists)

            app.terminate()
        }
    }
}
