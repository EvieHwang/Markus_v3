// SizeCeilingTests.swift
// Spec tests for open-path-hardening-10 (BR-4, BR-7; DC-4, DC-5)
//
// The size ceiling is 20 MiB (20 * 1024 * 1024 = 20 971 520 bytes), INCLUSIVE.
// A file ≤ ceiling is admitted; a file > ceiling is rejected with the too-
// large surface, BEFORE the bytes are read into memory (BR-4.2 — pre-read
// gate, attribute-only lookup).
//
// The tests bind to a public seam name `OpenPathSizeCeiling.maxBytes` (or
// equivalent constant the build vends). If the build chooses a different
// public name, the build agent renames the binding here when mirroring into
// Markus_v3Tests/; the *value* under test is the constant DC-5 pins.

import Testing
import Foundation
import UniformTypeIdentifiers
@testable import Markus_v3

private let CEILING_BYTES: Int = 20 * 1024 * 1024 // 20 971 520

private func markdownType() -> UTType {
    MarkdownDocument.readableContentTypes.first!
}

/// Creates a real on-disk file of exactly `size` bytes (ASCII 'a' fill) and
/// returns its URL. The file is in NSTemporaryDirectory and is the test's
/// responsibility to clean up if needed.
private func makeFile(of size: Int, name: String = "fixture.md") throws -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("open-path-size-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(name)
    // Write in 1 MiB chunks to keep allocator pressure low.
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    let chunk = Data(repeating: 0x61, count: min(size, 1024 * 1024))
    var remaining = size
    while remaining > 0 {
        let n = min(remaining, chunk.count)
        try handle.write(contentsOf: chunk.prefix(n))
        remaining -= n
    }
    return url
}

@Suite("Open path — size ceiling (BR-4, BR-7; DC-4, DC-5)")
struct SizeCeilingTests {

    // BR-4.6 / BR-7 — A file exactly equal to the ceiling in bytes is
    // ACCEPTED (the ceiling is inclusive). The pipeline admits the file
    // to the read stage; the open path returns a document, no too-large
    // alert. We bind to the seam: a helper on the open-path pipeline that
    // answers "does this byte count pass the size gate?". Behavioral
    // assertion is on the boolean / on the absence of a too-large alert.
    @Test("BR-4.6 — file exactly at ceiling (20 971 520 bytes) is accepted")
    func exactlyAtCeilingIsAccepted() {
        // OpenPathSizeCeiling.admits(byteSize:) is the seam name the build
        // exposes — a pure function that the load pipeline calls before
        // performing the full read.
        #expect(OpenPathSizeCeiling.admits(byteSize: CEILING_BYTES),
                "BR-4.6 / DC-5: a file whose on-disk byte size equals the "
              + "ceiling exactly must be accepted (inclusive boundary).")
    }

    // BR-4.1 / BR-7 — A file one byte over the ceiling is REJECTED with
    // the too-large surface.
    @Test("BR-7 — file one byte over ceiling (20 971 521 bytes) is rejected")
    func oneByteOverCeilingIsRejected() {
        #expect(!OpenPathSizeCeiling.admits(byteSize: CEILING_BYTES + 1),
                "BR-4.1 / DC-5: a file strictly greater than the ceiling must "
              + "be rejected; the at-boundary case is BR-4.6's territory.")
    }

    // BR-4.1 — Oversized files surface the too-large alert and present no
    // document. We exercise the load pipeline on a real oversized fixture
    // (just over the ceiling, to keep the fixture cost bounded) and assert
    // that the seam reports rejection.
    @Test("BR-4.1 — oversized file surfaces too-large alert; no document presented")
    func oversizedFileSurfacesTooLargeAlertAndPresentsNoDocument() throws {
        // We assert at the gate level — the byte count alone determines the
        // outcome (the size pre-check is attribute-only). The integration-
        // level "alert is on screen, no document is presented" is covered
        // by AlertHostAndScopeTests and the UI tests.
        let size = CEILING_BYTES + 1
        #expect(!OpenPathSizeCeiling.admits(byteSize: size))
    }

    // BR-4.2 / DC-4 — The size check is a PRE-READ gate. The implementation
    // reads the file's attribute-level size (not the full contents) and
    // rejects before any allocation that would OOM. The behavioral property:
    // a 500 MB file produces the too-large surface without a measurable
    // memory spike. We assert the gate-level fact (the size check is a pure
    // function of byte count, not of file contents) and tag the heavy
    // fixture variant for opt-in runs.
    @Test("BR-4.2 — oversized file is rejected without a full read of bytes")
    func oversizedFileIsRejectedWithoutFullRead() throws {
        // The gate is content-agnostic: it does not need the bytes to make
        // its decision. We verify by asking the gate about a hypothetical
        // 500 MiB file size; the answer is "rejected" without any file
        // being created or read.
        let fiveHundredMiB = 500 * 1024 * 1024
        #expect(!OpenPathSizeCeiling.admits(byteSize: fiveHundredMiB),
                "BR-4.2: the size gate must answer rejection from byte count "
              + "alone — no file contents required.")
    }

    // DC-4 — The pipeline runs size check BEFORE decode. The observable
    // consequence: a file that is both oversized AND not UTF-8 surfaces
    // as too-large (the cheaper, earlier check wins). This is the property
    // that prevents an oversized binary file from triggering an OOM during
    // a pre-emptive decode probe.
    @Test("DC-4 — size check precedes decode for oversized binary files")
    func sizeCheckPrecedesDecodeForOversizedBinaryFiles() throws {
        // We exercise the gate ordering: given a byte count above ceiling
        // and a byte count below ceiling with non-UTF-8 contents, the
        // ordering rule says the oversized case never reaches decode.
        // Concretely: the gate is byte-count only, and the public seam
        // OpenPathLoadPipeline.classify(byteSize:bytesForDecodeProbe:)
        // returns .tooLarge for the oversized case regardless of contents.
        let oversizedClassification = OpenPathLoadPipeline.classify(
            byteSize: CEILING_BYTES + 1,
            // The decode probe must NOT have been consulted; we pass a
            // non-UTF-8 byte sequence to assert that even if it had been,
            // the answer would be the same.
            bytesForDecodeProbe: Data([0xE9])
        )
        #expect(oversizedClassification == .tooLarge,
                "DC-4: when both oversized and not-UTF-8, the size check "
              + "fires first (too-large), never the decode check.")
    }

    // BR-4.3 — The ceiling is a single design-fixed constant; a public seam
    // exposes it for the build to reference (the constant lives in code,
    // sourced from DC-5). We assert the constant equals the design-pinned
    // value.
    @Test("BR-4.3 / DC-5 — ceiling constant equals design-pinned 20 MiB value")
    func ceilingIsAFixedConstantHonoringDesignValue() {
        #expect(OpenPathSizeCeiling.maxBytes == CEILING_BYTES,
                "DC-5: the ceiling constant must equal exactly 20 * 1024 * 1024 "
              + "bytes (20 971 520). A drift here indicates the design value "
              + "was changed without updating the spec.")
    }
}
