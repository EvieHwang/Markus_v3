import SwiftUI

struct DocumentLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Downloading…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
