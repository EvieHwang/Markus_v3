import SwiftUI
import UIKit

struct MarkdownTextViewBridge: View {
    @ObservedObject var document: MarkdownDocument
    let autosave: AutosaveCoordinator
    let scrollState: RawEditorScrollState
    @Binding var pendingScrollAnchor: ScrollAnchor?

    var body: some View {
        Representable(
            document: document,
            autosave: autosave,
            scrollState: scrollState,
            pendingScrollAnchor: $pendingScrollAnchor
        )
        .opacity(pendingScrollAnchor == nil ? 1 : 0)
        .animation(.easeIn(duration: 0.15), value: pendingScrollAnchor == nil)
    }

    struct Representable: UIViewRepresentable {
        @ObservedObject var document: MarkdownDocument
        let autosave: AutosaveCoordinator
        let scrollState: RawEditorScrollState
        @Binding var pendingScrollAnchor: ScrollAnchor?

        func makeCoordinator() -> Coordinator {
            Coordinator(parent: self)
        }

        func makeUIView(context: Context) -> MarkdownEditorTextView {
            let tv = MarkdownEditorTextView()
            tv.delegate = context.coordinator
            tv.text = document.text
            return tv
        }

        func updateUIView(_ uiView: MarkdownEditorTextView, context: Context) {
            context.coordinator.parent = self

            if uiView.text != document.text {
                uiView.text = document.text
            }

            if let anchor = pendingScrollAnchor, !context.coordinator.anchorApplied {
                let textView = uiView
                let pendingBinding = $pendingScrollAnchor
                let coordinator = context.coordinator
                DispatchQueue.main.async {
                    textView.layoutIfNeeded()
                    let scrollableHeight = max(0, textView.contentSize.height - textView.bounds.height)
                    let offsetY = anchor.fractionalY * scrollableHeight
                    let clamped = min(max(0, offsetY), scrollableHeight)
                    textView.setContentOffset(CGPoint(x: 0, y: clamped), animated: false)
                    coordinator.anchorApplied = true
                    pendingBinding.wrappedValue = nil
                }
            }
        }

        @MainActor
        final class Coordinator: NSObject, UITextViewDelegate {
            var parent: Representable
            var anchorApplied: Bool = false

            init(parent: Representable) {
                self.parent = parent
            }

            func textViewDidChange(_ textView: UITextView) {
                let newText = textView.text ?? ""
                if parent.document.text != newText {
                    parent.document.text = newText
                    parent.document.markDirty()
                    parent.autosave.textChanged()
                }
            }

            func scrollViewDidScroll(_ scrollView: UIScrollView) {
                let scrollableHeight = max(1, scrollView.contentSize.height - scrollView.bounds.height)
                parent.scrollState.currentFractionalY = Double(scrollView.contentOffset.y / scrollableHeight)
            }

            func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
                guard text == "\n" else { return true }

                let fullText = textView.text ?? ""
                guard let swiftRange = Range(range, in: fullText) else { return true }

                let cursorPos = swiftRange.lowerBound
                let result = ListContinuationHandler.result(for: fullText, cursorPosition: cursorPos)

                switch result {
                case .plainNewline:
                    return true

                case .continueList(let prefix):
                    let insertion = "\n" + prefix
                    guard
                        let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
                        let end = textView.position(from: start, offset: range.length),
                        let utvRange = textView.textRange(from: start, to: end)
                    else {
                        return true
                    }
                    textView.replace(utvRange, withText: insertion)
                    return false

                case .exitList:
                    let lineStart = lineStartIndex(of: fullText, around: cursorPos)
                    let nsRangeFromLineStart = NSRange(lineStart..<cursorPos, in: fullText)
                    let replaceLocation = nsRangeFromLineStart.location
                    let replaceLength = nsRangeFromLineStart.length + range.length
                    guard
                        let start = textView.position(from: textView.beginningOfDocument, offset: replaceLocation),
                        let end = textView.position(from: start, offset: replaceLength),
                        let utvRange = textView.textRange(from: start, to: end)
                    else {
                        return true
                    }
                    textView.replace(utvRange, withText: "\n")
                    return false
                }
            }

            private func lineStartIndex(of text: String, around index: String.Index) -> String.Index {
                var i = index
                while i > text.startIndex {
                    let prev = text.index(before: i)
                    if text[prev] == "\n" { break }
                    i = prev
                }
                return i
            }
        }
    }
}
