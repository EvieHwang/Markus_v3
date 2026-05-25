import Foundation
import UIKit

/// Handles the browser's "Create Document" affordance (design C4 /
/// DC-6/DC-8/DC-9/DC-10/DC-12).
///
/// Bound to `BrowserHostController.createDocumentRequestHandler` in
/// `SceneDelegate`. On invocation:
///
/// 1. Asks `CreateTargetResolver` for the resolved target directory
///    (last-opened dir if reachable+writable, else local Documents).
/// 2. Asks `NameProbe` for the collision-free `Untitled[ n].md` URL in
///    that directory.
/// 3. Calls `importHandler(nil, .none)` to abandon the system's create
///    dance (we are NOT materializing a file at the system's temp
///    location).
/// 4. Asks the host to present a fresh, in-memory `MarkdownDocument`
///    directly into the raw editor (keyboard active, deferred-write).
///
/// The deferred-write semantics (no on-disk trace until first keystroke,
/// name not consumed on abandon) are implemented inside
/// `MarkdownDocumentSaveBridge` (its `deferUntilFirstNonEmpty` mode).
@MainActor
final class CreateDocumentHandler {

    private let store: LastFileStore
    private weak var host: BrowserHostController?

    init(host: BrowserHostController, store: LastFileStore = LastFileStore()) {
        self.host = host
        self.store = store
    }

    /// Binds this handler to its host. After this call the host will
    /// route `documentBrowser(_:didRequestDocumentCreationWithHandler:)`
    /// through `handle(importHandler:)`.
    func install() {
        host?.createDocumentRequestHandler = { [weak self] importHandler in
            self?.handle(importHandler: importHandler)
        }
    }

    private func handle(importHandler: @escaping BrowserHostController.CreateImportHandler) {
        guard let host = self.host else {
            importHandler(nil, .none)
            return
        }

        let resolver = CreateTargetResolver(lastDirectoryProvider: LastFileStoreDirectoryAdapter(store: store))
        let targetDir: URL
        do {
            targetDir = try resolver.resolveTargetDirectory()
        } catch {
            importHandler(nil, .none)
            return
        }

        let newFileURL = NameProbe.availableName(in: targetDir)

        // Cancel the system creation cleanly; we present the editor
        // ourselves with a fresh in-memory document. The on-disk write is
        // deferred to first keystroke inside MarkdownDocumentSaveBridge.
        importHandler(nil, .none)

        let document = MarkdownDocument()
        host.presentDocument(
            at: newFileURL,
            initialMode: .raw,
            focusEditorOnAppear: true,
            deferUntilFirstNonEmpty: true,
            preloadedDocument: document
        )
    }
}

/// Bridges `LastFileStore` to the `LastDirectoryProviding` protocol that
/// `CreateTargetResolver` consults. Returns the *containing directory* of
/// the last-opened file's URL, not the file URL itself.
struct LastFileStoreDirectoryAdapter: LastDirectoryProviding {
    let store: LastFileStore

    func resolveLastDirectory() -> URL? {
        store.resolveLastOpened()?.deletingLastPathComponent()
    }
}
