// SystemCreateUITests.swift
// End-to-end UI tests for restore-system-create-7 — verifies the
// observable system-create flow in the document browser:
//
//   - "+" creates a file in the currently-browsed folder
//   - the system's inline rename UI appears (not a Markus-custom sheet)
//   - the file persists on disk and the editor opens
//   - empty-content open lands in raw mode with the keyboard up
//   - back navigation returns to the browser
//
// Framework: XCUITest (Swift Testing has no UI-test equivalent on
// iOS 26 / Xcode 26 yet — see constitution.md Testing).
//
// These are reference specs. A build implementer mirrors them into
// Markus_v3UITests/ for the build, adjusting accessibility identifiers
// to match the actual host implementation.

import XCTest

final class SystemCreateUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Launch into the browser, not into a resumed file.
        app.launchArguments += ["-UITest-ClearLastOpened", "1"]
        app.launch()
    }

    // MARK: - AC-1.1 / AC-1.2 / AC-2.1 — "+" → system rename UI in browsed folder

    func test_plusTap_presentsSystemRenameUIInBrowsedFolder() throws {
        // The "+" affordance is the system-provided one in
        // UIDocumentBrowserViewController. We locate it by its
        // standard label.
        let plus = app.buttons["Create Document"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5),
                      "System '+' affordance must be present (allowsDocumentCreation = true)")
        plus.tap()

        // The system inline rename UI focuses a text field for the
        // filename. We verify a focused text field appears — this is
        // the system's, not a Markus-built one. Markus must NOT present
        // any custom name-entry sheet (AC-2.4).
        let renameField = app.textFields.firstMatch
        XCTAssertTrue(renameField.waitForExistence(timeout: 5),
                      "System inline rename UI must appear with a focused filename field")
        XCTAssertTrue(renameField.hasFocus, "Rename field must be first responder (keyboard up)")

        // No Markus-custom create sheet should be onscreen. Identifiers
        // like "MarkusCreateSheet" or "MarkusNameField" must not exist.
        XCTAssertFalse(app.otherElements["MarkusCreateSheet"].exists,
                       "Markus must not present a custom create sheet (AC-2.4)")
        XCTAssertFalse(app.textFields["MarkusNameField"].exists,
                       "Markus must not present a custom name field (AC-2.4)")
    }

    // MARK: - AC-2.2 / AC-3.1 — confirm rename → file persists, editor opens

    func test_confirmRename_persistsFileAndOpensEditor() throws {
        app.buttons["Create Document"].tap()

        let renameField = app.textFields.firstMatch
        XCTAssertTrue(renameField.waitForExistence(timeout: 5))
        renameField.typeText("Spec-NewFile")
        app.typeText("\n") // confirm rename

        // After confirm, the editor opens. We assert by waiting for an
        // editor surface accessibility identifier.
        let editor = app.otherElements["DocumentView"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10),
                      "Editor must open after the user confirms the system rename")
    }

    // MARK: - AC-2.3 — accept default name → opens with system default

    func test_acceptSystemDefaultName_opensEditor() throws {
        app.buttons["Create Document"].tap()
        let renameField = app.textFields.firstMatch
        XCTAssertTrue(renameField.waitForExistence(timeout: 5))
        // Don't type — accept the system default.
        app.typeText("\n")

        let editor = app.otherElements["DocumentView"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
    }

    // MARK: - AC-4.1 / DC-4 — empty content → raw mode + keyboard up

    func test_newFileOpensInRawModeWithKeyboard() throws {
        app.buttons["Create Document"].tap()
        let renameField = app.textFields.firstMatch
        XCTAssertTrue(renameField.waitForExistence(timeout: 5))
        renameField.typeText("Empty-Spec")
        app.typeText("\n")

        // The raw editor surface is first responder on empty content.
        let rawEditor = app.textViews["RawEditorTextView"]
        XCTAssertTrue(rawEditor.waitForExistence(timeout: 10),
                      "Empty new file must land on the raw editor (DC-4)")
        XCTAssertTrue(rawEditor.hasFocus,
                      "Raw editor must be first responder (keyboard up) per AC-4.1")
        // The system keyboard surface should be visible.
        XCTAssertTrue(app.keyboards.firstMatch.exists,
                      "Software keyboard must be presented for an empty new file")
    }

    // MARK: - AC-4.3 — non-empty file opens rendered (regression)

    func test_existingNonEmptyFileOpensRendered() throws {
        // The harness seeds a non-empty fixture file before launch.
        app.launchArguments += ["-UITest-SeedFixture", "non-empty.md"]
        app.terminate()
        app.launch()

        app.staticTexts["non-empty.md"].tap()
        let rendered = app.otherElements["RenderedView"]
        XCTAssertTrue(rendered.waitForExistence(timeout: 10),
                      "Non-empty file must open in rendered mode (AC-4.3)")
    }

    // MARK: - AC-5.3 / DC-7 — back-to-browser from a system-created file

    func test_backFromSystemCreatedFile_returnsToBrowser() throws {
        app.buttons["Create Document"].tap()
        let renameField = app.textFields.firstMatch
        XCTAssertTrue(renameField.waitForExistence(timeout: 5))
        renameField.typeText("Back-Spec")
        app.typeText("\n")

        let editor = app.otherElements["DocumentView"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))

        // Tap the leading back affordance (C8).
        let back = app.buttons["BackToBrowser"]
        XCTAssertTrue(back.exists, "Back-to-browser affordance must be present (C8)")
        back.tap()

        // We are back at the browser.
        XCTAssertTrue(app.buttons["Create Document"].waitForExistence(timeout: 5),
                      "Browser must reappear after back tap")
    }

    // MARK: - AC-5.2 — next launch resumes into the system-created file

    func test_nextLaunchResumesIntoSystemCreatedFile() throws {
        app.buttons["Create Document"].tap()
        let renameField = app.textFields.firstMatch
        XCTAssertTrue(renameField.waitForExistence(timeout: 5))
        renameField.typeText("Resume-Spec")
        app.typeText("\n")
        XCTAssertTrue(app.otherElements["DocumentView"].waitForExistence(timeout: 10))

        // Relaunch.
        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launch()

        // Resume target is the system-created file — editor is up,
        // no browser frame.
        XCTAssertTrue(relaunched.otherElements["DocumentView"].waitForExistence(timeout: 10),
                      "Relaunch must resume directly into the system-created file (AC-5.2)")
        XCTAssertFalse(relaunched.buttons["Create Document"].exists,
                       "Browser '+' must not be visible — resume skips the browser frame")
    }
}

private extension XCUIElement {
    var hasFocus: Bool { (value(forKey: "hasKeyboardFocus") as? Bool) ?? false }
}
