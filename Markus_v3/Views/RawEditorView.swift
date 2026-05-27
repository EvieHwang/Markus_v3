import SwiftUI

struct RawEditorView: View {
    @ObservedObject var document: MarkdownDocument
    let coordinator: AutosaveCoordinator
    let scrollState: RawEditorScrollState
    @Binding var pendingScrollAnchor: ScrollAnchor?
    let focusOnAppear: Bool
    /// NP-4: R→L swipe handler. Called when the gesture passes the
    /// `SwipeGestureDecision.detect` thresholds with `.rightToLeft` direction.
    let onSwipeToRendered: (() -> Void)?

    init(document: MarkdownDocument,
         coordinator: AutosaveCoordinator,
         scrollState: RawEditorScrollState,
         pendingScrollAnchor: Binding<ScrollAnchor?>,
         focusOnAppear: Bool = false,
         onSwipeToRendered: (() -> Void)? = nil) {
        self.document = document
        self.coordinator = coordinator
        self.scrollState = scrollState
        self._pendingScrollAnchor = pendingScrollAnchor
        self.focusOnAppear = focusOnAppear
        self.onSwipeToRendered = onSwipeToRendered
    }

    var body: some View {
        MarkdownTextViewBridge(
            document: document,
            autosave: coordinator,
            scrollState: scrollState,
            pendingScrollAnchor: $pendingScrollAnchor,
            focusOnAppear: focusOnAppear
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    let direction = SwipeGestureDecision.detect(
                        translation: value.translation,
                        velocity: value.velocity,
                        startX: value.startLocation.x
                    )
                    if direction == .rightToLeft {
                        onSwipeToRendered?()
                    }
                }
        )
    }

    @MainActor func simulateEdit(_ newText: String) {
        document.text = newText
        document.markDirty()
        coordinator.textChanged()
    }
}
