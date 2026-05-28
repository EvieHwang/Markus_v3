// ChangeDetectorOrderedStartTests.swift
// Spec tests for resume-and-detector-hardening-11 — ordered ChangeDetector.start().
//
// Framework: Swift Testing (@Test, #expect, #require)
// Reference specs only; live under features/.../tests/ and are not part of the
// Xcode test target. Task ID labels are applied to verify.md in Stage 5.
//
// Covers:
//   C2 ChangeDetector — ordered start (DC-7/DC-8/DC-9/DC-10/DC-11)
//
// BRs covered: BR-8, BR-9, BR-10, BR-11, BR-12, BR-13, BR-17, BR-18, BR-19.

import Testing
import Foundation
@testable import Markus_v3

@MainActor
@Suite("ChangeDetector — ordered start: initial read before live callbacks")
struct ChangeDetectorOrderedStartTests {

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

    // BR-8 / DC-7 — between detector construction and `start()` returning, an external
    // write that lands on disk should be visible in `document.lastKnownDiskContent`
    // by the time `start()` returns. (The host-seeded prior is "on-disk", the
    // post-write content is "post-write".)
    @Test("Initial read seeds lastKnownDiskContent before presenter is live")
    func initialReadSeedsLastKnownDiskBeforePresenterLive() throws {
        let dir = try makeTempDir()
        defer { remove(dir) }
        let url = dir.appendingPathComponent("note.md")
        try write(url, "on-disk")

        let document = MarkdownDocument(text: "on-disk")
        document.lastKnownDiskContent = "host-seeded-prior"
        let detector = ChangeDetector(document: document, url: url)

        // Simulate an external write landing AFTER detector construction but
        // BEFORE start() runs (the start-time race the feature closes).
        try write(url, "post-write")

        detector.start()
        defer { detector.stop() }

        #expect(document.lastKnownDiskContent == "post-write")
    }

    // BR-10 / DC-7 — no callback handler runs before the initial read seed is written.
    // We assert this by relying on the program-order ordering inside start():
    // initial read happens before presenter registration, so on the same actor
    // turn no handler body can have executed against placeholder state.
    @Test("After start, lastKnownDiskContent is never placeholder")
    func handlersNeverObservePlaceholder() throws {
        let dir = try makeTempDir()
        defer { remove(dir) }
        let url = dir.appendingPathComponent("note.md")
        try write(url, "current")

        let document = MarkdownDocument(text: "current")
        // Deliberately do NOT pre-seed; let initial-read be the first writer.
        document.lastKnownDiskContent = ""
        let detector = ChangeDetector(document: document, url: url)

        detector.start()
        defer { detector.stop() }

        #expect(document.lastKnownDiskContent == "current")
    }

    // BR-13 / DC-8 — initial-read failure is non-fatal. We simulate by pointing the
    // detector at a URL that does not exist; start() should not throw, no surface.
    @Test("Unreadable initial read leaves host-seeded prior and raises no surface")
    func initialReadFailureFallsBackToHostSeeded() throws {
        let dir = try makeTempDir()
        defer { remove(dir) }
        let url = dir.appendingPathComponent("missing.md")
        // Do not create the file.

        let document = MarkdownDocument(text: "buffer")
        document.lastKnownDiskContent = "host-seeded"
        let detector = ChangeDetector(document: document, url: url)

        detector.start()
        defer { detector.stop() }

        #expect(document.lastKnownDiskContent == "host-seeded")
        #expect(detector.activeSurface == nil)
    }

    // BR-9 / DC-7 / DC-11 — once start has completed, a steady-state external write
    // is classified as absorb against the just-seeded lastKnownDiskContent and
    // does not leave a torn state (this exercises that the seed is the correct
    // baseline for the very first post-start callback).
    @Test("Post-start external write is classified against the seeded baseline")
    func postStartWriteClassifiedAgainstSeed() async throws {
        let dir = try makeTempDir()
        defer { remove(dir) }
        let url = dir.appendingPathComponent("note.md")
        try write(url, "seed")

        let document = MarkdownDocument(text: "seed")
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

        let document = MarkdownDocument(text: "x")
        let detector = ChangeDetector(document: document, url: url)
        let before = detector.displayURL

        detector.start()
        defer { detector.stop() }

        #expect(detector.displayURL == before)
    }
}
