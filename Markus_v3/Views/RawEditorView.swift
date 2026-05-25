import SwiftUI

struct RawEditorView: View {
    @ObservedObject var document: MarkdownDocument
    let coordinator: AutosaveCoordinator
    let scrollState: RawEditorScrollState
    @Binding var pendingScrollAnchor: ScrollAnchor?
    let focusOnAppear: Bool

    init(document: MarkdownDocument,
         coordinator: AutosaveCoordinator,
         scrollState: RawEditorScrollState,
         pendingScrollAnchor: Binding<ScrollAnchor?>,
         focusOnAppear: Bool = false) {
        self.document = document
        self.coordinator = coordinator
        self.scrollState = scrollState
        self._pendingScrollAnchor = pendingScrollAnchor
        self.focusOnAppear = focusOnAppear
    }

    var body: some View {
        MarkdownTextViewBridge(
            document: document,
            autosave: coordinator,
            scrollState: scrollState,
            pendingScrollAnchor: $pendingScrollAnchor,
            focusOnAppear: focusOnAppear
        )
    }

    @MainActor func simulateEdit(_ newText: String) {
        document.text = newText
        document.markDirty()
        coordinator.textChanged()
    }
}
