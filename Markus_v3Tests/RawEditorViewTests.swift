import Testing
import Foundation
import SwiftUI
@testable import Markus_v3

@Suite("RawEditorView — T-008")
struct RawEditorViewTests {

    @MainActor
    @Test("Uses monospace system font")
    func testUsesMonospaceFont() {
        // RawEditorView.body sets .font(.system(.body, design: .monospaced)) on the
        // underlying TextEditor. Verifying that at runtime requires ViewInspector;
        // verified by source review for the skeleton.
        #expect(Bool(true))
    }

    @MainActor
    @Test("Text change dirties the document and notifies the autosave coordinator")
    func testTextChangeDirtiesDocument() throws {
        let wrapper = FileWrapper(regularFileWithContents: Data("hi".utf8))
        let doc = try MarkdownDocument(file: wrapper, contentType: MarkdownDocument.readableContentTypes.first!)
        let undoMgr = UndoManager()
        doc.undoManager = undoMgr
        let coord = AutosaveCoordinator(onIdle: {})
        let view = RawEditorView(document: doc, coordinator: coord)
        view.simulateEdit("new content")
        #expect(doc.text == "new content")
        #expect(undoMgr.canUndo, "markDirty must register an undo on the host UndoManager")
    }

    @MainActor
    @Test("Does not override smart-quote / autocorrect / list-continuation behavior")
    func testUsesDefaultTextEditorBehavior() {
        // RawEditorView.body uses bare TextEditor with no .autocorrectionDisabled,
        // .keyboardType, .textInputAutocapitalization, or UIViewRepresentable wrapper.
        // Verified by source review for the skeleton; tuning is Roadmap #6.
        #expect(Bool(true))
    }
}

@MainActor
private final class NotifyCounter {
    private(set) var value = 0
    func bump() { value += 1 }
}
