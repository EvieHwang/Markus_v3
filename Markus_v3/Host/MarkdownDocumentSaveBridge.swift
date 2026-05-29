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
        // DC-22 — re-check at the write edge: a collision may have been classified
        // after this save was scheduled (the classify→present gap).
        guard allowsSaveBack() else { return }
        let textToWrite = document.text
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try Data(textToWrite.utf8).write(to: url, options: [.atomic])
        } catch {
            // DC-1 (save-bridge-hardening-9) — surface as a classified outcome
            // rather than silently swallowing. DC-2: success-only side effects
            // (lastKnownDiskContent refresh + settle-window open via onDidWrite)
            // do NOT fire on the failure path, so the buffer remains dirty
            // against last-known-disk (DC-3 / BR-1.4) and a subsequent successful
            // write clears it via the normal success path (BR-1.6).
            onDidFailWrite?(error)
            return
        }
        // DC-9 — a successful write is now the last-known-disk content, and a
        // settle trigger (DC-6) so the sync echo of our own write is suppressed.
        onDidWrite?(textToWrite)
    }
}
