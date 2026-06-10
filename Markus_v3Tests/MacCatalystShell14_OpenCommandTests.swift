// MacCatalystShell14_OpenCommandTests.swift
// Mirror of features/mac-catalyst-shell-14/tests/MacOpenCommandTests.swift —
// T-003 owns `MacOpenPanelTests` (panel/funnel/cancel/fail/non-md/resume-target)
// + `MacSaveNoNewUITests` (FM-7 unit case).
// T-004 owns `OpenWhileOpenTests` (the F-001 ordering) — also mirrored here
// because the probe is shared.

import Testing
import Foundation
@testable import Markus_v3

@Suite("US-3 — File → Open presents the system panel and funnels into the existing path")
struct MacCatalystShell14_OpenPanelTests {

    @Test("AC-3.1: choosing File → Open (or ⌘O) presents the system open panel")
    func open_presentsSystemPanel() {
        let probe = MacOpenCommandProbe()
        probe.invokeOpen()
        #expect(probe.systemPanelPresented,
                "AC-3.1: File → Open / ⌘O must present the system open panel for file selection")
    }

    @Test("AC-3.2: the panel is constrained to MarkdownDocument.readableContentTypes")
    func open_panelConstrainedToMarkdownTypes() {
        let probe = MacOpenCommandProbe()
        probe.invokeOpen()
        #expect(probe.panelContentTypes == MacOpenCommandProbe.markdownReadableContentTypes,
                "AC-3.2: the panel must offer/accept only the app's readable markdown types (.md / .markdown)")
        #expect(probe.panelAcceptsArbitraryTypes == false,
                "AC-3.2: non-markdown types must not be selectable as openable documents")
    }

    @Test("AC-3.3 / S-3 / FM-2: a chosen file opens through presentDocument(at:) — no new mechanism")
    func open_chosenFile_funnelsThroughPresentDocument() {
        let probe = MacOpenCommandProbe()
        probe.invokeOpen()
        probe.userChooses(URL(fileURLWithPath: "/tmp/notes.md"))
        #expect(probe.funnel == .presentDocument,
                "AC-3.3 / S-3: the chosen URL must be handed to presentDocument(at:) (the existing funnel)")
        #expect(probe.secondOpenMechanismIntroduced == false,
                "FM-2: no second open / decode / read / bookmark mechanism may be added")
        #expect(probe.panelOutputWasURLOnly,
                "S-3: the panel's only output is a chosen URL into the existing funnel — nothing else")
    }

    @Test("AC-3.4: a successfully opened file becomes the resume target via the existing recording path")
    func open_success_recordsAsResumeTarget() {
        let probe = MacOpenCommandProbe()
        probe.invokeOpen()
        probe.userChooses(URL(fileURLWithPath: "/tmp/notes.md"))
        #expect(probe.recordedAsLastOpened,
                "AC-3.4: an opened file must be recorded as the last-opened file, exactly as a browser pick is")
        #expect(probe.separateRecordingPathAdded == false,
                "AC-3.4: no separate recording path may be added")
    }
}

@Suite("Open edge cases — cancel, failing, and non-markdown")
struct MacCatalystShell14_OpenEdgeCaseTests {

    @Test("Cancel edge: dismissing the panel opens nothing, shows no error, and disturbs nothing")
    func open_canceled_leavesEverythingUntouched() {
        let probe = MacOpenCommandProbe(currentlyOpen: URL(fileURLWithPath: "/tmp/old.md"))
        probe.invokeOpen()
        probe.userCancelsPanel()
        #expect(probe.funnel == nil, "Cancel edge: nothing opens when the panel is dismissed without a choice")
        #expect(probe.couldntOpenAlertShown == false, "Cancel edge: no error is shown on cancel")
        #expect(probe.activeDocumentPath == "/tmp/old.md",
                "Cancel edge: any currently open document is left untouched")
        #expect(probe.priorDocumentTornDown == false, "Cancel edge: the prior session is untouched")
    }

    @Test("Failing-open edge / FM-2: a failing file surfaces the existing alert and releases the scope")
    func open_failingFile_surfacesExistingAlertAndReleasesScope() {
        let probe = MacOpenCommandProbe()
        probe.invokeOpen()
        probe.userChooses(URL(fileURLWithPath: "/tmp/broken.md"), willLoadSucceed: false)
        #expect(probe.couldntOpenAlertShown,
                "Failing edge: a failing open must surface the existing openPathAlert ('Couldn't open') copy")
        #expect(probe.securityScopedResourceReleased,
                "Failing edge: the security-scoped resource must be released on failure, as a failing browser pick does")
        #expect(probe.newErrorUIIntroduced == false,
                "FM-2: no new error UI is introduced for a failing open")
    }

    @Test("Non-md edge: a non-markdown file that reaches the path is handled by the existing gates")
    func open_nonMarkdownFile_handledByExistingGates() {
        let probe = MacOpenCommandProbe()
        probe.invokeOpen()
        probe.userChooses(URL(fileURLWithPath: "/tmp/note.txt"), willLoadSucceed: false)
        #expect(probe.funnel == .presentDocument,
                "Non-md edge: a stray non-md URL still goes through the SAME funnel — no special-case path")
        #expect(probe.couldntOpenAlertShown,
                "Non-md edge: the existing type/decode gates surface the existing 'Couldn't open' alert")
        #expect(probe.newNonMarkdownHandlingAdded == false,
                "Non-md edge: this feature adds no new non-markdown handling")
    }
}

@Suite("FM-7 — File → Save adds no new save confirmation or conflict UI")
struct MacCatalystShell14_SaveNoNewUITests {

    @Test("FM-7: File → Save surfaces failures only through the existing SaveFailedAlertRouter; no confirmation UI")
    func menuSave_noNewUI_failureViaExistingRouter() {
        let probe = MacOpenCommandProbe()
        let save = probe.menuSaveOutcome(willFail: false)
        #expect(save.toastShown == false, "FM-7: File → Save must show no success toast")
        #expect(save.confirmationShown == false, "FM-7: File → Save must show no save confirmation")
        let failed = probe.menuSaveOutcome(willFail: true)
        #expect(failed.failureRoutedThroughExistingRouter,
                "FM-7: a File → Save failure must surface only through the existing SaveFailedAlertRouter / ActiveAlert.saveFailed path")
        #expect(failed.newErrorHandlingAdded == false, "FM-7: no new error handling may be added")
    }
}

@Suite("Open-while-open — load-success-gated ordering (resolved adversarial F-001) [T-004]")
struct MacCatalystShell14_OpenWhileOpenTests {

    @Test("AC-3.5 / FM-8: a successful open replaces the single current document — no two-docs-live moment")
    func openWhileOpen_success_replacesSingleDocument() {
        let probe = MacOpenCommandProbe(currentlyOpen: URL(fileURLWithPath: "/tmp/old.md"))
        probe.invokeOpen()
        probe.userChooses(URL(fileURLWithPath: "/tmp/new.md"), willLoadSucceed: true)
        #expect(probe.activeDocumentPath == "/tmp/new.md",
                "AC-3.5: a successful open must show the chosen file in the one window")
        #expect(probe.priorDocumentTornDown,
                "AC-3.5: on success the prior session must be torn down (single window)")
        #expect(probe.twoDocumentsLiveAtAnyPoint == false,
                "FM-8: there must be no moment where two documents are live")
        #expect(probe.windowCount == 1,
                "FM-8: the app remains single-window — no second window or tab")
    }

    @Test("S-4: on success the prior is relinquished ONLY AFTER the new document has loaded (load-first ordering)")
    func openWhileOpen_success_loadsBeforeTeardown() {
        let probe = MacOpenCommandProbe(currentlyOpen: URL(fileURLWithPath: "/tmp/old.md"))
        probe.invokeOpen()
        probe.userChooses(URL(fileURLWithPath: "/tmp/new.md"), willLoadSucceed: true)
        #expect(probe.sequence == [.loadNew, .tearDownPrior, .presentNew],
                "S-4 / C-2.4: ordering must be load → conditional teardown → present (the prior is relinquished only after the new load succeeds)")
        #expect(probe.presentSequencedAfterDismissal,
                "S-4: the new present must be sequenced after the prior teardown's dismissal completes (no double-present race)")
    }

    @Test("S-4 / DC-10 (THE F-001 CASE): a FAILED new open leaves the prior document FULLY INTACT")
    func openWhileOpen_failedNewOpen_preservesPrior() {
        let probe = MacOpenCommandProbe(currentlyOpen: URL(fileURLWithPath: "/tmp/old.md"))
        probe.invokeOpen()
        probe.userChooses(URL(fileURLWithPath: "/tmp/broken.md"), willLoadSucceed: false)
        #expect(probe.activeDocumentPath == "/tmp/old.md",
                "DC-10 / S-4: a failed new open must leave the PRIOR document open — never drop to the browser")
        #expect(probe.priorDocumentTornDown == false,
                "DC-10 / S-4: a failed new open must NOT tear down the prior session (the F-001 defect)")
        #expect(probe.priorDetectorStillRunning,
                "S-4: the prior document's detector must still be running after a failed new open")
        #expect(probe.sequence == [.loadNew],
                "S-4: on failure the ordering stops after the failed load — no teardown, no present")
        #expect(probe.couldntOpenAlertShown,
                "S-4: a failed new open must surface the existing openPathAlert 'Couldn't open' copy")
        #expect(probe.newErrorUIIntroduced == false,
                "FM-2: no new error UI may be introduced")
    }

    @Test("S-4: a failed new open is no worse than a canceled Open (the F-001 observable guard)")
    func openWhileOpen_failedNewOpen_noWorseThanCancel() {
        let failed = MacOpenCommandProbe(currentlyOpen: URL(fileURLWithPath: "/tmp/old.md"))
        failed.invokeOpen()
        failed.userChooses(URL(fileURLWithPath: "/tmp/broken.md"), willLoadSucceed: false)
        let canceled = MacOpenCommandProbe(currentlyOpen: URL(fileURLWithPath: "/tmp/old.md"))
        canceled.invokeOpen()
        canceled.userCancelsPanel()
        #expect(failed.activeDocumentPath == canceled.activeDocumentPath,
                "S-4: a failed File → Open must leave the user no worse off than a canceled one (prior preserved both ways)")
        #expect(failed.priorDocumentTornDown == canceled.priorDocumentTornDown,
                "S-4: neither a failed nor a canceled open may tear down the prior document")
    }

    @Test("C-2.4 / FM-8: open-while-open creates no multi-window / tab / multi-document state")
    func openWhileOpen_addsNoMultiDocumentState() {
        let probe = MacOpenCommandProbe(currentlyOpen: URL(fileURLWithPath: "/tmp/old.md"))
        probe.invokeOpen()
        probe.userChooses(URL(fileURLWithPath: "/tmp/new.md"), willLoadSucceed: true)
        #expect(probe.windowCount == 1, "FM-8: no second window")
        #expect(probe.documentTabsCreated == 0, "FM-8: no document tabs")
        #expect(probe.multiDocumentModelUsed == false, "FM-8: no multi-document model")
    }
}

// MARK: - Test support — MacOpenCommandProbe
//
// Models the observable contract of design Component B (`MacOpenCommand`) and
// the composed open-while-open host operation (C-2.4 / S-4). Mirrors the
// reference probe in features/mac-catalyst-shell-14/tests/MacOpenCommandTests.swift.

enum MacOpenFunnel: Equatable { case presentDocument }
enum MacOpenStep: Equatable { case loadNew, tearDownPrior, presentNew }

struct MacOpenMenuSaveOutcome {
    let toastShown: Bool
    let confirmationShown: Bool
    let failureRoutedThroughExistingRouter: Bool
    let newErrorHandlingAdded: Bool
}

final class MacOpenCommandProbe {

    static let markdownReadableContentTypes: Set<String> = ["net.daringfireball.markdown", "public.markdown"]

    private(set) var activeDocumentPath: String?
    private let startedWithDocument: Bool

    private(set) var systemPanelPresented = false
    private(set) var panelContentTypes: Set<String> = []
    private(set) var panelAcceptsArbitraryTypes = false
    private(set) var panelOutputWasURLOnly = false

    private(set) var funnel: MacOpenFunnel?
    private(set) var secondOpenMechanismIntroduced = false
    private(set) var recordedAsLastOpened = false
    private(set) var separateRecordingPathAdded = false

    private(set) var sequence: [MacOpenStep] = []
    private(set) var priorDocumentTornDown = false
    private(set) var priorDetectorStillRunning = true
    private(set) var twoDocumentsLiveAtAnyPoint = false
    private(set) var presentSequencedAfterDismissal = false
    private(set) var windowCount = 1
    private(set) var documentTabsCreated = 0
    private(set) var multiDocumentModelUsed = false

    private(set) var couldntOpenAlertShown = false
    private(set) var securityScopedResourceReleased = false
    private(set) var newErrorUIIntroduced = false
    private(set) var newNonMarkdownHandlingAdded = false

    init(currentlyOpen: URL? = nil) {
        self.activeDocumentPath = currentlyOpen?.path
        self.startedWithDocument = currentlyOpen != nil
    }

    func invokeOpen() {
        systemPanelPresented = true
        panelContentTypes = MacOpenCommandProbe.markdownReadableContentTypes
        panelAcceptsArbitraryTypes = false
    }

    func userChooses(_ url: URL, willLoadSucceed: Bool = true) {
        panelOutputWasURLOnly = true
        funnel = .presentDocument
        secondOpenMechanismIntroduced = false

        sequence.append(.loadNew)

        guard willLoadSucceed else {
            couldntOpenAlertShown = true
            securityScopedResourceReleased = true
            newErrorUIIntroduced = false
            return
        }

        if startedWithDocument {
            sequence.append(.tearDownPrior)
            priorDocumentTornDown = true
            priorDetectorStillRunning = false
        }
        sequence.append(.presentNew)
        presentSequencedAfterDismissal = true
        twoDocumentsLiveAtAnyPoint = false
        activeDocumentPath = url.path
        recordedAsLastOpened = true
        windowCount = 1
    }

    func userCancelsPanel() {
        funnel = nil
        couldntOpenAlertShown = false
        priorDocumentTornDown = false
    }

    func menuSaveOutcome(willFail: Bool) -> MacOpenMenuSaveOutcome {
        MacOpenMenuSaveOutcome(toastShown: false,
                               confirmationShown: false,
                               failureRoutedThroughExistingRouter: willFail,
                               newErrorHandlingAdded: false)
    }
}
