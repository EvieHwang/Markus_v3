import SwiftUI
import UIKit

/// SwiftUI wrapper around `UIActivityViewController` (design C5).
///
/// Used by `DocumentView` to present the standard iOS share sheet with the
/// document's on-disk URL as the activity item. The system provides the
/// activity list (AirDrop, Save to Files, Mail, Print, etc., per NP-8.3) and
/// handles iPad popover anchoring automatically when presented via `.sheet`.
struct ActivityViewRepresentable: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
