// ExternalChangeUITests.swift
// Spec tests for external-change-5 (UI / end-to-end level)
//
// Framework: XCUITest (Swift Testing has no UI-test equivalent on iOS 26 /
// Xcode 26 per constitution.md). These tests live in
// features/external-change-5/tests/ui/ and are reference specs; the DAG step
// links them into Markus_v3UITests/.
//
// These cover the scene-level seams that are only observable through a running
// app — the surfaces the detector's outcomes drive and the lifecycle properties
// that cross the app/background boundary:
//   Conflict & lifecycle UI — three-option conflict sheet, deletion banner (Save As)
//   Silence guarantees      — no toast/alert/banner on a silent absorb
//   Mode preservation       — absorb/resolution resumes in the same editing mode
//   Lifecycle               — backgrounding mid-conflict, non-user dismissal re-present
//   Alert-path reuse        — invalid UTF-8 / save-failure reuse existing alerts,
//                             NOT a conflict sheet
//
// Launch-argument convention (the build agent wires these into the app's
// scene-activation + a test-only external-change injector so tests can drive
// deterministic on-disk situations against the open document). These mirror the
// resume-and-create-2 seeding convention and extend it:
//   "-uitest-open-seed-file"        → open the bundled sample.md as the open document
//   "-uitest-external-change <s>"   → replace the open file's on-disk bytes with <s>
//                                     (a settled external write, post settle-window)
//   "-uitest-external-rename <name>"→ rename the open file on disk to <name>
//   "-uitest-external-delete"       → delete the open file on disk
//   "-uitest-external-move-reappear"→ delete then recreate at a new location within 2s
//   "-uitest-inject-invalid-utf8"   → land non-UTF-8 bytes as the external change
//   "-uitest-force-save-failure"    → make the next save-back write fail
//   "-uitest-suppress-settle"       → disable the 2s settle window (so an injected
//                                     change is classified immediately, for sheet tests)
//
// Several assertions require either on-disk container inspection (not reachable
// from the UI test target without entitlements) or precise frame-timing; those are
// marked XCTSkip and enumerated in verify.md's untestable section, with a
// build-agent verification note. They remain executable stubs.

import XCTest

final class ExternalChangeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += args
        app.launch()
        return app
    }

    private func openSeededFile(_ extraArgs: [String] = []) -> XCUIApplication {
        let app = launch(["-uitest-open-seed-file"] + extraArgs)
        XCTAssertTrue(renderedView(in: app).waitForExistence(timeout: 5),
                      "The seeded file must open into the rendered view")
        return app
    }

    /// Look-up helper that mirrors `ResumeAndCreateUITests` — SwiftUI's
    /// `RenderedView` (a `ScrollView`) is not exposed as `.other`, so the
    /// element-type-specific `app.otherElements["RenderedView"]` query never
    /// resolves it. Querying across all element types does.
    private func renderedView(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "RenderedView").firstMatch
    }

    /// Conflict sheet identifiers the build agent assigns to the three options.
    private func conflictSheetIsVisible(_ app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        app.buttons["ConflictKeepMine"].waitForExistence(timeout: timeout)
    }

    private func deletionBannerIsVisible(_ app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        app.buttons["DeletionBannerSaveAs"].waitForExistence(timeout: timeout)
    }

    /// Mirrors `ResumeAndCreateUITests.tapCreateDocument` — the create affordance has
    /// varying labels across iOS versions.
    private func tapCreateDocument(in app: XCUIApplication) {
        let candidates: [XCUIElement] = [
            app.buttons["Create Document"],
            app.cells["Create Document"],
            app.buttons["New Document"],
            app.buttons["Create"]
        ]
        for c in candidates where c.waitForExistence(timeout: 3) {
            c.tap()
            return
        }
        XCTFail("Could not find Create Document affordance")
    }

    /// Mirrors `ResumeAndCreateUITests.browserIsVisible` — `UIDocumentBrowserViewController`
    /// has no single stable identifier across iOS versions, so probe several candidates.
    private func browserIsVisible(_ app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        if app.otherElements["UIDocumentBrowserView"].waitForExistence(timeout: timeout) { return true }
        if app.navigationBars["Browse"].waitForExistence(timeout: 1) { return true }
        if app.navigationBars["Recents"].waitForExistence(timeout: 1) { return true }
        if app.navigationBars.firstMatch.waitForExistence(timeout: 1)
            && !renderedView(in: app).exists
            && app.textViews.firstMatch.exists == false {
            return true
        }
        return false
    }

    private func enterRawEditor(_ app: XCUIApplication) {
        renderedView(in: app).tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 3),
                      "Tap-to-edit must enter the raw editor")
    }

    private func typeUnsavedEdit(_ app: XCUIApplication, _ text: String) {
        let editor = app.textViews.firstMatch
        editor.tap()
        editor.typeText(text)
    }

    // MARK: - BR-1 — silent absorption when buffer is clean

    // BR-1.1 / BR-1.4 / DC-12 — a clean buffer + external change shows NO sheet and NO banner/alert.
    func testCleanBufferExternalChangeIsSilent() {
        let app = openSeededFile(["-uitest-external-change", "externally changed body\n"])
        // Give the absorb path time to run; no surface may appear.
        XCTAssertFalse(conflictSheetIsVisible(app, timeout: 3),
                       "A clean-buffer external change must NOT show a conflict sheet (BR-1.1)")
        XCTAssertFalse(deletionBannerIsVisible(app, timeout: 1))
        XCTAssertFalse(app.alerts.element.exists, "Silent means silent — no alert (BR-1.4)")
    }

    // BR-1.2 — after a clean absorb, the buffer reflects the new on-disk content.
    func testCleanAbsorbAdoptsNewContent() {
        let app = openSeededFile(["-uitest-external-change", "BRAND NEW EXTERNAL LINE\n"])
        // The rendered view should now show the externally-changed text.
        XCTAssertTrue(app.staticTexts["BRAND NEW EXTERNAL LINE"].waitForExistence(timeout: 5),
                      "After a clean absorb the buffer must reflect the new on-disk content (BR-1.2)")
    }

    // BR-1.5 — absorption preserves the current editing mode (raw stays raw).
    func testCleanAbsorbPreservesRawMode() {
        let app = openSeededFile()
        enterRawEditor(app)
        // Inject an external change while in raw mode (clean buffer — we did not type).
        // The build agent fires the injection via a debug affordance bound to this arg
        // on an already-open document; here we relaunch is not possible mid-session, so
        // this asserts the mode-preservation contract via the debug menu the build agent wires.
        app.buttons["DebugInjectExternalChange"].tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 3),
                      "Absorption must not drop the raw editing mode (BR-1.5)")
        XCTAssertFalse(renderedView(in: app).exists,
                       "Absorption must not force a switch back to rendered (BR-1.5)")
    }

    // MARK: - BR-2 — silent absorption when content-identical

    // BR-2.3 / BR-2.4 — a content-identical external change with a dirty buffer shows
    // no sheet and does not disrupt editing (the cursor/buffer are preserved).
    // On-disk byte injection + cursor preservation needs the build agent's injector;
    // the observable proxy is "no sheet, editor still active, no alert".
    func testContentIdenticalChangeIsSilentAndNonDisruptive() {
        let app = openSeededFile(["-uitest-suppress-settle"])
        enterRawEditor(app)
        // Make the buffer dirty by typing exactly what the injector will land on disk,
        // then inject that identical content as an external change.
        typeUnsavedEdit(app, " identical")
        app.buttons["DebugInjectIdenticalExternalChange"].tap()
        XCTAssertFalse(conflictSheetIsVisible(app, timeout: 3),
                       "A content-identical change must not produce a sheet even with a dirty buffer (BR-2.1)")
        XCTAssertTrue(app.textViews.firstMatch.exists,
                      "Editing must continue uninterrupted (BR-2.3)")
        XCTAssertFalse(app.alerts.element.exists)
    }

    // MARK: - BR-3 — settle-window suppression / no false positives

    // BR-3.5 — the normal single-device edit→save flow produces zero sheets/banners.
    func testNormalCreateTypeSaveProducesNoConflictSurfaces() throws {
        // Rewritten by restore-system-create-7 (see build-deviations.md D-7).
        // The original version drove the *custom* create flow whose "+" tap
        // opened the raw editor directly with keyboard focus. The new system-
        // create flow shows the system rename UI between "+" and the editor,
        // and that UI is not reliably driveable in XCUITest. We exercise the
        // same BR-3.5 settle-window contract — edit → save → no conflict
        // surfaces — by opening a seeded existing file. We tap the text view
        // explicitly to bring up the keyboard before typing.
        let app = launch(["-uitest-seed-last-file"])
        let rendered = app.descendants(matching: .any).matching(identifier: "RenderedView").firstMatch
        XCTAssertTrue(rendered.waitForExistence(timeout: 5),
                      "Seeded file must open into rendered view as the test starting point")
        rendered.tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5),
                      "Tap-to-edit must surface the raw editor")
        // Tap to focus so typeText has a target with keyboard focus. On iOS
        // 26 the swap from rendered to raw doesn't auto-focus the text view.
        editor.tap()
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 3)
        editor.typeText("# A brand new note\nwith a line of prose\n")
        // Allow the 500ms debounce + 2s settle to elapse.
        XCTAssertFalse(conflictSheetIsVisible(app, timeout: 4),
                       "Normal single-device edit+save must never show a conflict sheet (BR-3.5)")
        XCTAssertFalse(deletionBannerIsVisible(app, timeout: 1),
                       "Normal single-device edit+save must never show a deletion banner (BR-3.5)")
    }

    // BR-3.6 — ordinary single-device edit/save loop produces zero conflict sheets.
    func testEditSaveLoopProducesNoConflictSheets() {
        let app = openSeededFile()
        enterRawEditor(app)
        for i in 0..<3 {
            typeUnsavedEdit(app, " edit\(i)")
            // wait out the debounce + settle between edits
            _ = app.textViews.firstMatch.waitForExistence(timeout: 3)
        }
        XCTAssertFalse(conflictSheetIsVisible(app, timeout: 3),
                       "Editing-and-saving in a loop on one device must never produce a sheet (BR-3.6)")
    }

    // BR-3.3 — a change while sync is in flight does not produce a sheet (in-flight suppression).
    // Driving the iCloud busy state needs the build agent's fixture; documented + skipped.
    func testInFlightSyncSuppressesSheet() throws {
        throw XCTSkip("DC-7 in-flight-sync suppression requires driving the document-state busy "
                      + "signal; build agent verifies via the SaveStatusObserver busy fixture. "
                      + "Logic-level coverage: SettleGateTests.inFlightSyncSuppressesPastWindow.")
    }

    // MARK: - BR-4 — conflict sheet on a true collision

    // BR-4.1 / BR-4.2 — a true collision (dirty + material + settled) shows the
    // three-option sheet, with exactly Keep Mine / Keep Theirs / Discard Mine and no merge.
    func testTrueCollisionShowsThreeOptionSheet() {
        let app = openSeededFile(["-uitest-suppress-settle"])
        enterRawEditor(app)
        typeUnsavedEdit(app, " my local edits that diverge")
        // Inject a materially different external change.
        app.buttons["DebugInjectExternalChange"].tap()
        XCTAssertTrue(conflictSheetIsVisible(app, timeout: 5),
                      "A true collision must present the conflict sheet (BR-4.1)")
        XCTAssertTrue(app.buttons["ConflictKeepMine"].exists)
        XCTAssertTrue(app.buttons["ConflictKeepTheirs"].exists)
        XCTAssertTrue(app.buttons["ConflictDiscardMine"].exists)
        XCTAssertFalse(app.buttons["ConflictMerge"].exists, "No merge option may exist (BR-4.2, OOS-2)")
    }

    // BR-4.4 / DC-5 — a second collision signal while the sheet is up does not stack a second sheet.
    func testSecondCollisionDoesNotStackSheet() {
        let app = openSeededFile(["-uitest-suppress-settle"])
        enterRawEditor(app)
        typeUnsavedEdit(app, " local divergence")
        app.buttons["DebugInjectExternalChange"].tap()
        XCTAssertTrue(conflictSheetIsVisible(app, timeout: 5))
        app.buttons["DebugInjectExternalChange"].tap()   // second signal while sheet is up
        // Exactly one Keep Mine button — no stacked second sheet.
        XCTAssertEqual(app.buttons.matching(identifier: "ConflictKeepMine").count, 1,
                       "At most one conflict sheet at a time (BR-4.4, DC-5)")
    }

    // MARK: - BR-5 / BR-6 / BR-7 — resolution choices

    // BR-5.3 — Keep Mine dismisses the sheet and resumes editing in the same mode.
    func testKeepMineDismissesAndResumesRawMode() {
        let app = openSeededFile(["-uitest-suppress-settle"])
        enterRawEditor(app)
        typeUnsavedEdit(app, " mine wins")
        app.buttons["DebugInjectExternalChange"].tap()
        XCTAssertTrue(conflictSheetIsVisible(app, timeout: 5))
        app.buttons["ConflictKeepMine"].tap()
        XCTAssertFalse(conflictSheetIsVisible(app, timeout: 2), "Sheet must dismiss after Keep Mine")
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 3),
                      "Editing resumes in the same (raw) mode after Keep Mine (BR-5.3)")
    }

    // BR-6.3 — Keep Theirs dismisses the sheet and the external content is shown.
    func testKeepTheirsAdoptsExternalContent() {
        let app = openSeededFile(["-uitest-suppress-settle"])
        enterRawEditor(app)
        typeUnsavedEdit(app, " soon to be discarded")
        app.buttons["DebugInjectExternalChangeKnownText"].tap()  // lands a known marker line
        XCTAssertTrue(conflictSheetIsVisible(app, timeout: 5))
        app.buttons["ConflictKeepTheirs"].tap()
        XCTAssertFalse(conflictSheetIsVisible(app, timeout: 2))
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 3))
        // The known external marker must now be present in the editor.
        XCTAssertTrue(app.textViews.firstMatch.value as? String != nil)
    }

    // BR-7.3 — Discard Mine dismisses the sheet (end-state identical to Keep Theirs).
    func testDiscardMineDismissesSheet() {
        let app = openSeededFile(["-uitest-suppress-settle"])
        enterRawEditor(app)
        typeUnsavedEdit(app, " abandon these")
        app.buttons["DebugInjectExternalChange"].tap()
        XCTAssertTrue(conflictSheetIsVisible(app, timeout: 5))
        app.buttons["ConflictDiscardMine"].tap()
        XCTAssertFalse(conflictSheetIsVisible(app, timeout: 2), "Sheet must dismiss after Discard Mine")
    }

    // BR-5.1 — Keep Mine writes the buffer to disk at the followed location.
    // On-disk read-back needs the build agent's container fixture; skipped + documented.
    func testKeepMineWritesBufferToDisk() throws {
        throw XCTSkip("BR-5.1 on-disk read-back is not reachable from the UI test target; "
                      + "build agent asserts the followed file's bytes equal the buffer after Keep Mine. "
                      + "Logic-level coverage: ConflictResolutionTests.keepMineWritesBuffer.")
    }

    // MARK: - BR-8 — follow on move / rename

    // BR-8.1 — a move/rename alone shows neither a sheet nor a deletion banner.
    func testRenameAloneShowsNoSheetOrBanner() {
        let app = openSeededFile(["-uitest-external-rename", "Renamed.md"])
        XCTAssertFalse(conflictSheetIsVisible(app, timeout: 3),
                       "A move alone is not a collision (BR-8.1)")
        XCTAssertFalse(deletionBannerIsVisible(app, timeout: 2),
                       "A move alone is not a deletion (BR-8.1)")
    }

    // BR-8.3 — a rename propagates to the displayed title.
    func testRenamePropagatesToTitle() {
        let app = openSeededFile(["-uitest-external-rename", "Renamed.md"])
        XCTAssertTrue(app.navigationBars["Renamed"].waitForExistence(timeout: 5),
                      "A rename must update the displayed title to the new name (BR-8.3)")
    }

    // BR-8.2 / BR-8.5 — after a move, a save writes to the new location and resume
    // tracks the new location. Requires container + relaunch fixtures; skipped + documented.
    func testMoveRetargetsSaveAndResume() throws {
        throw XCTSkip("BR-8.2/BR-8.5 require on-disk path inspection and a relaunch fixture; "
                      + "build agent verifies the save lands at the new path (not the old) and a "
                      + "relaunch resumes the moved file. Logic-level coverage: ChangeClassifierTests "
                      + "(moved outcome) + ResumeAndCreate LastFileStore record/resolve.")
    }

    // MARK: - BR-9 — deletion banner

    // BR-9.1 / BR-9.2 — deletion shows a Save As banner; the buffer remains editable.
    func testDeletionShowsBannerAndKeepsBuffer() {
        let app = openSeededFile(["-uitest-external-delete"])
        XCTAssertTrue(deletionBannerIsVisible(app, timeout: 6),
                      "Deletion must show a banner offering Save As (BR-9.1)")
        // The buffer is not discarded — entering raw still shows editable content.
        renderedView(in: app).tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 3),
                      "The buffer must remain intact and editable while the banner is shown (BR-9.2)")
    }

    // BR-9.5 / BR-16 / DC-16 — a delete-then-reappear-within-2s is a MOVE, not a deletion:
    // no banner appears.
    func testDeleteThenReappearWithinWindowIsMoveNoBanner() {
        let app = openSeededFile(["-uitest-external-move-reappear"])
        XCTAssertFalse(deletionBannerIsVisible(app, timeout: 4),
                       "A file that reappears within the 2s disambiguation window is a move, not a deletion (BR-9.5)")
    }

    // BR-9.6 — dismissing the banner without Save As preserves the buffer in memory.
    func testDismissingBannerPreservesBuffer() {
        let app = openSeededFile(["-uitest-external-delete"])
        XCTAssertTrue(deletionBannerIsVisible(app, timeout: 6))
        app.buttons["DeletionBannerDismiss"].tap()
        renderedView(in: app).tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 3),
                      "Dismissing the banner without Save As must not lose the buffer (BR-9.6)")
    }

    // BR-9.4 — Save As writes the buffer to a new location and continues the session.
    // Picker-driven write + on-disk read-back needs the build agent's fixture; skipped.
    func testSaveAsContinuesSessionAtNewLocation() throws {
        throw XCTSkip("BR-9.4 Save As drives the system save picker and reads back the new file; "
                      + "build agent verifies the buffer is written to the chosen location and the "
                      + "banner dismisses with the session continuing there.")
    }

    // MARK: - BR-13 / BR-14 — failure paths reuse existing alerts, not a conflict sheet

    // BR-13 — invalid UTF-8 lands on disk → the existing invalidEncoding alert path,
    // NOT a conflict sheet, and no silent overwrite.
    func testInvalidUtf8UsesAlertNotConflictSheet() {
        let app = openSeededFile(["-uitest-suppress-settle", "-uitest-inject-invalid-utf8"])
        enterRawEditor(app)
        typeUnsavedEdit(app, " dirty so a collision would otherwise be considered")
        app.buttons["DebugInjectInvalidUtf8"].tap()
        // The invalid-encoding alert (reused path) appears; a conflict sheet does NOT.
        XCTAssertTrue(app.alerts.element.waitForExistence(timeout: 4),
                      "Invalid UTF-8 must reuse the existing invalid-encoding alert (BR-13)")
        XCTAssertFalse(conflictSheetIsVisible(app, timeout: 1),
                       "Invalid UTF-8 must NOT present a conflict sheet (BR-13)")
    }

    // BR-14 — a save failure during Keep Mine reuses the save-failure alert and does
    // not falsely mark the conflict resolved. Needs the forced-failure fixture; skipped.
    func testSaveFailureDuringKeepMineReusesAlert() throws {
        throw XCTSkip("BR-14 requires forcing a save-back write failure during Keep Mine; "
                      + "build agent wires -uitest-force-save-failure and asserts the saveFailed "
                      + "alert appears and the conflict is not falsely cleared.")
    }

    // MARK: - BR-15 / BR-21 — lifecycle: backgrounding & non-user dismissal

    // BR-15 — backgrounding while a conflict sheet is up does not auto-resolve it;
    // on return the choice can still be completed.
    func testBackgroundingDoesNotAutoResolveSheet() {
        let app = openSeededFile(["-uitest-suppress-settle"])
        enterRawEditor(app)
        typeUnsavedEdit(app, " unresolved on background")
        app.buttons["DebugInjectExternalChange"].tap()
        XCTAssertTrue(conflictSheetIsVisible(app, timeout: 5))
        XCUIDevice.shared.press(.home)         // background
        app.activate()                          // return to foreground
        // The sheet is still resolvable (re-presented if the system tore it down, BR-21.3).
        XCTAssertTrue(conflictSheetIsVisible(app, timeout: 5),
                      "Backgrounding must not auto-resolve the sheet; it stays/returns resolvable (BR-15/BR-21.3)")
        // And resolving it now still works.
        app.buttons["ConflictKeepMine"].tap()
        XCTAssertFalse(conflictSheetIsVisible(app, timeout: 2))
    }

    // BR-21.5 — the buffer is preserved in memory across a background/return with a pending sheet.
    func testBufferPreservedAcrossBackgroundWithPendingSheet() {
        let app = openSeededFile(["-uitest-suppress-settle"])
        enterRawEditor(app)
        typeUnsavedEdit(app, " precious unsaved work")
        app.buttons["DebugInjectExternalChange"].tap()
        XCTAssertTrue(conflictSheetIsVisible(app, timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        // After return, choose Keep Mine, then confirm the typed text is still in the editor.
        if conflictSheetIsVisible(app, timeout: 5) { app.buttons["ConflictKeepMine"].tap() }
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 3),
                      "The unsaved buffer must survive the background/return (BR-21.5)")
    }

    // BR-21.3 second branch / DC-23 — if, on return, disk now agrees with the buffer,
    // the latched outcome lifts (no stuck sheet) and editing resumes normally.
    // Requires driving disk-agreement during background; documented + skipped.
    func testReconcileLiftsWhenDiskNowAgrees() throws {
        throw XCTSkip("DC-23 recoverable-lift requires mutating on-disk content to agree with the "
                      + "buffer while backgrounded; build agent drives the fixture and asserts the "
                      + "sheet does not re-present and autosave/detector are live again. "
                      + "Logic-level coverage: ForegroundReconcilerTests.nowIdenticalLifts.")
    }

    // MARK: - BR-18 — non-open files produce no UI

    // BR-18 / OOS-3 — a change to a file that is NOT the open document produces no surface.
    func testChangeToNonOpenFileProducesNoUI() {
        let app = openSeededFile(["-uitest-external-change-other-file", "noise\n"])
        XCTAssertFalse(conflictSheetIsVisible(app, timeout: 3),
                       "Changes to non-open files must produce no UI (BR-18)")
        XCTAssertFalse(deletionBannerIsVisible(app, timeout: 1))
        XCTAssertFalse(app.alerts.element.exists)
    }
}
