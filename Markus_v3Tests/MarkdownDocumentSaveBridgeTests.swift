import Testing
import Foundation
@testable import Markus_v3

@Suite("MarkdownDocumentSaveBridge — coordinated write")
struct MarkdownDocumentSaveBridgeTests {

    @MainActor
    @Test("saveSynchronously advances the file's modification date")
    func saveAdvancesModificationDate() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SaveBridgeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("doc.md")
        try Data("# original\n".utf8).write(to: url)
        let initialAttrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let initialMDate = try #require(initialAttrs[.modificationDate] as? Date)

        // APFS has sub-second resolution, but force a small gap so a stale
        // metadata read (no real update happened) is unambiguously detectable.
        Thread.sleep(forTimeInterval: 0.05)

        let doc = MarkdownDocument()
        doc.text = "# updated content\n"
        let bridge = MarkdownDocumentSaveBridge(document: doc, url: url)
        bridge.saveSynchronously()

        let afterAttrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let afterMDate = try #require(afterAttrs[.modificationDate] as? Date)
        #expect(afterMDate > initialMDate,
                "Coordinated write must update the file's modification date")

        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(written == "# updated content\n")
    }

    @MainActor
    @Test("Successful coordinated write invokes onDidWrite with the new text")
    func successInvokesOnDidWrite() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SaveBridgeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("doc.md")
        try Data("seed".utf8).write(to: url)

        let doc = MarkdownDocument()
        doc.text = "after"
        let bridge = MarkdownDocumentSaveBridge(document: doc, url: url)

        var written: String?
        bridge.onDidWrite = { written = $0 }
        bridge.saveSynchronously()

        #expect(written == "after")
    }

    @MainActor
    @Test("First-persist callback fires when writing creates the file")
    func firstPersistFiresOnCreation() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SaveBridgeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("new.md")
        let doc = MarkdownDocument()
        doc.text = "fresh content"
        let bridge = MarkdownDocumentSaveBridge(document: doc, url: url)

        var firstPersistURL: URL?
        bridge.onFirstPersist = { firstPersistURL = $0 }
        bridge.saveSynchronously()

        #expect(firstPersistURL == url)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}
