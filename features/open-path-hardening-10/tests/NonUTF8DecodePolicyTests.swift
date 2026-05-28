// NonUTF8DecodePolicyTests.swift
// Spec tests for open-path-hardening-10 (BR-2, BR-10, BR-11; DC-2)
//
// Decode policy is (b): non-UTF-8 bytes → encoding-error surface, no document
// presented, no lossy buffer with U+FFFD substitutions. (DC-2 pins this; the
// existing DocumentError.invalidEncoding / ActiveAlert.invalidEncoding path
// is reused — BR-2.5.)

import Testing
import Foundation
import UniformTypeIdentifiers
@testable import Markus_v3

private func markdownType() -> UTType {
    MarkdownDocument.readableContentTypes.first!
}

private func wrapper(_ bytes: [UInt8]) -> FileWrapper {
    FileWrapper(regularFileWithContents: Data(bytes))
}

@Suite("Open path — non-UTF-8 decode policy (BR-2, BR-10, BR-11; DC-2)")
struct NonUTF8DecodePolicyTests {

    // BR-2.1 / DC-2 — A Latin-1 file with high bytes is not valid UTF-8;
    // the open path produces the encoding-error surface (DocumentError
    // .invalidEncoding) and no MarkdownDocument is constructed.
    @Test("BR-2.1 — non-UTF-8 (Latin-1 high bytes) surfaces encoding alert; no document")
    func nonUTF8LatinFileSurfacesEncodingAlertAndPresentsNoDocument() {
        // 0xE9 is "é" in Latin-1; alone it is an invalid UTF-8 leading byte.
        let bytes: [UInt8] = [0x48, 0x65, 0x6C, 0x6C, 0xE9] // "Hell" + 0xE9
        #expect(throws: DocumentError.invalidEncoding) {
            _ = try MarkdownDocument(file: wrapper(bytes), contentType: markdownType())
        }
    }

    // BR-10 — A UTF-16 file (FF FE or FE FF BOM + UTF-16-encoded text) is
    // non-UTF-8 under strict decode and triggers BR-2. The decode throws
    // .invalidEncoding regardless of which UTF-16 BOM is present.
    @Test("BR-10 — UTF-16 BOM (LE and BE) surfaces encoding alert")
    func utf16BomFileSurfacesEncodingAlert() {
        // UTF-16 LE BOM + "h\0i\0" — the lone 0x00 bytes inside the
        // intended-as-UTF-8 stream are valid per byte but the overall
        // stream is not what UTF-8 says it is; in particular FF FE is
        // not a valid UTF-8 lead byte sequence.
        let leBytes: [UInt8] = [0xFF, 0xFE, 0x68, 0x00, 0x69, 0x00]
        #expect(throws: DocumentError.invalidEncoding) {
            _ = try MarkdownDocument(file: wrapper(leBytes), contentType: markdownType())
        }
        // UTF-16 BE BOM
        let beBytes: [UInt8] = [0xFE, 0xFF, 0x00, 0x68, 0x00, 0x69]
        #expect(throws: DocumentError.invalidEncoding) {
            _ = try MarkdownDocument(file: wrapper(beBytes), contentType: markdownType())
        }
    }

    // BR-11 — A file whose first N bytes decode as UTF-8 but whose later
    // bytes do not is non-UTF-8 and triggers BR-2. The open path does NOT
    // present a truncated document built from only the valid prefix.
    @Test("BR-11 — mixed encoding (valid prefix + invalid tail) surfaces encoding alert, no truncated document")
    func mixedEncodingFileSurfacesEncodingAlertAndPresentsNoTruncatedDocument() {
        // Valid UTF-8 prefix "# Heading\n", then a stray 0xC3 0x28 (invalid).
        var bytes: [UInt8] = Array("# Heading\n".utf8)
        bytes.append(contentsOf: [0xC3, 0x28])
        #expect(throws: DocumentError.invalidEncoding) {
            _ = try MarkdownDocument(file: wrapper(bytes), contentType: markdownType())
        }
        // No MarkdownDocument was constructed — by virtue of the throw, the
        // truncated-prefix document cannot have been built.
    }

    // BR-2.2 — under no input does a non-UTF-8 file produce a silent no-op:
    // either the encoding alert fires or (policy (a), not chosen here) a
    // labeled document is shown. With policy (b), the contract is "throws
    // DocumentError.invalidEncoding for every non-UTF-8 input class."
    @Test("BR-2.2 — every non-UTF-8 input class produces an alert, not a silent return")
    func everyNonUTF8InputProducesAnAlertNotASilentReturn() {
        let inputs: [[UInt8]] = [
            [0xE9],                            // lone Latin-1 high byte
            [0xFF, 0xFE, 0x68, 0x00],          // UTF-16 LE
            [0xFE, 0xFF, 0x00, 0x68],          // UTF-16 BE
            [0xC3, 0x28],                      // invalid 2-byte sequence
            [0xE2, 0x82],                      // truncated 3-byte sequence
            [0xF0, 0x90, 0x80],                // truncated 4-byte sequence
        ]
        for bytes in inputs {
            #expect(throws: DocumentError.invalidEncoding) {
                _ = try MarkdownDocument(file: wrapper(bytes), contentType: markdownType())
            }
        }
    }

    // DC-2 — Markus does not present a lossy buffer. For every non-UTF-8
    // input that throws, no MarkdownDocument exists to *contain* a U+FFFD;
    // the negative is asserted by the throw above. We additionally assert
    // the positive complement: no well-formed input produces a buffer
    // containing U+FFFD from this load path.
    @Test("DC-2 — no presented buffer contains the U+FFFD replacement character")
    func noPresentedBufferContainsReplacementCharacter() throws {
        // Well-formed UTF-8 with high-plane characters (emoji, accents) —
        // these MUST round-trip cleanly with no substitutions.
        let content = "café — naïve — 🌍 — \u{1F600}"
        let doc = try MarkdownDocument(
            file: FileWrapper(regularFileWithContents: Data(content.utf8)),
            contentType: markdownType()
        )
        #expect(doc.text == content)
        #expect(!doc.text.unicodeScalars.contains("\u{FFFD}"),
                "DC-2: the open path must not perform a lossy decode under any "
              + "configuration; U+FFFD must never appear from this load.")
    }

    // BR-2.4 — the encoding alert is dismissable and after dismissal the
    // user is in a pickable browser state (no stuck modal, no zombie
    // scope-access). This is a host-level property; the model-level
    // contract under test here is that the throw is recoverable — the same
    // model can be tried again on a different file in the same process.
    @Test("BR-2.4 — encoding alert is dismissable; returns to pickable browser")
    func encodingAlertIsDismissableAndReturnsToPickableBrowser() throws {
        // Failure on file A...
        #expect(throws: DocumentError.invalidEncoding) {
            _ = try MarkdownDocument(
                file: wrapper([0xE9, 0xE9]),
                contentType: markdownType()
            )
        }
        // ...followed by a successful open of file B in the same session.
        let okBytes = Data("# ok\n".utf8)
        let okDoc = try MarkdownDocument(
            file: FileWrapper(regularFileWithContents: okBytes),
            contentType: markdownType()
        )
        #expect(okDoc.text == "# ok\n",
                "BR-2.4: a failed decode must leave the open path in a state "
              + "that allows the next pick to succeed (no stuck state).")
    }
}
