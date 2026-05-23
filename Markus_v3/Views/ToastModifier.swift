import SwiftUI

struct ToastModifier: ViewModifier {
    @Binding var toast: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message = toast {
                Text(message)
                    .accessibilityHidden(true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(.regularMaterial))
                    .padding(.bottom, 40)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(2))
                        if !Task.isCancelled {
                            toast = nil
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toast)
    }
}

extension View {
    func toast(_ message: Binding<String?>) -> some View {
        modifier(ToastModifier(toast: message))
    }
}
