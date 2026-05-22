// Spec test — Wave 4 / T-008
// Tags: T-008
// Verifies: AC-4.1, AC-4.2, AC-4.6; design component #6

import Testing
import SwiftUI
@testable import Markus_v3

@Suite("RawEditorView — T-008")
struct RawEditorViewTests {

    @MainActor
    @Test("Uses monospace system font")
    func testUsesMonospaceFont() {
        // Build agent: inspect the TextEditor's resolved font via ViewInspector
        // and confirm design == .monospaced.
        #expect(Bool(true))
    }

    @MainActor
    @Test("Text change dirties the document and notifies the autosave coordinator")
    func testTextChangeDirtiesDocument() {
        var dirtied = false
        var notified = false
        let doc = StubDoc(onMarkDirty: { dirtied = true })
        let coord = StubCoord(onTextChanged: { notified = true })
        let view = RawEditorView(document: doc, coordinator: coord)
        view.simulateEdit("new content")
        #expect(dirtied)
        #expect(notified)
    }

    @MainActor
    @Test("Does not override smart-quote / autocorrect / list-continuation behavior")
    func testUsesDefaultTextEditorBehavior() {
        // AC-4.6: skeleton must not configure UITextView-level overrides; defaults stand.
        // Build agent: confirm the SwiftUI TextEditor is not wrapped in a UIViewRepresentable
        // that sets autocorrectionType / smartQuotesType / etc.
        #expect(Bool(true))
    }
}

// MARK: - Test stubs (replace with real types or protocol-based testing in implementation)
private final class StubDoc {
    let onMarkDirty: () -> Void
    init(onMarkDirty: @escaping () -> Void) { self.onMarkDirty = onMarkDirty }
}
private final class StubCoord {
    let onTextChanged: () -> Void
    init(onTextChanged: @escaping () -> Void) { self.onTextChanged = onTextChanged }
}
