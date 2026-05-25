import Testing
import Foundation
import SwiftUI
@testable import Markus_v3

@Suite("RawEditorView — bridge surface")
struct RawEditorViewTests {

    @MainActor
    @Test("Text change dirties the document and notifies the autosave coordinator")
    func testTextChangeDirtiesDocument() throws {
        let wrapper = FileWrapper(regularFileWithContents: Data("hi".utf8))
        let doc = try MarkdownDocument(file: wrapper, contentType: MarkdownDocument.readableContentTypes.first!)
        let undoMgr = UndoManager()
        doc.undoManager = undoMgr
        let coord = AutosaveCoordinator(onIdle: {})
        let scrollState = RawEditorScrollState()
        let view = RawEditorView(
            document: doc,
            coordinator: coord,
            scrollState: scrollState,
            pendingScrollAnchor: .constant(nil)
        )
        view.simulateEdit("new content")
        #expect(doc.text == "new content")
        #expect(undoMgr.canUndo, "markDirty must register an undo on the host UndoManager")
    }

    @MainActor
    @Test("Constructible with a non-nil pending scroll anchor")
    func testConstructibleWithPendingAnchor() throws {
        let wrapper = FileWrapper(regularFileWithContents: Data("hi".utf8))
        let doc = try MarkdownDocument(file: wrapper, contentType: MarkdownDocument.readableContentTypes.first!)
        let coord = AutosaveCoordinator(onIdle: {})
        let scrollState = RawEditorScrollState()
        let view = RawEditorView(
            document: doc,
            coordinator: coord,
            scrollState: scrollState,
            pendingScrollAnchor: .constant(ScrollAnchor(fractionalY: 0.5))
        )
        #expect(view.document === doc)
    }
}
