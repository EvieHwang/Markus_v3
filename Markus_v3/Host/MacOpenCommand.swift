import UIKit
import UniformTypeIdentifiers

/// File → Open / ⌘O adapter (mac-catalyst-shell-14, design Component B —
/// `MacOpenCommand`). A picker-to-funnel adapter: presents the system open
/// panel (UIDocumentPickerViewController, which surfaces as NSOpenPanel under
/// Mac Catalyst) constrained to `MarkdownDocument.readableContentTypes`, and
/// hands the chosen URL to the existing `BrowserHostController.presentDocument(at:)`
/// funnel.
///
/// Per the requirements / design contracts (FM-2, S-3): no second open, decode,
/// read, or security-scoped-bookmark mechanism is introduced. The panel's only
/// output is a URL into the existing funnel.
@MainActor
final class MacOpenCommand: NSObject, UIDocumentPickerDelegate {

    private let onPicked: (URL) -> Void
    private let onCanceled: (() -> Void)?
    private var picker: UIDocumentPickerViewController?

    init(onPicked: @escaping (URL) -> Void,
         onCanceled: (() -> Void)? = nil) {
        self.onPicked = onPicked
        self.onCanceled = onCanceled
        super.init()
    }

    /// Constrained to the app's existing markdown types — `.md` / `.markdown`
    /// (AC-3.2). Other types are not selectable.
    func present(from presenter: UIViewController) {
        let types = MarkdownDocument.readableContentTypes
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types,
                                                    asCopy: false)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = false
        picker.delegate = self
        self.picker = picker
        presenter.present(picker, animated: true)
    }

    // MARK: - UIDocumentPickerDelegate

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        defer { picker = nil }
        guard let url = urls.first else { return }
        onPicked(url)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        picker = nil
        onCanceled?()
    }
}
