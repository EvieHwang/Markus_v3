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
    private var currentSaveFailedRouter: SaveFailedAlertRouter?
    private var currentPresentedNav: UINavigationController?
    private var edgeSwipeRecognizer: UIScreenEdgePanGestureRecognizer?

    /// open-path-hardening-10 — current presented `MarkdownDocument`, if any.
    /// Read-only seam for spec tests asserting DC-10's "prior document
    /// survives a failed second pick." Set on successful open; cleared on
    /// dismiss.
    private(set) var activeDocument: MarkdownDocument?

    /// open-path-hardening-10 — host-level open-path alert channel (DC-6a).
    /// Written by the load pipeline on every failure terminal; observed by
    /// spec tests and (in production) drives a UIAlertController presented
    /// from `self`. The DocumentView retains its own `activeAlert` for
    /// running-document surfaces — these channels are independent (DC-10).
    var openPathAlert: ActiveAlert? {
        didSet {
            guard openPathAlert != oldValue else { return }
            if openPathAlert != nil {
                presentOpenPathAlertIfPossible()
            }
        }
    }

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
    ///
    /// open-path-hardening-10 — every failure terminal sets `openPathAlert`
    /// and releases the security-scoped resource it acquired (DC-1, DC-9);
    /// `activeDocument` is only mutated on success, so a failed pick after
    /// an opened document does not tear down the prior document (DC-10).
    @MainActor
    func presentDocument(at url: URL, animated: Bool = true) {
        let loadResult = Self.loadMarkdownDocument(at: url)
        switch loadResult {
        case .alert(let alert):
            openPathAlert = alert
            return
        case .document(let document):
            activeDocument = document
            installEditorSession(for: document, at: url, animated: animated)
        }
    }

    @MainActor
    private func installEditorSession(for document: MarkdownDocument,
                                      at url: URL,
                                      animated: Bool) {
        let settleEnabled = !ProcessInfo.processInfo.arguments.contains("-uitest-suppress-settle")
        let detector = ChangeDetector(document: document, url: url, settleEnabled: settleEnabled)
        self.currentDetector = detector

        // T-004 (save-bridge-hardening-9) — per-document router that routes
        // bridge failures to ActiveAlert.saveFailed with single-alert lifecycle,
        // background-latch (DC-13), and conflict-sheet precedence (DC-14). Lives
        // for the editor session; torn down when the document is dismissed.
        let router = SaveFailedAlertRouter()
        self.currentSaveFailedRouter = router

        let bridge = makeSaveBridge(document: document, url: url, detector: detector, router: router)
        self.currentSaveBridge = bridge

        detector.requestImmediateWrite = { [weak self] in
            self?.currentSaveBridge?.saveSynchronously()
        }
        detector.onRetarget = { [weak self, weak detector, weak router] newURL in
            guard let self, let detector else { return }
            let newBridge = self.makeSaveBridge(document: document, url: newURL, detector: detector, router: router)
            self.currentSaveBridge = newBridge
            self.lastFileStore.recordLastOpened(newURL)
        }

        let onBack: () -> Void = { [weak self] in
            self?.dismissPresentedEditor()
        }

        // ipad-expansion-13 — editor-session-scoped action handles (S-1).
        // The host wires `closeEditor` to the same `onBack` the toolbar back
        // button uses (S-3); `DocumentView.onAppear` wires `toggleMode` and
        // `saveNow` (S-2). The provider exists only for the session lifetime.
        let editorActions = EditorActions()
        editorActions.closeEditor = onBack

        let editor = DocumentView(
            document: document,
            fileURL: url,
            detector: detector,
            onBack: onBack,
            saveFailedRouter: router,
            editorActions: editorActions
        )
        let host = EditorKeyCommandHostingController(rootView: editor, actions: editorActions)
        let nav = UINavigationController(rootViewController: host)
        nav.modalPresentationStyle = .fullScreen
        self.currentPresentedNav = nav

        installEdgeSwipeDismiss(on: nav.view)

        present(nav, animated: animated) { [weak self] in
            self?.didOpenDocument?(url)
            // ipad-expansion-13 — make the key-command provider first
            // responder so its `keyCommands` are consulted even before the
            // text view becomes first responder in raw mode.
            _ = host.becomeFirstResponder()
        }
    }

    @MainActor
    private func makeSaveBridge(document: MarkdownDocument,
                                url: URL,
                                detector: ChangeDetector,
                                router: SaveFailedAlertRouter?) -> MarkdownDocumentSaveBridge {
        let bridge = MarkdownDocumentSaveBridge(document: document, url: url)
        bridge.allowsSaveBack = { [weak detector] in detector?.allowsSaveBack ?? true }
        bridge.onDidWrite = { [weak detector, weak router] written in
            detector?.noteSaveCompleted(writtenContent: written)
            // DC-12 / BR-6 — a successful write clears any latched/pending
            // save-failed alert via the router.
            router?.recordSuccess()
        }
        // DC-1 / DC-10 — every classified failure (atomic-write throw or
        // coordinator-acquisition error) is routed through the router into
        // the existing ActiveAlert.saveFailed surface in DocumentView, with
        // the DC-11/DC-13/DC-14/DC-15 lifecycle.
        bridge.onDidFailWrite = { [weak router] error in
            router?.recordFailure(error)
        }
        return bridge
    }

    @MainActor
    private func dismissPresentedEditor() {
        currentSaveBridge?.saveSynchronously()
        currentDetector?.stop()
        currentDetector = nil
        currentSaveBridge = nil
        currentSaveFailedRouter = nil
        currentPresentedNav = nil
        edgeSwipeRecognizer = nil
        activeDocument = nil
        dismiss(animated: true)
    }

    @MainActor
    private func presentOpenPathAlertIfPossible() {
        guard let alert = openPathAlert else { return }
        // Don't stack an alert on top of an existing modal presentation.
        // The presented document (or the conflict sheet) owns the screen
        // when present; the alert state remains for tests to observe and
        // the next browser-idle entry will present it.
        if presentedViewController != nil { return }
        let controller = UIAlertController(
            title: openPathAlertTitle(for: alert),
            message: OpenPathAlertCopy.message(for: alert),
            preferredStyle: .alert
        )
        controller.addAction(UIAlertAction(title: "Dismiss", style: .cancel) { [weak self] _ in
            self?.openPathAlert = nil
        })
        present(controller, animated: true)
    }

    private func openPathAlertTitle(for alert: ActiveAlert) -> String {
        switch alert {
        case .invalidEncoding, .permissionDenied, .fileMovedOrRemoved,
             .couldNotReadFile, .tooLarge:
            return "Couldn't open"
        case .saveFailed, .iCloudDownloadFailed:
            return ""
        }
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

    /// open-path-hardening-10 — four-stage gated open pipeline (DC-1, DC-4).
    /// Returns either a `.document(...)` for the caller to present, or an
    /// `.alert(...)` the caller must route to `openPathAlert` and surface
    /// before yielding control (BR-3.1, BR-3.5).
    @MainActor
    static func loadMarkdownDocument(at url: URL) -> OpenPathLoadResult {
        // Stage 1 — scope acquire.
        let scoped = OpenPathScopeAudit.startAccessing(url)
        defer { OpenPathScopeAudit.stopAccessing(url, didAcquire: scoped) }

        // Stage 2 — size pre-check (attribute only; BR-4.2 pre-read gate).
        let attrs: [FileAttributeKey: Any]
        do {
            attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            return OpenPathLoadPipeline.failureResult(for: error)
        }

        // BR-14 — directory / non-regular URL never reaches the read stage.
        if let fileType = attrs[.type] as? FileAttributeType,
           fileType != .typeRegular && fileType != .typeSymbolicLink {
            return .alert(.couldNotReadFile)
        }
        let byteSize = (attrs[.size] as? NSNumber)?.intValue ?? 0
        guard OpenPathSizeCeiling.admits(byteSize: byteSize) else {
            return .alert(.tooLarge)
        }

        // Stage 3 — coordinated read.
        let bytes: Data
        do {
            bytes = try Data(contentsOf: url)
        } catch {
            return OpenPathLoadPipeline.failureResult(for: error)
        }

        // Stage 4 — strict UTF-8 decode (BOM-retaining; DC-2, DC-3).
        do {
            let wrapper = FileWrapper(regularFileWithContents: bytes)
            let document = try MarkdownDocument(file: wrapper, contentType: .plainText)
            return .document(document)
        } catch {
            return OpenPathLoadPipeline.failureResult(for: error)
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
