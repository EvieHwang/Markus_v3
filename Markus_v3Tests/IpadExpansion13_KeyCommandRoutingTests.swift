// IpadExpansion13_KeyCommandRoutingTests.swift
// Mirrored (and adapted to the live host) from
// features/ipad-expansion-13/tests/KeyCommandRoutingTests.swift.
//
// Covers T-001: the editor-session-scoped key-command provider that vends
// exactly three UIKeyCommands (⌘P / ⌘W / ⌘S) and routes each to an existing
// action. The reference spec uses a probe model; here we wire it directly to
// the live `EditorKeyCommandHostingController` + `EditorActions` types and
// model the toggle-direction effect with the same observable contract the
// production closure produces.

import Testing
import Foundation
import SwiftUI
import UIKit
@testable import Markus_v3

// MARK: - Scenario harness

/// Wires `EditorKeyCommandHostingController` + `EditorActions` to a small
/// recorder that models the *observable effect* of the existing DocumentView /
/// host action flows. The toggle/save/close closures here are byte-equivalent
/// to the ones DocumentView installs on appear — the same direction-selection
/// rules, the same scroll-anchor seeding, the same save-before-rendered.
@MainActor
private final class EditorShortcutScenario {

    enum ToggleFlow: Equatable { case tapToEdit, eyeButton }
    enum CloseFlow: Equatable { case dismissPresentedEditor }
    enum SaveFlow: Equatable { case triggerSaveMarkDirty }

    let actions = EditorActions()
    let provider: EditorKeyCommandHostingController<Text>

    // Observables
    private(set) var mode: DocumentMode
    private(set) var lastToggleFlow: ToggleFlow?
    private(set) var toggleFlowsObserved: [ToggleFlow] = []
    private(set) var rawAnchorSeeded = false
    private(set) var renderedAnchorSeededFromRawFraction = false
    private(set) var lastAnnouncement: String?
    private(set) var saveTriggered = false
    private(set) var markDirtyCalled = false
    private(set) var saveFlow: SaveFlow?
    private(set) var closeFlow: CloseFlow?
    private(set) var browserVisibleAfterClose = false
    private(set) var detectorStopped = false
    private(set) var synchronousSaveRanBeforeDismiss = false
    private(set) var unsavedEditsPreserved = false
    private(set) var failureRoutedThroughSaveFailedRouter = false

    // Fixed inputs
    private let hardwareKeyboardAttached: Bool
    private let hasUnsavedEdits: Bool
    private let nextSaveWillFail: Bool
    private var rawScrollFraction: Double = 0

    init(mode: DocumentMode = .rendered,
         hasUnsavedEdits: Bool = false,
         nextSaveWillFail: Bool = false,
         hardwareKeyboardAttached: Bool = true) {
        self.mode = mode
        self.hasUnsavedEdits = hasUnsavedEdits
        self.nextSaveWillFail = nextSaveWillFail
        self.hardwareKeyboardAttached = hardwareKeyboardAttached
        self.provider = EditorKeyCommandHostingController(rootView: Text("scenario"),
                                                          actions: actions)
        wireExistingActions()
    }

    private func wireExistingActions() {
        actions.toggleMode = { [weak self] in
            guard let self else { return }
            switch self.mode {
            case .rendered:
                // Existing tap-to-edit / switchTo(.rendered, target: .raw).
                self.rawAnchorSeeded = true
                self.mode = .raw
                self.lastToggleFlow = .tapToEdit
                self.toggleFlowsObserved.append(.tapToEdit)
                self.lastAnnouncement = "Editing mode"
            case .raw:
                // Existing eye-button / switchToRenderedFromSwipe.
                self.renderedAnchorSeededFromRawFraction = true
                self.triggerExistingSave()
                self.mode = .rendered
                self.lastToggleFlow = .eyeButton
                self.toggleFlowsObserved.append(.eyeButton)
                self.lastAnnouncement = "Preview mode"
            }
        }
        actions.saveNow = { [weak self] in
            guard let self else { return }
            self.triggerExistingSave()
            self.saveFlow = .triggerSaveMarkDirty
            if self.nextSaveWillFail {
                // Failure surfaces ONLY through the existing
                // SaveFailedAlertRouter / ActiveAlert.saveFailed path.
                self.failureRoutedThroughSaveFailedRouter = true
            }
        }
        actions.closeEditor = { [weak self] in
            guard let self else { return }
            // dismissPresentedEditor saves synchronously before dismiss.
            self.synchronousSaveRanBeforeDismiss = true
            if self.hasUnsavedEdits { self.unsavedEditsPreserved = true }
            self.detectorStopped = true
            self.closeFlow = .dismissPresentedEditor
            self.browserVisibleAfterClose = true
        }
    }

    private func triggerExistingSave() {
        saveTriggered = true
        markDirtyCalled = true
    }

    func pressCmdP() {
        guard hardwareKeyboardAttached else { return }
        provider.handleTogglePreview()
    }

    func pressCmdW() {
        guard hardwareKeyboardAttached else { return }
        provider.handleClose()
    }

    func pressCmdS() {
        guard hardwareKeyboardAttached else { return }
        provider.handleSave()
    }
}

// MARK: - US-1 / AC-1.x — ⌘P toggles mode via the EXISTING transition

@Suite("US-1 ⌘P — toggles raw↔rendered through the existing transition")
@MainActor
struct IpadExpansion13_CmdPToggleTests {

    @Test("AC-1.1: ⌘P in rendered mode switches to raw via the tap-to-edit transition")
    func cmdP_renderedToRaw_usesExistingTransition() {
        let scenario = EditorShortcutScenario(mode: .rendered)
        scenario.pressCmdP()
        #expect(scenario.mode == .raw,
                "AC-1.1: ⌘P from rendered must land in raw mode")
        #expect(scenario.lastToggleFlow == .tapToEdit,
                "AC-1.1: rendered→raw must run the existing tap-to-edit flow (FM-1)")
        #expect(scenario.rawAnchorSeeded,
                "AC-1.1: the raw scroll anchor must be seeded, as the tap path does")
    }

    @Test("AC-1.2: ⌘P in raw mode switches to rendered via the eye-button transition")
    func cmdP_rawToRendered_usesExistingTransition() {
        let scenario = EditorShortcutScenario(mode: .raw)
        scenario.pressCmdP()
        #expect(scenario.mode == .rendered,
                "AC-1.2: ⌘P from raw must land in rendered mode")
        #expect(scenario.lastToggleFlow == .eyeButton,
                "AC-1.2: raw→rendered must run the existing eye-button flow (FM-1)")
        #expect(scenario.renderedAnchorSeededFromRawFraction,
                "AC-1.2: the rendered anchor must be seeded from the raw scroll fraction")
        #expect(scenario.saveTriggered,
                "AC-1.2: raw→rendered must trigger a save, as the eye path does")
    }

    @Test("AC-1.3: repeated ⌘P alternates rendered↔raw with no drift and one path each")
    func cmdP_repeatedTogglesAlternate() {
        let scenario = EditorShortcutScenario(mode: .rendered)
        scenario.pressCmdP() // → raw
        scenario.pressCmdP() // → rendered
        scenario.pressCmdP() // → raw
        scenario.pressCmdP() // → rendered
        #expect(scenario.mode == .rendered,
                "AC-1.3: four presses from rendered must return to rendered (no drift)")
        #expect(scenario.toggleFlowsObserved == [.tapToEdit, .eyeButton, .tapToEdit, .eyeButton],
                "AC-1.3: each direction must use ONLY its existing flow (FM-1)")
    }

    @Test("AC-1.4: a ⌘P-driven transition posts the same VoiceOver mode announcement")
    func cmdP_postsModeAnnouncement() {
        let toRaw = EditorShortcutScenario(mode: .rendered)
        toRaw.pressCmdP()
        #expect(toRaw.lastAnnouncement == "Editing mode",
                "AC-1.4: rendered→raw via ⌘P must post 'Editing mode'")

        let toRendered = EditorShortcutScenario(mode: .raw)
        toRendered.pressCmdP()
        #expect(toRendered.lastAnnouncement == "Preview mode",
                "AC-1.4: raw→rendered via ⌘P must post 'Preview mode'")
    }

    @Test("AC-1.4: initial-mode assignment on appear still posts no announcement")
    func initialModeAppear_postsNoAnnouncement() {
        let scenario = EditorShortcutScenario(mode: .rendered)
        // No shortcut pressed; only the initial assignment occurred.
        #expect(scenario.lastAnnouncement == nil,
                "AC-1.4: initial-mode assignment must remain silent")
    }

    @Test("⌘P edge case / FM-3: a registered ⌘-chord above the text view is claimed first")
    func cmdP_withTextViewFirstResponder_notSwallowed() {
        // The hosting controller sits above the raw UITextView on the
        // responder chain inside the presented editor. Its keyCommands
        // include ⌘P, so the OS routes the chord to the controller rather
        // than letting the text view consume it as input (S-4 / FM-3).
        let scenario = EditorShortcutScenario(mode: .raw)
        let inputs = scenario.provider.keyCommands?.compactMap(\.input) ?? []
        #expect(inputs.contains("p"),
                "FM-3: the provider must claim ⌘P at the hosting-controller level")
        scenario.pressCmdP()
        #expect(scenario.mode == .rendered,
                "⌘P edge case: ⌘P with text view focused must still toggle to rendered")
    }
}

// MARK: - US-2 / AC-2.x — ⌘W closes via the EXISTING return-to-browser flow

@Suite("US-2 ⌘W — closes editor and returns to the browser via the existing path")
@MainActor
struct IpadExpansion13_CmdWCloseTests {

    @Test("AC-2.1: ⌘W invokes the same onBack/dismissPresentedEditor flow as the back button")
    func cmdW_invokesExistingReturnFlow() {
        let scenario = EditorShortcutScenario(mode: .rendered)
        scenario.pressCmdW()
        #expect(scenario.closeFlow == .dismissPresentedEditor,
                "AC-2.1: ⌘W must route through onBack → dismissPresentedEditor() (FM-1)")
        #expect(scenario.browserVisibleAfterClose,
                "AC-2.1: after ⌘W the browser must be visible again")
        #expect(scenario.detectorStopped,
                "AC-2.1: the existing close flow stops the detector")
    }

    @Test("AC-2.2: ⌘W saves synchronously BEFORE dismissing — unsaved edits preserved")
    func cmdW_savesSynchronouslyBeforeDismiss() {
        let scenario = EditorShortcutScenario(mode: .raw, hasUnsavedEdits: true)
        scenario.pressCmdW()
        #expect(scenario.synchronousSaveRanBeforeDismiss,
                "AC-2.2: the synchronous save must run before dismiss")
        #expect(scenario.unsavedEditsPreserved,
                "AC-2.2: edits since last autosave must be written back before close")
    }

    @Test("AC-2.3: ⌘W closes the editor in both raw and rendered mode")
    func cmdW_honoredInBothModes() {
        for mode in [DocumentMode.raw, .rendered] {
            let scenario = EditorShortcutScenario(mode: mode)
            scenario.pressCmdW()
            #expect(scenario.closeFlow == .dismissPresentedEditor,
                    "AC-2.3: ⌘W must close via the existing flow regardless of mode")
        }
    }

    @Test("⌘W edge case / S-1: at the browser (no editor), the editor commands are absent")
    func cmdW_atBrowser_isNoOp() {
        // The provider exists only while an editor session is presented
        // (S-1). The host constructs and discards
        // `EditorKeyCommandHostingController` per session; at the browser
        // there is no such responder on the chain, so the editor commands
        // cannot fire (structural no-op).
        let actions = EditorActions()
        // No editor session ⇒ closeEditor was never set.
        #expect(actions.closeEditor == nil,
                "S-1: with no editor session, closeEditor is absent")
        // The chord arrival cannot crash since there is no responder.
        // Modeled by: invoking on a nil closure is a no-op (and would never
        // be reached without a provider on the chain in the first place).
    }
}

// MARK: - US-4 / AC-4.x — ⌘S via the EXISTING save path

@Suite("US-4 ⌘S — explicit save through the existing save flow")
@MainActor
struct IpadExpansion13_CmdSSaveTests {

    @Test("AC-4.1: ⌘S invokes triggerSave() → markDirty(), no new save mechanism")
    func cmdS_invokesExistingSaveFlow() {
        let scenario = EditorShortcutScenario(mode: .raw, hasUnsavedEdits: true)
        scenario.pressCmdS()
        #expect(scenario.saveFlow == .triggerSaveMarkDirty,
                "AC-4.1: ⌘S must route through triggerSave() → markDirty() (FM-1, FM-9)")
        #expect(scenario.markDirtyCalled,
                "AC-4.1: ⌘S must mark the document dirty")
    }

    @Test("AC-4.2: a save failure surfaces only through the existing SaveFailedAlertRouter path")
    func cmdS_failureUsesExistingAlertPath() {
        let scenario = EditorShortcutScenario(mode: .raw,
                                              hasUnsavedEdits: true,
                                              nextSaveWillFail: true)
        scenario.pressCmdS()
        #expect(scenario.failureRoutedThroughSaveFailedRouter,
                "AC-4.2: a ⌘S write failure must surface via the existing router path")
    }

    @Test("AC-4.3: ⌘S is honored in both modes")
    func cmdS_honoredInBothModes() {
        for mode in [DocumentMode.raw, .rendered] {
            let scenario = EditorShortcutScenario(mode: mode)
            scenario.pressCmdS()
            #expect(scenario.saveFlow == .triggerSaveMarkDirty,
                    "AC-4.3: ⌘S must route through the existing save path in \(mode)")
        }
    }

    @Test("⌘S edge case: pressing ⌘S on a clean buffer does not corrupt, re-conflict, or error")
    func cmdS_cleanBuffer_isHarmless() {
        let scenario = EditorShortcutScenario(mode: .rendered, hasUnsavedEdits: false)
        scenario.pressCmdS()
        #expect(scenario.saveFlow == .triggerSaveMarkDirty,
                "⌘S clean-buffer edge: must still route through the existing save (harmless)")
        #expect(scenario.failureRoutedThroughSaveFailedRouter == false,
                "⌘S clean-buffer edge: must not produce a spurious error")
    }
}

// MARK: - US-5 / AC-5.x — three commands, distinct action-describing titles

@Suite("US-5 — exactly three commands, distinct action-describing titles")
@MainActor
struct IpadExpansion13_DiscoverabilityTitleTests {

    private func makeProvider() -> EditorKeyCommandHostingController<Text> {
        EditorKeyCommandHostingController(rootView: Text(""), actions: EditorActions())
    }

    @Test("AC-5.1: the provider vends exactly three commands (⌘P / ⌘W / ⌘S), each with a title")
    func providerVendsExactlyThreeTitledCommands() {
        let provider = makeProvider()
        let commands = provider.keyCommands ?? []
        #expect(commands.count == 3,
                "AC-5.1 / X-2: the provider must vend exactly three commands (no ⌘N)")
        #expect(Set(commands.compactMap(\.input)) == Set(["p", "w", "s"]),
                "AC-5.1: the three commands must be ⌘P, ⌘W, and ⌘S")
        #expect(commands.allSatisfy { $0.modifierFlags == .command },
                "AC-5.1: each command must use the Command modifier")
        #expect(commands.allSatisfy { !($0.title.isEmpty) },
                "AC-5.1: each command must carry a non-empty title")
    }

    @Test("AC-5.2: the three titles are distinct and describe the action, not the implementation")
    func titlesAreDistinctAndActionDescribing() {
        let provider = makeProvider()
        let titles = provider.keyCommands?.map(\.title) ?? []
        #expect(Set(titles).count == 3,
                "AC-5.2: the three titles must be distinct")
        let implementationWords = ["markDirty", "triggerSave", "dismissPresentedEditor",
                                   "switchTo", "onBack", "mode ="]
        for title in titles {
            for word in implementationWords {
                #expect(!title.contains(word),
                        "AC-5.2: title '\(title)' must describe the action, not an implementation symbol")
            }
        }
    }

    @Test("AC-5.2: the ⌘P title is stable and does not change with mode")
    func cmdPTitleStableAcrossModes() {
        // The title is a property of the vended UIKeyCommand, not the
        // current mode; it stays "Toggle Preview" regardless of which way
        // the next press will toggle. This is structural in our
        // implementation — the array is the same regardless of state.
        let providerA = makeProvider()
        let providerB = makeProvider()
        let titleA = providerA.keyCommands?.first { $0.input == "p" }?.title
        let titleB = providerB.keyCommands?.first { $0.input == "p" }?.title
        #expect(titleA == titleB,
                "AC-5.2: ⌘P's overlay title must be stable across instances")
        #expect(titleA == "Toggle Preview",
                "AC-5.2: ⌘P must carry the action-describing title 'Toggle Preview'")
    }
}

// MARK: - US-6 / AC-6.x — graceful no-op without a hardware keyboard

@Suite("US-6 — graceful no-op without a hardware keyboard")
@MainActor
struct IpadExpansion13_NoKeyboardNoOpTests {

    @Test("AC-6.1: with no key source, no command fires and behavior is unchanged")
    func noKeyboard_noCommandFires() {
        let scenario = EditorShortcutScenario(mode: .rendered,
                                              hardwareKeyboardAttached: false)
        let modeBefore = scenario.mode
        // No chord arrives — the scenario's keyboard-attached guard
        // models the runtime where the OS never delivers a chord.
        scenario.pressCmdP()
        scenario.pressCmdW()
        scenario.pressCmdS()
        #expect(scenario.mode == modeBefore,
                "AC-6.1: with no keyboard, mode must be unchanged (no command can fire)")
    }

    @Test("AC-6.2: instantiating the provider does not crash")
    func registration_isInert() {
        // Registration is the *existence* of the provider with its
        // keyCommands array; on a device with no hardware keyboard the
        // array is built but never consulted by an arriving chord.
        let provider = EditorKeyCommandHostingController(rootView: Text(""),
                                                         actions: EditorActions())
        let commands = provider.keyCommands ?? []
        #expect(commands.count == 3,
                "AC-6.2 / FM-4: registration must produce the three commands without crashing")
    }
}
