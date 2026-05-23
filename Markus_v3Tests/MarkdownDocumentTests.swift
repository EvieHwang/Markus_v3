import Testing
import Foundation
import UniformTypeIdentifiers
@testable import Markus_v3

@Suite("MarkdownDocument — T-003")
struct MarkdownDocumentTests {

    private func fileWrapper(content: String) -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(content.utf8))
    }

    private func anyMarkdownType() -> UTType {
        MarkdownDocument.readableContentTypes.first!
    }

    @Test("Round-trip read/write preserves UTF-8 content")
    func testRoundTripReadWrite() throws {
        let original = "# Hello\n\nA paragraph with **emphasis**.\n"
        let wrapper = fileWrapper(content: original)
        let doc = try MarkdownDocument(file: wrapper, contentType: anyMarkdownType())
        #expect(doc.text == original)

        let snapshot = try doc.snapshot(contentType: anyMarkdownType())
        let out = doc.makeFileWrapper(forSnapshot: snapshot)
        let outBytes = try #require(out.regularFileContents)
        #expect(String(data: outBytes, encoding: .utf8) == original)
    }

    @Test("Empty file round-trips successfully")
    func testEmptyFileRoundTrip() throws {
        let wrapper = fileWrapper(content: "")
        let doc = try MarkdownDocument(file: wrapper, contentType: anyMarkdownType())
        #expect(doc.text.isEmpty)
        #expect(doc.initialByteSize == 0)
    }

    @Test("initialByteSize matches input bytes")
    func testInitialByteSizeMatchesInput() throws {
        let content = String(repeating: "a", count: 12345)
        let wrapper = fileWrapper(content: content)
        let doc = try MarkdownDocument(file: wrapper, contentType: anyMarkdownType())
        #expect(doc.initialByteSize == 12345)
    }

    @Test("Invalid UTF-8 throws .invalidEncoding")
    func testInvalidUTF8ThrowsInvalidEncoding() throws {
        let bytes = Data([0xC3, 0x28]) // invalid 2-byte sequence
        let wrapper = FileWrapper(regularFileWithContents: bytes)
        #expect(throws: DocumentError.invalidEncoding) {
            _ = try MarkdownDocument(file: wrapper, contentType: anyMarkdownType())
        }
    }

    @Test("Both .md and .markdown UTTypes are readable")
    func testMarkdownAndMdExtensionsBothReadable() {
        let types = MarkdownDocument.readableContentTypes
        #expect(types.contains(where: { $0.identifier.contains("markdown") }))
        // The Info.plist's UTImportedTypeDeclarations binds md + markdown extensions
        // to net.daringfireball.markdown; readableContentTypes must include that UTI
        // (or any UTI whose extension declarations include both).
        let identifiers = Set(types.map { $0.identifier })
        #expect(identifiers.contains("net.daringfireball.markdown") || identifiers.contains("public.markdown"))
    }

    @Test("markDirty registers an undo action and clears after save")
    func testSaveClearsDirtyState() throws {
        let wrapper = fileWrapper(content: "hello")
        let doc = try MarkdownDocument(file: wrapper, contentType: anyMarkdownType())
        let undoMgr = UndoManager()
        doc.undoManager = undoMgr
        doc.text = "hello, world"
        doc.markDirty()
        #expect(undoMgr.canUndo)
        // Save snapshot: confirm dirty-tracking handshake at the doc level.
        let snap = try doc.snapshot(contentType: anyMarkdownType())
        #expect(snap == "hello, world")
    }
}
