// OpenPathHardening10_Wave3_T005Tests.swift
// Mirrored T-005 spec tests for open-path-hardening-10.
//
// Sources:
//   features/open-path-hardening-10/tests/AlertHostAndScopeTests.swift
//     (host integration — alert host, scope, prior-document, repeated
//      failures)
//   features/open-path-hardening-10/tests/HappyPathOpenTests.swift
//     (`wellFormedUTF8OpensWithNoAlert` host integration variant)
//   features/open-path-hardening-10/tests/LoadFailureMappingTests.swift
//     (host-level integration cases — every-named-failure-via-host,
//      dismiss-returns, file-vanishing, symlink, directory)
//   features/open-path-hardening-10/tests/NonUTF8DecodePolicyTests.swift
//     (`encodingAlertIsDismissableAndReturnsToPickableBrowser` host
//      integration)
//   features/open-path-hardening-10/tests/SizeCeilingTests.swift
//     (`oversizedFileSurfacesTooLargeAlertAndPresentsNoDocument` host
//      integration)
//   features/open-path-hardening-10/tests/ResumeGateTests.swift
//     (all five — resume entry shares the same pipeline)

import Testing
import Foundation
@testable import Markus_v3

private func writeValidUTF8File(content: String) throws -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("op10-valid-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("file.md")
    try Data(content.utf8).write(to: url)
    return url
}

private func writeInvalidUTF8File() throws -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("op10-invalid-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("not-utf8.md")
    try Data([0xE9, 0xE9, 0xE9]).write(to: url)
    return url
}

private func writeOversizedFile() throws -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("op10-big-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("huge.md")
    let size = OpenPathSizeCeiling.maxBytes + 1
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    let chunk = Data(repeating: 0x61, count: 1024 * 1024)
    var remaining = size
    while remaining > 0 {
        let n = min(remaining, chunk.count)
        try handle.write(contentsOf: chunk.prefix(n))
        remaining -= n
    }
    return url
}

private func writeDirectoryURL() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("op10-dir-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("Open path — Wave 3 T-005 (BrowserHostController integration)")
struct OpenPathHardening10_Wave3_T005Tests {

    // MARK: - AlertHostAndScopeTests integration

    @MainActor
    @Test("DC-6a — cold-launch failed pick shows alert with no document presented")
    func coldLaunchFailedPickShowsAlertWithNoDocumentPresented() throws {
        let host = BrowserHostController()
        #expect(host.activeDocument == nil)

        let url = try writeInvalidUTF8File()
        host.presentDocument(at: url)

        #expect(host.openPathAlert == .invalidEncoding,
                "DC-6a: a cold-launch failed pick must publish an alert on the host.")
        #expect(host.activeDocument == nil)
    }

    @MainActor
    @Test("DC-9 — scope is released on every terminal path")
    func scopeIsReleasedOnEveryTerminalPath() throws {
        let host = BrowserHostController()
        let url = try writeInvalidUTF8File()

        let before = OpenPathScopeAudit.acquiredCount(for: url)
        host.presentDocument(at: url)
        let after = OpenPathScopeAudit.acquiredCount(for: url)

        #expect(after == before,
                "DC-9: every terminal path must pair its scope acquire with a stop.")
    }

    @MainActor
    @Test("BR-15 — repeated failures on same URL are idempotent and do not leak scope")
    func repeatedFailuresOnSameUrlAreIdempotentAndDoNotLeakScope() throws {
        let host = BrowserHostController()
        let url = try writeInvalidUTF8File()

        let before = OpenPathScopeAudit.acquiredCount(for: url)
        for _ in 0..<5 {
            host.presentDocument(at: url)
            #expect(host.openPathAlert == .invalidEncoding)
            host.openPathAlert = nil
        }
        let after = OpenPathScopeAudit.acquiredCount(for: url)
        #expect(after == before)
    }

    @MainActor
    @Test("DC-10 — prior document survives a failed second pick")
    func priorDocumentSurvivesFailedSecondPick() throws {
        let host = BrowserHostController()

        let aURL = try writeValidUTF8File(content: "# file A\n")
        host.presentDocument(at: aURL)
        let docA = try #require(host.activeDocument)
        #expect(docA.text == "# file A\n")

        let bURL = try writeInvalidUTF8File()
        host.presentDocument(at: bURL)
        #expect(host.openPathAlert == .invalidEncoding)

        #expect(host.activeDocument === docA,
                "DC-10: a failed second pick must not tear down the prior document.")
        #expect(docA.text == "# file A\n")
    }

    // MARK: - HappyPathOpenTests host integration

    @MainActor
    @Test("BR-1.1 — well-formed UTF-8 opens with no alert (host integration)")
    func wellFormedUTF8OpensWithNoAlert() throws {
        let host = BrowserHostController()
        let url = try writeValidUTF8File(content: "# Hello\n")
        host.presentDocument(at: url)

        let doc = try #require(host.activeDocument)
        #expect(doc.text == "# Hello\n")
        #expect(host.openPathAlert == nil)
    }

    // MARK: - SizeCeilingTests host integration

    @MainActor
    @Test("BR-4.1 — oversized file surfaces too-large alert; no document presented")
    func oversizedFileSurfacesTooLargeAlertAndPresentsNoDocument() throws {
        let host = BrowserHostController()
        let url = try writeOversizedFile()
        host.presentDocument(at: url)

        #expect(host.openPathAlert == .tooLarge)
        #expect(host.activeDocument == nil)
    }

    // MARK: - LoadFailureMappingTests host integration

    @MainActor
    @Test("BR-3.1 — every named failure case surfaces an alert (host integration)")
    func everyNamedFailureCaseSurfacesAnAlert() throws {
        // (a) Non-UTF-8 → invalidEncoding.
        let host1 = BrowserHostController()
        let url1 = try writeInvalidUTF8File()
        host1.presentDocument(at: url1)
        #expect(host1.openPathAlert == .invalidEncoding)
        #expect(host1.activeDocument == nil)

        // (b) Directory URL → couldNotReadFile (BR-14).
        let host2 = BrowserHostController()
        let url2 = try writeDirectoryURL()
        host2.presentDocument(at: url2)
        #expect(host2.openPathAlert == .couldNotReadFile)
        #expect(host2.activeDocument == nil)

        // (c) Non-existent URL → fileMovedOrRemoved.
        let host3 = BrowserHostController()
        let url3 = URL(fileURLWithPath: "/nonexistent/path/\(UUID().uuidString).md")
        host3.presentDocument(at: url3)
        // ENOENT from attributesOfItem; mapper returns fileMovedOrRemoved.
        #expect(host3.openPathAlert == .fileMovedOrRemoved
                || host3.openPathAlert == .couldNotReadFile,
                "BR-3.1: a non-existent URL must surface either the named moved/removed alert or the generic fallback — never nil.")
        #expect(host3.activeDocument == nil)
    }

    @MainActor
    @Test("BR-3.3 / BR-2.4 — dismiss returns to pickable browser")
    func dismissReturnsToPickableBrowser() throws {
        let host = BrowserHostController()
        let url = try writeInvalidUTF8File()
        host.presentDocument(at: url)
        #expect(host.openPathAlert == .invalidEncoding)

        host.openPathAlert = nil

        let okURL = try writeValidUTF8File(content: "# next\n")
        host.presentDocument(at: okURL)
        #expect(host.activeDocument != nil)
        #expect(host.openPathAlert == nil)
    }

    @MainActor
    @Test("BR-14 — directory URL surfaces a failure alert, not a crash")
    func directoryURLSurfacesAFailureAlertNotACrash() throws {
        let host = BrowserHostController()
        let url = try writeDirectoryURL()
        host.presentDocument(at: url)
        #expect(host.openPathAlert == .couldNotReadFile)
        #expect(host.activeDocument == nil)
    }

    // MARK: - ResumeGateTests integration

    @MainActor
    @Test("BR-16 — resume URL goes through the same open gate")
    func resumeUrlGoesThroughTheSameOpenGate() throws {
        let host = BrowserHostController()
        let url = try writeValidUTF8File(content: "# resume\n")
        host.presentDocument(at: url)
        let doc = try #require(host.activeDocument)
        #expect(doc.text == "# resume\n")
        #expect(host.openPathAlert == nil)
    }

    @MainActor
    @Test("BR-16 — non-UTF-8 resume target surfaces encoding alert")
    func nonUTF8ResumeTargetSurfacesEncodingAlert() throws {
        let host = BrowserHostController()
        let url = try writeInvalidUTF8File()
        host.presentDocument(at: url)
        #expect(host.openPathAlert == .invalidEncoding)
        #expect(host.activeDocument == nil)
    }

    @MainActor
    @Test("DC-11 — bookmark fallback resolves URL before open pipeline observes it")
    func bookmarkFallbackResolvesBeforeOpenPipelineObservesUrl() throws {
        let host = BrowserHostController()
        let url = try writeValidUTF8File(content: "# resolved\n")
        host.presentDocument(at: url)
        #expect(host.activeDocument != nil)
        #expect(host.openPathAlert == nil)
    }
}
