// OpenPathHardening10_Wave2_T004Tests.swift
// Mirrored T-004 spec tests for open-path-hardening-10.
//
// Sources:
//   features/open-path-hardening-10/tests/LoadFailureMappingTests.swift
//     (the pure-mapper subset T-004 vends, excluding host-integration
//      tests that need T-005 seams)
//   features/open-path-hardening-10/tests/SizeCeilingTests.swift
//     (sizeCheckPrecedesDecodeForOversizedBinaryFiles +
//      oversizedFileIsRejectedWithoutFullRead — gate ordering)
//   features/open-path-hardening-10/tests/NonUTF8DecodePolicyTests.swift
//     (utf16BomFileSurfacesEncodingAlert +
//      mixedEncodingFileSurfacesEncodingAlertAndPresentsNoTruncatedDocument +
//      everyNonUTF8InputProducesAnAlertNotASilentReturn +
//      nonUTF8LatinFileSurfacesEncodingAlertAndPresentsNoDocument)

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

private let CEILING_BYTES: Int = 20 * 1024 * 1024

@Suite("Open path — Wave 2 T-004 (classification + failure mapper)")
struct OpenPathHardening10_Wave2_T004Tests {

    // MARK: - Failure mapper (DC-8)

    @Test("DC-8 — NSFileReadNoPermissionError maps to permission-denied alert")
    func permissionDeniedErrorMapsToPermissionAlert() {
        let err = NSError(domain: NSCocoaErrorDomain,
                          code: NSFileReadNoPermissionError,
                          userInfo: nil)
        #expect(OpenPathFailureMapper.alert(for: err) == .permissionDenied)
    }

    @Test("DC-8 — NSFileReadNoSuchFileError maps to moved-removed alert")
    func noSuchFileErrorMapsToMovedRemovedAlert() {
        let err = NSError(domain: NSCocoaErrorDomain,
                          code: NSFileReadNoSuchFileError,
                          userInfo: nil)
        #expect(OpenPathFailureMapper.alert(for: err) == .fileMovedOrRemoved)
    }

    @Test("DC-8 — unknown read error maps to generic-couldn't-read alert")
    func unknownReadErrorMapsToGenericAlert() {
        let err = NSError(domain: NSCocoaErrorDomain,
                          code: NSFileReadUnknownError,
                          userInfo: nil)
        #expect(OpenPathFailureMapper.alert(for: err) == .couldNotReadFile)
    }

    @Test("DC-8 — DocumentError.invalidEncoding maps to invalidEncoding alert")
    func decodeFailureMapsToInvalidEncodingAlert() {
        #expect(OpenPathFailureMapper.alert(for: DocumentError.invalidEncoding)
                == .invalidEncoding)
    }

    @Test("BR-3.1 — every named failure case surfaces a (non-nil) alert")
    func everyNamedFailureCaseSurfacesAnAlert() {
        let errors: [Error] = [
            NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError),
            NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError),
            NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError),
            NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES)),
            NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT)),
            NSError(domain: NSPOSIXErrorDomain, code: Int(EIO)),
            DocumentError.invalidEncoding,
        ]
        for err in errors {
            let alert = OpenPathFailureMapper.alert(for: err)
            switch alert {
            case .permissionDenied, .fileMovedOrRemoved,
                 .couldNotReadFile, .invalidEncoding, .tooLarge:
                break
            default:
                Issue.record("BR-3.1: error \(err) mapped to an unexpected ActiveAlert case \(alert).")
            }
        }
    }

    @Test("BR-3.3 — dismiss returns to pickable browser (mapper is stateless)")
    func dismissReturnsToPickableBrowser() {
        let a = OpenPathFailureMapper.alert(for:
            NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError))
        let b = OpenPathFailureMapper.alert(for:
            NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError))
        #expect(a == .permissionDenied)
        #expect(b == .couldNotReadFile)
    }

    @Test("BR-3.5 — caller-facing seam has no silent-nil outcome")
    func callerConvertsEveryFailureToAlert() {
        let err = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
        let result = OpenPathLoadPipeline.failureResult(for: err)
        switch result {
        case .document:
            Issue.record("BR-3.5: a known failure must not produce a .document result.")
        case .alert(let alert):
            #expect(alert == .fileMovedOrRemoved)
        }
    }

    @Test("BR-8 — mid-load unreadable produces moved-or-permission alert")
    func fileVanishingMidLoadProducesMovedOrPermissionAlert() {
        let enoent = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))
        #expect(OpenPathFailureMapper.alert(for: enoent) == .fileMovedOrRemoved)

        let eacces = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        #expect(OpenPathFailureMapper.alert(for: eacces) == .permissionDenied)
    }

    @Test("BR-12 — iCloudDownloadFailed is not replaced by this feature's surfaces")
    func iCloudDownloadFailedIsNotReplacedByThisFeaturesSurfaces() {
        let alert = OpenPathFailureMapper.alert(for: DocumentError.iCloudDownloadFailed)
        #expect(alert == .iCloudDownloadFailed)
    }

    @Test("BR-13 — symlink to missing target surfaces moved-removed alert")
    func symlinkToMissingTargetSurfacesMovedRemovedAlert() {
        let err = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
        #expect(OpenPathFailureMapper.alert(for: err) == .fileMovedOrRemoved)
    }

    @Test("BR-14 — directory / non-regular URL surfaces a failure alert, not a crash")
    func directoryURLSurfacesAFailureAlertNotACrash() {
        let eisdir = NSError(domain: NSPOSIXErrorDomain, code: Int(EISDIR))
        let alert = OpenPathFailureMapper.alert(for: eisdir)
        #expect(alert == .couldNotReadFile)
    }

    // MARK: - Classifier gate ordering (DC-4 / DC-5 / BR-4.2)

    @Test("DC-4 — size check precedes decode for oversized binary files")
    func sizeCheckPrecedesDecodeForOversizedBinaryFiles() throws {
        let oversizedClassification = OpenPathLoadPipeline.classify(
            byteSize: CEILING_BYTES + 1,
            bytesForDecodeProbe: Data([0xE9])
        )
        #expect(oversizedClassification == .tooLarge)
    }

    @Test("BR-4.2 — oversized file is rejected without a full read of bytes")
    func oversizedFileIsRejectedWithoutFullRead() throws {
        let classification = OpenPathLoadPipeline.classify(
            byteSize: 500 * 1024 * 1024,
            bytesForDecodeProbe: Data()
        )
        #expect(classification == .tooLarge)
    }

    // MARK: - Decode policy via classifier (DC-2)

    @Test("BR-2.1 — non-UTF-8 (Latin-1 high bytes) surfaces encoding alert; no document")
    func nonUTF8LatinFileSurfacesEncodingAlertAndPresentsNoDocument() {
        let bytes: [UInt8] = [0x48, 0x65, 0x6C, 0x6C, 0xE9]
        #expect(OpenPathLoadPipeline.classify(byteSize: bytes.count,
                                              bytesForDecodeProbe: Data(bytes))
                == .invalidEncoding)
        // Also the model layer throws.
        #expect(throws: DocumentError.invalidEncoding) {
            _ = try MarkdownDocument(file: wrapper(bytes), contentType: markdownType())
        }
    }

    @Test("BR-10 — UTF-16 BOM (LE and BE) surfaces encoding alert")
    func utf16BomFileSurfacesEncodingAlert() {
        let leBytes: [UInt8] = [0xFF, 0xFE, 0x68, 0x00, 0x69, 0x00]
        #expect(OpenPathLoadPipeline.classify(byteSize: leBytes.count,
                                              bytesForDecodeProbe: Data(leBytes))
                == .invalidEncoding)
        #expect(throws: DocumentError.invalidEncoding) {
            _ = try MarkdownDocument(file: wrapper(leBytes), contentType: markdownType())
        }

        let beBytes: [UInt8] = [0xFE, 0xFF, 0x00, 0x68, 0x00, 0x69]
        #expect(OpenPathLoadPipeline.classify(byteSize: beBytes.count,
                                              bytesForDecodeProbe: Data(beBytes))
                == .invalidEncoding)
        #expect(throws: DocumentError.invalidEncoding) {
            _ = try MarkdownDocument(file: wrapper(beBytes), contentType: markdownType())
        }
    }

    @Test("BR-11 — mixed encoding (valid prefix + invalid tail) surfaces encoding alert")
    func mixedEncodingFileSurfacesEncodingAlertAndPresentsNoTruncatedDocument() {
        var bytes: [UInt8] = Array("# Heading\n".utf8)
        bytes.append(contentsOf: [0xC3, 0x28])
        #expect(OpenPathLoadPipeline.classify(byteSize: bytes.count,
                                              bytesForDecodeProbe: Data(bytes))
                == .invalidEncoding)
        #expect(throws: DocumentError.invalidEncoding) {
            _ = try MarkdownDocument(file: wrapper(bytes), contentType: markdownType())
        }
    }

    @Test("BR-2.2 — every non-UTF-8 input class produces an alert, not a silent return")
    func everyNonUTF8InputProducesAnAlertNotASilentReturn() {
        let inputs: [[UInt8]] = [
            [0xE9],
            [0xFF, 0xFE, 0x68, 0x00],
            [0xFE, 0xFF, 0x00, 0x68],
            [0xC3, 0x28],
            [0xE2, 0x82],
            [0xF0, 0x90, 0x80],
        ]
        for bytes in inputs {
            #expect(throws: DocumentError.invalidEncoding) {
                _ = try MarkdownDocument(file: wrapper(bytes), contentType: markdownType())
            }
        }
    }
}
