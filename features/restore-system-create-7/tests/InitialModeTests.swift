// InitialModeTests.swift
// Spec tests for restore-system-create-7 — verifies DC-4, the
// content-based initial-mode rule in DocumentView.onAppear.
//
// Empty content → .raw + keyboard up.
// Large content (>= 500 KB) → .raw.
// Otherwise → .rendered.
//
// The decision is a pure function of document content with no signal
// about how the file was reached (no "is this a fresh creation?" flag).
//
// Framework: Swift Testing.

import Testing
import Foundation
@testable import Markus_v3

@Suite("Initial mode — DC-4 content-based selection")
struct InitialModeTests {

    // MARK: - AC-4.1 / EC-6 — empty content

    @Test("Empty document opens in raw mode")
    func emptyContentSelectsRaw() throws {
        let mode = DocumentView.initialMode(forContent: "", byteSize: 0)
        #expect(mode == .raw)
    }

    @Test("Zero-byte pre-existing file opens in raw mode (provenance-independent)")
    func zeroBytePreexistingSelectsRaw() throws {
        // EC-6: a pre-existing zero-byte file is indistinguishable from a
        // freshly-created one at the initial-mode seam.
        let url = try writeFile(bytes: Data(), named: "preexisting-\(UUID().uuidString).md")
        let mode = DocumentView.initialMode(forFile: url)
        #expect(mode == .raw)
    }

    // MARK: - AC-4.3 — non-empty mid-size content

    @Test("Mid-size (non-empty, below large threshold) document opens in rendered mode")
    func midSizeSelectsRendered() {
        let content = String(repeating: "# Heading\nbody\n", count: 50) // ~700 bytes
        let mode = DocumentView.initialMode(forContent: content, byteSize: content.utf8.count)
        #expect(mode == .rendered)
    }

    // MARK: - Large content — existing behavior preserved

    @Test("Large document (>= 500 KB) opens in raw mode")
    func largeContentSelectsRaw() {
        let large = String(repeating: "x", count: 600_000) // ~600 KB
        let mode = DocumentView.initialMode(forContent: large, byteSize: large.utf8.count)
        #expect(mode == .raw)
    }

    // MARK: - AC-4.2 — pure function of content

    @Test("Same content yields same initial mode regardless of URL provenance")
    func decisionIgnoresProvenance() throws {
        // Two files with identical empty content but different parents —
        // one in temp, one elsewhere. The decision must be identical.
        let a = try writeFile(bytes: Data(), named: "a-\(UUID().uuidString).md", subdir: "from-create")
        let b = try writeFile(bytes: Data(), named: "b-\(UUID().uuidString).md", subdir: "from-browser")
        #expect(DocumentView.initialMode(forFile: a) == DocumentView.initialMode(forFile: b))
    }

    @Test("No caller-supplied initialMode flag is required at any create call site")
    func noCreatePathThreadsInitialMode() {
        // Behavioral observable: a DocumentView constructed without any
        // initialMode hint resolves its own mode from content. This test
        // exercises the no-hint path; if a non-nil hint were *required*,
        // this would fail to compile or throw at runtime.
        let view = DocumentView(fileURL: makeEmptyTempURL())
        _ = view // construction must not require initialMode
    }

    // MARK: - helpers

    private func writeFile(bytes: Data, named: String, subdir: String? = nil) throws -> URL {
        var dir = URL(fileURLWithPath: NSTemporaryDirectory())
        if let subdir {
            dir = dir.appendingPathComponent(subdir, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let url = dir.appendingPathComponent(named)
        try bytes.write(to: url)
        return url
    }

    private func makeEmptyTempURL() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("empty-\(UUID().uuidString).md")
        try? Data().write(to: url)
        return url
    }
}
