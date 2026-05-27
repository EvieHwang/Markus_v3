import Foundation
import Combine
import UIKit

/// Bridges in-memory `MarkdownDocument` text changes to on-disk writes for
/// the currently presented file. Lives in the host (C0) because the SwiftUI
/// `DocumentGroup` it replaces was previously the save-back path; without
/// `DocumentGroup`, no one else watches for edits.
///
/// Idle-debounce save: subscribes to `MarkdownDocument.$text` and, on every
/// change after the initial load, debounces 500ms (matching the existing
/// `AutosaveCoordinator` cadence) before writing the file atomically.
/// `saveSynchronously()` is the immediate-flush path for backgrounding and
/// host teardown.
///
/// Hard-seam compliance: neither `MarkdownDocument` nor `DocumentView` is
/// modified. The bridge attaches *underneath* the editor surface and is
/// owned by the host (`BrowserHostController`).
@MainActor
final class MarkdownDocumentSaveBridge {

    static let idleDelay: Duration = .milliseconds(500)

    private let document: MarkdownDocument
    private let url: URL
    private var subscription: AnyCancellable?
    private var pendingSave: Task<Void, Never>?

    /// When true, writes are deferred until the document's text has been
    /// non-empty at least once (i.e. the user has typed something into a
    /// freshly created file). Once the document persists, the bridge
    /// reverts to normal write-on-change behavior. Set by the create flow
    /// for new files (T-007 / DC-9).
    private let deferUntilFirstNonEmpty: Bool

    /// Tracks whether we have seen any non-empty text yet. Becomes true on
    /// the first change to a non-empty value; from that moment on, writes
    /// proceed normally (including saving an empty document, which is the
    /// user erasing all content).
    private var hasSeenContent: Bool

    /// Called once when the deferred write actually materializes the new
    /// file for the first time (i.e. transition from "never written" to
    /// "written"). Lets the host record the file as the last-opened
    /// reference (DC-10 / BR-15).
    var onFirstPersist: ((URL) -> Void)?

    /// DC-22 — save-back gate. When this returns false (a collision/deletion has
    /// been classified for the open document), the bridge does not write: the
    /// disagreeing on-disk content stays recoverable until the user resolves.
    /// Default allows all writes.
    var allowsSaveBack: () -> Bool = { true }

    /// DC-9 — invoked after a successful write with the bytes written, so the
    /// detector can reset last-known-disk and open the settle window (DC-6).
    var onDidWrite: ((String) -> Void)?

    init(document: MarkdownDocument,
         url: URL,
         deferUntilFirstNonEmpty: Bool = false) {
        self.document = document
        self.url = url
        self.deferUntilFirstNonEmpty = deferUntilFirstNonEmpty
        self.hasSeenContent = deferUntilFirstNonEmpty ? !document.text.isEmpty : true
        subscription = document.$text
            .dropFirst()
            .sink { [weak self] newText in
                self?.observed(newText: newText)
            }
    }

    private func observed(newText: String) {
        if deferUntilFirstNonEmpty && !hasSeenContent {
            if newText.isEmpty {
                return
            }
            hasSeenContent = true
        }
        scheduleSave()
    }

    deinit {
        pendingSave?.cancel()
    }

    /// Cancels any pending debounce and writes the current text immediately.
    func saveSynchronously() {
        // Honor the deferred-write contract: don't materialize an untyped
        // (still-empty) new file on background/teardown either (DC-9 /
        // BR-13 / BR-24).
        guard hasSeenContent else { return }
        // DC-22 — never flush over a classified-but-unresolved collision/deletion.
        guard allowsSaveBack() else { return }
        pendingSave?.cancel()
        pendingSave = nil
        writeNow()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.idleDelay)
                try Task.checkCancellation()
                self?.writeNow()
                self?.pendingSave = nil
            } catch {
                // cancelled — superseded by a later edit, or torn down.
            }
        }
    }

    private func writeNow() {
        // DC-22 — re-check at the write edge: a collision may have been classified
        // after this save was scheduled (the classify→present gap).
        guard allowsSaveBack() else { return }
        let didExistBefore = FileManager.default.fileExists(atPath: url.path)
        let textToWrite = document.text
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        // Coordinated write so the file provider's metadata catalog (modification
        // date, etc.) updates and any registered NSFilePresenter is informed.
        // Mirrors the coordinated-read pattern in ChangeDetector.
        var coordError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: url, options: [.forReplacing], error: &coordError) { writeURL in
            do {
                try Data(textToWrite.utf8).write(to: writeURL, options: [.atomic])
            } catch {
                writeError = error
            }
        }
        if coordError != nil || writeError != nil {
            // Save failed. Wave 3 swallows; a follow-up will route this into
            // SaveStatusObserver / the alert path that DocumentView already
            // surfaces. Recorded in features/resume-and-create-2/build-deviations.md.
            return
        }
        // DC-9 — a successful write is now the last-known-disk content, and a
        // settle trigger (DC-6) so the sync echo of our own write is suppressed.
        onDidWrite?(textToWrite)
        if !didExistBefore {
            onFirstPersist?(url)
        }
    }
}
