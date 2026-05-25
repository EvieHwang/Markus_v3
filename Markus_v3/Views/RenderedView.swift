import SwiftUI
import MarkdownUI

struct RenderedView: View {
    let text: String
    let onTap: (Double?) -> Void
    @Binding var pendingScrollAnchor: ScrollAnchor?

    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var scrollOffsetY: CGFloat = 0

    init(text: String, onTap: @escaping (Double?) -> Void, pendingScrollAnchor: Binding<ScrollAnchor?> = .constant(nil)) {
        self.text = text
        self.onTap = onTap
        self._pendingScrollAnchor = pendingScrollAnchor
    }

    var body: some View {
        ScrollView {
            Markdown(text)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { contentHeight = proxy.size.height }
                            .onChange(of: proxy.size.height) { _, new in contentHeight = new }
                    }
                )
        }
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, new in
            scrollOffsetY = new
        }
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.containerSize.height }) { _, new in
            viewportHeight = new
        }
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .local) { location in
            let contentY = location.y + scrollOffsetY
            let fractional = contentHeight > 0 ? Double(contentY / contentHeight) : 0
            onTap(fractional)
        }
        .environment(\.openURL, OpenURLAction { _ in
            onTap(nil)
            return .discarded
        })
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Edit") { onTap(nil) }
        .accessibilityIdentifier("RenderedView")
        .opacity(pendingScrollAnchor == nil ? 1 : 0)
        .animation(.easeIn(duration: 0.15), value: pendingScrollAnchor == nil)
        .task(id: pendingScrollAnchor) {
            await applyPendingAnchor()
        }
    }

    @MainActor
    private func applyPendingAnchor() async {
        guard let anchor = pendingScrollAnchor else { return }
        for _ in 0..<30 {
            if contentHeight > 0 { break }
            try? await Task.sleep(for: .milliseconds(16))
        }
        let scrollable = max(0, contentHeight - viewportHeight)
        let target = CGFloat(anchor.fractionalY) * scrollable
        scrollPosition.scrollTo(y: target)
        await Task.yield()
        pendingScrollAnchor = nil
    }

    @MainActor func simulateTap() { onTap(0) }

    @MainActor func simulateLinkTap(_ url: URL) {
        _ = url
        onTap(nil)
    }
}
