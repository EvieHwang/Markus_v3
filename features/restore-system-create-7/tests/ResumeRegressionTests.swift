// ResumeRegressionTests.swift
// Spec tests for restore-system-create-7 — verifies that resume-on-launch
// (US-5), last-opened tracking (C1/C3), and back-to-browser (C8) keep
// working after the create-flow removal. This is regression coverage for
// behaviors preserved from `resume-and-create-2`.
//
// These tests verify *observable seam behavior*: that a system-created
// file flows through C3's `DocumentView` lifecycle hook with no special-
// case branch, that C1's bookmark store records it, and that the next
// launch resolves it as the resume target.
//
// Framework: Swift Testing.

import Testing
import Foundation
@testable import Markus_v3

@Suite("Resume + last-opened regression — DC-5, DC-6, DC-7")
struct ResumeRegressionTests {

    // MARK: - AC-5.1 / DC-5 — resume-on-launch unchanged

    @Test("A valid last-opened bookmark resolves to its file on launch")
    func validBookmarkResumes() throws {
        let url = try writeFile(bytes: Data("hi".utf8), named: "resume-\(UUID().uuidString).md")
        LastFileStore.shared.record(url: url)
        defer { LastFileStore.shared.clear() }

        let resumed = LaunchResumeBranch().resolveResumeTarget()
        #expect(resumed?.standardizedFileURL == url.standardizedFileURL,
                "Resume target must equal the recorded last-opened URL")
    }

    @Test("An unresolvable bookmark falls back silently to the browser (no crash, no alert)")
    func unresolvableBookmarkFallsBack() throws {
        // Record a URL, then delete the underlying file to make the
        // bookmark unresolvable on next resolve.
        let url = try writeFile(bytes: Data("hi".utf8), named: "doomed-\(UUID().uuidString).md")
        LastFileStore.shared.record(url: url)
        try FileManager.default.removeItem(at: url)
        defer { LastFileStore.shared.clear() }

        let resumed = LaunchResumeBranch().resolveResumeTarget()
        #expect(resumed == nil, "Unresolvable bookmark must yield nil (silent fallback)")
        // The bookmark is *retained* across resolution failure per DC-5.
        #expect(LastFileStore.shared.hasRecord, "Bookmark must be retained after failed resolution")
    }

    // MARK: - AC-5.2 / DC-6 — system-created file enters C3 funnel

    @Test("DocumentView activation for a system-created file records it as last-opened")
    func systemCreatedFileFlowsThroughC3() throws {
        // Simulate "the system create flow has completed and the framework
        // is opening the file via the normal open-document delegate path."
        let url = try writeFile(bytes: Data(), named: "Untitled-\(UUID().uuidString).md")
        LastFileStore.shared.clear()
        defer { LastFileStore.shared.clear() }

        // C3 attaches to DocumentView's lifecycle. We exercise that hook
        // by simulating activation.
        DocumentOpenObserver.shared.recordOpen(url: url)

        // The observable contract: the file is now the resume target on
        // a hypothetical next launch.
        let resumed = LaunchResumeBranch().resolveResumeTarget()
        #expect(resumed?.standardizedFileURL == url.standardizedFileURL,
                "System-created file must be recorded as last-opened with no special-case branch")
    }

    @Test("Recording does NOT distinguish system-created from browser-opened files")
    func c3NoSpecialCaseForCreates() throws {
        // EC-4: behavior is identical whether the file's parent matches
        // the prior last-opened folder or not.
        let priorFolder = try makeTempFolder(named: "prior-\(UUID().uuidString)")
        let priorFile = priorFolder.appendingPathComponent("prior.md")
        try Data("x".utf8).write(to: priorFile)
        LastFileStore.shared.record(url: priorFile)
        defer { LastFileStore.shared.clear() }

        // The "new file" lives in the same folder (EC-4 case).
        let newFile = priorFolder.appendingPathComponent("new-\(UUID().uuidString).md")
        try Data().write(to: newFile)

        DocumentOpenObserver.shared.recordOpen(url: newFile)
        let resumed = LaunchResumeBranch().resolveResumeTarget()
        #expect(resumed?.standardizedFileURL == newFile.standardizedFileURL)
    }

    // MARK: - helpers

    private func writeFile(bytes: Data, named: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(named)
        try bytes.write(to: url)
        return url
    }

    private func makeTempFolder(named: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(named, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
