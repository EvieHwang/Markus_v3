// ResumeDetectorHardening11_T002Tests.swift
// Mirrored T-002 spec tests for resume-and-detector-hardening-11.
//
// Source:
//   features/resume-and-detector-hardening-11/tests/unit/ChangeDetectorOrderedStartTests.swift
//
// Covers C2 — ChangeDetector.start() ordered initial read
// (DC-7/DC-8/DC-9/DC-10/DC-11 → BR-8, BR-9, BR-10, BR-11, BR-12, BR-13, BR-17,
// BR-18, BR-19). The source spec test file is the human-readable authority;
// this file is the Xcode-target-executable mirror.
//
// Constructor adaptation (recorded in build-deviations.md as D-001): the spec
// uses `MarkdownDocument(text:)`, which is not present on the real type. The
// real document exposes `MarkdownDocument(file:contentType:)` only, which we
// drive via a `FileWrapper` to seed the same observable starting state
// (`text == content`, `lastKnownDiskContent == content`), then override
// `lastKnownDiskContent` to reproduce the spec's host-seeded scenarios.

import Testing
import Foundation
import UniformTypeIdentifiers
@testable import Markus_v3

@MainActor
@Suite("ChangeDetector — ordered start (T-002)")
struct ResumeDetectorHardening11_T002Tests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CDOrderedStart-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ url: URL, _ content: String) throws {
        try Data(content.utf8).write(to: url, options: [.atomic])
    }

    private func remove(_ dir: URL) { try? FileManager.default.removeItem(at: dir) }

    private func makeDocument(text: String) throws -> MarkdownDocument {
        let wrapper = FileWrapper(regularFileWithContents: Data(text.utf8))
        let contentType = MarkdownDocument.readableContentTypes.first!
        return try MarkdownDocument(file: wrapper, contentType: contentType)
    }

    // BR-8 / DC-7 — between detector construction and `start()` returning, an
    // external write that lands on disk should be visible in
    // `document.lastKnownDiskContent` by the time `start()` returns.
    @Test("Initial read seeds lastKnownDiskContent before presenter is live")
    func initialReadSeedsLastKnownDiskBeforePresenterLive() throws {
        let dir = try makeTempDir()
        defer { remove(dir) }
        let url = dir.appendingPathComponent("note.md")
        try write(url, "on-disk")

        let document = try makeDocument(text: "on-disk")
        document.lastKnownDiskContent = "host-seeded-prior"
        let detector = ChangeDetector(document: document, url: url)

        // Simulate an external write landing AFTER detector construction but
        // BEFORE start() runs (the start-time race the feature closes).
        try write(url, "post-write")

        detector.start()
        defer { detector.stop() }

        #expect(document.lastKnownDiskContent == "post-write")
    }

    // BR-10 / DC-7 — no callback handler runs before the initial read seed is
    // written. Asserted by program order inside start(): initial read happens
    // before presenter registration, so no handler body can execute against
    // placeholder state on the same actor turn.
    @Test("After start, lastKnownDiskContent is never placeholder")
    func handlersNeverObservePlaceholder() throws {
        let dir = try makeTempDir()
        defer { remove(dir) }
        let url = dir.appendingPathComponent("note.md")
        try write(url, "current")

        let document = try makeDocument(text: "current")
        // Deliberately NOT pre-seed; let initial-read be the first writer.
        document.lastKnownDiskContent = ""
        let detector = ChangeDetector(document: document, url: url)

        detector.start()
        defer { detector.stop() }

        #expect(document.lastKnownDiskContent == "current")
    }

    // BR-13 / DC-8 — initial-read failure is non-fatal. Detector points at a
    // URL that does not exist; start() does not throw and raises no surface.
    @Test("Unreadable initial read leaves host-seeded prior and raises no surface")
    func initialReadFailureFallsBackToHostSeeded() throws {
        let dir = try makeTempDir()
        defer { remove(dir) }
        let url = dir.appendingPathComponent("missing.md")
        // Do not create the file.

        let document = try makeDocument(text: "buffer")
        document.lastKnownDiskContent = "host-seeded"
        let detector = ChangeDetector(document: document, url: url)

        detector.start()
        defer { detector.stop() }

        #expect(document.lastKnownDiskContent == "host-seeded")
        #expect(detector.activeSurface == nil)
    }

    // BR-9 / DC-7 / DC-11 — once start has completed, a steady-state external
    // write is classified as absorb against the just-seeded lastKnownDiskContent
    // and does not leave a torn state.
    @Test("Post-start external write is classified against the seeded baseline")
    func postStartWriteClassifiedAgainstSeed() throws {
        let dir = try makeTempDir()
        defer { remove(dir) }
        let url = dir.appendingPathComponent("note.md")
        try write(url, "seed")

        let document = try makeDocument(text: "seed")
        document.lastKnownDiskContent = ""
        let detector = ChangeDetector(document: document, url: url, settleEnabled: false)

        detector.start()
        defer { detector.stop() }

        // Inject a clean external write — absorbed silently against the seed.
        detector.injectExternalChange("seed updated externally")

        // No surface (clean absorb against a clean buffer == seed).
        #expect(detector.activeSurface == nil)
        #expect(document.lastKnownDiskContent == "seed updated externally")
    }

    // BR-12 / DC-11 — `displayURL` is unchanged across start() (DC-9 precondition).
    @Test("displayURL is unchanged across start()")
    func displayURLUnchangedAcrossStart() throws {
        let dir = try makeTempDir()
        defer { remove(dir) }
        let url = dir.appendingPathComponent("note.md")
        try write(url, "x")

        let document = try makeDocument(text: "x")
        let detector = ChangeDetector(document: document, url: url)
        let before = detector.displayURL

        detector.start()
        defer { detector.stop() }

        #expect(detector.displayURL == before)
    }
}
