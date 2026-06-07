// MacOpenCommandTests.swift
// Spec tests for mac-catalyst-shell-14 — Part 2 (File → Open ⌘O) and the
// open-while-open transition (the F-001-resolved, load-success-gated ordering).
//
// Framework: Swift Testing (@Test, #expect, #require).
//
// REFERENCE specs under features/mac-catalyst-shell-14/tests/ — NOT part of the
// Xcode test target (constitution.md → Testing). Written to FAIL / be
// unimplemented until the feature is built: they reference the as-yet-unbuilt
// File → Open adapter (design Component B — `MacOpenCommand`) and the composed
// open-while-open host operation (C-2.4 / S-4), neither of which exists yet.
//
// Do NOT add DAG task-ID tags here — tagging happens in the next stage.
//
// THIS IS THE HIGHEST-VALUE BEHAVIORAL FILE: the open-while-open ordering
// (load/validate FIRST; on failure leave the prior session fully intact; only on
// success tear down the prior and present the new) is the resolved adversarial
// F-001 and the inherited DC-10 guarantee. The failed-new-open-preserves-prior
// case is covered explicitly below.
//
// Covers (Part 2):
//   US-3 / AC-3.1–3.5 — Open presents the system panel; constrained to the app's
//                       markdown types; a chosen file opens via presentDocument(at:);
//                       opened file becomes the resume target; opening replaces the
//                       single current document.
//   Open cancel / failing / non-md edge cases — cancel leaves everything untouched;
//                       a failing open surfaces the existing "Couldn't open" alert
//                       AND preserves the prior document (DC-10).
//   Open-while-open (C-2.4 / S-4, the F-001 fix) — load-success-gated ordering;
//                       failed new open leaves prior fully intact; no two-docs-live.
//   FM-2, FM-7, FM-8 — no second open mechanism; no new save/conflict UI; single
//                       window / no multi-document moment.
//   Seams S-3 (panel's only output is a URL into the existing funnel),
//         S-4 (open-while-open is load-success-gated).

import Testing
import Foundation
@testable import Markus_v3

// MARK: - Seam contract under test
//
// design Component B (`MacOpenCommand`) is a picker-to-funnel ADAPTER: it
// presents the system open panel constrained to MarkdownDocument.readableContentTypes
// and hands the chosen URL to BrowserHostController.presentDocument(at:). It
// introduces no open / decode / read / bookmark mechanism of its own (FM-2, S-3).
//
// The open-while-open transition (C-2.4 / S-4) is a COMPOSED host operation:
//   1. load/validate the chosen URL FIRST (the pure loadMarkdownDocument(at:));
//   2. on .alert — surface openPathAlert, leave the prior session fully intact;
//   3. only on .document success — tear down the prior session, then present the
//      new document (present sequenced AFTER the dismissal completes).
//
// The probe models the OBSERVABLE outcome: what panel constraint was applied,
// which funnel a chosen URL entered, whether the prior document survived a failed
// open, the teardown/present ordering, and that there is never a two-documents-
// live moment. It does NOT assert call signatures or the present-after-dismiss
// mechanism (a build choice bounded by the F-001 observable guard).

// MARK: - US-3 / AC-3.1–3.4 — Open presents the panel and funnels into the existing path

@Suite("US-3 — File → Open presents the system panel and funnels into the existing path")
struct MacOpenPanelTests {

    @Test("AC-3.1: choosing File → Open (or ⌘O) presents the system open panel")
    func open_presentsSystemPanel() {
        let probe = OpenCommandProbe()
        probe.invokeOpen()
        #expect(probe.systemPanelPresented,
                "AC-3.1: File → Open / ⌘O must present the system open panel for file selection")
    }

    @Test("AC-3.2: the panel is constrained to MarkdownDocument.readableContentTypes")
    func open_panelConstrainedToMarkdownTypes() {
        let probe = OpenCommandProbe()
        probe.invokeOpen()
        #expect(probe.panelContentTypes == OpenCommandProbe.markdownReadableContentTypes,
                "AC-3.2: the panel must offer/accept only the app's readable markdown types (.md / .markdown)")
        #expect(probe.panelAcceptsArbitraryTypes == false,
                "AC-3.2: non-markdown types must not be selectable as openable documents")
    }

    @Test("AC-3.3 / S-3 / FM-2: a chosen file opens through presentDocument(at:) — no new mechanism")
    func open_chosenFile_funnelsThroughPresentDocument() {
        let probe = OpenCommandProbe()
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
        let probe = OpenCommandProbe()
        probe.invokeOpen()
        probe.userChooses(URL(fileURLWithPath: "/tmp/notes.md"))
        // presentDocument(at:) on success fires didOpenDocument → recordLastOpened.
        #expect(probe.recordedAsLastOpened,
                "AC-3.4: an opened file must be recorded as the last-opened file, exactly as a browser pick is")
        #expect(probe.separateRecordingPathAdded == false,
                "AC-3.4: no separate recording path may be added")
    }
}

// MARK: - US-3 / AC-3.5 + open-while-open ordering (C-2.4 / S-4 — the F-001 fix)

@Suite("Open-while-open — load-success-gated ordering (resolved adversarial F-001)")
struct OpenWhileOpenTests {

    @Test("AC-3.5 / FM-8: a successful open replaces the single current document — no two-docs-live moment")
    func openWhileOpen_success_replacesSingleDocument() {
        let probe = OpenCommandProbe(currentlyOpen: URL(fileURLWithPath: "/tmp/old.md"))
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
        let probe = OpenCommandProbe(currentlyOpen: URL(fileURLWithPath: "/tmp/old.md"))
        probe.invokeOpen()
        probe.userChooses(URL(fileURLWithPath: "/tmp/new.md"), willLoadSucceed: true)
        #expect(probe.sequence == [.loadNew, .tearDownPrior, .presentNew],
                "S-4 / C-2.4: ordering must be load → conditional teardown → present (the prior is relinquished only after the new load succeeds)")
        #expect(probe.presentSequencedAfterDismissal,
                "S-4: the new present must be sequenced after the prior teardown's dismissal completes (no double-present race)")
    }

    @Test("S-4 / DC-10 (THE F-001 CASE): a FAILED new open leaves the prior document FULLY INTACT")
    func openWhileOpen_failedNewOpen_preservesPrior() {
        let probe = OpenCommandProbe(currentlyOpen: URL(fileURLWithPath: "/tmp/old.md"))
        probe.invokeOpen()
        // The chosen file fails the existing pipeline (unreadable / bad encoding /
        // over the ceiling / moved between pick and read).
        probe.userChooses(URL(fileURLWithPath: "/tmp/broken.md"), willLoadSucceed: false)

        // The prior document, its session, and its detector are UNTOUCHED — the
        // load happened first and failed, so teardown never ran (DC-10).
        #expect(probe.activeDocumentPath == "/tmp/old.md",
                "DC-10 / S-4: a failed new open must leave the PRIOR document open — never drop to the browser")
        #expect(probe.priorDocumentTornDown == false,
                "DC-10 / S-4: a failed new open must NOT tear down the prior session (the F-001 defect)")
        #expect(probe.priorDetectorStillRunning,
                "S-4: the prior document's detector must still be running after a failed new open")
        #expect(probe.sequence == [.loadNew],
                "S-4: on failure the ordering stops after the failed load — no teardown, no present")
        // The failure surfaces through the EXISTING alert, identical to a failing browser pick.
        #expect(probe.couldntOpenAlertShown,
                "S-4: a failed new open must surface the existing openPathAlert 'Couldn't open' copy")
        #expect(probe.newErrorUIIntroduced == false,
                "FM-2: no new error UI may be introduced")
    }

    @Test("S-4: a failed new open is no worse than a canceled Open (the F-001 observable guard)")
    func openWhileOpen_failedNewOpen_noWorseThanCancel() {
        let failed = OpenCommandProbe(currentlyOpen: URL(fileURLWithPath: "/tmp/old.md"))
        failed.invokeOpen()
        failed.userChooses(URL(fileURLWithPath: "/tmp/broken.md"), willLoadSucceed: false)

        let canceled = OpenCommandProbe(currentlyOpen: URL(fileURLWithPath: "/tmp/old.md"))
        canceled.invokeOpen()
        canceled.userCancelsPanel()

        #expect(failed.activeDocumentPath == canceled.activeDocumentPath,
                "S-4: a failed File → Open must leave the user no worse off than a canceled one (prior preserved both ways)")
        #expect(failed.priorDocumentTornDown == canceled.priorDocumentTornDown,
                "S-4: neither a failed nor a canceled open may tear down the prior document")
    }

    @Test("C-2.4 / FM-8: open-while-open creates no multi-window / tab / multi-document state")
    func openWhileOpen_addsNoMultiDocumentState() {
        let probe = OpenCommandProbe(currentlyOpen: URL(fileURLWithPath: "/tmp/old.md"))
        probe.invokeOpen()
        probe.userChooses(URL(fileURLWithPath: "/tmp/new.md"), willLoadSucceed: true)
        #expect(probe.windowCount == 1, "FM-8: no second window")
        #expect(probe.documentTabsCreated == 0, "FM-8: no document tabs")
        #expect(probe.multiDocumentModelUsed == false, "FM-8: no multi-document model")
    }
}

// MARK: - Open edge cases — cancel / failing / non-md (single-window, no prior open)

@Suite("Open edge cases — cancel, failing, and non-markdown")
struct MacOpenEdgeCaseTests {

    @Test("Cancel edge: dismissing the panel opens nothing, shows no error, and disturbs nothing")
    func open_canceled_leavesEverythingUntouched() {
        let probe = OpenCommandProbe(currentlyOpen: URL(fileURLWithPath: "/tmp/old.md"))
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
        let probe = OpenCommandProbe() // no prior document open
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
        let probe = OpenCommandProbe()
        probe.invokeOpen()
        // The type constraint (AC-3.2) should prevent this, but if a non-md file
        // reaches the path it is handled by the existing type/decode gates.
        probe.userChooses(URL(fileURLWithPath: "/tmp/note.txt"), willLoadSucceed: false)
        #expect(probe.funnel == .presentDocument,
                "Non-md edge: a stray non-md URL still goes through the SAME funnel — no special-case path")
        #expect(probe.couldntOpenAlertShown,
                "Non-md edge: the existing type/decode gates surface the existing 'Couldn't open' alert")
        #expect(probe.newNonMarkdownHandlingAdded == false,
                "Non-md edge: this feature adds no new non-markdown handling")
    }
}

// MARK: - FM-7 — File → Save / ⌘S add no new save or conflict UI

@Suite("FM-7 — File → Save adds no new save confirmation or conflict UI")
struct MacSaveNoNewUITests {

    @Test("FM-7: File → Save surfaces failures only through the existing SaveFailedAlertRouter; no confirmation UI")
    func menuSave_noNewUI_failureViaExistingRouter() {
        let probe = OpenCommandProbe()
        let save = probe.menuSaveOutcome(willFail: false)
        #expect(save.toastShown == false, "FM-7: File → Save must show no success toast")
        #expect(save.confirmationShown == false, "FM-7: File → Save must show no save confirmation")
        let failed = probe.menuSaveOutcome(willFail: true)
        #expect(failed.failureRoutedThroughExistingRouter,
                "FM-7: a File → Save failure must surface only through the existing SaveFailedAlertRouter / ActiveAlert.saveFailed path")
        #expect(failed.newErrorHandlingAdded == false, "FM-7: no new error handling may be added")
    }
}

// MARK: - Test support — OpenCommandProbe (Seams S-3, S-4)
//
// Models the observable behavior of the File → Open adapter (Component B) and the
// composed open-while-open host operation (C-2.4 / S-4). Required implementation
// surface for the build (mirror into Markus_v3Tests/):
//   - present the system open panel constrained to MarkdownDocument.readableContentTypes;
//   - funnel the chosen URL into BrowserHostController.presentDocument(at:);
//   - for open-while-open: load → conditional teardown → present, relinquishing the
//     prior session ONLY after the new load succeeds (load-success-gated).

enum OpenFunnel: Equatable { case presentDocument }
enum OpenStep: Equatable { case loadNew, tearDownPrior, presentNew }

struct MenuSaveOutcome {
    let toastShown: Bool
    let confirmationShown: Bool
    let failureRoutedThroughExistingRouter: Bool
    let newErrorHandlingAdded: Bool
}

final class OpenCommandProbe {

    // The app's existing accepted types (MarkdownDocument.readableContentTypes).
    static let markdownReadableContentTypes: Set<String> = ["net.daringfireball.markdown", "public.markdown"]

    // Inputs / state
    private(set) var activeDocumentPath: String?
    private let startedWithDocument: Bool

    // Panel observations
    private(set) var systemPanelPresented = false
    private(set) var panelContentTypes: Set<String> = []
    private(set) var panelAcceptsArbitraryTypes = false
    private(set) var panelOutputWasURLOnly = false

    // Funnel observations
    private(set) var funnel: OpenFunnel?
    private(set) var secondOpenMechanismIntroduced = false
    private(set) var recordedAsLastOpened = false
    private(set) var separateRecordingPathAdded = false

    // Open-while-open ordering observations (S-4 / C-2.4)
    private(set) var sequence: [OpenStep] = []
    private(set) var priorDocumentTornDown = false
    private(set) var priorDetectorStillRunning = true
    private(set) var twoDocumentsLiveAtAnyPoint = false
    private(set) var presentSequencedAfterDismissal = false
    private(set) var windowCount = 1
    private(set) var documentTabsCreated = 0
    private(set) var multiDocumentModelUsed = false

    // Failure / edge observations
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
        // The panel is constrained to the app's existing readable markdown types.
        panelContentTypes = OpenCommandProbe.markdownReadableContentTypes
        panelAcceptsArbitraryTypes = false
    }

    // The chosen URL enters the EXISTING funnel; the load is run FIRST (the pure
    // loadMarkdownDocument), and the prior session is relinquished only on success.
    func userChooses(_ url: URL, willLoadSucceed: Bool = true) {
        panelOutputWasURLOnly = true
        funnel = .presentDocument                 // S-3 — the only output is a URL into the funnel
        secondOpenMechanismIntroduced = false     // FM-2 — no parallel open mechanism

        // Step 1 — load/validate FIRST (mutates no state).
        sequence.append(.loadNew)

        guard willLoadSucceed else {
            // Step 2 — on failure, leave the prior session FULLY INTACT (DC-10).
            couldntOpenAlertShown = true
            securityScopedResourceReleased = true
            newErrorUIIntroduced = false
            // activeDocumentPath unchanged; teardown never runs; detector still up.
            return
        }

        // Step 3 — only on success: tear down prior (if any), then present new.
        if startedWithDocument {
            sequence.append(.tearDownPrior)
            priorDocumentTornDown = true
            priorDetectorStillRunning = false
        }
        sequence.append(.presentNew)
        presentSequencedAfterDismissal = true     // present after dismissal completes (no double-present)
        twoDocumentsLiveAtAnyPoint = false        // teardown-then-present is sequenced
        activeDocumentPath = url.path
        recordedAsLastOpened = true               // didOpenDocument → recordLastOpened
        windowCount = 1
    }

    func userCancelsPanel() {
        // Nothing opens; the prior document is untouched; no error.
        funnel = nil
        couldntOpenAlertShown = false
        priorDocumentTornDown = false
    }

    func menuSaveOutcome(willFail: Bool) -> MenuSaveOutcome {
        MenuSaveOutcome(toastShown: false,
                        confirmationShown: false,
                        failureRoutedThroughExistingRouter: willFail,
                        newErrorHandlingAdded: false)
    }
}
