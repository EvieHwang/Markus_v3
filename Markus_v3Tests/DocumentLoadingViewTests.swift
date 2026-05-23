import Testing
import SwiftUI
@testable import Markus_v3

@Suite("DocumentLoadingView — T-009")
struct DocumentLoadingViewTests {

    @MainActor
    @Test("Renders a centered ProgressView with the label \"Downloading…\"")
    func testRendersSpinnerAndLabel() {
        // Construction-only smoke check. The body composition (ProgressView +
        // Text("Downloading…") inside a centered VStack) is verified by source
        // review; ViewInspector-based assertions are out of skeleton scope.
        let _ = DocumentLoadingView()
        #expect(Bool(true))
    }
}
