// MacMenuBarUITests.swift
// End-to-end UI tests for mac-catalyst-shell-14 — Mac menu bar, File → Open, the
// open-while-open transition, and single-window state restoration.
//
// Framework: XCUITest (Swift Testing has no UI-test equivalent on iOS 26 /
// Xcode 26 — see constitution.md → Testing).
//
// REFERENCE specs under features/mac-catalyst-shell-14/tests/. A build implementer
// mirrors them into Markus_v3UITests/, adjusting accessibility identifiers / menu
// titles to match the live host. They are written to FAIL until the feature is
// built: before the Catalyst menu bar, File → Open, and Mac restoration exist, the
// menu-bar elements are absent and the assertions fail.
//
// THESE ARE CATALYST UI BEHAVIORS. Mirroring feature 13's precedent (which used
// XCUITest for the genuinely in-app behaviors a unit test cannot reach — the real
// ⌘-chord, the discoverability overlay, the live size-class transition), the menu
// bar, the system open panel, and scene restoration are exercised end-to-end here.
// They REQUIRE a Mac Catalyst run destination (the menu bar and File → Open panel
// are unreachable on the iPhone 17 simulator named in constitution.md). Noted in
// verify.md. The menu-bar / open-panel / relaunch driving primitives are left as
// documented helper seams (as feature 13 left holdKey / size-class transition),
// since the concrete XCUITest primitive depends on the target Xcode version.
//
// Do NOT add DAG task-ID tags here — tagging happens in the next stage.
//
// Covers: US-1/AC-1.1–1.6 (menu structure, ⌘ equivalents, routing, keyboard
//         access), US-2/AC-2.1–2.3 + disabled-shortcut edge (enablement),
//         US-3/AC-3.1–3.5 + cancel/failing edges (File → Open), open-while-open
//         (C-2.4/S-4), US-5/AC-5.1–5.3 + moved/first-launch edges (restoration).
//         FM-1, FM-4, FM-6, FM-8.

import XCTest

final class MacMenuBarUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Open straight into a seeded, non-empty document so the editor is the
        // active surface (non-empty → rendered mode).
        app.launchArguments += ["-UITest-SeedFixture", "mac-fixture.md"]
        app.launch()
        XCTAssertTrue(app.otherElements["DocumentView"].waitForExistence(timeout: 10),
                      "Editor must be the active surface at start")
    }

    // MARK: - US-1 / AC-1.1–1.3 — the menu structure

    func test_fileMenu_containsOpenSaveClose_noNew() throws {
        let file = menuBarItem("File")
        file.click()
        XCTAssertTrue(app.menuItems["Open…"].waitForExistence(timeout: 3),
                      "AC-1.1: File must contain Open…")
        XCTAssertTrue(app.menuItems["Save"].exists, "AC-1.1: File must contain Save")
        XCTAssertTrue(app.menuItems["Close"].exists, "AC-1.1: File must contain Close")
        XCTAssertFalse(app.menuItems["New"].exists,
                       "AC-1.1 / FM-4: no New item may appear")
    }

    func test_viewMenu_containsStableTitledTogglePreview() throws {
        // In rendered mode.
        menuBarItem("View").click()
        XCTAssertTrue(app.menuItems["Toggle Preview"].waitForExistence(timeout: 3),
                      "AC-1.2: View must contain a Toggle Preview item")
        dismissMenu()

        // Toggle to raw, reopen the View menu — the title must be unchanged.
        app.typeKey("p", modifierFlags: .command)
        XCTAssertTrue(app.textViews["RawEditorTextView"].waitForExistence(timeout: 5))
        menuBarItem("View").click()
        XCTAssertTrue(app.menuItems["Toggle Preview"].waitForExistence(timeout: 3),
                      "AC-1.2: the Toggle Preview title must be stable across modes")
        dismissMenu()
    }

    func test_editMenu_containsSystemStandardItems() throws {
        menuBarItem("Edit").click()
        for title in ["Undo", "Cut", "Copy", "Paste", "Select All"] {
            XCTAssertTrue(app.menuItems[title].waitForExistence(timeout: 3),
                          "AC-1.3: Edit must contain the system-standard \(title) item")
        }
        dismissMenu()
    }

    // MARK: - US-1 / AC-1.4–1.5 — menu actions drive the existing flows

    func test_menuTogglePreview_matchesCmdP() throws {
        // Choosing View → Toggle Preview must perform the same toggle as ⌘P.
        menuBarItem("View").click()
        app.menuItems["Toggle Preview"].click()
        XCTAssertTrue(app.textViews["RawEditorTextView"].waitForExistence(timeout: 5),
                      "AC-1.4: View → Toggle Preview must switch rendered→raw, same as ⌘P")
        // And back, via the shortcut — proving one shared path.
        app.typeKey("p", modifierFlags: .command)
        XCTAssertTrue(app.otherElements["RenderedView"].waitForExistence(timeout: 5),
                      "AC-1.5: ⌘P and the menu item drive the same toggle")
    }

    func test_menuClose_returnsToBrowser_likeCmdW() throws {
        menuBarItem("File").click()
        app.menuItems["Close"].click()
        XCTAssertTrue(app.buttons["Create Document"].waitForExistence(timeout: 5),
                      "AC-1.4: File → Close must return to the browser, same as ⌘W")
    }

    func test_menuSave_showsNoNewConfirmationUI() throws {
        // Edit in raw, then File → Save: no new toast/dialog.
        app.typeKey("p", modifierFlags: .command)
        let raw = app.textViews["RawEditorTextView"]
        XCTAssertTrue(raw.waitForExistence(timeout: 5))
        raw.tap()
        raw.typeText(" menu-save-edit")
        menuBarItem("File").click()
        app.menuItems["Save"].click()
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 2),
                       "FM-7: File → Save must show no save dialog on success")
        XCTAssertFalse(app.staticTexts["Saved"].exists,
                       "FM-7: File → Save must show no success toast")
    }

    // MARK: - US-2 / AC-2.1–2.3 — enablement

    func test_documentScopedItems_disabledAtBrowser() throws {
        // Close to the browser, then inspect the File / View menus.
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Create Document"].waitForExistence(timeout: 5))

        menuBarItem("File").click()
        XCTAssertFalse(app.menuItems["Save"].isEnabled,
                       "AC-2.1: Save must be disabled at the browser (no document open)")
        XCTAssertFalse(app.menuItems["Close"].isEnabled,
                       "AC-2.1: Close must be disabled at the browser")
        XCTAssertTrue(app.menuItems["Open…"].isEnabled,
                      "AC-2.3: Open must remain enabled at the browser")
        dismissMenu()

        menuBarItem("View").click()
        XCTAssertFalse(app.menuItems["Toggle Preview"].isEnabled,
                       "AC-2.1: Toggle Preview must be disabled at the browser")
        dismissMenu()
    }

    func test_documentScopedItems_enabledWithDocument() throws {
        menuBarItem("File").click()
        XCTAssertTrue(app.menuItems["Save"].isEnabled, "AC-2.2: Save enabled with a document open")
        XCTAssertTrue(app.menuItems["Close"].isEnabled, "AC-2.2: Close enabled with a document open")
        dismissMenu()
        menuBarItem("View").click()
        XCTAssertTrue(app.menuItems["Toggle Preview"].isEnabled,
                      "AC-2.2: Toggle Preview enabled with a document open")
        dismissMenu()
    }

    // MARK: - Disabled-shortcut-at-browser edge (C-2.5 / FM-6)

    func test_disabledShortcutsAtBrowser_areStructuralNoOps() throws {
        app.typeKey("w", modifierFlags: .command) // to the browser
        XCTAssertTrue(app.buttons["Create Document"].waitForExistence(timeout: 5))
        // Pressing the document-scoped chords at the browser must do nothing and
        // must not crash, dismiss, or leave a rootless app.
        app.typeKey("s", modifierFlags: .command)
        app.typeKey("w", modifierFlags: .command)
        app.typeKey("p", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Create Document"].exists,
                      "C-2.5 / FM-6: ⌘S/⌘W/⌘P at the browser must be a structural no-op — the browser stays visible")
    }

    // MARK: - US-3 / AC-3.1–3.4 — File → Open

    func test_fileOpen_presentsSystemPanel() throws {
        invokeFileOpen()
        XCTAssertTrue(openPanel().waitForExistence(timeout: 5),
                      "AC-3.1: File → Open must present the system open panel")
        cancelOpenPanel()
    }

    func test_fileOpen_opensChosenMarkdownFile() throws {
        // Close to the browser first so we can observe an open from scratch.
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Create Document"].waitForExistence(timeout: 5))

        invokeFileOpen()
        chooseInOpenPanel(named: "mac-fixture.md")
        XCTAssertTrue(app.otherElements["DocumentView"].waitForExistence(timeout: 10),
                      "AC-3.3: a chosen markdown file must open via the existing presentDocument path")
    }

    // MARK: - US-3 / AC-3.5 + open-while-open (C-2.4 / S-4)

    func test_openWhileOpen_success_replacesSingleDocument() throws {
        // A document is already open (mac-fixture.md). Open another; the one
        // window must show the new file — single-window replace.
        invokeFileOpen()
        chooseInOpenPanel(named: "mac-fixture-2.md")
        XCTAssertTrue(app.otherElements["DocumentView"].waitForExistence(timeout: 10),
                      "AC-3.5: opening while open must show the chosen file in the one window")
        // Single window: there is no second document window/scene.
        XCTAssertEqual(app.windows.count, 1,
                       "FM-8: open-while-open must remain single-window")
    }

    func test_openWhileOpen_failedNewOpen_preservesPriorDocument() throws {
        // THE F-001 CASE. A document is open; choosing a file that FAILS the load
        // pipeline must leave the PRIOR document open (DC-10), surface the existing
        // "Couldn't open" alert, and NOT drop the user to the browser.
        invokeFileOpen()
        chooseInOpenPanel(named: "broken-fixture.md") // seeded to fail the pipeline

        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5),
                      "S-4: a failed new open must surface the existing 'Couldn't open' alert")
        dismissAlert()

        // The prior document is STILL open — never torn down by the failed open.
        XCTAssertTrue(app.otherElements["DocumentView"].exists,
                      "DC-10 / S-4: a failed new open must leave the PRIOR document open, not drop to the browser")
        XCTAssertFalse(app.buttons["Create Document"].exists,
                       "DC-10 / S-4: the user must NOT be dropped to the browser by a failed open")
    }

    func test_openCanceled_leavesCurrentDocumentUntouched() throws {
        invokeFileOpen()
        cancelOpenPanel()
        XCTAssertTrue(app.otherElements["DocumentView"].exists,
                      "Cancel edge: dismissing the panel must leave the current document untouched")
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 2),
                       "Cancel edge: no error is shown on cancel")
    }

    // MARK: - US-5 / AC-5.1–5.3 — single-window state restoration

    func test_relaunch_restoresPreviouslyOpenDocument() throws {
        // The seeded fixture is open and recorded as last-opened. Relaunch should
        // restore it directly (not land on the browser).
        relaunchForRestoration()
        XCTAssertTrue(app.otherElements["DocumentView"].waitForExistence(timeout: 10),
                      "AC-5.1: relaunch must restore the previously open document via the existing resume path")
        XCTAssertEqual(app.windows.count, 1,
                       "AC-5.2: restoration must restore a single window")
    }

    func test_firstLaunch_landsOnBrowser() throws {
        // Relaunch with no recorded last file — must land on the browser, no error.
        let fresh = XCUIApplication()
        fresh.launchArguments += ["-UITest-ResetResumeStore", "1"]
        fresh.launch()
        XCTAssertTrue(fresh.buttons["Create Document"].waitForExistence(timeout: 10),
                      "C-5.5: first launch with no recorded file must land on the browser")
        XCTAssertFalse(fresh.alerts.firstMatch.waitForExistence(timeout: 2),
                       "C-5.5: no error UI / placeholder window on first launch")
    }

    func test_movedOrDeletedPriorDocument_landsOnBrowserNoError() throws {
        // Relaunch with the recorded file made unreachable (moved/deleted, no
        // bookmark retarget) — fail-closed to the browser, no error UI.
        let moved = XCUIApplication()
        moved.launchArguments += ["-UITest-ResumeFileUnreachable", "1"]
        moved.launch()
        XCTAssertTrue(moved.buttons["Create Document"].waitForExistence(timeout: 10),
                      "C-5.4: an unresolvable prior document must fail-closed to the browser")
        XCTAssertFalse(moved.alerts.firstMatch.waitForExistence(timeout: 2),
                       "C-5.4 / FM-3: restoration must show NO 'file missing' dialog")
    }

    // MARK: - Catalyst UI helpers (build-step seams)
    //
    // The menu-bar / open-panel / relaunch driving primitives depend on the
    // target Xcode version and the Catalyst run destination. The spec fixes the
    // observable outcome; the build implementer wires each helper to the concrete
    // XCUITest primitive (the macOS menu bar via app.menuBars, the open panel via
    // the file-dialog element tree, relaunch via terminate()/launch()). Left as
    // documented seams, mirroring feature 13's holdKey / size-class helpers.

    private func menuBarItem(_ title: String) -> XCUIElement {
        // Catalyst surfaces a real macOS menu bar; menu titles live under menuBars.
        app.menuBars.menuBarItems[title]
    }

    private func dismissMenu() {
        // Press Escape to close an open menu without choosing an item.
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
    }

    private func invokeFileOpen() {
        // Reference intent: choose File → Open…. The implementer may instead drive
        // the ⌘O chord; both reach the same command (AC-1.5).
        menuBarItem("File").click()
        app.menuItems["Open…"].click()
    }

    private func openPanel() -> XCUIElement {
        // The system open panel as it appears on Catalyst.
        app.dialogs.firstMatch
    }

    private func chooseInOpenPanel(named name: String) {
        // Reference intent: select `name` in the open panel and confirm. The
        // implementer maps to the file-dialog element tree / "Open" button. The
        // harness seeds these fixtures into a known directory at launch.
        _ = name
    }

    private func cancelOpenPanel() {
        // Reference intent: dismiss the panel without choosing (Cancel / Escape).
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
    }

    private func dismissAlert() {
        app.alerts.firstMatch.buttons.firstMatch.tap()
    }

    private func relaunchForRestoration() {
        // Reference intent: terminate and relaunch so Mac scene-state restoration
        // runs. The implementer preserves the resume store across the relaunch.
        app.terminate()
        app = XCUIApplication()
        app.launch()
    }
}
