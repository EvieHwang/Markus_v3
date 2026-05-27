import Foundation

/// Documented contract for the share button in `DocumentView` (design C5).
///
/// The share button is conditioned on the current `DocumentMode` and the
/// presence of an existing file on disk. Gating logic lives here as a pure
/// helper so the production toolbar and the test target consume the same
/// rules.
enum DocumentViewShareConfig {

    /// SF Symbol used for the share button. NP-8.1 fixes this.
    static let shareButtonSFSymbol = "square.and.arrow.up"

    /// True iff the share button is present in the toolbar for the given mode.
    /// NPC-11: absent in raw mode.
    static func shareButtonVisible(mode: DocumentMode) -> Bool {
        mode == .rendered
    }

    /// True iff the share sheet can be presented for the given URL — the URL
    /// is non-nil and the file exists on disk. Used by the share button's tap
    /// handler as the deleted-file / nil-URL guard (NP-8.6, NPC-12, NP-14).
    static func canPresentShare(for fileURL: URL?) -> Bool {
        guard let url = fileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}
