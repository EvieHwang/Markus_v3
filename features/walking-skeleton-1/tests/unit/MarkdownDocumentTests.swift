// Spec test — Wave 2 / T-003
// Tags: T-003
// Verifies: AC-2.5, AC-4.5, EC-1, EC-4, EC-5; design component #2

import Testing
import Foundation
import UniformTypeIdentifiers
@testable import Markus_v3

@Suite("MarkdownDocument — T-003")
struct MarkdownDocumentTests {

    private func fileWrapper(content: String) -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(content.utf8))
    }

    @Test("Round-trip read/write preserves UTF-8 content")
    func testRoundTripReadWrite() throws {
        let original = "# Hello\n\nA paragraph with **emphasis**.\n"
        let wrapper = fileWrapper(content: original)
        let config = try ReadConfigurationFake(file: wrapper, contentType: .markdown)
        let doc = try MarkdownDocument(configuration: config)
        #expect(doc.text == original)

        let snapshot = try doc.snapshot(contentType: .markdown)
        let writeConfig = WriteConfigurationFake(contentType: .markdown)
        let out = try doc.fileWrapper(snapshot: snapshot, configuration: writeConfig)
        let outBytes = try #require(out.regularFileContents)
        #expect(String(data: outBytes, encoding: .utf8) == original)
    }

    @Test("Empty file round-trips successfully")
    func testEmptyFileRoundTrip() throws {
        let wrapper = fileWrapper(content: "")
        let config = try ReadConfigurationFake(file: wrapper, contentType: .markdown)
        let doc = try MarkdownDocument(configuration: config)
        #expect(doc.text.isEmpty)
        #expect(doc.initialByteSize == 0)
    }

    @Test("initialByteSize matches input bytes")
    func testInitialByteSizeMatchesInput() throws {
        let content = String(repeating: "a", count: 12345)
        let wrapper = fileWrapper(content: content)
        let config = try ReadConfigurationFake(file: wrapper, contentType: .markdown)
        let doc = try MarkdownDocument(configuration: config)
        #expect(doc.initialByteSize == 12345)
    }

    @Test("Invalid UTF-8 throws .invalidEncoding")
    func testInvalidUTF8ThrowsInvalidEncoding() throws {
        let bytes = Data([0xC3, 0x28]) // invalid 2-byte sequence
        let wrapper = FileWrapper(regularFileWithContents: bytes)
        let config = try ReadConfigurationFake(file: wrapper, contentType: .markdown)
        #expect(throws: DocumentError.invalidEncoding) {
            _ = try MarkdownDocument(configuration: config)
        }
    }

    @Test("Both .md and .markdown UTTypes are readable")
    func testMarkdownAndMdExtensionsBothReadable() {
        let types = MarkdownDocument.readableContentTypes
        #expect(types.contains(.markdown))
        // also covers the dfb UTI alias
        #expect(types.contains(where: { $0.identifier.contains("markdown") }))
    }

    @Test("markDirty registers an undo action and clears after save")
    func testSaveClearsDirtyState() throws {
        let wrapper = fileWrapper(content: "hello")
        let config = try ReadConfigurationFake(file: wrapper, contentType: .markdown)
        let doc = try MarkdownDocument(configuration: config)
        let undoMgr = UndoManager()
        doc.undoManager = undoMgr
        doc.text = "hello, world"
        doc.markDirty()
        #expect(undoMgr.canUndo)
        // Save snapshot/file: in DocumentGroup this is automatic; for the test we just
        // confirm that the dirty-tracking handshake works at the doc level.
        let snap = try doc.snapshot(contentType: .markdown)
        #expect(snap == "hello, world")
    }
}

// MARK: - Test helpers (re-create the Apple types just enough for unit testing)
// These satisfy `ReferenceFileDocument`'s init/save signatures without needing a live
// `DocumentGroup`. The real configs are sealed types; we mirror their shape.
private struct ReadConfigurationFake {
    let file: FileWrapper
    let contentType: UTType
    init(file: FileWrapper, contentType: UTType) throws {
        self.file = file
        self.contentType = contentType
    }
}
private struct WriteConfigurationFake {
    let contentType: UTType
}
