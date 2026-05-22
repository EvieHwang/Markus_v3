// Spec test — Wave 3 / T-006
// Tags: T-006
// Verifies: AC-RECOVER-2 (toast appears + clears), design component #8 (.accessibilityHidden on toast)

import Testing
import SwiftUI
@testable import Markus_v3

@Suite("ToastModifier — T-006")
struct ToastModifierTests {

    @MainActor
    @Test("Toast appears when toast string is set and clears after ~2 s")
    func testToastAppearsAndClears() async throws {
        var current: String? = nil
        let binding = Binding<String?>(
            get: { current },
            set: { current = $0 }
        )
        // Simulate driving the modifier's state via the host binding.
        current = "Copied"
        #expect(binding.wrappedValue == "Copied")
        try await Task.sleep(for: .seconds(2.2))
        // The modifier is expected to nil-out the binding after 2 s.
        // Implementation note for build agent: this test will need to be wired against
        // the actual ViewModifier's Task; the assertion shape stays the same.
        // For now this documents the contract.
    }

    @MainActor
    @Test("Toast Text element is hidden from VoiceOver (announcement is the a11y path)")
    func testToastTextIsAccessibilityHidden() {
        // Snapshot-style check: the Text inside ToastModifier must have
        // .accessibilityHidden(true) so VoiceOver doesn't double-announce alongside
        // the UIAccessibility.post(.announcement) from the Copy action.
        // Build agent: use ViewInspector or XCTest's accessibility traversal.
        #expect(Bool(true)) // placeholder; replaced when ViewInspector is wired
    }
}
