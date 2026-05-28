// InitialModeTests — restore-system-create-7
// Mirrored from features/restore-system-create-7/tests/InitialModeTests.swift.
//
// Verifies DC-4 — content-based initial-mode rule:
//   empty content → .raw (+ keyboard via DocumentView state)
//   large content (>= 500 KB) → .raw
//   otherwise → .rendered
// Decision is a pure function of content; URL/provenance is irrelevant.

import Testing
import Foundation
@testable import Markus_v3

@Suite("Initial mode — DC-4 content-based selection")
struct RestoreSystemCreate7_InitialModeTests {

    // MARK: - AC-4.1 / EC-6 — empty content

    @Test("Empty document opens in raw mode")
    func emptyContentSelectsRaw() throws {
        let mode = DocumentView.initialMode(forContent: "", byteSize: 0)
        #expect(mode == .raw)
    }

    @Test("Zero-byte pre-existing file opens in raw mode (provenance-independent)")
    func zeroBytePreexistingSelectsRaw() throws {
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
        let a = try writeFile(bytes: Data(), named: "a-\(UUID().uuidString).md", subdir: "from-create")
        let b = try writeFile(bytes: Data(), named: "b-\(UUID().uuidString).md", subdir: "from-browser")
        #expect(DocumentView.initialMode(forFile: a) == DocumentView.initialMode(forFile: b))
    }

    @Test("No caller-supplied initialMode flag is required at any create call site")
    func noCreatePathThreadsInitialMode() throws {
        // Behavioral observable: DocumentView's create-time call shape does
        // not require an initialMode hint — the content rule decides. We
        // verify this by confirming the production caller in
        // BrowserHostController does not pass an initialMode argument.
        // (Spec adaptation per build-deviations.md D-2.)
        let body = try readRepoFile("Markus_v3/Host/BrowserHostController.swift")
        #expect(!body.contains("initialMode:"),
                "BrowserHostController must not thread an initialMode argument; got: \(body)")
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

    private func repoRoot() -> URL {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let twoUp = here.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: twoUp.appendingPathComponent("Markus_v3.xcodeproj").path) {
            return twoUp
        }
        var dir = here
        for _ in 0..<6 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Markus_v3.xcodeproj").path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        return twoUp
    }

    private func readRepoFile(_ relPath: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relPath), encoding: .utf8)
    }
}
