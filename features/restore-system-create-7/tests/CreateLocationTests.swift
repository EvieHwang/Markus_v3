// CreateLocationTests.swift
// Spec tests for restore-system-create-7 — verifies the create-location
// behavior contract (AC-1.*, DC-1, DC-2).
//
// These are reference / human-readable specs per constitution.md. They are
// not bundled into the Xcode test target as-is; a build implementer mirrors
// them into Markus_v3Tests/ (Swift Testing) and Markus_v3UITests/ when
// implementing the matching DAG tasks.
//
// Framework: Swift Testing (@Test, #expect, #require). The create-delegate
// behavior is *observable* (the new file appears in the browser's current
// folder, not in any app-resolved directory). We verify the delegate's
// template-handoff contract through its public side effects, not its
// implementation details.

import Testing
import Foundation
@testable import Markus_v3

@Suite("Create location — DC-1 template-only handoff")
struct CreateLocationTests {

    // MARK: - AC-1.1 / AC-1.3 / DC-1

    @Test("Create-delegate template URL points at a temp-dir .md, not an app-chosen target directory")
    func templateLandsInTempDir() async throws {
        // GIVEN BrowserHostController is acting as the
        // UIDocumentBrowserViewControllerDelegate.
        let host = BrowserHostController()

        // WHEN the system asks for a creation template, the delegate body
        // must complete the handler with a URL that lives under
        // NSTemporaryDirectory() — not under any Markus-resolved folder
        // (no last-opened dir, no app Documents fallback).
        let templateURL: URL = try await withCheckedThrowingContinuation { cont in
            host.documentBrowser(
                UIDocumentBrowserViewController(forOpening: nil),
                didRequestDocumentCreationWithHandler: { url, _ in
                    if let url { cont.resume(returning: url) }
                    else { cont.resume(throwing: TestError.nilTemplateURL) }
                }
            )
        }

        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory()).standardizedFileURL
        let templateParent = templateURL.deletingLastPathComponent().standardizedFileURL
        #expect(templateParent.path.hasPrefix(tempRoot.path),
                "Template URL must live in NSTemporaryDirectory(); got \(templateURL.path)")
        #expect(["md", "markdown"].contains(templateURL.pathExtension.lowercased()))
    }

    @Test("Template file is created and is empty (zero bytes) before handoff")
    func templateIsEmptyOnDisk() async throws {
        let host = BrowserHostController()
        let url: URL = try await withCheckedThrowingContinuation { cont in
            host.documentBrowser(
                UIDocumentBrowserViewController(forOpening: nil),
                didRequestDocumentCreationWithHandler: { url, _ in
                    if let url { cont.resume(returning: url) }
                    else { cont.resume(throwing: TestError.nilTemplateURL) }
                }
            )
        }
        #expect(FileManager.default.fileExists(atPath: url.path))
        let data = try Data(contentsOf: url)
        #expect(data.isEmpty, "Template content must be empty; got \(data.count) bytes")
    }

    @Test("Create-delegate completes with a success import mode, not .none")
    func templateCompletesWithSuccessMode() async throws {
        let host = BrowserHostController()
        let mode: UIDocumentBrowserViewController.ImportMode =
            try await withCheckedThrowingContinuation { cont in
                host.documentBrowser(
                    UIDocumentBrowserViewController(forOpening: nil),
                    didRequestDocumentCreationWithHandler: { _, mode in
                        cont.resume(returning: mode)
                    }
                )
            }
        // .copy or .move both satisfy DC-1's "success mode"; .none would mean
        // the framework rejects the create.
        #expect(mode == .copy || mode == .move,
                "Delegate must complete with a success import mode; got \(mode)")
    }

    // MARK: - AC-1.2 / DC-1 — last-opened directory is NOT used

    @Test("Template URL is independent of the last-opened file's folder")
    func templateURLIgnoresLastOpenedDirectory() async throws {
        // Pre-seed a last-opened bookmark pointing into folder Y.
        let folderY = try makeTempFolder(named: "folder-Y-\(UUID().uuidString)")
        let lastFile = folderY.appendingPathComponent("previous.md")
        try Data("hello".utf8).write(to: lastFile)
        LastFileStore.shared.record(url: lastFile)
        defer { LastFileStore.shared.clear() }

        let host = BrowserHostController()
        let templateURL: URL = try await withCheckedThrowingContinuation { cont in
            host.documentBrowser(
                UIDocumentBrowserViewController(forOpening: nil),
                didRequestDocumentCreationWithHandler: { url, _ in
                    if let url { cont.resume(returning: url) }
                    else { cont.resume(throwing: TestError.nilTemplateURL) }
                }
            )
        }
        let parent = templateURL.deletingLastPathComponent().standardizedFileURL
        #expect(!parent.path.hasPrefix(folderY.standardizedFileURL.path),
                "Template parent must not equal the last-opened folder Y")
    }

    // MARK: - helpers

    enum TestError: Error { case nilTemplateURL }

    private func makeTempFolder(named: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(named, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
