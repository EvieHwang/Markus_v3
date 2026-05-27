// NativePolish6_RecentsRegistrarTests.swift
// Wave-1 T-003 tests for native-polish-6 — NP-10 + C7 seam:
// RecentsRegistrar + BrowserHostController.presentDocument(isResumeOpen:)
// + LaunchResumeBranch wiring.
// Mirrors features/native-polish-6/tests/{BehavioralTests,SeamTests}.swift
// NP10 / C7 suites.

import Testing
import Foundation
import UIKit
@testable import Markus_v3

// MARK: - RecentsRegistrar direct contract

@Suite("RecentsRegistrar — call recording + failure handling")
struct RecentsRegistrarDirectTests {

    @MainActor
    @Test("register increments call count and records URL")
    func registerRecordsCall() {
        let r = RecentsRegistrar()
        let url = URL(fileURLWithPath: "/tmp/a.md")
        r.register(url: url)
        #expect(r.registerCallCount == 1)
        #expect(r.registeredURLs == [url])
    }

    @MainActor
    @Test("register on multiple URLs preserves access order")
    func registerPreservesOrder() {
        let r = RecentsRegistrar()
        let a = URL(fileURLWithPath: "/tmp/a.md")
        let b = URL(fileURLWithPath: "/tmp/b.md")
        r.register(url: a)
        r.register(url: b)
        #expect(r.registeredURLs == [a, b])
        #expect(r.registerCallCount == 2)
    }

    // NPC-16 — shouldFail=true: call still recorded, no crash, silent
    @MainActor
    @Test("Registration failure is silent — call still recorded, no crash")
    func registrationFailureIsSilent() {
        let r = RecentsRegistrar()
        r.shouldFail = true
        r.register(url: URL(fileURLWithPath: "/tmp/x.md"))
        #expect(r.registerCallCount == 1)
    }

    // Test override handler — used to inject test doubles
    @MainActor
    @Test("Override handler bypasses default mechanism but is invoked with URL")
    func overrideHandlerInvoked() {
        let r = RecentsRegistrar()
        var received: URL?
        r.overrideHandler = { received = $0 }
        let url = URL(fileURLWithPath: "/tmp/override.md")
        r.register(url: url)
        #expect(received == url)
    }
}

// MARK: - C7 Seam — BrowserHostController routing

@MainActor
@Suite("C7 Seam — BrowserHostController routes resume opens to RecentsRegistrar")
struct C7_RecentsRoutingTests {

    @Test("presentDocument with isResumeOpen=true calls RecentsRegistrar.register")
    func resumeOpenCallsRegistrar() throws {
        let host = BrowserHostController()
        let url = try Self.makeTempFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        host.presentDocument(at: url, animated: false, isResumeOpen: true)
        #expect(host.recentsRegistrar.registerCallCount == 1,
                "Resume-flagged open must call RecentsRegistrar.register")
        #expect(host.recentsRegistrar.registeredURLs.first == url)
    }

    @Test("presentDocument with isResumeOpen=false does NOT call RecentsRegistrar.register")
    func nonResumeOpenDoesNotCallRegistrar() throws {
        let host = BrowserHostController()
        let url = try Self.makeTempFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        host.presentDocument(at: url, animated: false, isResumeOpen: false)
        #expect(host.recentsRegistrar.registerCallCount == 0,
                "Browser-delegate opens (isResumeOpen=false) must NOT trigger registrar (NPC-17)")
    }

    @Test("presentDocument default isResumeOpen is false (browser delegate path)")
    func defaultIsResumeOpenIsFalse() throws {
        let host = BrowserHostController()
        let url = try Self.makeTempFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        host.presentDocument(at: url, animated: false)
        #expect(host.recentsRegistrar.registerCallCount == 0,
                "Default open path must NOT trigger registrar")
    }

    @Test("Repeated resume opens of same URL: register called every time")
    func registrarCalledEveryResumeOpen() throws {
        let host = BrowserHostController()
        let url = try Self.makeTempFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        host.presentDocument(at: url, animated: false, isResumeOpen: true)
        host.presentDocument(at: url, animated: false, isResumeOpen: true)
        host.presentDocument(at: url, animated: false, isResumeOpen: true)
        #expect(host.recentsRegistrar.registerCallCount == 3)
    }

    @Test("Mixed sequence: only isResumeOpen=true calls register")
    func mixedOpenSequenceOnlyResumeRegisters() throws {
        let host = BrowserHostController()
        let url1 = try Self.makeTempFile("a.md")
        let url2 = try Self.makeTempFile("b.md")
        let url3 = try Self.makeTempFile("c.md")
        defer {
            try? FileManager.default.removeItem(at: url1.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: url2.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: url3.deletingLastPathComponent())
        }
        host.presentDocument(at: url1, animated: false, isResumeOpen: false)
        host.presentDocument(at: url2, animated: false, isResumeOpen: true)
        host.presentDocument(at: url3, animated: false, isResumeOpen: false)
        #expect(host.recentsRegistrar.registerCallCount == 1)
        #expect(host.recentsRegistrar.registeredURLs.first?.lastPathComponent == "b.md")
    }

    @Test("Resume open with nonexistent file: still calls register (best-effort)")
    func resumeOpenWithMissingFileStillRegisters() {
        let host = BrowserHostController()
        // Nonexistent path: presentDocument bails out after registration attempt.
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).md")
        host.presentDocument(at: url, animated: false, isResumeOpen: true)
        #expect(host.recentsRegistrar.registerCallCount == 1,
                "Registration is attempted before document load; missing file must not block it")
    }

    static func makeTempFile(_ name: String = "test.md") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecentsRegistrarTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(name)
        try Data("# test\n".utf8).write(to: file)
        return file
    }
}

// MARK: - LaunchResumeBranch wiring

@MainActor
@Suite("NP-10 — LaunchResumeBranch passes isResumeOpen=true")
struct NP10_LaunchResumeBranchWiringTests {

    @Test("LaunchResumeBranch.resume triggers RecentsRegistrar via isResumeOpen=true")
    func resumeTriggersRegistrar() throws {
        let url = try C7_RecentsRoutingTests.makeTempFile("resume.md")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let suite = "LaunchResumeBranchTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LastFileStore(defaults: defaults)
        store.recordLastOpened(url)

        let host = BrowserHostController()
        let didResume = LaunchResumeBranch.resume(into: host, store: store)

        #expect(didResume == true, "Resume should succeed for a valid recorded URL")
        #expect(host.recentsRegistrar.registerCallCount == 1,
                "LaunchResumeBranch must pass isResumeOpen=true, triggering registrar")
        #expect(host.recentsRegistrar.registeredURLs.first?.lastPathComponent == "resume.md")
    }

    @Test("LaunchResumeBranch.resume with no recorded file does NOT trigger registrar")
    func noRecordedFileNoRegistrar() throws {
        let suite = "LaunchResumeBranchTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LastFileStore(defaults: defaults)

        let host = BrowserHostController()
        let didResume = LaunchResumeBranch.resume(into: host, store: store)
        #expect(didResume == false)
        #expect(host.recentsRegistrar.registerCallCount == 0)
    }
}
