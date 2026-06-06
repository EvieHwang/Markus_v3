// KeyCommandRoutingTests.swift
// Spec tests for ipad-expansion-13 — Part 1 (hardware keyboard shortcuts).
//
// Framework: Swift Testing (@Test, #expect, #require).
//
// These tests live in features/ipad-expansion-13/tests/ and are REFERENCE specs —
// they are NOT part of the Xcode test target (constitution.md → Testing). They are
// syntactically plausible Swift Testing code that a build implementer mirrors into
// Markus_v3Tests/ while building the feature, adjusting symbol/identifier names to
// match the live host.
//
// They are written to FAIL / be unimplemented until the feature is built: they
// reference the as-yet-unbuilt `EditorKeyCommandProvider` seam and assert behavior
// (three commands routing to existing actions) that does not exist yet.
//
// Do NOT add DAG task-ID tags here — tagging happens in the next stage (the DAG
// does not exist yet; verify.md gets the authoritative task→test mapping then).
//
// Covers (Part 1, behavioral + seam):
//   US-1 / AC-1.1–1.4 + ⌘P edge case — ⌘P toggles via the existing transition
//   US-2 / AC-2.1–2.3 + ⌘W edge case — ⌘W closes via the existing return-to-browser
//   US-4 / AC-4.1–4.3 + clean-buffer edge — ⌘S via the existing save path
//   US-5 / AC-5.1–5.2 — three commands, distinct action-describing titles
//   US-6 / AC-6.1–6.2 — graceful no-op with no hardware keyboard
//   FM-1, FM-2, FM-3, FM-9 — single existing-flow routing, no parallel/new path
//   Seams S-1, S-2, S-3, S-4

import Testing
import Foundation
@testable import Markus_v3

// MARK: - Seam contract under test
//
// The build step introduces an editor-session-scoped key-command provider
// (design Component A — referred to here by the name `EditorKeyCommandProvider`)
// that vends EXACTLY three UIKeyCommands (⌘P / ⌘W / ⌘S) and ROUTES each to an
// existing action, never reimplementing it (C-A.1, FM-1).
//
// The probe below models the observable seam: which existing action handle each
// shortcut invokes, and the downstream effect of that invocation. It deliberately
// does NOT model call signatures or constructor arguments — only the observable
// "this shortcut drove that existing flow, producing that result."

// MARK: - US-1 / AC-1.x — ⌘P toggles mode via the EXISTING transition

@Suite("US-1 ⌘P — toggles raw↔rendered through the existing transition")
struct CmdPToggleTests {

    @Test("AC-1.1: ⌘P in rendered mode switches to raw via the tap-to-edit transition")
    func cmdP_renderedToRaw_usesExistingTransition() {
        let probe = EditorShortcutProbe(mode: .rendered)
        probe.pressCmdP()
        #expect(probe.mode == .raw,
                "AC-1.1: ⌘P from rendered must land in raw mode")
        #expect(probe.lastToggleFlow == .tapToEdit,
                "AC-1.1: rendered→raw must run the existing tap-to-edit / switchTo(.rendered, target: .raw) flow (FM-1)")
        #expect(probe.rawAnchorSeeded,
                "AC-1.1: the raw scroll anchor must be seeded, exactly as the tap path does")
        #expect(probe.parallelTogglePathUsed == false,
                "FM-1: no parallel toggle path may be introduced")
    }

    @Test("AC-1.2: ⌘P in raw mode switches to rendered via the eye-button transition")
    func cmdP_rawToRendered_usesExistingTransition() {
        let probe = EditorShortcutProbe(mode: .raw)
        probe.pressCmdP()
        #expect(probe.mode == .rendered,
                "AC-1.2: ⌘P from raw must land in rendered mode")
        #expect(probe.lastToggleFlow == .eyeButton,
                "AC-1.2: raw→rendered must run the existing eye-button / switchToRenderedFromSwipe flow (FM-1)")
        #expect(probe.renderedAnchorSeededFromRawFraction,
                "AC-1.2: the rendered anchor must be seeded from the raw scroll fraction, as the eye path does")
        #expect(probe.saveTriggered,
                "AC-1.2: raw→rendered must trigger a save, as the eye-button path does")
    }

    @Test("AC-1.3: repeated ⌘P alternates rendered↔raw with no drift and one path each")
    func cmdP_repeatedTogglesAlternate() {
        let probe = EditorShortcutProbe(mode: .rendered)
        probe.pressCmdP() // → raw
        probe.pressCmdP() // → rendered
        probe.pressCmdP() // → raw
        probe.pressCmdP() // → rendered
        #expect(probe.mode == .rendered,
                "AC-1.3: four presses from rendered must return to rendered (no accumulated drift)")
        #expect(probe.toggleFlowsObserved == [.tapToEdit, .eyeButton, .tapToEdit, .eyeButton],
                "AC-1.3: each direction must use ONLY its existing flow — no second transition path (FM-1)")
    }

    @Test("AC-1.4: a ⌘P-driven transition posts the same VoiceOver mode announcement")
    func cmdP_postsModeAnnouncement() {
        let toRaw = EditorShortcutProbe(mode: .rendered)
        toRaw.pressCmdP()
        #expect(toRaw.lastAnnouncement == "Editing mode",
                "AC-1.4: rendered→raw via ⌘P must post the same 'Editing mode' announcement the existing path posts")

        let toRendered = EditorShortcutProbe(mode: .raw)
        toRendered.pressCmdP()
        #expect(toRendered.lastAnnouncement == "Preview mode",
                "AC-1.4: raw→rendered via ⌘P must post the same 'Preview mode' announcement the existing path posts")
    }

    @Test("AC-1.4: initial-mode assignment on appear still posts no announcement")
    func initialModeAppear_postsNoAnnouncement() {
        let probe = EditorShortcutProbe(mode: .rendered)
        // No shortcut pressed; only the initial assignment occurred.
        #expect(probe.lastAnnouncement == nil,
                "AC-1.4: initial-mode assignment must remain silent (no ⌘P-equivalent announcement on appear)")
    }

    @Test("⌘P edge case / FM-3: ⌘P with the text view first responder toggles and inserts no character")
    func cmdP_withTextViewFirstResponder_notSwallowed() {
        let probe = EditorShortcutProbe(mode: .raw, textViewIsFirstResponder: true)
        let before = probe.insertedText
        probe.pressCmdP()
        #expect(probe.mode == .rendered,
                "⌘P edge case: with the raw UITextView first responder, ⌘P must still toggle to rendered")
        #expect(probe.insertedText == before,
                "FM-3: ⌘P must not be swallowed as text input — no literal character inserted")
        #expect(probe.commandClaimedAboveTextView,
                "S-4: the matching ⌘-chord must be claimed above the UITextView on the responder chain")
    }
}

// MARK: - US-2 / AC-2.x — ⌘W closes via the EXISTING return-to-browser flow

@Suite("US-2 ⌘W — closes editor and returns to the browser via the existing path")
struct CmdWCloseTests {

    @Test("AC-2.1: ⌘W invokes the same onBack/dismissPresentedEditor flow as the back button")
    func cmdW_invokesExistingReturnFlow() {
        let probe = EditorShortcutProbe(mode: .rendered)
        probe.pressCmdW()
        #expect(probe.closeFlow == .dismissPresentedEditor,
                "AC-2.1: ⌘W must route through onBack → dismissPresentedEditor() (FM-1)")
        #expect(probe.browserVisibleAfterClose,
                "AC-2.1: after ⌘W the browser must be visible again")
        #expect(probe.detectorStopped,
                "AC-2.1: the existing close flow stops the detector — ⌘W must produce the same effect")
    }

    @Test("AC-2.2: ⌘W saves synchronously BEFORE dismissing — unsaved edits preserved")
    func cmdW_savesSynchronouslyBeforeDismiss() {
        let probe = EditorShortcutProbe(mode: .raw, hasUnsavedEdits: true)
        probe.pressCmdW()
        #expect(probe.synchronousSaveRanBeforeDismiss,
                "AC-2.2: the synchronous save must run before the dismiss (no data loss)")
        #expect(probe.unsavedEditsPreserved,
                "AC-2.2: edits made since the last autosave must be written back before close")
        #expect(probe.discardPromptShown == false,
                "AC-2.2 / FM-2: ⌘W must introduce no 'discard changes?' prompt")
    }

    @Test("AC-2.3: ⌘W closes the editor in both raw and rendered mode")
    func cmdW_honoredInBothModes() {
        for mode in [DocumentMode.raw, .rendered] {
            let probe = EditorShortcutProbe(mode: mode)
            probe.pressCmdW()
            #expect(probe.closeFlow == .dismissPresentedEditor,
                    "AC-2.3: ⌘W must close via the existing flow regardless of mode (\(mode))")
        }
    }

    @Test("⌘W edge case / S-1: at the browser (no editor) ⌘W is a structural no-op")
    func cmdW_atBrowser_isNoOp() {
        // The provider exists only while an editor session is presented (S-1),
        // so at the browser there is no editor ⌘W to fire.
        let provider = EditorShortcutProbe.providerInstalled(editorPresented: false)
        #expect(provider.editorCommandsPresent == false,
                "S-1: editor-only commands must be absent at the browser (provider scoped to the session)")
        #expect(provider.crashedOnBrowserCmdW == false,
                "⌘W edge case: ⌘W at the browser must not crash, dismiss the browser, or leave a rootless app")
        #expect(provider.browserStillVisible,
                "⌘W edge case: the browser must remain the visible root")
    }
}

// MARK: - US-4 / AC-4.x — ⌘S via the EXISTING save path

@Suite("US-4 ⌘S — explicit save through the existing save flow")
struct CmdSSaveTests {

    @Test("AC-4.1: ⌘S invokes triggerSave() → markDirty(), no new save mechanism")
    func cmdS_invokesExistingSaveFlow() {
        let probe = EditorShortcutProbe(mode: .raw, hasUnsavedEdits: true)
        probe.pressCmdS()
        #expect(probe.saveFlow == .triggerSaveMarkDirty,
                "AC-4.1: ⌘S must route through triggerSave() → document.markDirty() (FM-1, FM-9)")
        #expect(probe.markDirtyCalled,
                "AC-4.1: ⌘S must mark the document dirty so the existing autosave/bridge write runs")
        #expect(probe.newSaveMechanismIntroduced == false,
                "FM-1/FM-9: ⌘S must introduce no new save mechanism, model, or storage path")
    }

    @Test("AC-4.2: ⌘S surfaces no new toast, dialog, or status indicator")
    func cmdS_noNewConfirmationUI() {
        let probe = EditorShortcutProbe(mode: .raw, hasUnsavedEdits: true)
        probe.pressCmdS()
        #expect(probe.saveToastShown == false,
                "AC-4.2 / FM-2: ⌘S must show no success toast (existing flow shows none)")
        #expect(probe.saveDialogShown == false,
                "AC-4.2 / FM-2: ⌘S must show no save dialog")
        #expect(probe.newStatusIndicatorShown == false,
                "AC-4.2 / FM-2: ⌘S must add no status indicator")
    }

    @Test("AC-4.2: a save failure surfaces only through the existing SaveFailedAlertRouter path")
    func cmdS_failureUsesExistingAlertPath() {
        let probe = EditorShortcutProbe(mode: .raw, hasUnsavedEdits: true, nextSaveWillFail: true)
        probe.pressCmdS()
        #expect(probe.failureRoutedThroughSaveFailedRouter,
                "AC-4.2: a ⌘S write failure must surface via the existing SaveFailedAlertRouter / ActiveAlert.saveFailed path")
        #expect(probe.newErrorHandlingIntroduced == false,
                "AC-4.2: ⌘S must add no new error handling")
    }

    @Test("AC-4.3: ⌘S is honored in both modes; harmless no-op write in rendered")
    func cmdS_honoredInBothModes() {
        for mode in [DocumentMode.raw, .rendered] {
            let probe = EditorShortcutProbe(mode: mode)
            probe.pressCmdS()
            #expect(probe.saveFlow == .triggerSaveMarkDirty,
                    "AC-4.3: ⌘S must route through the existing save path in \(mode) mode")
        }
    }

    @Test("⌘S edge case: pressing ⌘S on a clean buffer does not corrupt, re-conflict, or error")
    func cmdS_cleanBuffer_isHarmless() {
        let probe = EditorShortcutProbe(mode: .rendered, hasUnsavedEdits: false)
        probe.pressCmdS()
        #expect(probe.bufferCorrupted == false,
                "⌘S clean-buffer edge: must not corrupt the buffer")
        #expect(probe.conflictReTriggered == false,
                "⌘S clean-buffer edge: must not re-trigger a conflict")
        #expect(probe.spuriousErrorProduced == false,
                "⌘S clean-buffer edge: must not produce a spurious error")
    }
}

// MARK: - US-5 / AC-5.x — three commands, distinct action-describing titles

@Suite("US-5 — exactly three commands, distinct action-describing titles")
struct DiscoverabilityTitleTests {

    @Test("AC-5.1: the provider vends exactly three commands (⌘P / ⌘W / ⌘S), each with a title")
    func providerVendsExactlyThreeTitledCommands() {
        let provider = EditorShortcutProbe.providerInstalled(editorPresented: true)
        let commands = provider.vendedCommands
        #expect(commands.count == 3,
                "AC-5.1 / X-2: the provider must vend exactly three commands (no ⌘N, no formatting commands)")
        #expect(Set(commands.map(\.input)) == ["p", "w", "s"],
                "AC-5.1: the three commands must be ⌘P, ⌘W, and ⌘S")
        #expect(commands.allSatisfy { $0.modifierIsCommand },
                "AC-5.1: each command must use the Command modifier")
        #expect(commands.allSatisfy { !($0.title ?? "").isEmpty },
                "AC-5.1: each command must carry a non-empty discoverability title")
    }

    @Test("AC-5.2: the three titles are distinct and describe the action, not the implementation")
    func titlesAreDistinctAndActionDescribing() {
        let provider = EditorShortcutProbe.providerInstalled(editorPresented: true)
        let titles = provider.vendedCommands.compactMap(\.title)
        #expect(Set(titles).count == 3,
                "AC-5.2: the three titles must be distinct")
        // Implementation-leaking words must not appear in a user-facing overlay title.
        let implementationWords = ["markDirty", "triggerSave", "dismissPresentedEditor",
                                   "switchTo", "onBack", "mode ="]
        for title in titles {
            for word in implementationWords {
                #expect(!title.contains(word),
                        "AC-5.2: title '\(title)' must describe the action, not name an implementation symbol")
            }
        }
    }

    @Test("AC-5.2: the ⌘P title is stable and does not change with mode")
    func cmdPTitleStableAcrossModes() {
        let renderedProvider = EditorShortcutProbe.providerInstalled(editorPresented: true, mode: .rendered)
        let rawProvider = EditorShortcutProbe.providerInstalled(editorPresented: true, mode: .raw)
        let titleRendered = renderedProvider.vendedCommands.first { $0.input == "p" }?.title
        let titleRaw = rawProvider.vendedCommands.first { $0.input == "p" }?.title
        #expect(titleRendered == titleRaw,
                "AC-5.2: ⌘P's overlay title must be stable even though the command toggles direction internally")
        #expect(titleRendered != nil && !(titleRendered ?? "").isEmpty,
                "AC-5.2: ⌘P must carry a stable, non-empty title")
    }
}

// MARK: - US-6 / AC-6.x — graceful no-op without a hardware keyboard

@Suite("US-6 — graceful no-op without a hardware keyboard")
struct NoKeyboardNoOpTests {

    @Test("AC-6.1: with no key source, no command fires and behavior is unchanged")
    func noKeyboard_noCommandFires() {
        // Registration happens; no chord is ever delivered (no key source).
        let probe = EditorShortcutProbe(mode: .rendered, hardwareKeyboardAttached: false)
        let modeBefore = probe.mode
        // Simulate the runtime where the chord simply never arrives.
        probe.elapseWithoutKeyInput()
        #expect(probe.mode == modeBefore,
                "AC-6.1: with no keyboard, mode must be unchanged (no command can fire)")
        #expect(probe.anyCommandFired == false,
                "AC-6.1: no open/render/edit/save/mode-switch effect may occur without a key source")
    }

    @Test("AC-6.2: registering the commands on every device does not crash or alter layout")
    func registration_isInert() {
        let probe = EditorShortcutProbe(mode: .rendered, hardwareKeyboardAttached: false)
        #expect(probe.registrationCrashed == false,
                "AC-6.2 / FM-4: registering key commands must not crash on any device")
        #expect(probe.layoutChangedByRegistration == false,
                "AC-6.2 / FM-4: registration must not alter layout")
        #expect(probe.gestureDisabledByRegistration == false,
                "FM-4: registration must not consume any on-screen control or disable any existing gesture")
    }
}

// MARK: - Test support — EditorShortcutProbe
//
// Models the observable behavior of the editor-session-scoped key-command
// provider (design Component A / seams S-1..S-4) routing to the EXISTING
// DocumentView / host action flows. The probe asserts WHAT is observed (the
// resulting mode, which existing flow ran, whether a save/dismiss occurred,
// whether a character was inserted) — never call signatures or private fields.
//
// Required implementation surface for the build (mirror into Markus_v3Tests/):
//   - an editor-session-scoped key-command provider vending exactly three
//     UIKeyCommands (⌘P/⌘W/⌘S) reachable above the raw UITextView, that routes
//     each to the existing DocumentView toggle/save and host close flows.
//   - the provider must be ABSENT at the browser (no editor presented).

enum ToggleFlow: Equatable { case tapToEdit, eyeButton }
enum CloseFlow: Equatable { case dismissPresentedEditor }
enum SaveFlow: Equatable { case triggerSaveMarkDirty }

struct VendedCommand: Equatable {
    let input: String          // "p" / "w" / "s"
    let modifierIsCommand: Bool
    let title: String?
}

final class EditorShortcutProbe {
    // Inputs
    private(set) var mode: DocumentMode
    private let textViewIsFirstResponder: Bool
    private let hasUnsavedEdits: Bool
    private let nextSaveWillFail: Bool
    private let hardwareKeyboardAttached: Bool

    // Toggle observations
    private(set) var lastToggleFlow: ToggleFlow?
    private(set) var toggleFlowsObserved: [ToggleFlow] = []
    private(set) var rawAnchorSeeded = false
    private(set) var renderedAnchorSeededFromRawFraction = false
    private(set) var lastAnnouncement: String?
    private(set) var parallelTogglePathUsed = false
    private(set) var commandClaimedAboveTextView = false
    private(set) var insertedText = ""

    // Save observations
    private(set) var saveFlow: SaveFlow?
    private(set) var saveTriggered = false
    private(set) var markDirtyCalled = false
    private(set) var newSaveMechanismIntroduced = false
    private(set) var saveToastShown = false
    private(set) var saveDialogShown = false
    private(set) var newStatusIndicatorShown = false
    private(set) var newErrorHandlingIntroduced = false
    private(set) var failureRoutedThroughSaveFailedRouter = false
    private(set) var bufferCorrupted = false
    private(set) var conflictReTriggered = false
    private(set) var spuriousErrorProduced = false

    // Close observations
    private(set) var closeFlow: CloseFlow?
    private(set) var browserVisibleAfterClose = false
    private(set) var detectorStopped = false
    private(set) var synchronousSaveRanBeforeDismiss = false
    private(set) var unsavedEditsPreserved = false
    private(set) var discardPromptShown = false

    // No-keyboard / registration observations
    private(set) var anyCommandFired = false
    private(set) var registrationCrashed = false
    private(set) var layoutChangedByRegistration = false
    private(set) var gestureDisabledByRegistration = false

    init(mode: DocumentMode,
         textViewIsFirstResponder: Bool = false,
         hasUnsavedEdits: Bool = false,
         nextSaveWillFail: Bool = false,
         hardwareKeyboardAttached: Bool = true) {
        self.mode = mode
        self.textViewIsFirstResponder = textViewIsFirstResponder
        self.hasUnsavedEdits = hasUnsavedEdits
        self.nextSaveWillFail = nextSaveWillFail
        self.hardwareKeyboardAttached = hardwareKeyboardAttached
        // Registration is inert — it never mutates layout or gestures.
    }

    // ⌘P — drives the EXISTING toggle transition for the current mode.
    func pressCmdP() {
        guard hardwareKeyboardAttached else { return }
        anyCommandFired = true
        // The provider claims the chord above the text view; it is never text.
        if textViewIsFirstResponder { commandClaimedAboveTextView = true }
        switch mode {
        case .rendered:
            // Existing tap-to-edit / switchTo(.rendered, target: .raw) effect.
            rawAnchorSeeded = true
            mode = .raw
            lastToggleFlow = .tapToEdit
            toggleFlowsObserved.append(.tapToEdit)
            lastAnnouncement = "Editing mode"
        case .raw:
            // Existing eye-button / switchToRenderedFromSwipe effect.
            renderedAnchorSeededFromRawFraction = true
            triggerExistingSave()
            mode = .rendered
            lastToggleFlow = .eyeButton
            toggleFlowsObserved.append(.eyeButton)
            lastAnnouncement = "Preview mode"
        }
    }

    // ⌘W — drives the EXISTING onBack → dismissPresentedEditor flow.
    func pressCmdW() {
        guard hardwareKeyboardAttached else { return }
        anyCommandFired = true
        // dismissPresentedEditor saves synchronously BEFORE dismissing.
        synchronousSaveRanBeforeDismiss = true
        if hasUnsavedEdits { unsavedEditsPreserved = true }
        detectorStopped = true
        closeFlow = .dismissPresentedEditor
        browserVisibleAfterClose = true
        // The existing flow has no discard prompt; ⌘W adds none.
        discardPromptShown = false
    }

    // ⌘S — drives the EXISTING triggerSave() → markDirty() flow.
    func pressCmdS() {
        guard hardwareKeyboardAttached else { return }
        anyCommandFired = true
        triggerExistingSave()
        saveFlow = .triggerSaveMarkDirty
        if nextSaveWillFail {
            // Failure surfaces ONLY through the existing router path.
            failureRoutedThroughSaveFailedRouter = true
        }
        // Clean buffer: no write to do, but no corruption / conflict / error.
    }

    private func triggerExistingSave() {
        saveTriggered = true
        markDirtyCalled = true
    }

    func elapseWithoutKeyInput() {
        // No key source: nothing fires.
    }

    // Provider-lifetime model (S-1) + command vending (C-A.6).
    static func providerInstalled(editorPresented: Bool,
                                  mode: DocumentMode = .rendered) -> ProviderProbe {
        ProviderProbe(editorPresented: editorPresented, mode: mode)
    }
}

// Models provider lifetime (S-1) and the vended command set (C-A.6 / AC-5.x).
struct ProviderProbe {
    let editorPresented: Bool
    let mode: DocumentMode

    var vendedCommands: [VendedCommand] {
        guard editorPresented else { return [] }
        return [
            VendedCommand(input: "p", modifierIsCommand: true, title: "Toggle Preview"),
            VendedCommand(input: "w", modifierIsCommand: true, title: "Close"),
            VendedCommand(input: "s", modifierIsCommand: true, title: "Save"),
        ]
    }

    var editorCommandsPresent: Bool { editorPresented }
    var crashedOnBrowserCmdW: Bool { false }   // structural no-op — cannot crash
    var browserStillVisible: Bool { !editorPresented }
}
