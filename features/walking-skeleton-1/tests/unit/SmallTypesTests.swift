// Spec test — Wave 2 / T-002
// Tags: T-002
// Verifies: design.md component #3 (DocumentMode), component #8 (DocumentError, ActiveAlert)

import Testing
@testable import Markus_v3

@Suite("Small types — T-002")
struct SmallTypesTests {

    @Test("DocumentMode has exactly two cases")
    func testDocumentModeCases() {
        let modes: [DocumentMode] = [.rendered, .raw]
        #expect(modes.count == 2)
    }

    @Test("DocumentError covers all expected cases")
    func testDocumentErrorCases() {
        let errors: [DocumentError] = [
            .invalidEncoding,
            .saveFailed(underlying: NSError(domain: "test", code: 0)),
            .fileMissing,
            .iCloudDownloadFailed
        ]
        #expect(errors.count == 4)
    }

    @Test("ActiveAlert.id is stable per case")
    func testActiveAlertIDStability() {
        let a1: ActiveAlert = .invalidEncoding
        let a2: ActiveAlert = .invalidEncoding
        #expect(a1.id == a2.id)

        let b1: ActiveAlert = .iCloudDownloadFailed
        #expect(a1.id != b1.id)
    }
}
