// Spec test — resume-and-create-2 (reference / human-readable; not in the Xcode test target)
// Verifies: BR-1, BR-5, BR-15, BR-18, BR-19, BR-20 · DC-1, DC-4, DC-5, DC-15 · component C1 (LastFileStore)
//
// Initial state: fails to compile (no `LastFileStore` symbol) until C1 lands. Fail-on-import
// is the expected pre-build signal.
//
// C1 owns the single durable last-opened reference: it records a (security-scoped) bookmark
// for a file and resolves it back to a usable URL on demand. The OBSERVABLE contract is:
//   • exactly one reference at a time; opening another replaces it (DC-1)
//   • a failed resolution does NOT clear the reference (DC-5 RETAIN-on-failure)
//   • a successful open of a different file REPLACES it (DC-5 REPLACE-on-success)
//   • resolving a corrupt/stale bookmark returns "no usable URL" rather than crashing (DC-4/BR-19)
//
// These tests use real on-disk files in a temp directory. Bookmark/persistence storage is
// implementation latitude (F-004); tests assert durability through the store's own API,
// re-instantiating the store to simulate a relaunch rather than asserting a storage location.
//
// Do NOT add DAG task-ID tags here — tagging happens in the next stage.

import Testing
import Foundation
@testable import Markus_v3

@Suite("LastFileStore — durable last-opened reference (C1)", .serialized)
struct LastFileStoreTests {

    private func makeTempFile(name: String = "doc.md", contents: String = "# hi") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LastFileStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    /// A fresh, isolated store. The build agent wires this to a test-scoped persistence
    /// backing (e.g. a per-suite suite-name UserDefaults) so suites don't bleed state.
    private func makeStore() -> LastFileStore {
        LastFileStore(persistenceKey: "test-\(UUID().uuidString)")
    }

    // MARK: BR-1 / DC-1 — a recorded reference survives "relaunch" and resolves

    @Test("Recorded reference resolves to the same file after re-instantiation")
    func testReferenceSurvivesRelaunch() throws {
        let file = try makeTempFile()
        let key = "survives-\(UUID().uuidString)"

        let store = LastFileStore(persistenceKey: key)
        try store.record(url: file)

        // Simulate full termination + relaunch: a brand-new store reading the same backing.
        let relaunched = LastFileStore(persistenceKey: key)
        let resolved = relaunched.resolve()
        #expect(resolved?.standardizedFileURL.path == file.standardizedFileURL.path)
    }

    // MARK: DC-1 — exactly one reference; opening another replaces it

    @Test("Recording a second file replaces the first (only one reference)")
    func testSecondRecordReplacesFirst() throws {
        let first = try makeTempFile(name: "first.md")
        let second = try makeTempFile(name: "second.md")
        let store = makeStore()

        try store.record(url: first)
        try store.record(url: second)

        let resolved = store.resolve()
        #expect(resolved?.standardizedFileURL.path == second.standardizedFileURL.path)
    }

    // MARK: DC-4 / BR-5 / BR-19 — unresolvable reference yields nil, no crash

    @Test("Resolving after the file is deleted returns nil, does not crash")
    func testDeletedFileResolvesToNil() throws {
        let file = try makeTempFile()
        let store = makeStore()
        try store.record(url: file)
        try FileManager.default.removeItem(at: file)

        let resolved = store.resolve()
        #expect(resolved == nil)
    }

    @Test("No reference recorded → resolve returns nil (first-ever launch)")
    func testNoReferenceResolvesToNil() {
        let store = makeStore()
        #expect(store.resolve() == nil)
    }

    // MARK: DC-5 — RETAIN-on-failure: a failed resolution does not clear the reference

    @Test("A failed resolution retains the reference; it recovers when the file returns")
    func testFailedResolutionRetainsReference() throws {
        let file = try makeTempFile()
        let key = "retain-\(UUID().uuidString)"
        let store = LastFileStore(persistenceKey: key)
        try store.record(url: file)

        // Make the file temporarily unreachable, then resolve (a failing launch).
        let stash = file.deletingLastPathComponent()
            .appendingPathComponent("stash-\(UUID().uuidString).md")
        try FileManager.default.moveItem(at: file, to: stash)
        #expect(store.resolve() == nil, "Failing launch resolves to nil (DC-4)")

        // The reference must NOT have been cleared. Restore the file and relaunch.
        try FileManager.default.moveItem(at: stash, to: file)
        let relaunched = LastFileStore(persistenceKey: key)
        let recovered = relaunched.resolve()
        #expect(recovered?.standardizedFileURL.path == file.standardizedFileURL.path,
                "RETAIN-on-failure: reference recovers once the file is reachable again")
    }

    // MARK: DC-5 — REPLACE-on-success: a successful open of a different file replaces it

    @Test("Recording a different reachable file replaces the retained one")
    func testSuccessfulOpenReplacesReference() throws {
        let original = try makeTempFile(name: "original.md")
        let replacement = try makeTempFile(name: "replacement.md")
        let store = makeStore()

        try store.record(url: original)
        try store.record(url: replacement)   // a successful open of a different file
        #expect(store.resolve()?.standardizedFileURL.path == replacement.standardizedFileURL.path)
    }

    // MARK: BR-19 — corrupt/stale bookmark does not crash

    @Test("A corrupt persisted reference resolves to nil without crashing")
    func testCorruptReferenceDoesNotCrash() throws {
        let key = "corrupt-\(UUID().uuidString)"
        // Seed the backing with garbage where a bookmark would live, then resolve.
        LastFileStore.seedCorruptReferenceForTesting(persistenceKey: key)
        let store = LastFileStore(persistenceKey: key)
        #expect(store.resolve() == nil)
    }

    // MARK: BR-18 / DC-15 — leaving a file does not clear the reference

    @Test("There is no clear-on-leave path: the reference persists until replaced")
    func testReferenceIsNotClearedByLeaving() throws {
        // C1 exposes no clear() invoked by back-navigation (C8 guarantees the dismiss path
        // does not call into C1's clear). Recording then re-instantiating still resolves.
        let file = try makeTempFile()
        let key = "noclear-\(UUID().uuidString)"
        let store = LastFileStore(persistenceKey: key)
        try store.record(url: file)
        // Simulate back-to-browser + relaunch (no record/clear in between).
        let relaunched = LastFileStore(persistenceKey: key)
        #expect(relaunched.resolve()?.standardizedFileURL.path == file.standardizedFileURL.path)
    }
}
