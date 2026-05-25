// NameProbeTests.swift
// Wave-1 unit tests for resume-and-create-2 / C5 NameProbe (BR-7, BR-8, BR-9,
// BR-22, BR-26 / DC-6, DC-7, DC-11). Mirrors the NameProbeTests suite in
// features/resume-and-create-2/tests/unit/ResumeAndCreateTests.swift.

import Testing
import Foundation
@testable import Markus_v3

@Suite("NameProbe — collision-free Untitled naming")
struct NameProbeTests {

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

    @Test("Collision-free directory yields exactly Untitled.md")
    func emptyDirectoryYieldsUntitled() throws {
        let dir = try makeTempDir()
        defer { remove(dir) }
        let url = NameProbe.availableName(in: dir)
        #expect(url.lastPathComponent == "Untitled.md")
    }

    @Test("Probed name ends in .md")
    func probedNameHasMdExtension() throws {
        let dir = try makeTempDir()
        defer { remove(dir) }
        let url = NameProbe.availableName(in: dir)
        #expect(url.pathExtension == "md")
    }

    @Test("Untitled.md present yields Untitled 2.md")
    func firstCollisionYieldsTwo() throws {
        let dir = try makeTempDir()
        defer { remove(dir) }
        try touch(dir, "Untitled.md")
        let url = NameProbe.availableName(in: dir)
        #expect(url.lastPathComponent == "Untitled 2.md")
    }

    @Test("Untitled.md and Untitled 2.md present yields Untitled 3.md")
    func secondCollisionYieldsThree() throws {
        let dir = try makeTempDir()
        defer { remove(dir) }
        try touch(dir, "Untitled.md")
        try touch(dir, "Untitled 2.md")
        let url = NameProbe.availableName(in: dir)
        #expect(url.lastPathComponent == "Untitled 3.md")
    }

    @Test("Gap in numbering is filled — lowest available integer wins")
    func gapIsFilled() throws {
        let dir = try makeTempDir()
        defer { remove(dir) }
        try touch(dir, "Untitled.md")
        try touch(dir, "Untitled 3.md")
        let url = NameProbe.availableName(in: dir)
        #expect(url.lastPathComponent == "Untitled 2.md")
    }

    @Test("Existing files are never overwritten or altered")
    func existingFilesUntouched() throws {
        let dir = try makeTempDir()
        defer { remove(dir) }
        let payload = Data("keep me".utf8)
        try payload.write(to: dir.appendingPathComponent("Untitled.md"))

        _ = NameProbe.availableName(in: dir)

        let after = try Data(contentsOf: dir.appendingPathComponent("Untitled.md"))
        #expect(after == payload, "Probing must not write to or alter existing files")
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("Untitled 2.md").path),
                "Probing must not create the candidate file")
    }

    @Test("Unrelated files do not consume Untitled numbering")
    func unrelatedFilesIgnored() throws {
        let dir = try makeTempDir()
        defer { remove(dir) }
        try touch(dir, "notes.md")
        try touch(dir, "Untitled-draft.md")
        let url = NameProbe.availableName(in: dir)
        #expect(url.lastPathComponent == "Untitled.md")
    }

    @Test("Probe is computed against the supplied directory only")
    func anchoredToSuppliedDirectory() throws {
        let dirA = try makeTempDir()
        let dirB = try makeTempDir()
        defer { remove(dirA); remove(dirB) }
        try touch(dirA, "Untitled.md")

        let inB = NameProbe.availableName(in: dirB)
        #expect(inB.lastPathComponent == "Untitled.md",
                "Collisions in a different directory must not influence the result")
        #expect(inB.deletingLastPathComponent().standardizedFileURL == dirB.standardizedFileURL)
    }
}
