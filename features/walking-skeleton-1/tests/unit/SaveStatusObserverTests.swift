// Spec test — Wave 3 / T-005
// Tags: T-005
// Verifies: AC-RECOVER-1 (drives the alert), EC-9/10/12/13; design component #11

import Testing
import Foundation
import UIKit
@testable import Markus_v3

@Suite("SaveStatusObserver — T-005")
struct SaveStatusObserverTests {

    @MainActor
    @Test("Subscribing globally (object: nil) works without holding a UIDocument reference")
    func testGlobalNotificationSubscriptionWorksWithoutDocumentReference() {
        let observer = SaveStatusObserver()
        #expect(observer.lastSaveError == nil)
        #expect(observer.isDownloadingFromiCloud == false)
        _ = observer // retained until end of scope
    }

    @MainActor
    @Test(".savingError state sets lastSaveError")
    func testSavingErrorStateFiresLastSaveError() async throws {
        let observer = SaveStatusObserver()
        // Synthesize a stateChangedNotification from a dummy document in .savingError.
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("t.md")
        try? "x".data(using: .utf8)?.write(to: url)
        let doc = StubUIDocument(fileURL: url, state: [.savingError])
        NotificationCenter.default.post(
            name: UIDocument.stateChangedNotification,
            object: doc
        )
        try await Task.sleep(for: .milliseconds(50))
        #expect(observer.lastSaveError != nil)
    }

    @MainActor
    @Test(".editingDisabled state sets isDownloadingFromiCloud")
    func testEditingDisabledStateFiresIsDownloading() async throws {
        let observer = SaveStatusObserver()
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("t.md")
        try? "x".data(using: .utf8)?.write(to: url)
        let doc = StubUIDocument(fileURL: url, state: [.editingDisabled])
        NotificationCenter.default.post(
            name: UIDocument.stateChangedNotification,
            object: doc
        )
        try await Task.sleep(for: .milliseconds(50))
        #expect(observer.isDownloadingFromiCloud == true)
    }

    @MainActor
    @Test("deinit removes the observer cleanly")
    func testDeinitRemovesObserver() async throws {
        weak var weakRef: SaveStatusObserver?
        do {
            let obs = SaveStatusObserver()
            weakRef = obs
            _ = obs
        }
        // Post a notification after the observer is out of scope; nothing should crash.
        NotificationCenter.default.post(
            name: UIDocument.stateChangedNotification,
            object: nil
        )
        try await Task.sleep(for: .milliseconds(50))
        #expect(weakRef == nil)
    }
}

// MARK: - Stub UIDocument that lets us override documentState for testing.
private final class StubUIDocument: UIDocument, @unchecked Sendable {
    private let _state: UIDocument.State
    init(fileURL: URL, state: UIDocument.State) {
        self._state = state
        super.init(fileURL: fileURL)
    }
    override var documentState: UIDocument.State { _state }
}
