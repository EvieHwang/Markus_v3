// ResumeDetectorHardening11_T001Tests.swift
// Mirrored T-001 spec tests for resume-and-detector-hardening-11.
//
// Source:
//   features/resume-and-detector-hardening-11/tests/unit/LastFileStoreBookmarkFallbackTests.swift
//
// Covers C1 — LastFileStore.resolveLastOpened() bookmark-fallback branch
// (DC-1/DC-2/DC-3/DC-4/DC-5/DC-6 → BR-1, BR-2, BR-3, BR-4, BR-5, BR-6, BR-7,
// BR-14, BR-15, BR-16). The source spec test file is the human-readable
// authority; this file is the Xcode-target-executable mirror.

import Testing
import Foundation
@testable import Markus_v3

@Suite("LastFileStore — bookmark-fallback resolve (T-001)")
struct ResumeDetectorHardening11_T001Tests {

    private func makeTempDir(_ tag: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LFSBookmarkFallback-\(tag)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ dir: URL, _ name: String, _ content: String = "hello") throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data(content.utf8).write(to: url)
        return url
    }

    private func remove(_ dir: URL) { try? FileManager.default.removeItem(at: dir) }

    private func freshStore(_ tag: String) -> (LastFileStore, UserDefaults, String) {
        let suiteName = "LFSBookmarkFallback.\(tag).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = LastFileStore(
            defaults: defaults,
            bookmarkKey: "bookmark",
            pathKey: "path"
        )
        return (store, defaults, suiteName)
    }

    // BR-3 / DC-2 — no regression in same-path case.
    @Test("Same-path resume returns the URL (no regression)")
    func samePathResumeReturnsURL() throws {
        let dir = try makeTempDir("samepath")
        defer { remove(dir) }
        let file = try write(dir, "note.md")
        let (store, _, _) = freshStore("samepath")
        store.recordLastOpened(file)

        let url = store.resolveLastOpened()
        #expect(url?.lastPathComponent == "note.md")
    }

    // BR-1 / BR-2 / DC-1 / DC-3 — move file in place; bookmark fallback returns the new URL.
    @Test("Moved file resolves via bookmark fallback to new URL")
    func movedFileResolvesViaBookmark() throws {
        let dir = try makeTempDir("moved")
        defer { remove(dir) }
        let original = try write(dir, "note.md", "original content")
        let (store, _, _) = freshStore("moved")
        store.recordLastOpened(original)

        let renamed = dir.appendingPathComponent("renamed.md")
        try FileManager.default.moveItem(at: original, to: renamed)

        let url = try #require(store.resolveLastOpened())
        #expect(url.lastPathComponent == "renamed.md")
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    // BR-4 / DC-3 — bookmark resolves but URL is also gone → nil.
    @Test("Deleted file returns nil (bookmark resolves but unreachable)")
    func deletedFileReturnsNil() throws {
        let dir = try makeTempDir("deleted")
        defer { remove(dir) }
        let file = try write(dir, "note.md")
        let (store, _, _) = freshStore("deleted")
        store.recordLastOpened(file)

        try FileManager.default.removeItem(at: file)

        #expect(store.resolveLastOpened() == nil)
    }

    // BR-5 / DC-6 — RETAIN-on-failure across the fallback branch too.
    @Test("hasRecord remains true after a failed bookmark-fallback resolve")
    func retainOnFailureAcrossFallback() throws {
        let dir = try makeTempDir("retain")
        defer { remove(dir) }
        let file = try write(dir, "note.md")
        let (store, _, _) = freshStore("retain")
        store.recordLastOpened(file)

        try FileManager.default.removeItem(at: file)
        _ = store.resolveLastOpened()

        #expect(store.hasRecord == true)
    }

    // BR-4 + recovery — after a failed resolve, restoring the file lets a later resolve succeed.
    @Test("After failed resolve, restoring file lets a later resolve succeed")
    func recoveryAfterFailedResolve() throws {
        let dir = try makeTempDir("recover")
        defer { remove(dir) }
        let file = try write(dir, "note.md")
        let (store, _, _) = freshStore("recover")
        store.recordLastOpened(file)

        // First, fail.
        try FileManager.default.removeItem(at: file)
        #expect(store.resolveLastOpened() == nil)

        // Then restore at the same path; resolve again (steady-state branch is enough).
        _ = try write(dir, "note.md")
        let url = store.resolveLastOpened()
        #expect(url?.lastPathComponent == "note.md")
    }

    // BR-6 / DC-4 — recorded path string is not rewritten on a fallback resolve.
    @Test("Recorded path is unchanged after a bookmark-fallback resolve")
    func recordedPathUnchangedAfterFallback() throws {
        let dir = try makeTempDir("nopathwrite")
        defer { remove(dir) }
        let original = try write(dir, "note.md")
        let (store, defaults, _) = freshStore("nopathwrite")
        store.recordLastOpened(original)
        let recordedBefore = defaults.string(forKey: "path")

        let renamed = dir.appendingPathComponent("renamed.md")
        try FileManager.default.moveItem(at: original, to: renamed)
        _ = store.resolveLastOpened()

        let recordedAfter = defaults.string(forKey: "path")
        #expect(recordedBefore == recordedAfter)
        #expect(recordedAfter?.hasSuffix("note.md") == true)
    }

    // BR-16 / DC-3 — corrupt bookmark + existing recorded path → nil.
    @Test("Corrupt bookmark returns nil even if recorded path exists")
    func corruptBookmarkReturnsNil() throws {
        let (store, defaults, _) = freshStore("corrupt")
        defaults.set(Data([0xFF, 0xFE]), forKey: "bookmark")
        defaults.set("/tmp/does-not-need-to-exist.md", forKey: "path")

        #expect(store.resolveLastOpened() == nil)
        #expect(store.hasRecord == true)  // BR-5 still holds for corrupt-bookmark too
    }
}
