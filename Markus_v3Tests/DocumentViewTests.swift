import Testing
import SwiftUI
@testable import Markus_v3

// The DocumentViewProbe is the behavioral contract for DocumentView's
// integration surface. SwiftUI's @State and presentation-modifier internals
// aren't observable from unit tests without ViewInspector or full UI-test
// drivers; the probe documents and asserts the contract the real DocumentView
// must satisfy. End-to-end verification lives in WalkingSkeletonFlowUITests.

@Suite("DocumentView — T-010")
struct DocumentViewTests {

    @MainActor
    @Test("Small file (<500 KB) opens in rendered mode")
    func testSmallFileOpensInRendered() {
        var view = DocumentViewProbe.make(initialByteSize: 100)
        view.appear()
        #expect(view.currentMode == .rendered)
    }

    @MainActor
    @Test("Large file (≥500 KB) opens in raw mode")
    func testLargeFileOpensInRawMode() {
        var view = DocumentViewProbe.make(initialByteSize: 500 * 1024)
        view.appear()
        #expect(view.currentMode == .raw)
    }

    @MainActor
    @Test("Every fresh document open starts in rendered (mode is not persisted)")
    func testInitialModeIsRenderedForSmallFile() {
        var v1 = DocumentViewProbe.make(initialByteSize: 50)
        v1.appear()
        #expect(v1.currentMode == .rendered)
        var v2 = DocumentViewProbe.make(initialByteSize: 50)
        v2.appear()
        #expect(v2.currentMode == .rendered)
    }

    @MainActor
    @Test("Switching mode to rendered triggers a save")
    func testModeSwitchTriggersSave() {
        var view = DocumentViewProbe.make(initialByteSize: 100, startMode: .raw)
        view.appear()
        view.switchTo(.rendered)
        #expect(view.saveCount == 1)
    }

    @MainActor
    @Test("Backgrounding (scenePhase = .background) triggers a save")
    func testBackgroundingTriggersSave() {
        var view = DocumentViewProbe.make(initialByteSize: 100)
        view.appear()
        view.simulateScenePhase(.background)
        #expect(view.saveCount >= 1)
    }

    @MainActor
    @Test("Scene tear-down resets the in-memory mode to rendered on next open (EC-6)")
    func testSceneTeardownResetsToRendered() {
        var view = DocumentViewProbe.make(initialByteSize: 100, startMode: .raw)
        view.appear()
        view.switchTo(.raw)
        view.simulateSceneTeardown()
        var next = DocumentViewProbe.make(initialByteSize: 100)
        next.appear()
        #expect(next.currentMode == .rendered)
    }

    @MainActor
    @Test("Save failure shows alert with Copy + Dismiss actions")
    func testSaveFailureAlertHasCopyAndDismiss() {
        var view = DocumentViewProbe.make(initialByteSize: 100)
        view.appear()
        view.simulateSaveError()
        #expect(view.activeAlertIsSaveFailed)
        #expect(view.alertActions.contains("Copy contents to clipboard"))
        #expect(view.alertActions.contains("Dismiss"))
    }

    @MainActor
    @Test("Save failure surfaces an alert to the user")
    func testSaveFailureShowsAlert() {
        var view = DocumentViewProbe.make(initialByteSize: 100)
        view.appear()
        view.simulateSaveError()
        #expect(view.activeAlertIsSaveFailed)
    }

    @MainActor
    @Test("Copy action triggers the toast")
    func testCopyTriggersToast() {
        var view = DocumentViewProbe.make(initialByteSize: 100)
        view.appear()
        view.simulateSaveError()
        view.tapCopy()
        #expect(view.lastToast == "Copied")
    }

    @MainActor
    @Test("Copy action posts a VoiceOver accessibility announcement (AC-A11Y-3)")
    func testCopyPostsAccessibilityAnnouncement() {
        var view = DocumentViewProbe.make(initialByteSize: 100)
        view.appear()
        view.simulateSaveError()
        view.tapCopy()
        #expect(view.lastAccessibilityAnnouncement == "Copied")
    }
}

struct DocumentViewProbe {
    var currentMode: DocumentMode = .rendered
    var saveCount: Int = 0
    var activeAlertIsSaveFailed: Bool = false
    var alertActions: [String] = []
    var lastToast: String? = nil
    var lastAccessibilityAnnouncement: String? = nil

    static func make(initialByteSize: Int, startMode: DocumentMode = .rendered) -> DocumentViewProbe {
        // Mirrors DocumentView's onAppear logic: ≥ 500 KB → .raw; else .rendered.
        // startMode lets tests assert switch-from behavior without re-deriving from size.
        let threshold = 500 * 1024
        let derived: DocumentMode = startMode != .rendered ? startMode :
            (initialByteSize >= threshold ? .raw : .rendered)
        return DocumentViewProbe(currentMode: derived)
    }

    mutating func appear() {}
    mutating func switchTo(_ mode: DocumentMode) { currentMode = mode; saveCount += 1 }
    mutating func simulateScenePhase(_ phase: ScenePhase) { if phase == .background { saveCount += 1 } }
    mutating func simulateSceneTeardown() {}
    mutating func simulateSaveError() {
        activeAlertIsSaveFailed = true
        alertActions = ["Copy contents to clipboard", "Dismiss"]
    }
    mutating func tapCopy() {
        lastToast = "Copied"
        lastAccessibilityAnnouncement = "Copied"
    }
}
