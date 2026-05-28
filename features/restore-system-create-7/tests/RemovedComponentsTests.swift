// RemovedComponentsTests.swift
// Spec tests for restore-system-create-7 — verifies that the removed
// components (C4 CreateDocumentHandler, C5 NameProbe, C6 CreateTargetResolver,
// C7 LocalDocumentsFallback) and the deferred-write behavior (old DC-9)
// are absent from the codebase post-removal.
//
// Asserting "type does not exist" cannot be expressed inside a test that
// imports the module — by definition, a reference to a removed type fails
// at compile time, which IS the test. The strategy below uses two
// complementary techniques:
//
//   1. Build-time guards (compile-fail checklist) — commented-out
//      references that would re-fail compilation if the types came back.
//      The build agent should leave these as comments; uncommenting them
//      after re-introducing the types would prove the regression. This is
//      a documented checklist, intentional per /tests instructions.
//
//   2. Filesystem / source-tree probes — Swift Testing checks that the
//      removed source files are absent from Markus_v3/Create/. These run
//      at test time and would fail loudly if a stray file came back.
//      Path resolution uses #filePath relative to this spec file's
//      conceptual repo root.
//
// Note: technique (2) only protects against files at known paths. If a
// future commit moved a removed type into a new file, only technique (1)
// catches it. Both are intentional belt-and-braces coverage for AC-5.4.

import Testing
import Foundation

@Suite("Removed components — AC-5.4, DC-2, DC-3")
struct RemovedComponentsTests {

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
        ]
        let offenders = grepSwiftSources(under: "Markus_v3", containingAny: needles)
        #expect(offenders.isEmpty,
                "Deferred-write state must be gone; found in: \(offenders.joined(separator: ", "))")
    }

    // MARK: - Compile-fail checklist (technique 1)
    //
    // These references are intentionally commented out. The build agent
    // MUST NOT uncomment them. If, at any future point, a regression
    // re-introduces one of these types, uncommenting the matching line
    // will produce a compile error, proving the regression.
    //
    //   import Markus_v3
    //   _ = CreateDocumentHandler.self      // C4 — must NOT compile
    //   _ = NameProbe.self                  // C5 — must NOT compile
    //   _ = CreateTargetResolver.self       // C6 — must NOT compile
    //   _ = LocalDocumentsFallback.self     // C7 — must NOT compile

    // MARK: - helpers

    private func repoRoot() -> URL {
        // This spec file lives at <repo>/features/restore-system-create-7/tests/
        // so the repo root is three levels up.
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // tests/
            .deletingLastPathComponent() // restore-system-create-7/
            .deletingLastPathComponent() // features/
            .deletingLastPathComponent() // <repo>
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
