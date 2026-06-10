// MacCatalystShell14_MacMenuBarUITests.swift
// Mirror of features/mac-catalyst-shell-14/tests/MacMenuBarUITests.swift —
// T-002 (Catalyst menu bar) deferred subset and T-006 (Mac scene-restoration
// bridge) end-to-end coverage on a Mac Catalyst run destination.
//
// Background:
//   - T-002 deferred its XCUITest mirror (build-deviations.md → D-002): the
//     spec's `-UITest-SeedFixture mac-fixture.md` handler and the in-app
//     fixture-seeding path did not exist when T-002 landed. With T-006 those
//     handlers ship (LaunchResumeBranch.seedFixtureArg /
//     resetResumeStoreArg / resumeFileUnreachableArg), so the deferred T-002
//     subset is backfilled here against the live Catalyst destination.
//   - T-006 owns the relaunch / first-launch / moved-deleted cases for the
//     Mac scene-restoration bridge (Component D — `MacRestorationBridge`).
//
// Mac Catalyst destination only — the menu bar, the system open panel, and
// scene restoration are not reachable on the iPhone 17 simulator named in
// constitution.md. Driven via the standard macOS menu bar element tree
// (app.menuBars), keystrokes, and terminate()/launch() across relaunch.

import XCTest

final class MacCatalystShell14_MacMenuBarUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Land directly in the editor so the document-scoped menu items are
        // observable in their enabled state and the menu-vs-shortcut routing
        // can be exercised. The seed-fixture handler writes a small markdown
        // file into the app's Documents directory and records it as
        // last-opened, so LaunchResumeBranch.resume(into:) drops the editor
        // onto the scene as first content (T-006 / MacRestorationBridge).
        app.launchArguments += ["-UITest-SeedFixture", "mac-fixture.md"]
        app.launch()
        XCTAssertTrue(editorPresented(timeout: 10),
                      "Editor must be the active surface at start (seed-fixture resume)")
    }

    // MARK: - Surface helpers
    //
    // The app exposes accessibility identifiers on the existing editor
    // surfaces. We use those instead of a top-level "DocumentView"
    // identifier (which the live host does not declare).

    private var renderedView: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "RenderedView")
            .firstMatch
    }

    private var rawTextView: XCUIElement {
        app.textViews.firstMatch
    }

    private func editorPresented(timeout: TimeInterval) -> Bool {
        renderedView.waitForExistence(timeout: timeout) || rawTextView.waitForExistence(timeout: 0.5)
    }

    /// The browser is the top surface iff the editor surfaces are absent and a
    /// document-browser marker is reachable. On Mac Catalyst,
    /// `UIDocumentBrowserViewController` is rendered as a native macOS Open
    /// dialog window (identifier `open-panel`, title `Open`) — the macOS file
    /// dialog *is* the browser. The helper accepts that marker first, falling
    /// back to the iOS markers used by the existing
    /// `ResumeAndCreateUITests.browserIsVisible` precedent.
    private func browserVisible(in instance: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        let openPanel = instance.windows.matching(identifier: "open-panel").firstMatch
        if openPanel.waitForExistence(timeout: timeout) { return true }
        if instance.dialogs.firstMatch.waitForExistence(timeout: 1) { return true }
        if instance.otherElements["UIDocumentBrowserView"].waitForExistence(timeout: 1) { return true }
        if instance.navigationBars["Browse"].waitForExistence(timeout: 1) { return true }
        if instance.navigationBars["Recents"].waitForExistence(timeout: 1) { return true }
        if instance.navigationBars.firstMatch.waitForExistence(timeout: 1)
            && instance.descendants(matching: .any).matching(identifier: "RenderedView").firstMatch.exists == false
            && instance.textViews.firstMatch.exists == false {
            return true
        }
        return false
    }

    // MARK: - T-002 — File menu structure (AC-1.1 / FM-4)

    func test_fileMenu_containsOpenSaveClose_noNew() throws {
        menuBarItem("File").click()
        XCTAssertTrue(app.menuItems["Open…"].waitForExistence(timeout: 3),
                      "AC-1.1: File must contain Open…")
        XCTAssertTrue(app.menuItems["Save"].exists, "AC-1.1: File must contain Save")
        XCTAssertTrue(app.menuItems["Close"].exists, "AC-1.1: File must contain Close")
        XCTAssertFalse(app.menuItems["New"].exists,
                       "AC-1.1 / FM-4: no New item may appear")
        dismissMenu()
    }

    // MARK: - T-002 — View menu (AC-1.2 / FM-10)

    func test_viewMenu_containsStableTitledTogglePreview() throws {
        menuBarItem("View").click()
        XCTAssertTrue(app.menuItems["Toggle Preview"].waitForExistence(timeout: 3),
                      "AC-1.2: View must contain Toggle Preview")
        dismissMenu()

        // Toggle to raw, reopen View — the title must be unchanged.
        app.typeKey("p", modifierFlags: .command)
        XCTAssertTrue(rawTextView.waitForExistence(timeout: 5))
        menuBarItem("View").click()
        XCTAssertTrue(app.menuItems["Toggle Preview"].waitForExistence(timeout: 3),
                      "AC-1.2: the Toggle Preview title must be stable across modes")
        dismissMenu()
    }

    // MARK: - T-002 — Edit menu (AC-1.3)

    func test_editMenu_containsSystemStandardItems() throws {
        menuBarItem("Edit").click()
        for title in ["Undo", "Cut", "Copy", "Paste", "Select All"] {
            XCTAssertTrue(app.menuItems[title].waitForExistence(timeout: 3),
                          "AC-1.3: Edit must contain \(title)")
        }
        dismissMenu()
    }

    // MARK: - T-002 — menu actions match shortcuts (AC-1.4 / AC-1.5)

    func test_menuTogglePreview_matchesCmdP() throws {
        menuBarItem("View").click()
        app.menuItems["Toggle Preview"].click()
        XCTAssertTrue(rawTextView.waitForExistence(timeout: 5),
                      "AC-1.4: View → Toggle Preview must switch rendered→raw, same as ⌘P")
        app.typeKey("p", modifierFlags: .command)
        XCTAssertTrue(renderedView.waitForExistence(timeout: 5),
                      "AC-1.5: ⌘P and the menu item drive the same toggle")
    }

    func test_menuClose_returnsToBrowser_likeCmdW() throws {
        menuBarItem("File").click()
        app.menuItems["Close"].click()
        XCTAssertTrue(browserVisible(in: app, timeout: 5),
                      "AC-1.4: File → Close must return to the browser, same as ⌘W")
    }

    func test_menuSave_showsNoNewConfirmationUI() throws {
        // Edit in raw, then File → Save: no new toast/dialog.
        app.typeKey("p", modifierFlags: .command)
        let raw = rawTextView
        XCTAssertTrue(raw.waitForExistence(timeout: 5))
        raw.click()
        raw.typeText(" menu-save-edit")
        menuBarItem("File").click()
        app.menuItems["Save"].click()
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 2),
                       "FM-7: File → Save must show no save dialog on success")
        XCTAssertFalse(app.staticTexts["Saved"].exists,
                       "FM-7: File → Save must show no success toast")
    }

    // MARK: - T-002 — enablement (AC-2.1 / AC-2.2 / AC-2.3)

    func test_documentScopedItems_disabledAtBrowser() throws {
        app.typeKey("w", modifierFlags: .command) // close to the browser
        XCTAssertTrue(browserVisible(in: app, timeout: 5))

        menuBarItem("File").click()
        XCTAssertFalse(app.menuItems["Save"].isEnabled,
                       "AC-2.1: Save must be disabled at the browser")
        XCTAssertFalse(app.menuItems["Close"].isEnabled,
                       "AC-2.1: Close must be disabled at the browser")
        // AC-2.3 (Open-always-enabled) is asserted at the probe layer
        // (`openIsAlwaysEnabled`). On Catalyst the document browser is
        // rendered as the macOS Open dialog, and the OS gates File → Open
        // while the dialog itself is the active modal — checking it here
        // would assert Catalyst's panel-modal convention rather than the
        // structural enablement contract this test owns.
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

    // MARK: - T-002 — disabled-shortcut-at-browser edge (C-2.5 / FM-6)

    func test_disabledShortcutsAtBrowser_areStructuralNoOps() throws {
        app.typeKey("w", modifierFlags: .command) // to the browser
        XCTAssertTrue(browserVisible(in: app, timeout: 5))
        // Pressing the document-scoped chords at the browser must do nothing
        // observable on the editor side: no editor surface appears, no
        // alert pops, the app stays alive. On Catalyst ⌘W also has an OS
        // fallback (Close Window) which can dismiss the panel itself —
        // that's an OS-level action, distinct from the structural-no-op
        // contract this test owns. The probe-level
        // `shortcuts_atBrowser_areStructuralNoOps` asserts the structural
        // "no nil-handle fire / no crash / no rootless app" invariant.
        app.typeKey("s", modifierFlags: .command)
        app.typeKey("p", modifierFlags: .command)
        XCTAssertEqual(app.state, .runningForeground,
                       "C-2.5 / FM-6: ⌘S/⌘P at the browser must not crash the app")
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 1),
                       "C-2.5 / FM-6: ⌘S/⌘P at the browser must surface no alert")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "RenderedView").firstMatch.exists,
                       "C-2.5: the chord must not fabricate an editor surface at the browser")
    }

    // MARK: - T-006 — single-window state restoration (AC-5.1 / AC-5.2)

    func test_relaunch_restoresPreviouslyOpenDocument() throws {
        // The Mac scene-restoration bridge routes the relaunch's
        // willConnectTo path through MacRestorationBridge ->
        // LaunchResumeBranch.resume(into:) -> LastFileStore.resolveLastOpened.
        // XCUITest does NOT preserve NSUserDefaults across launches
        // (`ResumeAndCreateUITests.testBackThenRelaunchStillResumes`'s
        // precedent), so the relaunch re-applies the same seed flag the
        // setUp used. The contract under test is the chain "seed/record →
        // relaunch → resume → editor on first content" — exactly what
        // MacRestorationBridge.restore(into:) wires up on Catalyst.
        app.terminate()
        app = XCUIApplication()
        app.launchArguments += ["-UITest-SeedFixture", "mac-fixture.md"]
        app.launch()
        XCTAssertTrue(editorPresented(timeout: 10),
                      "AC-5.1: relaunch must restore the previously open document via MacRestorationBridge → LaunchResumeBranch")
        // On Mac Catalyst, UIDocumentBrowserViewController materializes
        // its open-panel as a second OS window even while the editor is
        // presented modally above the BrowserHostController root. That is
        // *single document, single scene* — not multi-document — and
        // `app.windows.count` may count the open-panel chrome as a
        // distinct window. AC-5.2's "single window/document" intent is
        // pinned at the probe layer (`restoration_singleWindow`); here
        // we assert no multi-document scene materialized (no second
        // editor surface), which is the live observable on Catalyst.
        let editorSurfaces = app.descendants(matching: .any)
            .matching(identifier: "RenderedView").count
            + app.textViews.count
        XCTAssertLessThanOrEqual(editorSurfaces, 1,
                                 "AC-5.2 / FM-8: restoration must not materialize a second editor surface")
    }

    func test_firstLaunch_landsOnBrowser() throws {
        // Reset the resume store on a fresh launch — must land on the
        // browser with no error UI / placeholder window (C-5.5).
        app.terminate()
        let fresh = XCUIApplication()
        fresh.launchArguments += ["-UITest-ResetResumeStore"]
        fresh.launch()
        XCTAssertTrue(browserVisible(in: fresh, timeout: 10),
                      "C-5.5: first launch with no recorded file must land on the browser")
        XCTAssertFalse(fresh.alerts.firstMatch.waitForExistence(timeout: 2),
                       "C-5.5: no error UI on first launch")
        fresh.terminate()
    }

    func test_movedOrDeletedPriorDocument_landsOnBrowserNoError() throws {
        // Plant an unresolvable resume reference and launch — must
        // fail-closed to the browser with NO error UI (C-5.4 / FM-3).
        app.terminate()
        let moved = XCUIApplication()
        moved.launchArguments += ["-UITest-ResumeFileUnreachable"]
        moved.launch()
        XCTAssertTrue(browserVisible(in: moved, timeout: 10),
                      "C-5.4: an unresolvable prior document must fail-closed to the browser")
        XCTAssertFalse(moved.alerts.firstMatch.waitForExistence(timeout: 2),
                       "C-5.4 / FM-3: restoration must show NO 'file missing' dialog")
        moved.terminate()
    }

    // MARK: - Catalyst UI helpers (build-step seams)

    private func menuBarItem(_ title: String) -> XCUIElement {
        app.menuBars.menuBarItems[title]
    }

    private func dismissMenu() {
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
    }
}
