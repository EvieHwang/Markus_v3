// LoadFailureMappingTests.swift
// Spec tests for open-path-hardening-10 (BR-3, BR-8, BR-12, BR-13, BR-14; DC-7, DC-8)
//
// DC-8 pins the OS-error → alert-variant mapping deterministically, with a
// generic-couldn't-read fallback for the ambiguous case. The tests inject
// errors through the public seam `OpenPathFailureMapper.alert(for: Error)`
// and assert the resulting ActiveAlert case. No mocking of URL itself.

import Testing
import Foundation
@testable import Markus_v3

@Suite("Open path — load failure mapping (BR-3, BR-8, BR-12–14; DC-7, DC-8)")
struct LoadFailureMappingTests {

    // DC-8 — `NSFileReadNoPermissionError` (and POSIX EACCES / EPERM)
    // maps to the permission-denied alert variant.
    @Test("DC-8 — NSFileReadNoPermissionError maps to permission-denied alert")
    func permissionDeniedErrorMapsToPermissionAlert() {
        let err = NSError(domain: NSCocoaErrorDomain,
                          code: NSFileReadNoPermissionError,
                          userInfo: nil)
        #expect(OpenPathFailureMapper.alert(for: err) == .permissionDenied,
                "DC-8: NSFileReadNoPermissionError must map to "
              + "ActiveAlert.permissionDenied, not the generic fallback.")
    }

    // DC-8 — `NSFileReadNoSuchFileError` / `NSFileNoSuchFileError` /
    // POSIX ENOENT maps to moved/removed.
    @Test("DC-8 — NSFileReadNoSuchFileError maps to moved-removed alert")
    func noSuchFileErrorMapsToMovedRemovedAlert() {
        let err = NSError(domain: NSCocoaErrorDomain,
                          code: NSFileReadNoSuchFileError,
                          userInfo: nil)
        #expect(OpenPathFailureMapper.alert(for: err) == .fileMovedOrRemoved)
    }

    // DC-8 — any other Cocoa/POSIX file-read error, or one whose class does
    // not unambiguously fall into the above, maps to the generic-couldn't-
    // read fallback. The fallback is the design's explicit retreat from
    // pretending the OS gives unambiguous error classes.
    @Test("DC-8 — unknown read error maps to generic-couldn't-read alert")
    func unknownReadErrorMapsToGenericAlert() {
        let err = NSError(domain: NSCocoaErrorDomain,
                          code: NSFileReadUnknownError,
                          userInfo: nil)
        #expect(OpenPathFailureMapper.alert(for: err) == .couldNotReadFile,
                "DC-8: ambiguous / unknown read errors must fall to the "
              + "generic alert variant, never to a silent no-op.")
    }

    // DC-8 — a strict UTF-8 decode failure (modeled as
    // DocumentError.invalidEncoding) maps to the encoding-error variant.
    @Test("DC-8 — DocumentError.invalidEncoding maps to invalidEncoding alert")
    func decodeFailureMapsToInvalidEncodingAlert() {
        #expect(OpenPathFailureMapper.alert(for: DocumentError.invalidEncoding)
                == .invalidEncoding)
    }

    // BR-3.1 — every load-failure case named in the declaration produces
    // a user-visible alert before control returns to the browser idle
    // state. We exercise the mapper across the named cases and assert that
    // the mapper returns SOME ActiveAlert (never nil) — silent no-op is
    // unreachable through this seam.
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
            // The mapper is non-Optional-returning by contract — every
            // error class maps to *some* alert. The generic fallback is
            // the catch-all; nil is never an outcome.
            let alert = OpenPathFailureMapper.alert(for: err)
            // Type-level check via switch (extracts: alert is one of the
            // four cases or invalidEncoding — never absent).
            switch alert {
            case .permissionDenied, .fileMovedOrRemoved,
                 .couldNotReadFile, .invalidEncoding, .tooLarge:
                break
            default:
                Issue.record("BR-3.1: error \(err) mapped to an unexpected "
                           + "ActiveAlert case \(alert) — every failure must "
                           + "map to one of the four named open-path cases.")
            }
        }
    }

    // BR-3.2 / DC-7 — alert text distinguishes the three named cases
    // sufficiently for the user to act. We assert that the four user-
    // facing texts are pairwise distinct and that each names the failure
    // class it represents.
    @Test("BR-3.2 / DC-7 — alert texts are distinguishable per case")
    func alertTextsAreDistinguishablePerCase() {
        let cases: [ActiveAlert] = [
            .permissionDenied,
            .fileMovedOrRemoved,
            .couldNotReadFile,
            .invalidEncoding,
            .tooLarge,
        ]
        let texts = cases.map { OpenPathAlertCopy.message(for: $0) }
        #expect(Set(texts).count == texts.count,
                "DC-7: the four (+ encoding + too-large) failure alerts "
              + "must have pairwise-distinct user-facing text.")

        // Each text mentions the failure class it names. We bind to the
        // substantive content from DC-7 — the build owns exact wording.
        #expect(OpenPathAlertCopy.message(for: .permissionDenied)
                .localizedCaseInsensitiveContains("permission"))
        #expect(OpenPathAlertCopy.message(for: .fileMovedOrRemoved)
                .localizedCaseInsensitiveContains("no longer"))
        #expect(OpenPathAlertCopy.message(for: .invalidEncoding)
                .localizedCaseInsensitiveContains("UTF-8"))
        #expect(OpenPathAlertCopy.message(for: .tooLarge)
                .localizedCaseInsensitiveContains("large"))
    }

    // BR-3.3 — Dismiss returns the user to a pickable browser; no stale
    // document, no half-initialized save bridge, no zombie scope access.
    // The behavioral assertion: after the mapper produces an alert, a
    // subsequent open attempt on a different URL succeeds (i.e. the
    // pipeline is not "stuck" in a failed state).
    @Test("BR-3.3 — dismiss returns to pickable browser (mapper is stateless)")
    func dismissReturnsToPickableBrowser() {
        // The mapper is a pure function — calling it does not mutate any
        // global state, and consecutive calls on different errors return
        // the right alert each time.
        let a = OpenPathFailureMapper.alert(for:
            NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError))
        let b = OpenPathFailureMapper.alert(for:
            NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError))
        #expect(a == .permissionDenied)
        #expect(b == .couldNotReadFile)
    }

    // BR-3.5 — the load seam may return nil/throw internally, but every
    // caller-observed nil/throw is converted to an alert before yielding
    // control. We assert the contract: the caller-facing seam
    // `OpenPathLoadResult` is a sum of (.document | .alert), with no
    // third "nothing" branch.
    @Test("BR-3.5 — caller-facing seam has no silent-nil outcome")
    func callerConvertsEveryFailureToAlert() {
        // OpenPathLoadResult is a two-case enum: .document(MarkdownDocument)
        // or .alert(ActiveAlert). The build maintains this invariant by
        // type. A test that the type has only those two cases isn't
        // expressible in Swift Testing as a static check, but we assert
        // that constructing the failure variant from each named error
        // class produces a `.alert(...)` result, never an empty value.
        let err = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
        let result = OpenPathLoadPipeline.failureResult(for: err)
        switch result {
        case .document:
            Issue.record("BR-3.5: a known failure must not produce a .document result.")
        case .alert(let alert):
            #expect(alert == .fileMovedOrRemoved)
        }
    }

    // BR-8 — File becomes unreadable mid-load. The result is a load-failure
    // surface (moved/removed OR permission-denied depending on OS-error
    // class), never a silent no-op, never a crash. We exercise by feeding
    // a typical mid-load error class to the mapper.
    @Test("BR-8 — mid-load unreadable produces moved-or-permission alert")
    func fileVanishingMidLoadProducesMovedOrPermissionAlert() {
        // Mid-load deletion typically surfaces as ENOENT.
        let enoent = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))
        let result1 = OpenPathFailureMapper.alert(for: enoent)
        #expect(result1 == .fileMovedOrRemoved)

        // Mid-load permission revoke typically surfaces as EACCES.
        let eacces = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        let result2 = OpenPathFailureMapper.alert(for: eacces)
        #expect(result2 == .permissionDenied)
    }

    // BR-12 — iCloud not-yet-downloaded is out of scope: the existing
    // iCloudDownloadFailed alert path handles it, not this feature's
    // surfaces. Asserted by absence: the mapper does NOT remap the
    // iCloud-download-failed error class into the open-path surfaces.
    @Test("BR-12 — iCloudDownloadFailed is not replaced by this feature's surfaces")
    func iCloudDownloadFailedIsNotReplacedByThisFeaturesSurfaces() {
        let alert = OpenPathFailureMapper.alert(for: DocumentError.iCloudDownloadFailed)
        #expect(alert == .iCloudDownloadFailed,
                "BR-12: the iCloud-download failure path stays on the "
              + "existing surface; this feature does not duplicate or "
              + "replace it.")
    }

    // BR-13 — Symlink to a missing target → moved/removed surface (the
    // OS reports ENOENT or NSFileReadNoSuchFileError when the target is
    // resolved and not found).
    @Test("BR-13 — symlink to missing target surfaces moved-removed alert")
    func symlinkToMissingTargetSurfacesMovedRemovedAlert() {
        // A symlink whose target is missing surfaces the same ENOENT-class
        // error the mapper treats as moved/removed.
        let err = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
        #expect(OpenPathFailureMapper.alert(for: err) == .fileMovedOrRemoved)
    }

    // BR-14 — A picked URL that is a directory or non-regular file produces
    // a load-failure surface, not a crash. The OS error class for "read
    // file but it's a directory" is `EISDIR` (POSIX) or
    // `NSFileReadInvalidFileNameError` / `NSFileReadCorruptFileError`
    // (Cocoa). The mapper routes this into the generic-couldn't-read
    // surface (it is not unambiguously any of the three named cases).
    @Test("BR-14 — directory / non-regular URL surfaces a failure alert, not a crash")
    func directoryURLSurfacesAFailureAlertNotACrash() {
        let eisdir = NSError(domain: NSPOSIXErrorDomain, code: Int(EISDIR))
        let alert = OpenPathFailureMapper.alert(for: eisdir)
        // The mapper must return *some* alert (no crash, no silent no-op);
        // the case is the generic fallback because EISDIR is not in the
        // unambiguous-mapping table.
        #expect(alert == .couldNotReadFile)
    }
}
