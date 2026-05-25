// CreateTargetResolverTests.swift
// Wave-2 unit tests for resume-and-create-2 / C6 CreateTargetResolver
// (BR-10, BR-11, BR-21, BR-22 / DC-12). Mirrors the CreateTargetResolverTests
// suite in features/resume-and-create-2/tests/unit/ResumeAndCreateTests.swift
// (split per build-deviations.md D-001).

import Testing
import Foundation
@testable import Markus_v3

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

    @Test("Writable last directory is chosen as the target")
    func writableLastDirectoryChosen() throws {
        let last = try makeTempDir()
        defer { remove(last) }
        let resolver = CreateTargetResolver(lastDirectoryProvider: StubLastDirectoryProvider(last))
        let target = try resolver.resolveTargetDirectory()
        #expect(target.standardizedFileURL == last.standardizedFileURL)
    }

    @Test("No last reference falls back to local Documents")
    func noLastReferenceFallsBack() throws {
        let resolver = CreateTargetResolver(lastDirectoryProvider: StubLastDirectoryProvider(nil))
        let target = try resolver.resolveTargetDirectory()
        let docs = try LocalDocumentsFallback.documentsDirectory()
        #expect(target.standardizedFileURL == docs.standardizedFileURL)
    }

    @Test("Unreachable last directory falls back to local Documents")
    func unreachableLastDirectoryFallsBack() throws {
        let gone = try makeTempDir()
        remove(gone)
        let resolver = CreateTargetResolver(lastDirectoryProvider: StubLastDirectoryProvider(gone))
        let target = try resolver.resolveTargetDirectory()
        let docs = try LocalDocumentsFallback.documentsDirectory()
        #expect(target.standardizedFileURL == docs.standardizedFileURL)
    }

    @Test("Read-only last directory falls back to local Documents")
    func readOnlyLastDirectoryFallsBack() throws {
        let last = try makeTempDir()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: last.path)
            remove(last)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: last.path)

        let resolver = CreateTargetResolver(lastDirectoryProvider: StubLastDirectoryProvider(last))
        let target = try resolver.resolveTargetDirectory()
        let docs = try LocalDocumentsFallback.documentsDirectory()
        #expect(target.standardizedFileURL == docs.standardizedFileURL,
                "A non-writable last directory must fall through to local Documents")
    }

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

    @Test("Name probing is anchored to the resolved fallback directory")
    func nameProbeAnchoredToResolvedDirectory() throws {
        let gone = try makeTempDir()
        remove(gone)
        let resolver = CreateTargetResolver(lastDirectoryProvider: StubLastDirectoryProvider(gone))
        let target = try resolver.resolveTargetDirectory()

        let chosenName = NameProbe.availableName(in: target)
        #expect(chosenName.deletingLastPathComponent().standardizedFileURL == target.standardizedFileURL,
                "The chosen new-file URL must live in the resolver's chosen directory")
    }
}
