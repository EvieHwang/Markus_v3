import Testing
import Foundation
@testable import Markus_v3

@Suite("AutosaveCoordinator — T-004")
struct AutosaveCoordinatorTests {

    @MainActor
    @Test("Rapid textChanged() calls collapse to one save after 500 ms idle")
    func testDebouncedSaveAfter500ms() async throws {
        let counter = Counter()
        let coord = AutosaveCoordinator(onIdle: { counter.increment() })
        coord.textChanged()
        try await Task.sleep(for: .milliseconds(100))
        coord.textChanged()
        try await Task.sleep(for: .milliseconds(100))
        coord.textChanged()
        #expect(counter.value == 0)
        try await Task.sleep(for: .milliseconds(700))
        #expect(counter.value == 1)
    }

    @MainActor
    @Test("No save fires before the 500 ms idle window elapses")
    func testNoSaveBefore500msIdle() async throws {
        let counter = Counter()
        let coord = AutosaveCoordinator(onIdle: { counter.increment() })
        coord.textChanged()
        try await Task.sleep(for: .milliseconds(400))
        #expect(counter.value == 0)
    }

    @MainActor
    @Test("A later textChanged() cancels the in-flight save Task")
    func testCancellationOnOverlap() async throws {
        let counter = Counter()
        let coord = AutosaveCoordinator(onIdle: { counter.increment() })
        coord.textChanged()
        try await Task.sleep(for: .milliseconds(450))
        coord.textChanged() // cancels & restarts the timer
        try await Task.sleep(for: .milliseconds(450))
        #expect(counter.value == 0, "First timer should have been cancelled")
        try await Task.sleep(for: .milliseconds(200))
        #expect(counter.value == 1)
    }
}

@MainActor
private final class Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
