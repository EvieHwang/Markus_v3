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
        pendingSave?.cancel()
        pendingSave = nil
        Self.write(text: document.text, to: url)
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let url = self.url
        let docRef = document
        pendingSave = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.idleDelay)
                try Task.checkCancellation()
                Self.write(text: docRef.text, to: url)
                self?.pendingSave = nil
            } catch {
                // cancelled — superseded by a later edit, or torn down.
            }
        }
    }

    private static func write(text: String, to url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try Data(text.utf8).write(to: url, options: [.atomic])
        } catch {
            // Save failed. Wave 3 swallows; a follow-up will route this into
            // SaveStatusObserver / the alert path that DocumentView already
            // surfaces. Recorded in features/resume-and-create-2/build-deviations.md.
        }
    }
}
