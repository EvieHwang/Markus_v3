// Spec test — Wave 3 / T-004
// Tags: T-004
// Verifies: AC-4.4 (500 ms debounce), EC-7 (bound), design component #7

import Testing
import Foundation
@testable import Markus_v3

@Suite("AutosaveCoordinator — T-004")
struct AutosaveCoordinatorTests {

    @MainActor
    @Test("Rapid textChanged() calls collapse to one save after 500 ms idle")
    func testDebouncedSaveAfter500ms() async throws {
        var saveCount = 0
        let coord = AutosaveCoordinator(onIdle: { saveCount += 1 })
        coord.textChanged()
        try await Task.sleep(for: .milliseconds(100))
        coord.textChanged()
        try await Task.sleep(for: .milliseconds(100))
        coord.textChanged()
        // Still within debounce window
        #expect(saveCount == 0)
        try await Task.sleep(for: .milliseconds(700))
        #expect(saveCount == 1)
    }

    @MainActor
    @Test("No save fires before the 500 ms idle window elapses")
    func testNoSaveBefore500msIdle() async throws {
        var saveCount = 0
        let coord = AutosaveCoordinator(onIdle: { saveCount += 1 })
        coord.textChanged()
        try await Task.sleep(for: .milliseconds(400))
        #expect(saveCount == 0)
    }

    @MainActor
    @Test("A later textChanged() cancels the in-flight save Task")
    func testCancellationOnOverlap() async throws {
        var saveCount = 0
        let coord = AutosaveCoordinator(onIdle: { saveCount += 1 })
        coord.textChanged()
        try await Task.sleep(for: .milliseconds(450))
        coord.textChanged() // cancels & restarts the timer
        try await Task.sleep(for: .milliseconds(450))
        #expect(saveCount == 0, "First timer should have been cancelled")
        try await Task.sleep(for: .milliseconds(200))
        #expect(saveCount == 1)
    }
}
