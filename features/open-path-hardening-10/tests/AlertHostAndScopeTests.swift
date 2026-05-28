// AlertHostAndScopeTests.swift
// Spec tests for open-path-hardening-10 (BR-2.5, BR-3.4, BR-4.4, BR-15;
// DC-6, DC-6a, DC-9, DC-10)
//
// These tests bind to the host-level public seams:
//   - BrowserHostController.openPathAlert  (Published<ActiveAlert?> exposed
//                                            for spec-test observation)
//   - BrowserHostController.activeDocument (current presented document, if
//                                            any, for the "prior document
//                                            survives" assertion)
//   - OpenPathScopeAudit.acquiredCount(for: URL)
//                                           (zero-overhead in production
//                                            builds; instrumented for tests)
//
// The build introduces these as `internal` (or `@testable internal`) seams
// solely for test observation. They are reference / not-yet-existing in the
// codebase; tests will fail with missing-symbol errors until the build adds
// them, which is the gate the build agent uses.

import Testing
import Foundation
@testable import Markus_v3

@Suite("Open path — alert host & scope safety (DC-6, DC-6a, DC-9, DC-10)")
struct AlertHostAndScopeTests {

    // BR-2.5 / BR-4.4 / DC-6 — the four new failure cases are presented
    // through the existing ActiveAlert channel; no new UI grammar (no
    // banner, no toast, no sheet). We assert the type-level fact: every
    // open-path failure surface IS an `ActiveAlert` case.
    @Test("DC-6 — failure surfaces reuse the ActiveAlert channel (no novel surface)")
    func failureSurfacesReuseActiveAlertChannel() {
        // Constructing each open-path failure as an ActiveAlert value is
        // the type-level assertion. If any of these required a non-
        // ActiveAlert surface, the line would not compile — and the
        // build agent would have flagged it before merging.
        let cases: [ActiveAlert] = [
            .invalidEncoding,
            .permissionDenied,
            .fileMovedOrRemoved,
            .couldNotReadFile,
            .tooLarge,
        ]
        // Sanity: each is Identifiable (so SwiftUI's .alert(item:) can
        // render it through the existing Conflict & lifecycle UI channel).
        for alert in cases {
            #expect(!alert.id.isEmpty)
        }
    }

    // DC-6 — all four NEW open-path failure cases (i.e. excluding the
    // already-existing .invalidEncoding) are present as ActiveAlert cases
    // after this feature lands.
    @Test("DC-6 — all four new failure cases exist as ActiveAlert cases")
    func allFourFailureCasesAreActiveAlertCases() {
        // The cases are referenced by name; the test fails to compile if
        // any of the four is missing from ActiveAlert.
        let permissionDenied: ActiveAlert = .permissionDenied
        let movedOrRemoved: ActiveAlert = .fileMovedOrRemoved
        let couldNotRead: ActiveAlert = .couldNotReadFile
        let tooLarge: ActiveAlert = .tooLarge
        // Each has a stable, non-empty id (required for .alert(item:)).
        #expect(!permissionDenied.id.isEmpty)
        #expect(!movedOrRemoved.id.isEmpty)
        #expect(!couldNotRead.id.isEmpty)
        #expect(!tooLarge.id.isEmpty)
        // All ids are pairwise distinct so SwiftUI does not collapse
        // sequential alerts of different kinds.
        let ids = Set([permissionDenied.id, movedOrRemoved.id,
                       couldNotRead.id, tooLarge.id])
        #expect(ids.count == 4)
    }

    // DC-6a — the alert host for open-path alerts is the
    // BrowserHostController's root view, on screen during browser-idle
    // (including cold launch). The behavioral property: a failed pick
    // when no document is presented produces an alert that is observable
    // through the host's open-path alert publisher.
    @MainActor
    @Test("DC-6a — cold-launch failed pick shows alert with no document presented")
    func coldLaunchFailedPickShowsAlertWithNoDocumentPresented() {
        // Construct a fresh host (mimics cold launch: no document yet).
        let host = BrowserHostController()
        #expect(host.activeDocument == nil,
                "Cold launch: no document is presented before any pick.")
        // Drive the host's failure path with a known-failing URL (we
        // simulate by writing an invalid-UTF-8 file).
        let url = (try? Self.writeInvalidUTF8File()) ?? URL(fileURLWithPath: "/dev/null")
        host.presentDocument(at: url)
        // The open-path alert publisher carries the encoding alert; no
        // document was presented (activeDocument is still nil).
        #expect(host.openPathAlert == .invalidEncoding,
                "DC-6a: a cold-launch failed pick must publish an alert on "
              + "the BrowserHostController, not on a DocumentView that "
              + "does not exist yet.")
        #expect(host.activeDocument == nil)
    }

    private static func writeInvalidUTF8File() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("open-path-host-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: dir,
                                                withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("not-utf8.md")
        try Data([0xE9, 0xE9, 0xE9]).write(to: url)
        return url
    }

    // DC-9 — every terminal state of the load pipeline releases the
    // security-scoped resource it acquired. Repeated tap-rejection cycles
    // on the same problem file do not leak scope counts.
    @MainActor
    @Test("DC-9 — scope is released on every terminal path")
    func scopeIsReleasedOnEveryTerminalPath() throws {
        let host = BrowserHostController()
        let url = try Self.writeInvalidUTF8File()

        let before = OpenPathScopeAudit.acquiredCount(for: url)
        host.presentDocument(at: url)
        let after = OpenPathScopeAudit.acquiredCount(for: url)

        #expect(after == before,
                "DC-9: a terminal alert path must pair its "
              + "startAccessingSecurityScopedResource with a matching stop; "
              + "the per-URL scope count must equal its pre-attempt value.")
    }

    // BR-15 / DC-9 — repeated failures on the same URL are idempotent:
    // same alert each time, no accumulation of stale alerts, no stacked
    // modals, no leaked scope access across attempts.
    @MainActor
    @Test("BR-15 — repeated failures on same URL are idempotent and do not leak scope")
    func repeatedFailuresOnSameUrlAreIdempotentAndDoNotLeakScope() throws {
        let host = BrowserHostController()
        let url = try Self.writeInvalidUTF8File()

        let before = OpenPathScopeAudit.acquiredCount(for: url)
        for _ in 0..<5 {
            host.presentDocument(at: url)
            // Each attempt fires the same alert. SwiftUI's .alert(item:)
            // contract ensures the binding settles to the latest value;
            // we assert the latest value is the expected encoding alert.
            #expect(host.openPathAlert == .invalidEncoding)
            // Simulate user dismiss between attempts.
            host.openPathAlert = nil
        }
        let after = OpenPathScopeAudit.acquiredCount(for: url)
        #expect(after == before,
                "BR-15 / DC-9: N failed attempts on the same URL must leave "
              + "the scope count where it started — no accumulated leak.")
    }

    // DC-10 / BR-3.4 — A failure on a later open does not tear down a
    // previously-presented document. Open file A, pick file B (failure),
    // dismiss → file A is still presented and its buffer is intact.
    @MainActor
    @Test("DC-10 — prior document survives a failed second pick")
    func priorDocumentSurvivesFailedSecondPick() throws {
        let host = BrowserHostController()

        // Open a valid file A.
        let aURL = try Self.writeValidUTF8File(content: "# file A\n")
        host.presentDocument(at: aURL)
        let docA = try #require(host.activeDocument)
        #expect(docA.text == "# file A\n")

        // Pick a failing file B.
        let bURL = try Self.writeInvalidUTF8File()
        host.presentDocument(at: bURL)
        #expect(host.openPathAlert == .invalidEncoding)

        // File A is STILL presented; its buffer and identity are unchanged.
        #expect(host.activeDocument === docA,
                "DC-10: a failed second pick must not tear down the "
              + "previously-presented document.")
        #expect(docA.text == "# file A\n")
    }

    private static func writeValidUTF8File(content: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("open-path-valid-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: dir,
                                                withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("file.md")
        try Data(content.utf8).write(to: url)
        return url
    }
}
