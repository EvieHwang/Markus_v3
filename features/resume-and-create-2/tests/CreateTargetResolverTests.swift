// Spec test — resume-and-create-2 (reference / human-readable; not in the Xcode test target)
// Verifies: BR-10, BR-11, BR-21, BR-22, BR-23 · DC-11, DC-12 · components C6 (CreateTargetResolver),
//           C7 (LocalDocumentsFallback)
//
// Initial state: fails to compile (no `CreateTargetResolver` / `LocalDocumentsFallback` symbols)
// until C6/C7 land. Fail-on-import is the expected pre-build signal.
//
// C6 chooses the create-target directory: the last-opened file's directory when it is
// reachable AND writable (via a pre-write probe, DC-12), otherwise the app's local
// Documents directory (C7). These tests assert the OBSERVABLE outcome — which directory
// the resolver returns and that the writability PROBE leaves no stray file behind — not
// the probe technique. The "last directory" is supplied via a LastFileStore seam (C1);
// tests inject directories directly through the store rather than asserting call shapes.
//
// Do NOT add DAG task-ID tags here — tagging happens in the next stage.

import Testing
import Foundation
@testable import Markus_v3

@Suite("CreateTargetResolver — target directory + writability (C6/C7)")
struct CreateTargetResolverTests {

    private func makeTempDir(writable: Bool = true) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CreateTarget-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !writable {
            // 0o555 = r-x for owner; removes write permission so the probe must fail.
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o555], ofItemAtPath: dir.path
            )
        }
        return dir
    }

    /// The app's guaranteed-writable fallback (C7). Compared by standardized path so the
    /// test is robust to trailing-slash / symlink differences.
    private func isLocalDocuments(_ url: URL) -> Bool {
        let fallback = LocalDocumentsFallback.documentsDirectory
        return url.standardizedFileURL.path == fallback.standardizedFileURL.path
    }

    // MARK: BR-10 / DC-12 — last directory chosen when writable

    @Test("Writable last directory is chosen as the target")
    func testWritableLastDirectoryIsTarget() throws {
        let lastDir = try makeTempDir(writable: true)
        let resolver = CreateTargetResolver(lastDirectoryProvider: { lastDir })
        let target = try resolver.resolveTargetDirectory()
        #expect(target.standardizedFileURL.path == lastDir.standardizedFileURL.path)
    }

    // MARK: BR-11 — fallback to local Documents when no last directory

    @Test("No last directory → local Documents")
    func testNoLastDirectoryFallsBackToLocalDocuments() throws {
        let resolver = CreateTargetResolver(lastDirectoryProvider: { nil })
        let target = try resolver.resolveTargetDirectory()
        #expect(isLocalDocuments(target))
    }

    // MARK: BR-11 / BR-21 / DC-12 — non-writable last directory → local Documents

    @Test("Read-only last directory → local Documents (no write-error)")
    func testNonWritableLastDirectoryFallsBackToLocalDocuments() throws {
        let lastDir = try makeTempDir(writable: false)
        // Restore permissions at the end so the temp dir can be cleaned up.
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lastDir.path) }
        let resolver = CreateTargetResolver(lastDirectoryProvider: { lastDir })
        let target = try resolver.resolveTargetDirectory()
        #expect(isLocalDocuments(target))
    }

    @Test("Unreachable (nonexistent) last directory → local Documents")
    func testUnreachableLastDirectoryFallsBackToLocalDocuments() throws {
        let gone = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString)", isDirectory: true)
        let resolver = CreateTargetResolver(lastDirectoryProvider: { gone })
        let target = try resolver.resolveTargetDirectory()
        #expect(isLocalDocuments(target))
    }

    // MARK: DC-12 — probe is side-effect-free on success (no stray file)

    @Test("Writability probe leaves no residual file in the chosen directory")
    func testProbeLeavesNoStrayFile() throws {
        let lastDir = try makeTempDir(writable: true)
        let before = try FileManager.default.contentsOfDirectory(atPath: lastDir.path).sorted()
        let resolver = CreateTargetResolver(lastDirectoryProvider: { lastDir })
        _ = try resolver.resolveTargetDirectory()
        let after = try FileManager.default.contentsOfDirectory(atPath: lastDir.path).sorted()
        #expect(before == after, "Probe must not leave any residual file on success")
    }

    // MARK: BR-22 / DC-11 — collision probe is anchored to the RESOLVED directory

    @Test("On fallback, name is computed from local Documents, not the rejected directory")
    func testCollisionProbeAnchoredToResolvedDirectory() throws {
        // Last directory is read-only AND already contains Untitled.md. Because the resolver
        // must fall back to local Documents, the Untitled.md in the rejected directory must
        // NOT influence the chosen name — NameProbe runs against the resolved (fallback) dir.
        let lastDir = try makeTempDir(writable: true)
        try Data().write(to: lastDir.appendingPathComponent("Untitled.md"))
        // Now make it read-only so it is rejected.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: lastDir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lastDir.path) }

        let resolver = CreateTargetResolver(lastDirectoryProvider: { lastDir })
        let target = try resolver.resolveTargetDirectory()
        #expect(isLocalDocuments(target), "Read-only last dir must be rejected")

        // The name is probed in the resolved (fallback) directory's contents, which do not
        // contain the rejected dir's Untitled.md.
        let name = NameProbe.nextAvailableName(in: target)
        // Regardless of what local Documents holds from other tests, the name must be probed
        // against `target`, never against `lastDir`.
        let collidesWithTarget = FileManager.default.fileExists(
            atPath: target.appendingPathComponent(name).path
        )
        #expect(collidesWithTarget == false)
    }

    // MARK: C7 — local Documents is the app container, always available

    @Test("LocalDocumentsFallback vends the app container Documents directory")
    func testLocalDocumentsIsAppContainer() {
        let docs = LocalDocumentsFallback.documentsDirectory
        let expected = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        #expect(docs.standardizedFileURL.path == expected?.standardizedFileURL.path)
    }
}
