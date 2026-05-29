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

    /// DC-22 — save-back gate. When this returns false (a collision/deletion has
    /// been classified for the open document), the bridge does not write: the
    /// disagreeing on-disk content stays recoverable until the user resolves.
    /// Default allows all writes.
    var allowsSaveBack: () -> Bool = { true }

    /// DC-9 — invoked after a successful write with the bytes written, so the
    /// detector can reset last-known-disk and open the settle window (DC-6).
    var onDidWrite: ((String) -> Void)?

    /// DC-1 (save-bridge-hardening-9) — paired with `onDidWrite`: invoked when a
    /// write attempt throws (atomic write or, in T-003, coordinator acquisition).
    /// The host routes this to `ActiveAlert.saveFailed`. Failure here does NOT
    /// fire the success-only side effects (DC-2): `lastKnownDiskContent` is not
    /// advanced and the settle window is not opened, so the buffer remains dirty
    /// against last-known-disk and a subsequent successful write clears it via
    /// the normal success path (DC-3 / BR-1.4–1.6).
    var onDidFailWrite: ((Error) -> Void)?

    init(document: MarkdownDocument, url: URL) {
        self.document = document
        self.url = url
        subscription = document.$text
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleSave()
            }
    }

    deinit {
        pendingSave?.cancel()
    }

    /// Cancels any pending debounce and writes the current text immediately.
    func saveSynchronously() {
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
        // DC-4 (save-bridge-hardening-9) / DC-22 (external-change-5) — gate FIRST,
        // BEFORE entering the coordinator. A classified collision/deletion
        // suspends save-back; a gated-out attempt pays no coordination cost and
        // is neither a success nor a failure on the outcome bus (NR-4). The gate
        // is re-checked here at the write edge because a collision may have been
        // classified after this save was scheduled (the classify→present gap).
        guard allowsSaveBack() else { return }

        let textToWrite = document.text
        var writeError: Error?
        var coordError: NSError?

        // DC-5 — every write attempt (debounced and immediate-flush) runs inside
        // the coordinator so the bridge serializes with the rest of the
        // coordinated file world (iCloud, other presenters, our own detector).
        // Mirrors the coordinated-read pattern in
        // ChangeDetector.coordinatedReadData.
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: url, options: [], error: &coordError) { writeURL in
            // DC-8 — security-scoped access is balanced across BOTH the success
            // and failure paths (defer runs even if the atomic write throws), so
            // repeated failing writes do not leak scoped accesses.
            let scoped = writeURL.startAccessingSecurityScopedResource()
            defer { if scoped { writeURL.stopAccessingSecurityScopedResource() } }
            do {
                // DC-7 — atomic-write semantics inside the coordinated block:
                // disk is either pre-write or post-write, never partial. A throw
                // here is a clean failure surfaced via the outcome bus.
                try Data(textToWrite.utf8).write(to: writeURL, options: [.atomic])
            } catch {
                writeError = error
            }
        }

        // DC-6 — coordinated-or-fail: a coordinator-acquisition error (timeout,
        // contention, presenter veto) resolves as failure on the outcome bus;
        // there is NO uncoordinated best-effort fallback.
        if let coordError {
            onDidFailWrite?(coordError)
            return
        }
        if let writeError {
            // DC-1 / DC-2 — atomic-write throw inside the coordinated block;
            // success-only side effects do not fire (lastKnownDiskContent is not
            // advanced; settle window does not open). Buffer remains dirty
            // against last-known-disk; a subsequent successful write clears it
            // via the normal success path (DC-3 / BR-1.6).
            onDidFailWrite?(writeError)
            return
        }
        // DC-9 — a successful coordinated write is observationally
        // indistinguishable from the pre-hardening atomic write on the steady-
        // state path: settle window opens and last-known-disk refreshes via
        // onDidWrite. Coordination's cost is only paid under actual contention.
        onDidWrite?(textToWrite)
    }
}
