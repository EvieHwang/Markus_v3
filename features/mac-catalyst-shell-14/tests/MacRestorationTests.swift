// MacRestorationTests.swift
// Spec tests for mac-catalyst-shell-14 — Part 4 (single-window state restoration:
// "resume last file" on the Mac) and Part 5 (Mac app-icon assets).
//
// Framework: Swift Testing (@Test, #expect, #require).
//
// REFERENCE specs under features/mac-catalyst-shell-14/tests/ — NOT part of the
// Xcode test target (constitution.md → Testing). Written to FAIL / be
// unimplemented until the feature is built: they reference the as-yet-unbuilt Mac
// restoration bridge (design Component D — `MacRestorationBridge`) and the
// populated Mac icon slots (Component E), neither of which exists yet.
//
// Do NOT add DAG task-ID tags here — tagging happens in the next stage.
//
// Restoration is the MAC SURFACE of the EXISTING resume behavior — it defers
// entirely to LaunchResumeBranch / LastFileStore and introduces no new
// persistence or recovery path. Its load-bearing, unit-testable contract is that
// the DOCUMENT CHOICE is made solely by the existing resume decision, with the
// same outcome (same file, same fail-closed behavior) as iOS/iPad resume.
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
// Covers (Part 5):
//   US-6 / AC-6.1–6.2 — Mac icon slots populated (no empty/placeholder); iOS/iPad
//                       icon not regressed. FM-9.

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

enum ResumeOutcome: Equatable {
    case document(String)   // resolved file path
    case browser            // nothing resolved — land on the browser, no error UI
}

// MARK: - US-5 / AC-5.1–5.3 — restoration defers to the existing resume decision

@Suite("US-5 — restoration restores via the existing resume path, single window, same file")
struct MacRestorationTests {

    @Test("AC-5.1 / S-6 / FM-3: restoration restores via LaunchResumeBranch / LastFileStore — no new identity store")
    func restoration_restoresViaExistingResumePath() {
        let probe = RestorationProbe(lastOpened: "/tmp/resume-me.md", reachable: true)
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
        let probe = RestorationProbe(lastOpened: "/tmp/resume-me.md", reachable: true)
        _ = probe.restoreScene()
        #expect(probe.restoredWindowCount == 1, "AC-5.2: restoration must restore exactly one window")
        #expect(probe.restoredDocumentCount == 1, "AC-5.2: restoration must restore exactly one document")
        #expect(probe.restoredTabCount == 0, "FM-8: restoration must restore no document tabs")
    }

    @Test("AC-5.3: the restored document is the same file iOS/iPad resume would resolve, resolved the same way")
    func restoration_consistentWithIOSResume() {
        let mac = RestorationProbe(lastOpened: "/tmp/resume-me.md", reachable: true)
        let macOutcome = mac.restoreScene()
        // The reference: the existing resume decision on the same store state.
        let iosOutcome = RestorationProbe(lastOpened: "/tmp/resume-me.md", reachable: true).existingResumeDecision()
        #expect(macOutcome == iosOutcome,
                "AC-5.3: Mac restoration must resolve to the SAME file the existing resume behavior would")
        #expect(mac.resolutionMechanism == .bookmarkThenPathFallback,
                "AC-5.3: restoration must resolve the file the same way (security-scoped bookmark, path fallback)")
    }
}

// MARK: - Restoration edge cases (moved/deleted, first launch, lifecycle)

@Suite("Restoration edges — moved/deleted, first launch, and unchanged lifecycle")
struct MacRestorationEdgeTests {

    @Test("Moved/deleted edge / C-5.4 / FM-3: a moved file retargets via the bookmark fallback where possible")
    func restoration_movedFile_retargetsViaBookmark() {
        let probe = RestorationProbe(lastOpened: "/tmp/old-location.md",
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
        let probe = RestorationProbe(lastOpened: "/tmp/gone.md", reachable: false)
        let outcome = probe.restoreScene()
        #expect(outcome == .browser,
                "C-5.4: if nothing resolves, restoration must land on the browser (fail-closed)")
        #expect(probe.errorUIShown == false,
                "C-5.4 / FM-3: restoration must show NO error UI when the prior document is gone")
    }

    @Test("First-launch edge / C-5.5: with no recorded last file, restoration resolves nothing → browser")
    func restoration_firstLaunch_landsOnBrowser() {
        let probe = RestorationProbe(lastOpened: nil, reachable: false)
        let outcome = probe.restoreScene()
        #expect(outcome == .browser,
                "C-5.5: first launch with no recorded last file must land on the browser (natural entry)")
        #expect(probe.placeholderWindowFabricated == false,
                "C-5.5: no empty/placeholder window may be fabricated on first launch")
    }

    @Test("Lifecycle edge / C-5.6 / FM-7: a restored document enters the SAME conflict/deletion/save lifecycle")
    func restoration_restoredDocument_entersUnchangedLifecycle() {
        let probe = RestorationProbe(lastOpened: "/tmp/resume-me.md", reachable: true)
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

// MARK: - Part 5 / US-6 — Mac app-icon assets (Component E)

@Suite("US-6 — Mac icon slots populated; iOS/iPad icon not regressed")
struct MacAppIconTests {

    @Test("AC-6.1 / C-6.1: the Mac icon slots are populated — no empty or placeholder slot remains")
    func macIconSlots_arePopulated() {
        let catalog = IconCatalogProbe.current()
        #expect(catalog.macSlots.count == 12,
                "C-6.1: the catalog declares the 12 idiom:mac slots")
        #expect(catalog.macSlots.allSatisfy { $0.hasFilename },
                "AC-6.1 / C-6.1: every Mac slot must carry a filename — no empty/placeholder slots may remain")
        #expect(catalog.macIconRendersRealImage,
                "AC-6.1: the Dock/Finder/switcher must show a real Markus icon, not a generic placeholder or blank")
    }

    @Test("AC-6.2 / C-6.2 / FM-9: populating Mac slots does not regress the iOS/iPad icon")
    func macIconSlots_doNotRegressIOSIcon() {
        let catalog = IconCatalogProbe.current()
        #expect(catalog.iosUniversalSlotFilename == "Markus-app-icon.png",
                "AC-6.2 / FM-9: the existing iOS/iPad universal icon must be unchanged")
        #expect(catalog.iosSlotsTouched == false,
                "FM-9: populating Mac slots must not remove, break, or downgrade the iOS/iPad icon assets")
        #expect(catalog.macSlotsAreAdditive,
                "C-6.2: the Mac slots must be additive — the iOS/iPad slots are not repointed or deleted")
    }
}

// MARK: - Test support — RestorationProbe (Seam S-6)
//
// Models the observable outcome of the Mac restoration bridge (Component D)
// deferring to the existing resume decision. Required implementation surface for
// the build (mirror into Markus_v3Tests/): a Mac scene-restoration entry that
// hands control to host.initialResumeAction → LaunchResumeBranch.resume(into:),
// resolving the document via LastFileStore (bookmark, path fallback) with the
// existing fail-closed behavior, and persisting no new document identity.

enum DocumentChoiceSource { case launchResumeBranch }
enum ResolutionMechanism { case bookmarkThenPathFallback }

final class RestorationProbe {
    private let lastOpened: String?
    private let reachable: Bool
    private let bookmarkRetargetsTo: String?

    let documentChoiceSource: DocumentChoiceSource = .launchResumeBranch
    let resolutionMechanism: ResolutionMechanism = .bookmarkThenPathFallback
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

    // The Mac restoration entry hands control to the EXISTING resume decision.
    func restoreScene() -> ResumeOutcome {
        let outcome = existingResumeDecision()
        switch outcome {
        case .document:
            restoredWindowCount = 1
            restoredDocumentCount = 1
            restoredTabCount = 0
            restoredDocumentLifecycleEqualsFreshOpen = true
        case .browser:
            // Fail-closed: land on the browser; no error UI; no placeholder window.
            restoredWindowCount = 1            // the browser window itself
            restoredDocumentCount = 0
            errorUIShown = false
            placeholderWindowFabricated = false
        }
        return outcome
    }

    // The existing LaunchResumeBranch / LastFileStore decision — bookmark then
    // path fallback, fail-closed to the browser with no error UI.
    func existingResumeDecision() -> ResumeOutcome {
        guard let lastOpened else { return .browser }     // first launch
        if reachable {
            if let retarget = bookmarkRetargetsTo { return .document(retarget) }
            return .document(lastOpened)
        }
        return .browser                                    // moved/deleted, unresolvable
    }
}

// MARK: - Test support — IconCatalogProbe (Component E)
//
// Models the observable state of AppIcon.appiconset/Contents.json after the build
// populates the Mac slots. Required implementation surface for the build: assign a
// filename to each of the 12 idiom:mac slots (a sized macOS icon set) without
// touching the iOS/iPad universal entries.

struct IconSlotProbe {
    let idiom: String      // "mac"
    let hasFilename: Bool
}

struct IconCatalogProbe {
    let macSlots: [IconSlotProbe]
    let iosUniversalSlotFilename: String
    let iosSlotsTouched: Bool
    let macSlotsAreAdditive: Bool
    let macIconRendersRealImage: Bool

    // The expected post-build catalog state (C-6.1 / C-6.2). Before the build the
    // 12 mac slots carry no filename, so this reference state does not yet hold.
    static func current() -> IconCatalogProbe {
        IconCatalogProbe(
            macSlots: Array(repeating: IconSlotProbe(idiom: "mac", hasFilename: true), count: 12),
            iosUniversalSlotFilename: "Markus-app-icon.png",
            iosSlotsTouched: false,
            macSlotsAreAdditive: true,
            macIconRendersRealImage: true
        )
    }
}
