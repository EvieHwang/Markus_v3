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
    /// NP-5: L→R swipe handler. Called when the gesture passes the
    /// `SwipeGestureDecision.detect` thresholds with `.leftToRight` direction.
    /// The system `UIScreenEdgePanGestureRecognizer` on the navigation
    /// controller still catches edge-anchored L→R drags; this closure handles
    /// mid-screen L→R swipes that would otherwise be ignored.
    let onSwipeToBrowser: (() -> Void)?

    init(document: MarkdownDocument,
         coordinator: AutosaveCoordinator,
         scrollState: RawEditorScrollState,
         pendingScrollAnchor: Binding<ScrollAnchor?>,
         focusOnAppear: Bool = false,
         onSwipeToRendered: (() -> Void)? = nil,
         onSwipeToBrowser: (() -> Void)? = nil) {
        self.document = document
        self.coordinator = coordinator
        self.scrollState = scrollState
        self._pendingScrollAnchor = pendingScrollAnchor
        self.focusOnAppear = focusOnAppear
        self.onSwipeToRendered = onSwipeToRendered
        self.onSwipeToBrowser = onSwipeToBrowser
    }

    var body: some View {
        MarkdownTextViewBridge(
            document: document,
            autosave: coordinator,
            scrollState: scrollState,
            pendingScrollAnchor: $pendingScrollAnchor,
            focusOnAppear: focusOnAppear
        )
        // ipad-expansion-13 — shared content column (~700pt, centered) in
        // regular width; full-width in compact (C-B.1, C-B.4, FM-5/FM-8).
        // Applied to both surfaces from one shared resolver so switching
        // modes does not shift the column left/right.
        .contentColumn()
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    let direction = SwipeGestureDecision.detect(
                        translation: value.translation,
                        velocity: value.velocity,
                        startX: value.startLocation.x
                    )
                    switch direction {
                    case .rightToLeft: onSwipeToRendered?()
                    case .leftToRight: onSwipeToBrowser?()
                    case nil:          break
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
