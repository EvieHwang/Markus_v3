import Foundation

/// Single funnel that records every successful document open into
/// `LastFileStore` (design C3 / BR-1 / DC-15). Bound to
/// `BrowserHostController.didOpenDocument` in `SceneDelegate`, which
/// fires for all three entry paths:
///
/// - Browser pick / import (`documentBrowser(_:didPickDocumentsAt:)` and
///   `documentBrowser(_:didImportDocumentAt:toDestinationURL:)`)
/// - Resume (via `LaunchResumeBranch` calling
///   `presentDocument(at:animated:)`)
/// - Newly-created file's first persistence (via
///   `MarkdownDocumentSaveBridge.onFirstPersist`, which the host
///   re-routes through `didOpenDocument`)
@MainActor
final class DocumentOpenObserver {

    private let store: LastFileStore
    private weak var host: BrowserHostController?

    init(host: BrowserHostController, store: LastFileStore = LastFileStore()) {
        self.host = host
        self.store = store
    }

    /// Binds this observer to its host. After this call, every
    /// `didOpenDocument` fired by the host records the opened URL into
    /// `LastFileStore`. This is the only writer to the store outside the
    /// UI-test seeding helpers.
    func install() {
        host?.didOpenDocument = { [weak self] url in
            self?.store.recordLastOpened(url)
        }
    }
}
