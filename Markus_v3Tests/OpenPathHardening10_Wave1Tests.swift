// OpenPathHardening10_Wave1Tests.swift
// Mirrored Wave-1 spec tests for open-path-hardening-10.
//
// Sources:
//   features/open-path-hardening-10/tests/AlertHostAndScopeTests.swift
//     (only the type-level subset that T-001 alone is sufficient for —
//      `allFourFailureCasesAreActiveAlertCases`,
//      `failureSurfacesReuseActiveAlertChannel`)
//   features/open-path-hardening-10/tests/LoadFailureMappingTests.swift
//     (only `alertTextsAreDistinguishablePerCase` — T-001's copy seam)
//   features/open-path-hardening-10/tests/SizeCeilingTests.swift
//     (only the pure constant/predicate subset T-002 vends —
//      `ceilingIsAFixedConstantHonoringDesignValue`,
//      `exactlyAtCeilingIsAccepted`, `oneByteOverCeilingIsRejected`)
//
// The remaining tests in those spec files bind to seams introduced in
// later waves and are mirrored when their owning task lands.

import Testing
import Foundation
@testable import Markus_v3

private let CEILING_BYTES: Int = 20 * 1024 * 1024 // 20 971 520

@Suite("Open path — Wave 1 (T-001 ActiveAlert + copy, T-002 size ceiling)")
struct OpenPathHardening10_Wave1Tests {

    // T-001 / DC-6 — the four new cases exist and are constructible.
    @Test("T-001 / DC-6 — failure surfaces reuse the ActiveAlert channel")
    func failureSurfacesReuseActiveAlertChannel() {
        let cases: [ActiveAlert] = [
            .invalidEncoding,
            .permissionDenied,
            .fileMovedOrRemoved,
            .couldNotReadFile,
            .tooLarge,
        ]
        for alert in cases {
            #expect(!alert.id.isEmpty)
        }
    }

    // T-001 / DC-6 — all four new cases exist on ActiveAlert with stable,
    // pairwise-distinct ids.
    @Test("T-001 / DC-6 — all four new failure cases exist as ActiveAlert cases")
    func allFourFailureCasesAreActiveAlertCases() {
        let permissionDenied: ActiveAlert = .permissionDenied
        let movedOrRemoved: ActiveAlert = .fileMovedOrRemoved
        let couldNotRead: ActiveAlert = .couldNotReadFile
        let tooLarge: ActiveAlert = .tooLarge
        #expect(!permissionDenied.id.isEmpty)
        #expect(!movedOrRemoved.id.isEmpty)
        #expect(!couldNotRead.id.isEmpty)
        #expect(!tooLarge.id.isEmpty)
        let ids = Set([permissionDenied.id, movedOrRemoved.id,
                       couldNotRead.id, tooLarge.id])
        #expect(ids.count == 4)
    }

    // T-001 / DC-7 — alert texts are pairwise distinguishable and each
    // mentions its failure class.
    @Test("T-001 / DC-7 — alert texts are distinguishable per case")
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
                "DC-7: the open-path failure alerts must have pairwise-distinct user-facing text.")

        #expect(OpenPathAlertCopy.message(for: .permissionDenied)
                .localizedCaseInsensitiveContains("permission"))
        #expect(OpenPathAlertCopy.message(for: .fileMovedOrRemoved)
                .localizedCaseInsensitiveContains("no longer"))
        #expect(OpenPathAlertCopy.message(for: .invalidEncoding)
                .localizedCaseInsensitiveContains("UTF-8"))
        #expect(OpenPathAlertCopy.message(for: .tooLarge)
                .localizedCaseInsensitiveContains("large"))
    }

    // T-002 / BR-4.3 / DC-5 — the ceiling equals the design-pinned 20 MiB.
    @Test("T-002 / BR-4.3 / DC-5 — ceiling constant equals 20 MiB")
    func ceilingIsAFixedConstantHonoringDesignValue() {
        #expect(OpenPathSizeCeiling.maxBytes == CEILING_BYTES,
                "DC-5: the ceiling must equal 20 * 1024 * 1024 = 20 971 520.")
    }

    // T-002 / BR-4.6 — at-boundary inclusive.
    @Test("T-002 / BR-4.6 — file exactly at ceiling is accepted")
    func exactlyAtCeilingIsAccepted() {
        #expect(OpenPathSizeCeiling.admits(byteSize: CEILING_BYTES))
    }

    // T-002 / BR-7 — one byte over is rejected.
    @Test("T-002 / BR-7 — file one byte over ceiling is rejected")
    func oneByteOverCeilingIsRejected() {
        #expect(!OpenPathSizeCeiling.admits(byteSize: CEILING_BYTES + 1))
    }
}
