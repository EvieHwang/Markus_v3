import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// `UIDocumentBrowserViewController` subclass + delegate that hosts the system
/// document browser as the app's scene root (design C0). Replaces the SwiftUI
/// `DocumentGroup` host. Owns three Wave-4 control points the previous host
/// did not expose:
///
/// - **`createDocumentRequestHandler`** — bound by T-007 to handle
///   `documentBrowser(_:didRequestDocumentCreationWithHandler:)`. Lets the
///   create flow choose the document's URL (target directory + name) and
///   defer the on-disk write until first keystroke (design DC-9 / DC-12).
/// - **`didOpenDocument`** — fires whenever a document is presented (browser
///   pick, import, resume, or create-then-persist). T-008 binds this to
///   `LastFileStore.recordLastOpened` so BR-1 holds for all three entry
///   paths.
/// - **`willPresentInitialContent`** — invoked from the scene's
///   `willConnectTo` path *before* the browser is the visible top view
///   controller. T-006 binds this to make the resume decision and present
///   the editor as the scene's first content (design DC-3). The default is
///   a no-op, so the browser is the natural landing.
///
/// The class also exposes `presentDocument(at:)` — the shared open path
/// reused by the browser pick callback, the resume branch, and the create
/// handler — so all three open paths funnel through the same code (and
/// therefore the same `didOpenDocument` notification).
final class BrowserHostController: UIDocumentBrowserViewController {

    typealias CreateImportHandler = (URL?, UIDocumentBrowserViewController.ImportMode) -> Void

    /// Wave-4 T-007 hook. When set, takes over the system create-document
    /// callback completely. The handler is responsible for invoking the
    /// supplied `importHandler` exactly once (with `(nil, .none)` to cancel
    /// or with a real URL to materialize). Default behavior: cancel the
    /// system create cleanly.
    var createDocumentRequestHandler: ((@escaping CreateImportHandler) -> Void)?

    /// Wave-4 T-008 hook. Fired whenever a document opens successfully — at
    /// the moment the editor scene becomes active for a real on-disk file.
    var didOpenDocument: ((URL) -> Void)?

    /// Wave-4 T-006 hook. Invoked once from the scene's `willConnectTo`
    /// path with this controller and the connection options. The
    /// implementation may call `presentDocument(at:)` to land the user
    /// directly in the editor before the browser becomes visible.
    var willPresentInitialContent: ((BrowserHostController, UIScene.ConnectionOptions) -> Void)?

    private var currentSaveBridge: MarkdownDocumentSaveBridge?

    init() {
        super.init(forOpening: MarkdownDocument.readableContentTypes)
        delegate = self
        allowsDocumentCreation = true
        allowsPickingMultipleItems = false
        shouldShowFileExtensions = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for BrowserHostController")
    }

    /// Asks the host to present the file at `url` in the editor. Used by
    /// the browser pick callback, the resume branch (T-006), and the
    /// create-document handler (T-007). Reuses the unchanged
    /// `DocumentView` as the editor surface (hard-seam: `MarkdownDocument`
    /// and the rendered/raw mode-switch are not touched).
    ///
    /// - Parameters:
    ///   - url: the file to open. Must be a `.md`/`.markdown` file already
    ///     resolvable in the current security scope.
    ///   - initialMode: hint for the editor's first mode. The walking
    ///     skeleton already chooses an initial mode in `.onAppear` (large
    ///     file → `.raw`); this parameter is reserved for T-007 to request
    ///     `.raw` for newly created files (design seam, no mode-switch
    ///     change).
    ///   - animated: passed to `present`. Default true.
    @MainActor
    func presentDocument(at url: URL, initialMode: DocumentMode? = nil, animated: Bool = true) {
        guard let document = Self.loadMarkdownDocument(at: url) else {
            return
        }

        let bridge = MarkdownDocumentSaveBridge(document: document, url: url)
        self.currentSaveBridge = bridge

        let editor = DocumentView(document: document, fileURL: url)
        let host = UIHostingController(rootView: editor)
        let nav = UINavigationController(rootViewController: host)
        nav.modalPresentationStyle = .fullScreen

        present(nav, animated: animated) { [weak self] in
            self?.didOpenDocument?(url)
        }
    }

    /// Flush any in-flight saves for the currently presented document.
    /// Called by `SceneDelegate` on background / disconnect.
    @MainActor
    func flushPendingSaves() {
        currentSaveBridge?.saveSynchronously()
    }

    @MainActor
    static func loadMarkdownDocument(at url: URL) -> MarkdownDocument? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let wrapper = try FileWrapper(url: url, options: [])
            return try MarkdownDocument(file: wrapper, contentType: .plainText)
        } catch {
            return nil
        }
    }
}

extension BrowserHostController: UIDocumentBrowserViewControllerDelegate {

    func documentBrowser(_ controller: UIDocumentBrowserViewController,
                         didRequestDocumentCreationWithHandler importHandler: @escaping CreateImportHandler) {
        if let handler = createDocumentRequestHandler {
            handler(importHandler)
        } else {
            // Default: cancel the system create cleanly. Wave 4 T-007 binds
            // `createDocumentRequestHandler` to take over.
            importHandler(nil, .none)
        }
    }

    func documentBrowser(_ controller: UIDocumentBrowserViewController,
                         didPickDocumentsAt documentURLs: [URL]) {
        guard let url = documentURLs.first else { return }
        presentDocument(at: url)
    }

    func documentBrowser(_ controller: UIDocumentBrowserViewController,
                         didImportDocumentAt sourceURL: URL,
                         toDestinationURL destinationURL: URL) {
        presentDocument(at: destinationURL)
    }

    func documentBrowser(_ controller: UIDocumentBrowserViewController,
                         failedToImportDocumentAt documentURL: URL,
                         error: Error?) {
        // Silent failure per design DC-4 (no error UI on routine failures).
    }
}
