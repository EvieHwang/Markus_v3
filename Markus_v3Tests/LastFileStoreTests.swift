// LastFileStoreTests.swift
// Wave-1 unit tests for resume-and-create-2 / C1 LastFileStore (BR-1, BR-15,
// BR-18, BR-20 / DC-1, DC-5, DC-15). Mirrors the LastFileStoreTests suite in
// features/resume-and-create-2/tests/unit/ResumeAndCreateTests.swift, split
// out so each wave can land its tests without referencing later-wave symbols
// (see features/resume-and-create-2/build-deviations.md).

import Testing
import Foundation
@testable import Markus_v3

@Suite("LastFileStore — durable reference + RETAIN-on-failure")
struct LastFileStoreTests {

    private func makeTempFile(_ name: String = "doc.md") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LastFileStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(name)
        try Data("# hi\n".utf8).write(to: file)
        return file
    }

    private func makeStore() throws -> (LastFileStore, UserDefaults, String) {
        let suite = "LastFileStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (LastFileStore(defaults: defaults), defaults, suite)
    }

    @Test("Recorded file resolves back to the same file")
    func recordAndResolve() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        store.recordLastOpened(file)
        let resolved = try #require(store.resolveLastOpened())
        #expect(resolved.lastPathComponent == file.lastPathComponent)
    }

    @Test("Reference survives a fresh store over the same backing store")
    func referenceIsDurable() throws {
        let suite = "LastFileStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        LastFileStore(defaults: defaults).recordLastOpened(file)

        let relaunched = LastFileStore(defaults: defaults)
        let resolved = try #require(relaunched.resolveLastOpened())
        #expect(resolved.lastPathComponent == file.lastPathComponent)
    }

    @Test("Recording a second file replaces the first reference")
    func recordReplaces() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = try makeTempFile("first.md")
        let second = try makeTempFile("second.md")
        defer {
            try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: second.deletingLastPathComponent())
        }

        store.recordLastOpened(first)
        store.recordLastOpened(second)
        let resolved = try #require(store.resolveLastOpened())
        #expect(resolved.lastPathComponent == "second.md")
    }

    @Test("Deleted file resolves to nil, no crash")
    func deletedFileResolvesNil() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = try makeTempFile()
        store.recordLastOpened(file)
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())

        let resolved = store.resolveLastOpened()
        #expect(resolved == nil, "An unreachable reference must resolve to nil")
    }

    @Test("Corrupt stored reference resolves to nil, no crash")
    func corruptReferenceResolvesNil() throws {
        let suite = "LastFileStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = LastFileStore(defaults: defaults)
        store.recordLastOpened(file)

        for (key, value) in defaults.dictionaryRepresentation() where value is Data {
            defaults.set(Data([0x00, 0x01, 0x02, 0x03]), forKey: key)
        }

        let resolved = LastFileStore(defaults: defaults).resolveLastOpened()
        #expect(resolved == nil, "A corrupt bookmark must fail closed (nil), not crash")
    }

    @Test("Failed resolution retains the reference for later recovery")
    func retainOnFailure() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = try makeTempFile()
        let dir = file.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: dir) }

        store.recordLastOpened(file)

        let stashed = dir.appendingPathComponent("stashed.md")
        try FileManager.default.moveItem(at: file, to: stashed)
        #expect(store.resolveLastOpened() == nil, "While unreachable, resolution returns nil (DC-4)")

        try FileManager.default.moveItem(at: stashed, to: file)
        let recovered = store.resolveLastOpened()
        #expect(recovered != nil,
                "RETAIN-on-failure: a transient miss must not erase the reference (DC-5)")
    }

    @Test("Repeated reads never erase the reference")
    func readsAreNonDestructive() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        store.recordLastOpened(file)
        _ = store.resolveLastOpened()
        _ = store.resolveLastOpened()
        let stillThere = store.resolveLastOpened()
        #expect(stillThere != nil, "Resolving must be read-only; it must not clear the reference")
    }
}
