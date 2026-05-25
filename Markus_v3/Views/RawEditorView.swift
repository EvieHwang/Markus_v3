import SwiftUI

struct RawEditorView: View {
    @ObservedObject var document: MarkdownDocument
    let coordinator: AutosaveCoordinator
    let scrollState: RawEditorScrollState
    @Binding var pendingScrollAnchor: ScrollAnchor?

    var body: some View {
        MarkdownTextViewBridge(
            document: document,
            autosave: coordinator,
            scrollState: scrollState,
            pendingScrollAnchor: $pendingScrollAnchor
        )
    }

    @MainActor func simulateEdit(_ newText: String) {
        document.text = newText
        document.markDirty()
        coordinator.textChanged()
    }
}
