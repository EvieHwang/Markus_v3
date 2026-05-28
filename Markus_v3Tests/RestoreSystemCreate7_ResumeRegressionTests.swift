// ResumeRegressionTests — restore-system-create-7
// Mirrored from features/restore-system-create-7/tests/ResumeRegressionTests.swift.
//
// Adapted to the live API (build-deviations.md D-2):
//   - LastFileStore.shared → an instance with isolated UserDefaults keys
//     per test (the live store also uses UserDefaults, so a shared-instance
//     pattern is achievable but isolation per test is safer here).
//   - LaunchResumeBranch().resolveResumeTarget() → store.resolveLastOpened()
//     directly (the production path delegates to the same call).
//   - DocumentOpenObserver.shared.recordOpen(url:) → store.recordLastOpened(url)
//     directly (DocumentOpenObserver.install() wires didOpenDocument →
//     LastFileStore.recordLastOpened; the observable is identical).
//
// Verifies DC-5 (resume-on-launch unchanged), DC-6 (system-created files
// funnel through C3 unchanged), and the regression guards in AC-5.*.

import Testing
import Foundation
@testable import Markus_v3

@Suite("Resume + last-opened regression — DC-5, DC-6, DC-7")
struct RestoreSystemCreate7_ResumeRegressionTests {

    // MARK: - AC-5.1 / DC-5 — resume-on-launch unchanged

    @Test("A valid last-opened bookmark resolves to its file on launch")
    func validBookmarkResumes() throws {
        let store = isolatedStore()
        let url = try writeFile(bytes: Data("hi".utf8), named: "resume-\(UUID().uuidString).md")
        store.recordLastOpened(url)

        let resumed = store.resolveLastOpened()
        #expect(resumed?.standardizedFileURL == url.standardizedFileURL,
                "Resume target must equal the recorded last-opened URL")
    }

    @Test("An unresolvable bookmark falls back silently to the browser (no crash, no alert)")
    func unresolvableBookmarkFallsBack() throws {
        let store = isolatedStore()
        let url = try writeFile(bytes: Data("hi".utf8), named: "doomed-\(UUID().uuidString).md")
        store.recordLastOpened(url)
        try FileManager.default.removeItem(at: url)

        let resumed = store.resolveLastOpened()
        #expect(resumed == nil, "Unresolvable bookmark must yield nil (silent fallback)")
        // The bookmark is *retained* across resolution failure per DC-5.
        #expect(store.hasRecord, "Bookmark must be retained after failed resolution")
    }

    // MARK: - AC-5.2 / DC-6 — system-created file enters C3 funnel

    @Test("Recording an opened file from the system-create path makes it the next resume target")
    func systemCreatedFileFlowsThroughC3() throws {
        let store = isolatedStore()
        let url = try writeFile(bytes: Data(), named: "Untitled-\(UUID().uuidString).md")

        // DocumentOpenObserver wires host.didOpenDocument → store.recordLastOpened.
        // The behavioral observable is the same call, adapted per build-deviations D-2.
        store.recordLastOpened(url)

        let resumed = store.resolveLastOpened()
        #expect(resumed?.standardizedFileURL == url.standardizedFileURL,
                "System-created file must be recorded as last-opened with no special-case branch")
    }

    @Test("Recording does NOT distinguish system-created from browser-opened files")
    func c3NoSpecialCaseForCreates() throws {
        let store = isolatedStore()
        let priorFolder = try makeTempFolder(named: "prior-\(UUID().uuidString)")
        let priorFile = priorFolder.appendingPathComponent("prior.md")
        try Data("x".utf8).write(to: priorFile)
        store.recordLastOpened(priorFile)

        // The "new file" lives in the same folder (EC-4 case).
        let newFile = priorFolder.appendingPathComponent("new-\(UUID().uuidString).md")
        try Data().write(to: newFile)

        store.recordLastOpened(newFile)
        let resumed = store.resolveLastOpened()
        #expect(resumed?.standardizedFileURL == newFile.standardizedFileURL)
    }

    // MARK: - helpers

    private func isolatedStore() -> LastFileStore {
        // Per-test isolation via unique UserDefaults keys so concurrent test
        // runs don't interfere with each other or with the live app state.
        LastFileStore(
            defaults: .standard,
            bookmarkKey: "test.\(UUID().uuidString).bookmark",
            pathKey: "test.\(UUID().uuidString).path"
        )
    }

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

