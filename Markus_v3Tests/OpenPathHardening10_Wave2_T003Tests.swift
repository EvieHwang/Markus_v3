// OpenPathHardening10_Wave2_T003Tests.swift
// Mirrored T-003 spec tests for open-path-hardening-10.
//
// Sources:
//   features/open-path-hardening-10/tests/HappyPathOpenTests.swift
//     (the subset that hits MarkdownDocument's load path —
//      well-formed open, BOM retention, BOM render suppression,
//      no-edit save round-trip, empty file, latency budget)
//   features/open-path-hardening-10/tests/NonUTF8DecodePolicyTests.swift
//     (`noPresentedBufferContainsReplacementCharacter` — the negative
//      complement DC-2 pins: no U+FFFD substitution from this load.)

import Testing
import Foundation
import UniformTypeIdentifiers
@testable import Markus_v3

private func markdownType() -> UTType {
    MarkdownDocument.readableContentTypes.first!
}

private let BOM: [UInt8] = [0xEF, 0xBB, 0xBF]

@Suite("Open path — Wave 2 T-003 (MarkdownDocument decode + BOM)")
struct OpenPathHardening10_Wave2_T003Tests {

    @Test("BR-1.2 — buffer matches on-disk bytes after normalization")
    func bufferMatchesOnDiskAfterNormalization() throws {
        let content = "line one\nline two\nline three\n"
        let bytes = Data(content.utf8)
        let wrapper = FileWrapper(regularFileWithContents: bytes)
        let doc = try MarkdownDocument(file: wrapper, contentType: markdownType())
        #expect(doc.text == content)
        #expect(doc.initialByteSize == bytes.count)
    }

    @Test("BR-1.3 / BR-9 — BOM-prefixed UTF-8 opens and retains BOM bytes in buffer")
    func bomPrefixedFileOpensAndRetainsBomBytes() throws {
        var bytes = Data(BOM)
        bytes.append(Data("# heading\n".utf8))
        let wrapper = FileWrapper(regularFileWithContents: bytes)
        let doc = try MarkdownDocument(file: wrapper, contentType: markdownType())

        let firstScalar = try #require(doc.text.unicodeScalars.first)
        #expect(firstScalar == "\u{FEFF}",
                "DC-3: load must retain the leading BOM in the in-memory buffer.")
    }

    @Test("DC-3 — BOM is not rendered as a visible character")
    func bomIsNotRenderedAsVisibleCharacter() throws {
        var bytes = Data(BOM)
        bytes.append(Data("hello".utf8))
        let wrapper = FileWrapper(regularFileWithContents: bytes)
        let doc = try MarkdownDocument(file: wrapper, contentType: markdownType())

        #expect(doc.text.unicodeScalars.first == "\u{FEFF}")

        // displayText is the renderer-facing form: leading BOM dropped.
        #expect(doc.displayText.hasPrefix("hello"),
                "DC-3: the renderer-facing form must not begin with U+FEFF.")
    }

    @Test("DC-3 — no-edit save of a BOM-prefixed file is byte-identical")
    func noEditSaveOfBomFileIsByteIdentical() throws {
        var bytes = Data(BOM)
        bytes.append(Data("# heading\n\nbody\n".utf8))
        let wrapper = FileWrapper(regularFileWithContents: bytes)
        let doc = try MarkdownDocument(file: wrapper, contentType: markdownType())

        let snap = try doc.snapshot(contentType: markdownType())
        let outWrapper = doc.makeFileWrapper(forSnapshot: snap)
        let outBytes = try #require(outWrapper.regularFileContents)

        #expect(outBytes == bytes,
                "DC-3: a no-edit save must round-trip the original on-disk bytes, including the leading BOM.")
    }

    @Test("BR-6 — empty file opens with an empty buffer and no alert")
    func emptyFileOpensWithEmptyBuffer() throws {
        let wrapper = FileWrapper(regularFileWithContents: Data())
        let doc = try MarkdownDocument(file: wrapper, contentType: markdownType())
        #expect(doc.text.isEmpty)
        #expect(doc.initialByteSize == 0)
    }

    @Test("BR-1.4 — happy-path latency is within human-perception budget")
    func happyPathLatencyIsWithinBudget() throws {
        let content = String(repeating: "lorem ipsum dolor sit amet.\n", count: 4096)
        let bytes = Data(content.utf8)
        let wrapper = FileWrapper(regularFileWithContents: bytes)

        let start = Date()
        let doc = try MarkdownDocument(file: wrapper, contentType: markdownType())
        let elapsed = Date().timeIntervalSince(start)

        #expect(doc.text == content)
        #expect(elapsed < 0.1,
                "BR-1.4: happy-path open of a 100 KiB file must be sub-100ms.")
    }

    @Test("DC-2 — no presented buffer contains the U+FFFD replacement character")
    func noPresentedBufferContainsReplacementCharacter() throws {
        let content = "café — naïve — 🌍 — \u{1F600}"
        let doc = try MarkdownDocument(
            file: FileWrapper(regularFileWithContents: Data(content.utf8)),
            contentType: markdownType()
        )
        #expect(doc.text == content)
        #expect(!doc.text.unicodeScalars.contains("\u{FFFD}"),
                "DC-2: the open path must not perform a lossy decode under any configuration.")
    }
}
