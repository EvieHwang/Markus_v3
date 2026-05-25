// LocalDocumentsFallbackTests.swift
// Wave-1 unit tests for resume-and-create-2 / C7 LocalDocumentsFallback (BR-11
// / DC-12 fallback half). Mirrors the LocalDocumentsFallbackTests suite in
// features/resume-and-create-2/tests/unit/ResumeAndCreateTests.swift.

import Testing
import Foundation
@testable import Markus_v3

@Suite("LocalDocumentsFallback — guaranteed-writable target")
struct LocalDocumentsFallbackTests {

    @Test("Fallback vends the app's local Documents directory")
    func vendsDocumentsDirectory() throws {
        let url = try LocalDocumentsFallback.documentsDirectory()
        let expected = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        #expect(url.standardizedFileURL == expected.standardizedFileURL)
    }

    @Test("Fallback directory exists and is writable")
    func directoryExistsAndWritable() throws {
        let url = try LocalDocumentsFallback.documentsDirectory()
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir))
        #expect(isDir.boolValue)
        #expect(FileManager.default.isWritableFile(atPath: url.path))
    }
}
