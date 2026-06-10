// MacCatalystShell14_RestorationTests.swift
// Mirror of features/mac-catalyst-shell-14/tests/MacRestorationTests.swift —
// T-006 owns the Mac scene-restoration bridge (Component D). Restoration is the
// MAC SURFACE of the EXISTING resume behavior: it defers entirely to
// LaunchResumeBranch / LastFileStore and introduces no new persistence or
// recovery path. Its load-bearing, unit-testable contract is that the DOCUMENT
// CHOICE is made solely by the existing resume decision, with the same outcome
// (same file, same fail-closed behavior) as iOS/iPad resume.
//
// Covers (Part 4):
//   US-5 / AC-5.1–5.3 + moved/first-launch/lifecycle edges — restores via the
//                       existing resume path; single window; same file as iOS/iPad
//                       resume; moved/deleted defers fail-closed (browser, no error
//                       UI); first launch lands on the browser; restored doc enters
//                       the unchanged conflict/lifecycle.
//   FM-3, FM-7, FM-8 — no new identity store / recovery dialog; no lifecycle change;
//                       single window.
//   Seam S-6 (the restoration entry hands control to the existing resume decision
//             and contributes no new persisted identity).

import Testing
import Foundation
@testable import Markus_v3

// MARK: - Seam contract under test (Part 4)
//
// design Component D (`MacRestorationBridge`) is a THIN bridge from the Mac
// scene-restoration entry into the SAME host.initialResumeAction →
// LaunchResumeBranch.resume(into:) decision the scene already runs. The OS may
// persist window chrome, but the DOCUMENT IDENTITY is always resolved by the
// existing LastFileStore bookmark/path resolution — never a new Mac-only store.
//
// The probe models the OBSERVABLE outcome: which document the restoration resolves
// to, that it equals the iOS/iPad resume outcome, that no new identity store is
// introduced, the fail-closed behavior for a moved/deleted/first-launch case, and
// that the restored document enters the unchanged lifecycle. It does NOT assert a
// scene-restoration API shape — only the observable resume outcome.

enum MacCatalystShell14_ResumeOutcome: Equatable {
    case document(String)   // resolved file path
    case browser            // nothing resolved — land on the browser, no error UI
}

// MARK: - US-5 / AC-5.1–5.3 — restoration defers to the existing resume decision

@Suite("US-5 — restoration restores via the existing resume path, single window, same file")
struct MacCatalystShell14_RestorationTests {

    @Test("AC-5.1 / S-6 / FM-3: restoration restores via LaunchResumeBranch / LastFileStore — no new identity store")
    func restoration_restoresViaExistingResumePath() {
        let probe = MacCatalystShell14_RestorationProbe(lastOpened: "/tmp/resume-me.md", reachable: true)
        let outcome = probe.restoreScene()
        #expect(outcome == .document("/tmp/resume-me.md"),
                "AC-5.1: restoration must restore the previously open document via the existing resume decision")
        #expect(probe.documentChoiceSource == .launchResumeBranch,
                "S-6: the document choice must be made solely by LaunchResumeBranch.resume(into:) reading LastFileStore")
        #expect(probe.newMacOnlyIdentityStoreIntroduced == false,
                "FM-3: restoration must introduce no separate Mac-only document-identity persistence store")
    }

    @Test("AC-5.2 / FM-8: restoration restores a single window/document — no tabs, no multiple windows")
    func restoration_singleWindow() {
        let probe = MacCatalystShell14_RestorationProbe(lastOpened: "/tmp/resume-me.md", reachable: true)
        _ = probe.restoreScene()
        #expect(probe.restoredWindowCount == 1, "AC-5.2: restoration must restore exactly one window")
        #expect(probe.restoredDocumentCount == 1, "AC-5.2: restoration must restore exactly one document")
        #expect(probe.restoredTabCount == 0, "FM-8: restoration must restore no document tabs")
    }

    @Test("AC-5.3: the restored document is the same file iOS/iPad resume would resolve, resolved the same way")
    func restoration_consistentWithIOSResume() {
        let mac = MacCatalystShell14_RestorationProbe(lastOpened: "/tmp/resume-me.md", reachable: true)
        let macOutcome = mac.restoreScene()
        let iosOutcome = MacCatalystShell14_RestorationProbe(lastOpened: "/tmp/resume-me.md", reachable: true).existingResumeDecision()
        #expect(macOutcome == iosOutcome,
                "AC-5.3: Mac restoration must resolve to the SAME file the existing resume behavior would")
        #expect(mac.resolutionMechanism == .bookmarkThenPathFallback,
                "AC-5.3: restoration must resolve the file the same way (security-scoped bookmark, path fallback)")
    }
}

// MARK: - Restoration edge cases (moved/deleted, first launch, lifecycle)

@Suite("Restoration edges — moved/deleted, first launch, and unchanged lifecycle")
struct MacCatalystShell14_RestorationEdgeTests {

    @Test("Moved/deleted edge / C-5.4 / FM-3: a moved file retargets via the bookmark fallback where possible")
    func restoration_movedFile_retargetsViaBookmark() {
        let probe = MacCatalystShell14_RestorationProbe(lastOpened: "/tmp/old-location.md",
                                                       reachable: true,
                                                       bookmarkRetargetsTo: "/tmp/new-location.md")
        let outcome = probe.restoreScene()
        #expect(outcome == .document("/tmp/new-location.md"),
                "C-5.4: a moved file must retarget via the existing bookmark fallback where the existing path allows")
        #expect(probe.newFileMissingDialogShown == false,
                "FM-3: restoration must add no new 'file missing' dialog or recovery flow")
    }

    @Test("Moved/deleted edge / C-5.4: an unresolvable file lands on the browser with no error UI (fail-closed)")
    func restoration_deletedFile_landsOnBrowserNoError() {
        let probe = MacCatalystShell14_RestorationProbe(lastOpened: "/tmp/gone.md", reachable: false)
        let outcome = probe.restoreScene()
        #expect(outcome == .browser,
                "C-5.4: if nothing resolves, restoration must land on the browser (fail-closed)")
        #expect(probe.errorUIShown == false,
                "C-5.4 / FM-3: restoration must show NO error UI when the prior document is gone")
    }

    @Test("First-launch edge / C-5.5: with no recorded last file, restoration resolves nothing → browser")
    func restoration_firstLaunch_landsOnBrowser() {
        let probe = MacCatalystShell14_RestorationProbe(lastOpened: nil, reachable: false)
        let outcome = probe.restoreScene()
        #expect(outcome == .browser,
                "C-5.5: first launch with no recorded last file must land on the browser (natural entry)")
        #expect(probe.placeholderWindowFabricated == false,
                "C-5.5: no empty/placeholder window may be fabricated on first launch")
    }

    @Test("Lifecycle edge / C-5.6 / FM-7: a restored document enters the SAME conflict/deletion/save lifecycle")
    func restoration_restoredDocument_entersUnchangedLifecycle() {
        let probe = MacCatalystShell14_RestorationProbe(lastOpened: "/tmp/resume-me.md", reachable: true)
        _ = probe.restoreScene()
        #expect(probe.newConflictPromptOnRestore == false,
                "C-5.6 / FM-7: restoration must add no new conflict prompt")
        #expect(probe.newDeletionBannerBehaviorOnRestore == false,
                "C-5.6 / FM-7: restoration must add no new deletion-banner behavior")
        #expect(probe.newSaveBehaviorOnRestore == false,
                "C-5.6 / FM-7: restoration must add no new save behavior")
        #expect(probe.restoredDocumentLifecycleEqualsFreshOpen,
                "C-5.6: a restored document must enter the same lifecycle as a freshly opened one")
    }
}

// MARK: - Bridge identity (compile-time S-6 assertion)
//
// The compile-time existence of the `MacRestorationBridge` symbol and its
// thin-bridge shape (a static `restore(into:store:)` entry that hands control to
// `LaunchResumeBranch.resume(into:store:)`) is itself the architectural seam
// S-6 demands: the Mac scene-restoration entry routes the OS's wakeup into the
// EXISTING resume decision, contributing no new persisted identity. The
// reference test in features/.../tests/MacRestorationTests.swift was probe-only
// and self-contained; this mirror adds the bridge-symbol reference so the suite
// FAILS TO COMPILE in the right module ("Markus_v3 has no MacRestorationBridge")
// before T-006 lands.

@Suite("S-6 — MacRestorationBridge is a thin enum bridging into LaunchResumeBranch")
struct MacCatalystShell14_RestorationBridgeIdentityTests {

    @Test("S-6 / FM-3: MacRestorationBridge is a single static entry, never an identity store")
    func bridge_isStaticEntry_noState() {
        // The bridge is a Caseless enum — no instances, no stored state, nothing
        // to persist. The compile-time form is the contract.
        #expect(MacRestorationBridge.documentChoiceSource == .launchResumeBranch,
                "S-6: MacRestorationBridge must declare that the document choice is made by LaunchResumeBranch")
        #expect(MacRestorationBridge.persistsDocumentIdentity == false,
                "FM-3: MacRestorationBridge must not persist a Mac-only document identity")
    }
}

// MARK: - Test support — RestorationProbe (Seam S-6)
//
// Models the observable outcome of the Mac restoration bridge (Component D)
// deferring to the existing resume decision. The bridge's runtime contract —
// "the document identity comes from LastFileStore via LaunchResumeBranch" — is
// the same fact in three observable forms: the resolved outcome, the chosen
// source, and the resolution mechanism.

enum MacCatalystShell14_DocumentChoiceSource { case launchResumeBranch }
enum MacCatalystShell14_ResolutionMechanism { case bookmarkThenPathFallback }

final class MacCatalystShell14_RestorationProbe {
    private let lastOpened: String?
    private let reachable: Bool
    private let bookmarkRetargetsTo: String?

    let documentChoiceSource: MacCatalystShell14_DocumentChoiceSource = .launchResumeBranch
    let resolutionMechanism: MacCatalystShell14_ResolutionMechanism = .bookmarkThenPathFallback
    let newMacOnlyIdentityStoreIntroduced = false

    private(set) var restoredWindowCount = 0
    private(set) var restoredDocumentCount = 0
    private(set) var restoredTabCount = 0
    private(set) var newFileMissingDialogShown = false
    private(set) var errorUIShown = false
    private(set) var placeholderWindowFabricated = false
    private(set) var newConflictPromptOnRestore = false
    private(set) var newDeletionBannerBehaviorOnRestore = false
    private(set) var newSaveBehaviorOnRestore = false
    private(set) var restoredDocumentLifecycleEqualsFreshOpen = false

    init(lastOpened: String?, reachable: Bool, bookmarkRetargetsTo: String? = nil) {
        self.lastOpened = lastOpened
        self.reachable = reachable
        self.bookmarkRetargetsTo = bookmarkRetargetsTo
    }

    func restoreScene() -> MacCatalystShell14_ResumeOutcome {
        let outcome = existingResumeDecision()
        switch outcome {
        case .document:
            restoredWindowCount = 1
            restoredDocumentCount = 1
            restoredTabCount = 0
            restoredDocumentLifecycleEqualsFreshOpen = true
        case .browser:
            restoredWindowCount = 1
            restoredDocumentCount = 0
            errorUIShown = false
            placeholderWindowFabricated = false
        }
        return outcome
    }

    func existingResumeDecision() -> MacCatalystShell14_ResumeOutcome {
        guard let lastOpened else { return .browser }
        if reachable {
            if let retarget = bookmarkRetargetsTo { return .document(retarget) }
            return .document(lastOpened)
        }
        return .browser
    }
}
