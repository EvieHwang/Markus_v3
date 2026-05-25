// ResumeAndCreateTests.swift
// Spec tests for resume-and-create-2 (unit / integration-seam level)
//
// Framework: Swift Testing (@Test, #expect, #require)
// These tests live in features/resume-and-create-2/tests/ and are reference
// specs — they are NOT part of the Xcode test target until the DAG step copies /
// links them into Markus_v3Tests/. They will fail with ImportError (missing
// symbols) until each task is implemented.
//
// Do NOT add DAG task-ID tags here — tagging happens in Stage 5 (verify.md is the
// authoritative task→test mapping after the DAG is committed).
//
// These cover the logic-level seams of the feature:
//   C5 NameProbe            — collision-free Untitled[ n].md naming
//   C6 CreateTargetResolver — last-directory-vs-local-Documents choice + writability probe
//   C7 LocalDocumentsFallback — the always-writable fallback target
//   C1 LastFileStore        — durable last-opened reference, RETAIN-on-failure
//
// The launch-branch (C2), back-navigation (C8), keyboard-active (C4/DC-8) and
// deferred-write-end-to-end (DC-9/DC-10) behaviors are observable only through a
// running scene; those are exercised in ../ui/ResumeAndCreateUITests.swift.

import Testing
import Foundation
@testable import Markus_v3

// MARK: - C5 NameProbe — collision-free Untitled naming
//
// Verifies BR-8, BR-9, BR-22, BR-26 / DC-7, DC-11.
// NameProbe is a pure function of a directory's contents: given a directory,
// it returns the lowest-available `Untitled[ n].md`, never colliding with or
// mutating an existing entry.

@Suite("NameProbe — collision-free Untitled naming")
struct NameProbeTests {

    /// Creates a fresh, empty temp directory and returns its URL. Caller cleans up.
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NameProbeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func touch(_ dir: URL, _ name: String) throws {
        try Data().write(to: dir.appendingPathComponent(name))
    }

    private func remove(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    // BR-8 / DC-7 — empty directory → exactly "Untitled.md"
    @Test("Collision-free directory yields exactly Untitled.md")
    func emptyDirectoryYieldsUntitled() throws {
        let dir = try makeTempDir()
        defer { remove(dir) }
        let url = NameProbe.availableName(in: dir)
        #expect(url.lastPathComponent == "Untitled.md")
    }

    // BR-7 / DC-6 — the produced name always ends in .md (never .markdown / .txt)
    @Test("Probed name ends in .md")
    func probedNameHasMdExtension() throws {
        let dir = try makeTempDir()
        defer { remove(dir) }
        let url = NameProbe.availableName(in: dir)
        #expect(url.pathExtension == "md")
    }

    // BR-9 / DC-7 — Untitled.md taken → "Untitled 2.md"
    @Test("Untitled.md present yields Untitled 2.md")
    func firstCollisionYieldsTwo() throws {
        let dir = try makeTempDir()
        defer { remove(dir) }
        try touch(dir, "Untitled.md")
        let url = NameProbe.availableName(in: dir)
        #expect(url.lastPathComponent == "Untitled 2.md")
    }

    // BR-9 / DC-7 — Untitled.md and Untitled 2.md taken → "Untitled 3.md"
    @Test("Untitled.md and Untitled 2.md present yields Untitled 3.md")
    func secondCollisionYieldsThree() throws {
        let dir = try makeTempDir()
        defer { remove(dir) }
        try touch(dir, "Untitled.md")
        try touch(dir, "Untitled 2.md")
        let url = NameProbe.availableName(in: dir)
        #expect(url.lastPathComponent == "Untitled 3.md")
    }

    // BR-9 / DC-7 — gap-filling: Untitled.md + Untitled 3.md present (2 free) → "Untitled 2.md"
    @Test("Gap in numbering is filled — lowest available integer wins")
    func gapIsFilled() throws {
        let dir = try makeTempDir()
        defer { remove(dir) }
        try touch(dir, "Untitled.md")
        try touch(dir, "Untitled 3.md")
        let url = NameProbe.availableName(in: dir)
        #expect(url.lastPathComponent == "Untitled 2.md")
    }

    // BR-9 / BR-26 — probing never overwrites or mutates an existing file
    @Test("Existing files are never overwritten or altered")
    func existingFilesUntouched() throws {
        let dir = try makeTempDir()
        defer { remove(dir) }
        let payload = Data("keep me".utf8)
        try payload.write(to: dir.appendingPathComponent("Untitled.md"))

        _ = NameProbe.availableName(in: dir)

        let after = try Data(contentsOf: dir.appendingPathComponent("Untitled.md"))
        #expect(after == payload, "Probing must not write to or alter existing files")
        // The probe must not itself materialize the new name on disk.
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("Untitled 2.md").path),
                "Probing must not create the candidate file")
    }

    // BR-9 — non-Untitled files in the directory do not affect the chosen name
    @Test("Unrelated files do not consume Untitled numbering")
    func unrelatedFilesIgnored() throws {
        let dir = try makeTempDir()
        defer { remove(dir) }
        try touch(dir, "notes.md")
        try touch(dir, "Untitled-draft.md") // different stem, not "Untitled n"
        let url = NameProbe.availableName(in: dir)
        #expect(url.lastPathComponent == "Untitled.md")
    }

    // DC-11 — the probe is anchored to the directory it is handed, nothing else
    @Test("Probe is computed against the supplied directory only")
    func anchoredToSuppliedDirectory() throws {
        let dirA = try makeTempDir()
        let dirB = try makeTempDir()
        defer { remove(dirA); remove(dirB) }
        try touch(dirA, "Untitled.md") // collision exists only in A

        let inB = NameProbe.availableName(in: dirB)
        #expect(inB.lastPathComponent == "Untitled.md",
                "Collisions in a different directory must not influence the result")
        #expect(inB.deletingLastPathComponent().standardizedFileURL == dirB.standardizedFileURL)
    }
}

// MARK: - C7 LocalDocumentsFallback — always-available create target
//
// Verifies the fallback half of BR-11 / DC-12. The fallback vends the app's own
// local Documents directory, which is guaranteed to exist and be writable.

@Suite("LocalDocumentsFallback — guaranteed-writable target")
struct LocalDocumentsFallbackTests {

    // BR-11 — the fallback resolves to the app container's Documents directory
    @Test("Fallback vends the app's local Documents directory")
    func vendsDocumentsDirectory() throws {
        let url = try LocalDocumentsFallback.documentsDirectory()
        let expected = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        #expect(url.standardizedFileURL == expected.standardizedFileURL)
    }

    // BR-11 — the vended directory exists and is writable
    @Test("Fallback directory exists and is writable")
    func directoryExistsAndWritable() throws {
        let url = try LocalDocumentsFallback.documentsDirectory()
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir))
        #expect(isDir.boolValue)
        #expect(FileManager.default.isWritableFile(atPath: url.path))
    }
}

// MARK: - C6 CreateTargetResolver — target directory + writability probe
//
// Verifies BR-10, BR-11, BR-21, BR-22 / DC-12. The resolver chooses the last
// directory only when a side-effect-free writability probe succeeds; otherwise it
// falls back to local Documents. The probe leaves no stray file behind on success.
//
// The store dependency is exercised through a lightweight in-test conformer so the
// resolver can be tested without a live security-scoped bookmark. The contract under
// test is observable directory CHOICE, not a call signature.

/// Minimal stand-in for the last-opened-directory provider C6 consults.
/// Mirrors the observable behavior C1 exposes to C6: "give me the last directory,
/// or nil if there is no resolvable last file."
private final class StubLastDirectoryProvider: LastDirectoryProviding {
    var lastDirectory: URL?
    init(_ url: URL?) { self.lastDirectory = url }
    func resolveLastDirectory() -> URL? { lastDirectory }
}

@Suite("CreateTargetResolver — directory choice + writability probe")
struct CreateTargetResolverTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResolverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func remove(_ dir: URL) { try? FileManager.default.removeItem(at: dir) }

    private func directoryContents(_ dir: URL) -> Set<String> {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return Set(items)
    }

    // BR-10 / DC-12 — last directory reachable & writable → target is that directory
    @Test("Writable last directory is chosen as the target")
    func writableLastDirectoryChosen() throws {
        let last = try makeTempDir()
        defer { remove(last) }
        let resolver = CreateTargetResolver(lastDirectoryProvider: StubLastDirectoryProvider(last))
        let target = try resolver.resolveTargetDirectory()
        #expect(target.standardizedFileURL == last.standardizedFileURL)
    }

    // BR-11 / DC-12 — no last reference → target is local Documents
    @Test("No last reference falls back to local Documents")
    func noLastReferenceFallsBack() throws {
        let resolver = CreateTargetResolver(lastDirectoryProvider: StubLastDirectoryProvider(nil))
        let target = try resolver.resolveTargetDirectory()
        let docs = try LocalDocumentsFallback.documentsDirectory()
        #expect(target.standardizedFileURL == docs.standardizedFileURL)
    }

    // BR-11 / BR-21 / DC-12 — last directory unreachable → fall back to local Documents
    @Test("Unreachable last directory falls back to local Documents")
    func unreachableLastDirectoryFallsBack() throws {
        // A directory that was created then removed: the provider still hands back the
        // URL, but it no longer exists on disk.
        let gone = try makeTempDir()
        remove(gone)
        let resolver = CreateTargetResolver(lastDirectoryProvider: StubLastDirectoryProvider(gone))
        let target = try resolver.resolveTargetDirectory()
        let docs = try LocalDocumentsFallback.documentsDirectory()
        #expect(target.standardizedFileURL == docs.standardizedFileURL)
    }

    // BR-21 / DC-12 — read-only last directory → fall back to local Documents
    @Test("Read-only last directory falls back to local Documents")
    func readOnlyLastDirectoryFallsBack() throws {
        let last = try makeTempDir()
        defer {
            // restore perms so cleanup can succeed
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: last.path)
            remove(last)
        }
        // Make the directory read-only (no write/execute-for-create).
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: last.path)

        let resolver = CreateTargetResolver(lastDirectoryProvider: StubLastDirectoryProvider(last))
        let target = try resolver.resolveTargetDirectory()
        let docs = try LocalDocumentsFallback.documentsDirectory()
        #expect(target.standardizedFileURL == docs.standardizedFileURL,
                "A non-writable last directory must fall through to local Documents")
    }

    // DC-12 — the writability probe is side-effect-free on success: no stray file remains.
    @Test("Writability probe leaves no residual file in a writable directory")
    func probeLeavesNoResidue() throws {
        let last = try makeTempDir()
        defer { remove(last) }
        let before = directoryContents(last)

        let resolver = CreateTargetResolver(lastDirectoryProvider: StubLastDirectoryProvider(last))
        let target = try resolver.resolveTargetDirectory()
        #expect(target.standardizedFileURL == last.standardizedFileURL)

        let after = directoryContents(last)
        #expect(after == before, "The probe must remove any temporary entry it created")
    }

    // BR-22 / DC-11+DC-12 — name probe is anchored to the resolved directory.
    // When create falls back, the Untitled name is computed from local Documents,
    // not from the (unwritable/absent) last directory.
    @Test("Name probing is anchored to the resolved fallback directory")
    func nameProbeAnchoredToResolvedDirectory() throws {
        // Last directory is gone, so the resolver must return local Documents and the
        // name probe must run there.
        let gone = try makeTempDir()
        remove(gone)
        let resolver = CreateTargetResolver(lastDirectoryProvider: StubLastDirectoryProvider(gone))
        let target = try resolver.resolveTargetDirectory()

        let chosenName = NameProbe.availableName(in: target)
        #expect(chosenName.deletingLastPathComponent().standardizedFileURL == target.standardizedFileURL,
                "The chosen new-file URL must live in the resolver's chosen directory")
    }
}

// MARK: - C1 LastFileStore — durable last-opened reference, RETAIN-on-failure
//
// Verifies BR-1, BR-15, BR-18, BR-20 / DC-1, DC-5, DC-15.
// The store records a durable reference to a file and resolves it back. A failed
// resolution (stale bookmark) must NOT clear the stored reference (RETAIN-on-failure),
// and must not crash. Recording a new file REPLACES the reference.

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

    /// A fresh store backed by an isolated UserDefaults suite so tests don't bleed.
    private func makeStore() throws -> (LastFileStore, UserDefaults, String) {
        let suite = "LastFileStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (LastFileStore(defaults: defaults), defaults, suite)
    }

    // BR-1 / DC-1 — recording a file produces a reference that resolves back to it.
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

    // BR-1 / DC-1 — the reference is durable: a second store reading the same backing
    // store resolves the file (stand-in for survival across full termination).
    @Test("Reference survives a fresh store over the same backing store")
    func referenceIsDurable() throws {
        let suite = "LastFileStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        LastFileStore(defaults: defaults).recordLastOpened(file)

        // A brand-new store instance (as on relaunch) resolves the same file.
        let relaunched = LastFileStore(defaults: defaults)
        let resolved = try #require(relaunched.resolveLastOpened())
        #expect(resolved.lastPathComponent == file.lastPathComponent)
    }

    // DC-1 — opening a different file REPLACES the reference (exactly one reference).
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

    // BR-5 / BR-19 / DC-4 — a deleted (unreachable) file resolves to nil without crashing.
    @Test("Deleted file resolves to nil, no crash")
    func deletedFileResolvesNil() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = try makeTempFile()
        store.recordLastOpened(file)
        // Remove the file (and its directory) out from under the bookmark.
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())

        let resolved = store.resolveLastOpened()
        #expect(resolved == nil, "An unreachable reference must resolve to nil")
    }

    // BR-19 / DC-4 — a corrupt/garbage stored reference resolves to nil without crashing.
    @Test("Corrupt stored reference resolves to nil, no crash")
    func corruptReferenceResolvesNil() throws {
        let suite = "LastFileStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // Plant a garbage value under whatever key the store uses, by recording a real
        // file first, then corrupting the backing data.
        let file = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = LastFileStore(defaults: defaults)
        store.recordLastOpened(file)

        // Overwrite every stored data value with junk to simulate a stale/invalid bookmark.
        for (key, value) in defaults.dictionaryRepresentation() where value is Data {
            defaults.set(Data([0x00, 0x01, 0x02, 0x03]), forKey: key)
        }

        let resolved = LastFileStore(defaults: defaults).resolveLastOpened()
        #expect(resolved == nil, "A corrupt bookmark must fail closed (nil), not crash")
    }

    // BR-20 / DC-5 — RETAIN-on-failure: a failed resolution does NOT clear the reference.
    // After the file becomes reachable again, a later resolution recovers it.
    @Test("Failed resolution retains the reference for later recovery")
    func retainOnFailure() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = try makeTempFile()
        let dir = file.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: dir) }

        store.recordLastOpened(file)

        // Simulate the file becoming temporarily unreachable (e.g. sync placeholder):
        // move it aside, resolve (fails), then move it back.
        let stashed = dir.appendingPathComponent("stashed.md")
        try FileManager.default.moveItem(at: file, to: stashed)
        #expect(store.resolveLastOpened() == nil, "While unreachable, resolution returns nil (DC-4)")

        // Reference must NOT have been cleared by that failed resolution.
        try FileManager.default.moveItem(at: stashed, to: file)
        let recovered = store.resolveLastOpened()
        #expect(recovered != nil,
                "RETAIN-on-failure: a transient miss must not erase the reference (DC-5)")
    }

    // BR-18 / DC-15 — there is no clear-on-leave path: nothing in back-navigation touches
    // the store. We assert the store exposes no observable "clear" side effect from a
    // read: repeated resolution attempts (as would happen across back-and-relaunch) keep
    // the reference intact.
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
