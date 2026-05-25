// ResumeAndCreateUITests.swift
// Spec tests for resume-and-create-2 (UI / end-to-end level)
//
// Framework: XCUITest (Swift Testing has no UI-test equivalent on iOS 26 / Xcode 26
// per constitution.md). These tests live in features/resume-and-create-2/tests/ui/
// and are reference specs; the DAG step links them into Markus_v3UITests/.
//
// These cover the scene-level seams that can only be observed through a running app:
//   C2 LaunchResumeBranch — resume-vs-browser at scene activation, zero browser flash
//   C4 CreateDocumentHandler — new file opens in raw editor, keyboard up, deferred write
//   C8 BackToBrowser — leading back chevron + edge-swipe reveal the browser
//
// Several tests use XCTSkip where the assertion requires on-disk inspection of the app
// container (not reachable from the test target without entitlements) or requires a
// device-only timing observation (frame-zero presentation order). These are marked and
// also enumerated in verify.md's untestable section — they remain executable stubs that
// the build agent fills in with the chosen simulator/Files-app fixture path.
//
// Launch-argument convention used below (the build agent wires these into the app's
// scene-activation path so tests can drive deterministic launch states):
//   "-uitest-reset-last-file"   → clear any stored last-opened reference (first-launch)
//   "-uitest-stale-last-file"   → plant a stored reference that cannot resolve
//   "-uitest-seed-last-file"    → plant a resolvable reference to the bundled sample.md

import XCTest

final class ResumeAndCreateUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += args
        app.launch()
        return app
    }

    private func browserIsVisible(_ app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        app.otherElements["UIDocumentBrowserView"].waitForExistence(timeout: timeout)
            || app.navigationBars["Browse"].waitForExistence(timeout: timeout)
    }

    // MARK: - Story A: Resume on launch (C2)

    // BR-4 / DC-4 — first-ever launch (no stored reference) lands in the browser.
    func testFirstLaunchShowsDocumentBrowser() {
        let app = launch(["-uitest-reset-last-file"])
        XCTAssertTrue(browserIsVisible(app), "First launch must land in the document browser")
        XCTAssertFalse(app.staticTexts["Welcome"].exists, "No onboarding/splash allowed")
    }

    // BR-2 / DC-2 — a launch with a resolvable reference lands directly in the rendered view.
    func testResumeLaunchOpensRenderedView() {
        let app = launch(["-uitest-seed-last-file"])
        // The rendered view of the seeded sample is the first interactive screen.
        XCTAssertTrue(app.otherElements["RenderedView"].waitForExistence(timeout: 5),
                      "A resolvable last-file reference must open straight into the rendered view")
    }

    // BR-2 / DC-2 — on resume, the browser is NOT the landing screen.
    func testResumeLaunchDoesNotLandOnBrowser() {
        let app = launch(["-uitest-seed-last-file"])
        _ = app.otherElements["RenderedView"].waitForExistence(timeout: 5)
        // Once the rendered view is up, the browser must not be the top/visible screen.
        XCTAssertTrue(app.otherElements["RenderedView"].exists)
        XCTAssertFalse(app.navigationBars["Browse"].exists,
                       "Browser must not be the landing screen on resume")
    }

    // BR-3 / DC-3 — no browser flash on resume.
    // XCUITest cannot reliably sample frame-zero presentation order on the simulator;
    // DC-3 is the design's named build-time escalation trigger. This stub documents the
    // contract and must be verified on a physical device by the build agent.
    func testNoBrowserFlashOnResume() throws {
        throw XCTSkip("DC-3 zero-frame-flash is a device-only timing observation; verify on device. "
                      + "If the host cannot present the editor at frame zero, escalate per design.md.")
    }

    // BR-5 / BR-19 / DC-4 — an unreachable/stale reference falls through to the browser, silently.
    func testStaleReferenceFallsThroughSilently() {
        let app = launch(["-uitest-stale-last-file"])
        XCTAssertTrue(browserIsVisible(app), "A stale reference must fall through to the browser")
        // No error UI attributing the fallback to a missing file.
        XCTAssertFalse(app.alerts.element.exists, "No alert allowed on stale-bookmark fallback")
        XCTAssertFalse(app.staticTexts["File not found"].exists)
        XCTAssertFalse(app.staticTexts["Could not open"].exists)
    }

    // BR-6 — a resumed file supports the same tap-to-edit behavior as a browser-opened file.
    func testResumedFileIsEditable() {
        let app = launch(["-uitest-seed-last-file"])
        XCTAssertTrue(app.otherElements["RenderedView"].waitForExistence(timeout: 5))
        app.otherElements["RenderedView"].tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 2),
                      "A resumed file must enter raw editing identically to a browser-opened file")
    }

    // BR-18 / DC-15 — leaving via back and relaunching still resumes the same file.
    // Inspecting on-disk persistence across relaunch needs the build agent's fixture; the
    // observable here is that a second launch with the same seed still resumes.
    func testBackThenRelaunchStillResumes() {
        let app = launch(["-uitest-seed-last-file"])
        XCTAssertTrue(app.otherElements["RenderedView"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap() // back to browser
        XCTAssertTrue(browserIsVisible(app))
        // Relaunch without clearing the reference: it must resume again.
        app.terminate()
        let relaunched = launch(["-uitest-seed-last-file"])
        XCTAssertTrue(relaunched.otherElements["RenderedView"].waitForExistence(timeout: 5),
                      "Back navigation must not clear the last-opened reference (DC-15)")
    }

    // MARK: - Story B: New file creation (C4)

    // BR-7 / BR-8 / DC-6 — Create Document produces an Untitled.md and opens it.
    func testCreateDocumentOpensUntitledMd() {
        let app = launch(["-uitest-reset-last-file"])
        XCTAssertTrue(browserIsVisible(app))
        tapCreateDocument(in: app)
        // New file opens; its title (filename without extension) is "Untitled".
        XCTAssertTrue(app.navigationBars["Untitled"].waitForExistence(timeout: 5),
                      "Create Document must produce a file named Untitled.md")
    }

    // BR-12 / DC-8 — new file opens directly in the raw editor.
    func testNewFileOpensInRawEditor() {
        let app = launch(["-uitest-reset-last-file"])
        XCTAssertTrue(browserIsVisible(app))
        tapCreateDocument(in: app)
        // The raw editor's text view is present and is the first screen (not RenderedView).
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5),
                      "A new file must open straight into the raw editor")
        XCTAssertFalse(app.otherElements["RenderedView"].exists,
                       "A new file must not open in the rendered view")
    }

    // BR-12 / DC-8 — the editor's text view is first responder with the keyboard up.
    func testNewFileEditorHasKeyboardFocus() {
        let app = launch(["-uitest-reset-last-file"])
        XCTAssertTrue(browserIsVisible(app))
        tapCreateDocument(in: app)
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(editor.hasKeyboardFocus,
                      "A new file's editor must be first responder with the keyboard active")
    }

    // BR-13 / BR-24 / BR-25 / DC-9 — an untyped new file leaves no trace and does not
    // consume the Untitled name. On-disk inspection of the app container is not reachable
    // from the test target; the observable proxy is that a second Create still yields
    // "Untitled" (name not consumed).
    func testUntypedNewFileDoesNotConsumeName() {
        let app = launch(["-uitest-reset-last-file"])
        XCTAssertTrue(browserIsVisible(app))

        tapCreateDocument(in: app)
        XCTAssertTrue(app.navigationBars["Untitled"].waitForExistence(timeout: 5))
        // Leave without typing.
        app.navigationBars.buttons.firstMatch.tap() // back to browser
        XCTAssertTrue(browserIsVisible(app))

        // A second Create must still produce "Untitled" (not "Untitled 2") — name not consumed.
        tapCreateDocument(in: app)
        XCTAssertTrue(app.navigationBars["Untitled"].waitForExistence(timeout: 5),
                      "Abandoning an untyped new file must not consume the Untitled name (DC-9)")
        XCTAssertFalse(app.navigationBars["Untitled 2"].exists)
    }

    // BR-14 — once content is typed and saved, the file persists at its resolved name.
    // Direct on-disk verification needs the build agent's container path; the in-app
    // observable is that the typed content survives a close/reopen.
    func testTypedNewFilePersists() throws {
        throw XCTSkip("Requires on-disk container inspection of the persisted Untitled[ n].md; "
                      + "build agent verifies the file exists with typed content at the resolved path.")
    }

    // BR-15 — a persisted new file becomes the last-opened file (resumes on relaunch).
    func testTypedNewFileBecomesLastOpened() throws {
        throw XCTSkip("Requires terminate+relaunch with the newly persisted file as the resume target; "
                      + "build agent wires the fixture (depends on BR-14 persistence).")
    }

    // BR-23 — first-ever launch then create lands a new Untitled.md in the raw editor.
    func testFirstLaunchThenCreate() {
        let app = launch(["-uitest-reset-last-file"])
        XCTAssertTrue(browserIsVisible(app), "Fresh install lands in the browser (BR-4)")
        tapCreateDocument(in: app)
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5),
                      "Create from a first-ever-launch browser opens a new file in the raw editor")
        XCTAssertTrue(app.navigationBars["Untitled"].exists)
    }

    // MARK: - Story C: Back navigation (C8)

    // BR-16 / DC-13 — the rendered view exposes a leading back chevron to the browser.
    func testBackChevronFromRenderedReturnsToBrowser() {
        let app = launch(["-uitest-seed-last-file"])
        XCTAssertTrue(app.otherElements["RenderedView"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(browserIsVisible(app), "Back chevron from rendered view must reveal the browser")
    }

    // BR-16 / DC-13 — the raw editor also exposes a leading back chevron to the browser.
    func testBackChevronFromRawEditorReturnsToBrowser() {
        let app = launch(["-uitest-seed-last-file"])
        XCTAssertTrue(app.otherElements["RenderedView"].waitForExistence(timeout: 5))
        app.otherElements["RenderedView"].tap() // enter raw mode
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 2))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(browserIsVisible(app), "Back chevron from raw editor must reveal the browser")
    }

    // BR-17 / DC-14 — the standard edge-swipe-back returns to the browser.
    func testEdgeSwipeBackReturnsToBrowser() {
        let app = launch(["-uitest-seed-last-file"])
        XCTAssertTrue(app.otherElements["RenderedView"].waitForExistence(timeout: 5))
        // Swipe from the very left edge rightwards — the standard interactive pop.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(browserIsVisible(app), "Edge-swipe-back must reveal the browser")
    }

    // BR-25 — back navigation out of an untyped new file leaves no file (name not consumed).
    func testBackFromUntypedNewFileLeavesNoFile() {
        let app = launch(["-uitest-reset-last-file"])
        XCTAssertTrue(browserIsVisible(app))
        tapCreateDocument(in: app)
        XCTAssertTrue(app.navigationBars["Untitled"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap() // back without typing
        XCTAssertTrue(browserIsVisible(app))
        // Re-create: still "Untitled", confirming nothing was left behind.
        tapCreateDocument(in: app)
        XCTAssertTrue(app.navigationBars["Untitled"].waitForExistence(timeout: 5))
    }

    // MARK: - Helper

    /// Taps the system browser's "Create Document" affordance. The exact element label /
    /// position is supplied by UIDocumentBrowserViewController; the build agent confirms
    /// the accessibility identifier for the chosen iOS version.
    private func tapCreateDocument(in app: XCUIApplication) {
        let create = app.buttons["Create Document"]
        if create.waitForExistence(timeout: 3) {
            create.tap()
        } else {
            // Fallback: the create affordance may be a cell or a "+"-style control on the
            // browser. The build agent pins the correct identifier here.
            app.cells["Create Document"].tap()
        }
    }
}

private extension XCUIElement {
    var hasKeyboardFocus: Bool {
        (self.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }
}
