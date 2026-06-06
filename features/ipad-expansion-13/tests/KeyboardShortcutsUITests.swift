// KeyboardShortcutsUITests.swift
// End-to-end UI tests for ipad-expansion-13 — Part 1 (hardware keyboard shortcuts).
//
// Framework: XCUITest (Swift Testing has no UI-test equivalent on iOS 26 /
// Xcode 26 — see constitution.md → Testing).
//
// REFERENCE specs under features/ipad-expansion-13/tests/. A build implementer
// mirrors them into Markus_v3UITests/, adjusting accessibility identifiers to
// match the live host. They are written to FAIL until the feature is built:
// before ⌘P/⌘W/⌘S are wired, typing the chord has no effect, so the assertions
// (mode toggled, browser returned, etc.) fail.
//
// HOW ⌘-CHORDS ARE SENT: XCUIElement.typeKey(_:modifierFlags:) injects a
// hardware-keyboard chord into the simulator, which is exactly how the iPad
// discoverability overlay / UIKeyCommand path is exercised. Run on an iPad
// simulator with "Connect Hardware Keyboard" enabled (the destination in
// constitution.md is iPhone 17; the discoverability/regular-width cases below
// require an iPad simulator — note in verify.md).
//
// Do NOT add DAG task-ID tags here — tagging happens in the next stage.
//
// Covers: US-1/AC-1.x (+ ⌘P edge), US-2/AC-2.x (+ ⌘W edge), US-4/AC-4.x,
//         US-5/AC-5.x (discoverability overlay), US-6/AC-6.x (no-op no keyboard),
//         FM-3, FM-4.

import XCTest

final class KeyboardShortcutsUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Open straight into a seeded, non-empty document so the editor is the
        // active surface (non-empty → rendered mode per DC-4).
        app.launchArguments += ["-UITest-SeedFixture", "shortcut-fixture.md"]
        app.launch()
        // Wait for the editor surface.
        XCTAssertTrue(app.otherElements["DocumentView"].waitForExistence(timeout: 10),
                      "Editor must be the active surface at start")
    }

    // MARK: - US-1 / AC-1.1–1.3 — ⌘P toggles mode

    func test_cmdP_togglesRenderedToRawToRendered() throws {
        // Starts in rendered (seeded non-empty file).
        XCTAssertTrue(app.otherElements["RenderedView"].waitForExistence(timeout: 5),
                      "Seeded non-empty file must open in rendered mode")

        // ⌘P → raw
        app.typeKey("p", modifierFlags: .command)
        let rawEditor = app.textViews["RawEditorTextView"]
        XCTAssertTrue(rawEditor.waitForExistence(timeout: 5),
                      "AC-1.1: ⌘P from rendered must switch to the raw editor")

        // ⌘P → rendered
        app.typeKey("p", modifierFlags: .command)
        XCTAssertTrue(app.otherElements["RenderedView"].waitForExistence(timeout: 5),
                      "AC-1.2: ⌘P from raw must switch back to rendered")
    }

    func test_cmdP_repeatedAlternatesNoDrift() throws {
        for _ in 0..<4 { app.typeKey("p", modifierFlags: .command) }
        // Four presses from rendered → back to rendered.
        XCTAssertTrue(app.otherElements["RenderedView"].waitForExistence(timeout: 5),
                      "AC-1.3: four ⌘P presses must return to rendered (no accumulated drift)")
    }

    // MARK: - ⌘P edge case / FM-3 — chord not swallowed by the text view

    func test_cmdP_withKeyboardUp_togglesAndInsertsNoCharacter() throws {
        // Enter raw mode and focus the text view (keyboard up).
        app.typeKey("p", modifierFlags: .command)
        let rawEditor = app.textViews["RawEditorTextView"]
        XCTAssertTrue(rawEditor.waitForExistence(timeout: 5))
        rawEditor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "Keyboard must be up before testing the swallow case")

        let before = rawEditor.value as? String ?? ""

        // ⌘P with the text view as first responder.
        app.typeKey("p", modifierFlags: .command)

        // It must toggle to rendered (not be eaten as input).
        XCTAssertTrue(app.otherElements["RenderedView"].waitForExistence(timeout: 5),
                      "⌘P edge: with the text view focused, ⌘P must still toggle to rendered")

        // And it must NOT have inserted a literal character. Toggle back and read.
        app.typeKey("p", modifierFlags: .command)
        let rawAgain = app.textViews["RawEditorTextView"]
        XCTAssertTrue(rawAgain.waitForExistence(timeout: 5))
        let after = rawAgain.value as? String ?? ""
        XCTAssertEqual(before, after,
                       "FM-3: ⌘P must not be swallowed as text — no 'p' may be inserted")
    }

    // MARK: - US-4 / AC-4.x — ⌘S saves with no new UI

    func test_cmdS_savesWithNoNewConfirmationUI() throws {
        // Edit in raw mode, then ⌘S.
        app.typeKey("p", modifierFlags: .command)
        let rawEditor = app.textViews["RawEditorTextView"]
        XCTAssertTrue(rawEditor.waitForExistence(timeout: 5))
        rawEditor.tap()
        rawEditor.typeText(" edit-for-save")

        app.typeKey("s", modifierFlags: .command)

        // AC-4.2 / FM-2: no new save dialog, toast, or alert appears.
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 2),
                       "AC-4.2/FM-2: ⌘S must show no save dialog on success")
        XCTAssertFalse(app.staticTexts["Saved"].exists,
                       "AC-4.2/FM-2: ⌘S must show no success toast")
        // The editor remains in raw mode, undisturbed.
        XCTAssertTrue(rawEditor.exists,
                      "AC-4.3: ⌘S must not change mode or disturb the editor")
    }

    func test_cmdS_inRenderedMode_isHarmless() throws {
        // Stays in rendered; ⌘S routes through the existing save (no-op write).
        XCTAssertTrue(app.otherElements["RenderedView"].waitForExistence(timeout: 5))
        app.typeKey("s", modifierFlags: .command)
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 2),
                       "⌘S clean-buffer edge: must produce no error/alert in rendered mode")
        XCTAssertTrue(app.otherElements["RenderedView"].exists,
                      "AC-4.3: ⌘S in rendered mode must not change the surface")
    }

    // MARK: - US-2 / AC-2.x — ⌘W returns to the browser

    func test_cmdW_returnsToBrowser_inRenderedMode() throws {
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Create Document"].waitForExistence(timeout: 5),
                      "AC-2.1: ⌘W in rendered mode must return to the browser")
    }

    func test_cmdW_returnsToBrowser_inRawMode() throws {
        app.typeKey("p", modifierFlags: .command)
        XCTAssertTrue(app.textViews["RawEditorTextView"].waitForExistence(timeout: 5))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Create Document"].waitForExistence(timeout: 5),
                      "AC-2.3: ⌘W in raw mode must also return to the browser")
    }

    func test_cmdW_preservesUnsavedEdits() throws {
        // Make an edit, ⌘W (which saves synchronously), then reopen and verify.
        app.typeKey("p", modifierFlags: .command)
        let rawEditor = app.textViews["RawEditorTextView"]
        XCTAssertTrue(rawEditor.waitForExistence(timeout: 5))
        rawEditor.tap()
        rawEditor.typeText("\nUNSAVED-MARKER-ABC")

        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Create Document"].waitForExistence(timeout: 5),
                      "AC-2.1: ⌘W must return to the browser")
        // AC-2.2 / FM-2: no discard-changes prompt appeared during close.
        XCTAssertFalse(app.alerts["Discard Changes?"].exists,
                       "AC-2.2/FM-2: ⌘W must introduce no discard-changes prompt")

        // Reopen the file from the browser; the edit must be present (saved sync).
        app.staticTexts["shortcut-fixture.md"].tap()
        XCTAssertTrue(app.otherElements["DocumentView"].waitForExistence(timeout: 10))
        app.typeKey("p", modifierFlags: .command) // into raw to read text
        let reopened = app.textViews["RawEditorTextView"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 5))
        let text = reopened.value as? String ?? ""
        XCTAssertTrue(text.contains("UNSAVED-MARKER-ABC"),
                      "AC-2.2: ⌘W must save synchronously before dismissing — the edit must persist")
    }

    // MARK: - US-5 / AC-5.x — discoverability overlay (iPad + hardware keyboard)

    func test_discoverabilityOverlay_listsThreeCommands() throws {
        // Holding ⌘ surfaces the discoverability HUD. We press-and-hold the
        // Command key; the overlay elements carry each command's title.
        // (Requires an iPad simulator with a hardware keyboard connected.)
        let cmd = XCUIKeyboardKey.command
        app.holdKey(cmd.rawValue, forDuration: 1.5) // helper below

        // The three action-describing titles must be visible.
        XCTAssertTrue(app.staticTexts["Toggle Preview"].waitForExistence(timeout: 3),
                      "AC-5.1: ⌘P must appear in the overlay with an action title")
        XCTAssertTrue(app.staticTexts["Close"].exists,
                      "AC-5.1: ⌘W must appear in the overlay with an action title")
        XCTAssertTrue(app.staticTexts["Save"].exists,
                      "AC-5.1: ⌘S must appear in the overlay with an action title")

        // AC-5.2: exactly three editor commands — no ⌘N / 'New Document' entry.
        XCTAssertFalse(app.staticTexts["New Document"].exists,
                       "AC-5.2/X-2: no ⌘N 'New Document' entry — ⌘N is out of scope")
    }

    func test_discoverabilityOverlay_titleStableAcrossModes() throws {
        // The ⌘P title must not change with mode (stable, action-describing).
        app.typeKey("p", modifierFlags: .command) // → raw
        XCTAssertTrue(app.textViews["RawEditorTextView"].waitForExistence(timeout: 5))
        app.holdKey(XCUIKeyboardKey.command.rawValue, forDuration: 1.5)
        XCTAssertTrue(app.staticTexts["Toggle Preview"].waitForExistence(timeout: 3),
                      "AC-5.2: ⌘P's overlay title must be the same 'Toggle Preview' in raw mode")
    }

    // MARK: - US-6 / AC-6.x — graceful no-op without a hardware keyboard

    func test_noHardwareKeyboard_shortcutsAreNoOp() throws {
        // Relaunch declaring no hardware keyboard so the harness does not inject
        // chords; assert the editor behaves exactly as before (no crash, no
        // mode change from a chord that never arrives).
        app.terminate()
        let noKb = XCUIApplication()
        noKb.launchArguments += ["-UITest-SeedFixture", "shortcut-fixture.md",
                                 "-UITest-NoHardwareKeyboard", "1"]
        noKb.launch()
        XCTAssertTrue(noKb.otherElements["RenderedView"].waitForExistence(timeout: 10),
                      "AC-6.1: with no keyboard the seeded file still opens in rendered mode")
        // No chord can be delivered; the surface is unchanged and the app is alive.
        XCTAssertTrue(noKb.otherElements["DocumentView"].exists,
                      "AC-6.2/FM-4: registration must not crash or alter the editor without a keyboard")
    }

    func test_registration_doesNotDisableExistingGestures() throws {
        // FM-4: tap-to-edit (a touch gesture) must still work alongside the
        // registered key commands.
        XCTAssertTrue(app.otherElements["RenderedView"].waitForExistence(timeout: 5))
        app.otherElements["RenderedView"].tap()
        XCTAssertTrue(app.textViews["RawEditorTextView"].waitForExistence(timeout: 5),
                      "FM-4: tap-to-edit must still switch to raw mode with key commands registered")
        // And the back button still works (not consumed by the ⌘W command).
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Create Document"].waitForExistence(timeout: 5),
                      "FM-4: the toolbar back button must still return to the browser")
    }
}

// MARK: - Helpers

private extension XCUIElement {
    var hasFocus: Bool { (value(forKey: "hasKeyboardFocus") as? Bool) ?? false }
}

private extension XCUIApplication {
    /// Press and hold a single key for a duration to surface the iPad
    /// discoverability overlay (hold ⌘). The build implementer wires this to
    /// the available XCUITest key-hold primitive on the target Xcode version
    /// (e.g. perform a key-down via the HID event stream); the spec captures
    /// the intent: ⌘ held long enough to reveal the shortcut HUD.
    func holdKey(_ key: String, forDuration duration: TimeInterval) {
        // Reference intent only. Implementer maps to the concrete hold primitive.
        // A common realization: `typeKey` does not hold; use a key-down/up pair
        // separated by `duration`. Left as a documented seam for the build step.
        typeKey(key, modifierFlags: [])
        _ = duration
    }
}
