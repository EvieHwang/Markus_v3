// Spec test — resume-and-create-2 (reference / human-readable; not in the Xcode test target)
// Verifies: BR-8, BR-9, BR-22, BR-26 · DC-7, DC-11 · component C5 (NameProbe)
//
// Initial state: fails to compile (no `NameProbe` symbol) until C5 lands. Fail-on-import
// is the expected pre-build signal per CLAUDE.md's build-flow note.
//
// C5 is specified as a pure function of directory contents: given a target directory it
// returns the lowest available `Untitled[ n].md`, never overwriting an existing entry.
// These tests exercise it against a real temp directory so the observable (a URL whose
// last path component is the resolved name) is what is asserted — not any private state.
//
// Do NOT add DAG task-ID tags here — tagging happens in the next stage.

import Testing
import Foundation
@testable import Markus_v3

@Suite("NameProbe — collision-free Untitled naming (C5)")
struct NameProbeTests {

    // MARK: helpers

    /// Fresh, empty temp directory; caller is responsible for nothing — each test gets its own.
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NameProbeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    private func touch(_ name: String, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data().write(to: url)
        return url
    }

    private func resolvedName(in dir: URL) -> String {
        // Observable contract: NameProbe yields a URL/name for the next Untitled file.
        NameProbe.nextAvailableName(in: dir)
    }

    // MARK: BR-8 / DC-7 — default name in a collision-free directory

    @Test("Collision-free directory yields exactly Untitled.md")
    func testEmptyDirectoryYieldsUntitled() throws {
        let dir = try makeTempDir()
        #expect(resolvedName(in: dir) == "Untitled.md")
    }

    @Test("Directory with unrelated .md files still yields Untitled.md")
    func testUnrelatedFilesDoNotCollide() throws {
        let dir = try makeTempDir()
        try touch("Notes.md", in: dir)
        try touch("Draft.markdown", in: dir)
        #expect(resolvedName(in: dir) == "Untitled.md")
    }

    // MARK: BR-9 / DC-7 — deterministic auto-increment

    @Test("Untitled.md present → Untitled 2.md")
    func testFirstCollisionIncrementsToTwo() throws {
        let dir = try makeTempDir()
        try touch("Untitled.md", in: dir)
        #expect(resolvedName(in: dir) == "Untitled 2.md")
    }

    @Test("Untitled.md + Untitled 2.md present → Untitled 3.md")
    func testSecondCollisionIncrementsToThree() throws {
        let dir = try makeTempDir()
        try touch("Untitled.md", in: dir)
        try touch("Untitled 2.md", in: dir)
        #expect(resolvedName(in: dir) == "Untitled 3.md")
    }

    @Test("Gap is filled: Untitled.md + Untitled 3.md present → Untitled 2.md")
    func testGapIsFilledWithLowestAvailable() throws {
        let dir = try makeTempDir()
        try touch("Untitled.md", in: dir)
        try touch("Untitled 3.md", in: dir)
        // Lowest available integer ≥ 2 is 2, even though 3 exists.
        #expect(resolvedName(in: dir) == "Untitled 2.md")
    }

    @Test("Higher gap is filled: Untitled.md, 2, 4 present → Untitled 3.md")
    func testHigherGapIsFilled() throws {
        let dir = try makeTempDir()
        try touch("Untitled.md", in: dir)
        try touch("Untitled 2.md", in: dir)
        try touch("Untitled 4.md", in: dir)
        #expect(resolvedName(in: dir) == "Untitled 3.md")
    }

    // MARK: BR-26 — existing files never overwritten

    @Test("Resolved name never matches an existing entry")
    func testResolvedNameNeverCollides() throws {
        let dir = try makeTempDir()
        try touch("Untitled.md", in: dir)
        try touch("Untitled 2.md", in: dir)
        let chosen = resolvedName(in: dir)
        let exists = FileManager.default.fileExists(
            atPath: dir.appendingPathComponent(chosen).path
        )
        #expect(exists == false, "Probe must never return the name of an existing file")
    }

    @Test("Probing leaves existing file contents untouched")
    func testProbeDoesNotMutateExistingFiles() throws {
        let dir = try makeTempDir()
        let existing = try touch("Untitled.md", in: dir)
        try Data("original".utf8).write(to: existing)
        _ = resolvedName(in: dir)
        let after = try String(contentsOf: existing, encoding: .utf8)
        #expect(after == "original")
    }

    // MARK: extension discipline — only .md considered for the Untitled family

    @Test("Untitled.markdown does not block Untitled.md")
    func testMarkdownExtensionDoesNotCollideWithMd() throws {
        let dir = try makeTempDir()
        // A .markdown file with the Untitled stem is a different filename; the .md slot is free.
        try touch("Untitled.markdown", in: dir)
        #expect(resolvedName(in: dir) == "Untitled.md")
    }
}
