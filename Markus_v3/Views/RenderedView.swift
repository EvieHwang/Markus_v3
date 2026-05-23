import SwiftUI
import MarkdownUI

struct RenderedView: View {
    let text: String
    let onTap: () -> Void

    var body: some View {
        ScrollView {
            Markdown(text)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .environment(\.openURL, OpenURLAction { _ in
            onTap()
            return .discarded
        })
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Edit") { onTap() }
        .accessibilityIdentifier("RenderedView")
    }

    @MainActor func simulateTap() { onTap() }

    @MainActor func simulateLinkTap(_ url: URL) {
        _ = url
        onTap()
    }
}
