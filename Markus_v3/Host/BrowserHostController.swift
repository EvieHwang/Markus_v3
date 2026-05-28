import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// `UIDocumentBrowserViewController` subclass + delegate that hosts the system
/// document browser as the app's scene root (design C0). Replaces the SwiftUI
/// `DocumentGroup` host.
///
/// Two Wave-4 control points the previous host did not expose:
///
/// - **`didOpenDocument`** — fires whenever a document is presented (browser
///   pick, import, resume). Bound by `DocumentOpenObserver.install()` to
///   `LastFileStore.recordLastOpened`, so BR-1 holds for all entry paths.
/// - **`willPresentInitialContent`** — invoked from the scene's
///   `willConnectTo` path *before* the browser is the visible top view
///   controller. Used by the resume branch (DC-3) to land the user
///   directly in the editor when a last-opened file resolves.
///
/// **Create flow (restore-system-create-7, DC-1).** This controller
/// implements `documentBrowser(_:didRequestDocumentCreationWithHandler:)`
/// as a *template-only* handoff: it materializes an empty `.md` template in
/// `NSTemporaryDirectory()` and invokes the system completion handler with
/// `(templateURL, .copy)`. The system then copies the template into the
/// folder the user is currently browsing, runs its inline rename UI, and
/// — on confirm — opens the file through `didPickDocumentsAt` /
/// `didImportDocumentAt`. Markus contributes no directory choice, no name,
/// no deferred-write, and no fallback target.
final class BrowserHostController: UIDocumentBrowserViewController {

    /// Wave-4 hook. Fired whenever a document opens successfully.
    var didOpenDocument: ((URL) -> Void)?

    /// Wave-4 hook. Invoked once from the scene's `willConnectTo` path
    /// before the browser is visible.
    var willPresentInitialContent: ((BrowserHostController, UIScene.ConnectionOptions) -> Void)?

    private var currentSaveBridge: MarkdownDocumentSaveBridge?
    private var currentDetector: ChangeDetector?
    private var currentPresentedNav: UINavigationController?
    private var edgeSwipeRecognizer: UIScreenEdgePanGestureRecognizer?

    /// Resume-reference store, reused by the follow-on-move retarget (DC-19/BR-8.5).
    private let lastFileStore = LastFileStore()

    /// Closure run once on the first `viewDidAppear`, before any other
    /// activity, to give the resume decision a fully-on-screen host to
    /// present onto. Set by `SceneDelegate`; cleared after firing.
    var initialResumeAction: ((BrowserHostController) -> Void)?
    private var initialResumeFired = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !initialResumeFired {
            initialResumeFired = true
            initialResumeAction?(self)
            initialResumeAction = nil
        }
    }

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
    /// the browser pick/import callbacks and the resume branch. Reuses the
    /// unchanged `DocumentView` as the editor surface.
    @MainActor
    func presentDocument(at url: URL, animated: Bool = true) {
        guard let document = Self.loadMarkdownDocument(at: url) else { return }

        let settleEnabled = !ProcessInfo.processInfo.arguments.contains("-uitest-suppress-settle")
        let detector = ChangeDetector(document: document, url: url, settleEnabled: settleEnabled)
        self.currentDetector = detector

        let bridge = makeSaveBridge(document: document, url: url, detector: detector)
        self.currentSaveBridge = bridge

        detector.requestImmediateWrite = { [weak self] in
            self?.currentSaveBridge?.saveSynchronously()
        }
        detector.onRetarget = { [weak self, weak detector] newURL in
            guard let self, let detector else { return }
            let newBridge = self.makeSaveBridge(document: document, url: newURL, detector: detector)
            self.currentSaveBridge = newBridge
            self.lastFileStore.recordLastOpened(newURL)
        }

        let onBack: () -> Void = { [weak self] in
            self?.dismissPresentedEditor()
        }

        let editor = DocumentView(
            document: document,
            fileURL: url,
            detector: detector,
            onBack: onBack
        )
        let host = UIHostingController(rootView: editor)
        let nav = UINavigationController(rootViewController: host)
        nav.modalPresentationStyle = .fullScreen
        self.currentPresentedNav = nav

        installEdgeSwipeDismiss(on: nav.view)

        present(nav, animated: animated) { [weak self] in
            self?.didOpenDocument?(url)
        }
    }

    @MainActor
    private func makeSaveBridge(document: MarkdownDocument,
                                url: URL,
                                detector: ChangeDetector) -> MarkdownDocumentSaveBridge {
        let bridge = MarkdownDocumentSaveBridge(document: document, url: url)
        bridge.allowsSaveBack = { [weak detector] in detector?.allowsSaveBack ?? true }
        bridge.onDidWrite = { [weak detector] written in
            detector?.noteSaveCompleted(writtenContent: written)
        }
        return bridge
    }

    @MainActor
    private func dismissPresentedEditor() {
        currentSaveBridge?.saveSynchronously()
        currentDetector?.stop()
        currentDetector = nil
        currentSaveBridge = nil
        currentPresentedNav = nil
        edgeSwipeRecognizer = nil
        dismiss(animated: true)
    }

    @MainActor
    private func installEdgeSwipeDismiss(on view: UIView) {
        let pan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleEdgeSwipeDismiss(_:)))
        pan.edges = .left
        view.addGestureRecognizer(pan)
        self.edgeSwipeRecognizer = pan
    }

    @MainActor
    @objc private func handleEdgeSwipeDismiss(_ recognizer: UIScreenEdgePanGestureRecognizer) {
        guard recognizer.state == .ended || recognizer.state == .recognized else { return }
        dismissPresentedEditor()
    }

    /// Flush any in-flight saves for the currently presented document.
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

    /// DC-1 — template-only system create delegate. Materialize an empty
    /// `.md` in `NSTemporaryDirectory()` and hand it to the system with
    /// `.copy` import mode. The system copies the template into the
    /// folder the user is currently browsing, presents its inline rename
    /// UI, and on confirm opens the file through the normal open-document
    /// delegate path. Markus contributes no directory choice, no name, no
    /// deferred-write, and no fallback/probe logic.
    func documentBrowser(_ controller: UIDocumentBrowserViewController,
                         didRequestDocumentCreationWithHandler importHandler: @escaping (URL?, UIDocumentBrowserViewController.ImportMode) -> Void) {
        let templateURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Untitled-\(UUID().uuidString).md")
        do {
            try Data().write(to: templateURL, options: [.atomic])
            importHandler(templateURL, .copy)
        } catch {
            // Framework contract: if the template cannot be materialized,
            // complete with nil + .none so the browser doesn't hang.
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
