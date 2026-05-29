import Foundation

/// The terminal outcome of one `MarkdownDocumentSaveBridge` write attempt
/// (DC-1, save-bridge-hardening-9).
///
/// Every write attempt the bridge performs — debounced or `saveSynchronously()` —
/// resolves to exactly one of these. The host observes the resolution and routes
/// failures to the save-status surface (`ActiveAlert.saveFailed`); success
/// continues to fire the existing two success-only side effects
/// (`MarkdownDocument.lastKnownDiskContent` update + the detector's settle-window
/// open via `noteSaveCompleted`).
///
/// `gatedOut` is **not** a write attempt — it is the not-attempted state when the
/// DC-22 `allowsSaveBack()` gate refused before any I/O. It is distinct from
/// `success` and `failure` so callers can tell "we never tried" from "we tried
/// and failed" (DC-4 / NR-4).
enum WriteOutcome: Equatable {
    case success
    case failure(message: String)
    case gatedOut

    static func == (lhs: WriteOutcome, rhs: WriteOutcome) -> Bool {
        switch (lhs, rhs) {
        case (.success, .success), (.gatedOut, .gatedOut):
            return true
        case let (.failure(l), .failure(r)):
            return l == r
        default:
            return false
        }
    }
}
