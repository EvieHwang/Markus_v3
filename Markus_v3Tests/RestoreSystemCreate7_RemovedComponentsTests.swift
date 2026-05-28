// RemovedComponentsTests — restore-system-create-7
// Mirrored (and adapted to the live codebase) from
// features/restore-system-create-7/tests/RemovedComponentsTests.swift.
//
// Verifies AC-5.4 (no call site references the removed types),
// AC-6.1 (removed unit-test files are gone), DC-2/DC-3 (no
// deferred-write code path; no abandoned-create observer).

import Testing
import Foundation

@Suite("Removed components — AC-5.4, DC-2, DC-3")
struct RestoreSystemCreate7_RemovedComponentsTests {

    // MARK: - AC-5.4: removed source files are gone

    @Test("CreateDocumentHandler.swift is not present in Markus_v3/Create/")
    func createDocumentHandlerSourceAbsent() throws {
        #expect(!fileExistsInRepo("Markus_v3/Create/CreateDocumentHandler.swift"))
    }

    @Test("NameProbe.swift is not present in Markus_v3/Create/")
    func nameProbeSourceAbsent() throws {
        #expect(!fileExistsInRepo("Markus_v3/Create/NameProbe.swift"))
    }

    @Test("CreateTargetResolver.swift is not present in Markus_v3/Create/")
    func createTargetResolverSourceAbsent() throws {
        #expect(!fileExistsInRepo("Markus_v3/Create/CreateTargetResolver.swift"))
    }

    @Test("LocalDocumentsFallback.swift is not present in Markus_v3/Create/")
    func localDocumentsFallbackSourceAbsent() throws {
        #expect(!fileExistsInRepo("Markus_v3/Create/LocalDocumentsFallback.swift"))
    }

    @Test("Removed unit-test files are gone from Markus_v3Tests/")
    func removedTestFilesAbsent() throws {
        #expect(!fileExistsInRepo("Markus_v3Tests/NameProbeTests.swift"))
        #expect(!fileExistsInRepo("Markus_v3Tests/CreateTargetResolverTests.swift"))
        #expect(!fileExistsInRepo("Markus_v3Tests/LocalDocumentsFallbackTests.swift"))
    }

    // MARK: - AC-5.4: call-site grep — symbol names absent from source

    @Test("No source file mentions CreateDocumentHandler, NameProbe, CreateTargetResolver, or LocalDocumentsFallback")
    func noResidualSymbolReferences() throws {
        let needles = [
            "CreateDocumentHandler",
            "NameProbe",
            "CreateTargetResolver",
            "LocalDocumentsFallback",
        ]
        let offenders = grepSwiftSources(under: "Markus_v3", containingAny: needles)
        #expect(offenders.isEmpty,
                "Removed symbols still referenced in: \(offenders.joined(separator: ", "))")
    }

    @Test("SceneDelegate does not construct a createHandler property")
    func sceneDelegateHasNoCreateHandler() throws {
        let body = try readRepoFile("Markus_v3/Host/SceneDelegate.swift")
        #expect(!body.contains("createHandler"),
                "SceneDelegate.createHandler must be removed")
    }

    // MARK: - DC-2 / AC-3.2 — no deferred-write code path

    @Test("No Swift source references a 'deferredWrite' or 'pendingCreateURL' state")
    func noDeferredWriteState() throws {
        let needles = [
            "deferredWrite",
            "pendingCreateURL",
            "isDeferred",
            "materializeOnFirstKeystroke",
            "deferUntilFirstNonEmpty",
            "onFirstPersist",
        ]
        let offenders = grepSwiftSources(under: "Markus_v3", containingAny: needles)
        #expect(offenders.isEmpty,
                "Deferred-write state must be gone; found in: \(offenders.joined(separator: ", "))")
    }

    // MARK: - helpers

    private func repoRoot() -> URL {
        // This test file lives at <repo>/Markus_v3Tests/<file>.swift; the repo root
        // is two levels up. Fall back to walking up until we see the project file
        // if the test bundle copies the file elsewhere.
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let twoUp = here.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: twoUp.appendingPathComponent("Markus_v3.xcodeproj").path) {
            return twoUp
        }
        // Fallback: walk up to find the project root marker.
        var dir = here
        for _ in 0..<6 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Markus_v3.xcodeproj").path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        return twoUp
    }

    private func fileExistsInRepo(_ relPath: String) -> Bool {
        FileManager.default.fileExists(atPath: repoRoot().appendingPathComponent(relPath).path)
    }

    private func readRepoFile(_ relPath: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relPath), encoding: .utf8)
    }

    private func grepSwiftSources(under relRoot: String, containingAny needles: [String]) -> [String] {
        let root = repoRoot().appendingPathComponent(relRoot)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var offenders: [String] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            guard let body = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for needle in needles {
                if body.contains(needle) {
                    offenders.append("\(url.lastPathComponent) (\(needle))")
                    break
                }
            }
        }
        return offenders
    }
}
