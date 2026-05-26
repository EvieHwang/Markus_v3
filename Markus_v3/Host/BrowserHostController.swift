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
    /// the browser pick callback, the resume branch (T-006), and the
    /// create-document handler (T-007). Reuses the unchanged
    /// `DocumentView` as the editor surface.
    ///
    /// - Parameters:
    ///   - url: the file to open. Must be a `.md`/`.markdown` file already
    ///     resolvable in the current security scope.
    ///   - initialMode: hint for the editor's first mode. The walking
    ///     skeleton already chooses an initial mode in `.onAppear` (large
    ///     file → `.raw`); the create path uses this to request `.raw` for
    ///     newly created files (DC-8).
    ///   - focusEditorOnAppear: when true (create flow) the editor's text
    ///     view becomes first responder on first appearance, so the
    ///     keyboard is active (BR-12 / DC-8).
    ///   - deferUntilFirstNonEmpty: when true (create flow) the save bridge
    ///     does not write the file to disk until the user types at least
    ///     one character (BR-13 / DC-9).
    ///   - preloadedDocument: when non-nil, the host uses this in-memory
    ///     document instead of reading file contents from `url`. Used by
    ///     the create flow (the new file does not yet exist on disk).
    ///   - animated: passed to `present`. Default true.
    @MainActor
    func presentDocument(at url: URL,
                         initialMode: DocumentMode? = nil,
                         focusEditorOnAppear: Bool = false,
                         deferUntilFirstNonEmpty: Bool = false,
                         preloadedDocument: MarkdownDocument? = nil,
                         animated: Bool = true) {
        let document: MarkdownDocument
        if let preloadedDocument {
            document = preloadedDocument
        } else if let loaded = Self.loadMarkdownDocument(at: url) {
            document = loaded
        } else {
            return
        }

        // DC-1 — the owned change detector, created beside the save bridge and
        // wired to it through the shared `MarkdownDocument` (last-known-disk) and
        // the suspension gate (DC-22). Settle suppression can be disabled for
        // deterministic UI tests via `-uitest-suppress-settle`.
        let settleEnabled = !ProcessInfo.processInfo.arguments.contains("-uitest-suppress-settle")
        let detector = ChangeDetector(document: document, url: url, settleEnabled: settleEnabled)
        self.currentDetector = detector

        let bridge = makeSaveBridge(document: document,
                                    url: url,
                                    deferUntilFirstNonEmpty: deferUntilFirstNonEmpty,
                                    detector: detector)
        self.currentSaveBridge = bridge

        // DC-13/BR-5 — Keep Mine and Save As ask the bridge for the single
        // deliberate write; suspension was already lifted by the resolution.
        detector.requestImmediateWrite = { [weak self] in
            self?.currentSaveBridge?.saveSynchronously()
        }
        // DC-19/BR-8 — on a followed move, retarget the save bridge to the new
        // location and update the resume reference so a later launch resumes there.
        detector.onRetarget = { [weak self, weak detector] newURL in
            guard let self, let detector else { return }
            let newBridge = self.makeSaveBridge(document: document,
                                                url: newURL,
                                                deferUntilFirstNonEmpty: false,
                                                detector: detector)
            self.currentSaveBridge = newBridge
            self.lastFileStore.recordLastOpened(newURL)
        }

        let onBack: () -> Void = { [weak self] in
            self?.dismissPresentedEditor()
        }

        let editor = DocumentView(
            document: document,
            fileURL: url,
            initialMode: initialMode,
            focusEditorOnAppear: focusEditorOnAppear,
            detector: detector,
            onBack: onBack
        )
        let host = UIHostingController(rootView: editor)
        let nav = UINavigationController(rootViewController: host)
        nav.modalPresentationStyle = .fullScreen
        self.currentPresentedNav = nav

        installEdgeSwipeDismiss(on: nav.view)

        present(nav, animated: animated) { [weak self] in
            // For pre-existing files (no deferred-write), the open path
            // records-on-open via didOpenDocument. For deferred-write
            // creates, didOpenDocument fires later (via onFirstPersist)
            // when the file first hits disk.
            if !deferUntilFirstNonEmpty {
                self?.didOpenDocument?(url)
            }
        }
    }

    /// Builds a save bridge wired to the detector: it consults the suspension gate
    /// before writing (DC-22), and on a successful write resets last-known-disk and
    /// opens the settle window (DC-9/DC-6).
    @MainActor
    private func makeSaveBridge(document: MarkdownDocument,
                                url: URL,
                                deferUntilFirstNonEmpty: Bool,
                                detector: ChangeDetector) -> MarkdownDocumentSaveBridge {
        let bridge = MarkdownDocumentSaveBridge(
            document: document,
            url: url,
            deferUntilFirstNonEmpty: deferUntilFirstNonEmpty
        )
        bridge.allowsSaveBack = { [weak detector] in detector?.allowsSaveBack ?? true }
        bridge.onDidWrite = { [weak detector] written in
            detector?.noteSaveCompleted(writtenContent: written)
        }
        bridge.onFirstPersist = { [weak self, weak detector] persistedURL in
            detector?.noteFirstPersist(content: document.text)
            // For a deferred-write create, the file becoming real on disk for the
            // first time also makes it the new last-opened reference (DC-10/BR-15).
            self?.didOpenDocument?(persistedURL)
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

    /// Installs a screen-edge pan recognizer on the presented editor's view
    /// to emulate the "interactive pop" gesture for the modal-presented
    /// editor (DC-14). `UINavigationController`'s built-in
    /// `interactivePopGestureRecognizer` only fires when the stack has more
    /// than one view controller; here the editor is the root, so we
    /// supplement with a dedicated edge-pan that triggers dismissal.
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
