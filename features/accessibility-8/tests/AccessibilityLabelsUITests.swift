// AccessibilityLabelsUITests.swift
// Spec tests for accessibility-8 — Component 4: Accessibility labels and hints on DetectorSurfaces.
//
// Framework: XCUITest (per constitution.md).
// These live under features/accessibility-8/tests/ as reference / human-readable
// specs; they are NOT part of the Xcode test target. The DAG step adds task-ID
// labels by updating verify.md — do not add task annotations here.
//
// Coverage:
//   AC-4.1  "Keep Mine" button has a non-empty .accessibilityLabel.
//   AC-4.2  "Keep Theirs" button has a non-empty .accessibilityLabel.
//   AC-4.3  "Discard Mine" button has a non-empty .accessibilityLabel.
//   AC-4.4  "Discard Mine" button has a non-empty .accessibilityHint.
//   AC-4.5  "Save As" (deletion banner) button has a non-empty .accessibilityLabel.
//   AC-4.6  "Dismiss" (deletion banner) button has a context-specific label
//            (not the bare word "Dismiss" alone; must include context).
//   AC-4.7  All five .accessibilityIdentifier values are present and unchanged.
//   AC-4.9  After deletion banner dismissal, a .layoutChanged notification is
//            posted (verified structurally: the banner disappears without crash
//            and the app remains usable — direct notification interception is not
//            possible in XCUITest).
//
// Launch arguments:
//   -uitest-open-seed-file          → opens sample.md into DocumentView with a live detector.
//   -uitest-suppress-settle         → disables the 2s settle window for faster conflict injection.
//   -uitest-external-change <text>  → injects a divergent external change to trigger the conflict sheet.
//   -uitest-external-delete         → injects an external file deletion to trigger the deletion banner.
//
// These mirror the patterns in ExternalChangeUITests.swift.

import XCTest

final class AccessibilityLabelsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func launch(_ args: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += args
        app.launch()
        return app
    }

    private func renderedView(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "RenderedView").firstMatch
    }

    private func openSeededFile(extraArgs: [String] = []) -> XCUIApplication {
        let app = launch(["-uitest-open-seed-file"] + extraArgs)
        XCTAssertTrue(renderedView(in: app).waitForExistence(timeout: 5),
                      "Seed file must open into the rendered view")
        return app
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

    private func waitForConflictSheet(_ app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        app.buttons["ConflictKeepMine"].waitForExistence(timeout: timeout)
    }

    private func waitForDeletionBanner(_ app: XCUIApplication, timeout: TimeInterval = 6) -> Bool {
        app.buttons["DeletionBannerSaveAs"].waitForExistence(timeout: timeout)
    }

    // MARK: - AC-4.7: .accessibilityIdentifier values are preserved

    /// AC-4.7 — All five accessibility identifiers must be present on their buttons
    /// after the feature is implemented. This verifies CC-1: no existing identifiers
    /// are removed or renamed (UI tests depend on them).
    func testConflictSheetButtonIdentifiersArePreserved() {
        let app = openSeededFile(["-uitest-suppress-settle"])
        enterRawEditor(app)
        typeUnsavedEdit(app, " divergent local edit for conflict")
        app.buttons["DebugInjectExternalChange"].tap()
        XCTAssertTrue(waitForConflictSheet(app),
                      "Conflict sheet must appear before identifier tests can run")

        XCTAssertTrue(app.buttons["ConflictKeepMine"].exists,
            "ConflictKeepMine identifier must be present and unchanged (AC-4.7)")
        XCTAssertTrue(app.buttons["ConflictKeepTheirs"].exists,
            "ConflictKeepTheirs identifier must be present and unchanged (AC-4.7)")
        XCTAssertTrue(app.buttons["ConflictDiscardMine"].exists,
            "ConflictDiscardMine identifier must be present and unchanged (AC-4.7)")
    }

    func testDeletionBannerButtonIdentifiersArePreserved() {
        let app = openSeededFile(["-uitest-external-delete"])
        XCTAssertTrue(waitForDeletionBanner(app),
                      "Deletion banner must appear before identifier tests can run")

        XCTAssertTrue(app.buttons["DeletionBannerSaveAs"].exists,
            "DeletionBannerSaveAs identifier must be present and unchanged (AC-4.7)")
        XCTAssertTrue(app.buttons["DeletionBannerDismiss"].exists,
            "DeletionBannerDismiss identifier must be present and unchanged (AC-4.7)")
    }

    // MARK: - AC-4.1 / AC-4.2 / AC-4.3: Conflict sheet button accessibility labels

    /// AC-4.1 — "Keep Mine" button must have a non-empty accessibilityLabel.
    func testKeepMineHasNonEmptyAccessibilityLabel() {
        let app = openSeededFile(["-uitest-suppress-settle"])
        enterRawEditor(app)
        typeUnsavedEdit(app, " local edits for label test")
        app.buttons["DebugInjectExternalChange"].tap()
        XCTAssertTrue(waitForConflictSheet(app))

        let button = app.buttons["ConflictKeepMine"]
        XCTAssertTrue(button.exists)
        let label = button.label
        XCTAssertFalse(label.isEmpty,
            "Keep Mine button must have a non-empty accessibilityLabel (AC-4.1). Got: '\(label)'")
    }

    /// AC-4.2 — "Keep Theirs" button must have a non-empty accessibilityLabel.
    func testKeepTheirsHasNonEmptyAccessibilityLabel() {
        let app = openSeededFile(["-uitest-suppress-settle"])
        enterRawEditor(app)
        typeUnsavedEdit(app, " local edits for label test")
        app.buttons["DebugInjectExternalChange"].tap()
        XCTAssertTrue(waitForConflictSheet(app))

        let button = app.buttons["ConflictKeepTheirs"]
        XCTAssertTrue(button.exists)
        let label = button.label
        XCTAssertFalse(label.isEmpty,
            "Keep Theirs button must have a non-empty accessibilityLabel (AC-4.2). Got: '\(label)'")
    }

    /// AC-4.3 — "Discard Mine" button must have a non-empty accessibilityLabel.
    func testDiscardMineHasNonEmptyAccessibilityLabel() {
        let app = openSeededFile(["-uitest-suppress-settle"])
        enterRawEditor(app)
        typeUnsavedEdit(app, " local edits for discard label test")
        app.buttons["DebugInjectExternalChange"].tap()
        XCTAssertTrue(waitForConflictSheet(app))

        let button = app.buttons["ConflictDiscardMine"]
        XCTAssertTrue(button.exists)
        let label = button.label
        XCTAssertFalse(label.isEmpty,
            "Discard Mine button must have a non-empty accessibilityLabel (AC-4.3). Got: '\(label)'")
    }

    // MARK: - AC-4.4: "Discard Mine" has a non-empty accessibilityHint

    /// AC-4.4 — "Discard Mine" must carry a hint explaining the action is irreversible.
    /// XCUIElement.value is not the hint; we must query via the button's accessibilityValue
    /// or use the label channel if the hint is appended. In XCUITest the hint is not
    /// directly readable as a separate property; we verify it is configured by checking
    /// the button's full accessibility label string from the app's accessibility tree.
    ///
    /// NOTE: XCUITest does not expose .accessibilityHint as a separate property on
    /// XCUIElement. The hint is spoken by VoiceOver but not readable in automation.
    /// We verify that the button exists and has a non-empty label (AC-4.3 already covers
    /// label presence); for the hint we document this limitation and rely on the structural
    /// unit-test verification in DocumentViewModeAnnouncementTests (where the probe
    /// models the hint being set). The XCUITest here is a best-effort stub.
    func testDiscardMineHasAccessibilityHint() throws {
        // XCUITest cannot read .accessibilityHint as a separate value from XCUIElement.
        // The hint is VoiceOver-only. This test serves as a documented stub confirming
        // the button is configured (label present) and that the test obligation for
        // AC-4.4 is acknowledged. Build-agent verification: enable VoiceOver on device,
        // trigger the conflict sheet, navigate to "Discard Mine", and confirm the hint
        // is announced after a VoiceOver pause.
        throw XCTSkip(
            "XCUITest cannot read .accessibilityHint as a separate property from XCUIElement. "
            + "AC-4.4 hint presence is verified structurally in the DetectorSurfaces source "
            + "(the .accessibilityHint modifier is present on ConflictDiscardMine). "
            + "Manual verification: VoiceOver on device, navigate to 'Discard Mine' in the "
            + "conflict sheet, and confirm the hint is announced (e.g., "
            + "'Your local edits cannot be recovered after this action.')."
        )
    }

    // MARK: - AC-4.5: "Save As" deletion banner button has a non-empty label

    /// AC-4.5 — The "Save As" button in the deletion banner must have a non-empty
    /// accessibilityLabel communicating saving to a new location.
    func testDeletionBannerSaveAsHasNonEmptyLabel() {
        let app = openSeededFile(["-uitest-external-delete"])
        XCTAssertTrue(waitForDeletionBanner(app))

        let button = app.buttons["DeletionBannerSaveAs"]
        XCTAssertTrue(button.exists)
        let label = button.label
        XCTAssertFalse(label.isEmpty,
            "Save As button must have a non-empty accessibilityLabel (AC-4.5). Got: '\(label)'")
    }

    // MARK: - AC-4.6: "Dismiss" banner button has a context-specific label

    /// AC-4.6 — The "Dismiss" deletion banner button must have a context-specific label
    /// that is NOT the bare word "Dismiss" alone. WCAG 2.4.6 requires the label to be
    /// descriptive enough to identify the control's purpose.
    ///
    /// Acceptable: "Dismiss file deleted notice", "Dismiss deleted-file banner", etc.
    /// Not acceptable: "Dismiss" (bare word alone).
    func testDismissBannerButtonHasContextSpecificLabel() {
        let app = openSeededFile(["-uitest-external-delete"])
        XCTAssertTrue(waitForDeletionBanner(app))

        let button = app.buttons["DeletionBannerDismiss"]
        XCTAssertTrue(button.exists)
        let label = button.label

        // Must not be empty.
        XCTAssertFalse(label.isEmpty,
            "Dismiss banner button must have a non-empty accessibilityLabel (AC-4.6). Got: '\(label)'")

        // Must not be the bare word "Dismiss" (case-insensitive).
        let isBareDismiss = label.trimmingCharacters(in: .whitespaces)
                                  .caseInsensitiveCompare("Dismiss") == .orderedSame
        XCTAssertFalse(isBareDismiss,
            "Dismiss banner button label must be context-specific, not the bare word 'Dismiss' "
            + "(AC-4.6 / WCAG 2.4.6). Got: '\(label)'")

        // Should contain context words indicating what is being dismissed.
        // Accept any label that is longer than "Dismiss" alone (7 chars).
        XCTAssertGreaterThan(label.count, 7,
            "Dismiss banner button label ('\(label)') must include context beyond 'Dismiss' (AC-4.6)")
    }

    // MARK: - AC-4.9: VoiceOver focus moves after banner dismissal (best-effort)

    /// AC-4.9 — After the deletion banner is dismissed, VoiceOver focus must not remain
    /// on the now-invisible banner controls. The mechanism is a UIAccessibility.post
    /// notification. In XCUITest we cannot intercept the notification directly, but we
    /// verify that:
    ///   (a) The banner is no longer visible after "Dismiss" is tapped.
    ///   (b) The app remains usable (no crash, document is accessible).
    ///
    /// This is sufficient end-to-end coverage for the "no stuck focus" contract; full
    /// VoiceOver focus-destination verification requires on-device manual testing.
    func testDeletionBannerDismissHidesBannerAndAppRemainsUsable() {
        let app = openSeededFile(["-uitest-external-delete"])
        XCTAssertTrue(waitForDeletionBanner(app))

        // Dismiss the banner.
        app.buttons["DeletionBannerDismiss"].tap()

        // The banner must disappear.
        XCTAssertFalse(app.buttons["DeletionBannerDismiss"].waitForExistence(timeout: 2),
            "Deletion banner must disappear after 'Dismiss' is tapped (AC-4.9)")
        XCTAssertFalse(app.buttons["DeletionBannerSaveAs"].exists,
            "Deletion banner Save As button must also disappear (AC-4.9)")

        // The app must remain usable — either rendered view or raw editor is accessible.
        let appStillUsable = renderedView(in: app).waitForExistence(timeout: 3)
            || app.textViews.firstMatch.waitForExistence(timeout: 1)
        XCTAssertTrue(appStillUsable,
            "App must remain usable after banner dismissal; "
            + "RenderedView or raw editor must be accessible (AC-4.9 no-stuck-focus guard)")
    }

    // MARK: - AC-4.8: Conflict sheet title is readable by VoiceOver

    /// AC-4.8 — The conflict sheet's title ("This file changed on another device") and
    /// subtitle remain unchanged and accessible. Verified by asserting the static text is
    /// visible when the sheet is presented.
    func testConflictSheetTitleIsPresent() {
        let app = openSeededFile(["-uitest-suppress-settle"])
        enterRawEditor(app)
        typeUnsavedEdit(app, " some local edit")
        app.buttons["DebugInjectExternalChange"].tap()
        XCTAssertTrue(waitForConflictSheet(app))

        XCTAssertTrue(app.staticTexts["This file changed on another device"].exists,
            "Conflict sheet title must be present and accessible (AC-4.8)")
    }
}
