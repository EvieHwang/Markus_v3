import SwiftUI

struct RawEditorView: View {
    @ObservedObject var document: MarkdownDocument
    let coordinator: AutosaveCoordinator

    var body: some View {
        TextEditor(text: $document.text)
            .font(.system(.body, design: .monospaced))
            .onChange(of: document.text) { _, _ in
                document.markDirty()
                coordinator.textChanged()
            }
    }

    @MainActor func simulateEdit(_ newText: String) {
        document.text = newText
        document.markDirty()
        coordinator.textChanged()
    }
}
