// CreateLocationTests — restore-system-create-7
// Mirrored (and adapted to the live codebase API) from
// features/restore-system-create-7/tests/CreateLocationTests.swift.
//
// Verifies DC-1 — the system create delegate is template-only: it
// completes the system handler with a URL in NSTemporaryDirectory(),
// a `.md` extension, an empty file on disk, and a success import mode.
// The template URL is independent of any last-opened directory.

import Testing
import Foundation
import UIKit
@testable import Markus_v3

@MainActor
@Suite("Create location — DC-1 template-only handoff")
struct RestoreSystemCreate7_CreateLocationTests {

    // MARK: - AC-1.1 / AC-1.3 / DC-1

    @Test("Create-delegate template URL points at a temp-dir .md, not an app-chosen target directory")
    func templateLandsInTempDir() async throws {
        let host = BrowserHostController()
        let templateURL = try await invokeCreateDelegate(on: host).url
        #expect(templateURL != nil, "Template URL must be non-nil")
        guard let templateURL else { return }

        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory()).standardizedFileURL
        let templateParent = templateURL.deletingLastPathComponent().standardizedFileURL
        #expect(templateParent.path.hasPrefix(tempRoot.path),
                "Template URL must live in NSTemporaryDirectory(); got \(templateURL.path)")
        #expect(["md", "markdown"].contains(templateURL.pathExtension.lowercased()))
    }

    @Test("Template file is created and is empty (zero bytes) before handoff")
    func templateIsEmptyOnDisk() async throws {
        let host = BrowserHostController()
        let outcome = try await invokeCreateDelegate(on: host)
        guard let url = outcome.url else {
            Issue.record("Template URL was nil")
            return
        }
        #expect(FileManager.default.fileExists(atPath: url.path))
        let data = try Data(contentsOf: url)
        #expect(data.isEmpty, "Template content must be empty; got \(data.count) bytes")
    }

    @Test("Create-delegate completes with a success import mode, not .none")
    func templateCompletesWithSuccessMode() async throws {
        let host = BrowserHostController()
        let outcome = try await invokeCreateDelegate(on: host)
        // .copy or .move both satisfy DC-1's "success mode"; .none would mean
        // the framework rejects the create.
        #expect(outcome.mode == .copy || outcome.mode == .move,
                "Delegate must complete with a success import mode; got \(outcome.mode)")
    }

    // MARK: - AC-1.2 / DC-1 — last-opened directory is NOT used

    @Test("Template URL is independent of the last-opened file's folder")
    func templateURLIgnoresLastOpenedDirectory() async throws {
        // Pre-seed a last-opened record pointing into folder Y, using
        // the actual LastFileStore API (D-2 in build-deviations.md).
        let store = LastFileStore(
            defaults: .standard,
            bookmarkKey: "test.\(UUID().uuidString).bookmark",
            pathKey: "test.\(UUID().uuidString).path"
        )
        // Note: we use the live store to mimic the production write path,
        // but the template URL must ignore last-opened regardless — the
        // store's contents are irrelevant to the delegate body.
        let folderY = try makeTempFolder(named: "folder-Y-\(UUID().uuidString)")
        let lastFile = folderY.appendingPathComponent("previous.md")
        try Data("hello".utf8).write(to: lastFile)
        store.recordLastOpened(lastFile)

        let host = BrowserHostController()
        guard let templateURL = try await invokeCreateDelegate(on: host).url else {
            Issue.record("Template URL was nil")
            return
        }
        let parent = templateURL.deletingLastPathComponent().standardizedFileURL
        #expect(!parent.path.hasPrefix(folderY.standardizedFileURL.path),
                "Template parent must not equal the last-opened folder Y")
    }

    // MARK: - helpers

    private struct CreateOutcome {
        let url: URL?
        let mode: UIDocumentBrowserViewController.ImportMode
    }

    @MainActor
    private func invokeCreateDelegate(on host: BrowserHostController) async throws -> CreateOutcome {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CreateOutcome, Error>) in
            host.documentBrowser(
                host,
                didRequestDocumentCreationWithHandler: { url, mode in
                    cont.resume(returning: CreateOutcome(url: url, mode: mode))
                }
            )
        }
    }

    private func makeTempFolder(named: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(named, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
