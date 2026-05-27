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

    /// True iff the share sheet can be presented for the given URL. We do
    /// **not** check file existence here: the document URL is typically
    /// security-scoped (Files / iCloud / sync providers), and
    /// `FileManager.fileExists` returns `false` for those without the scope
    /// active — silently blocking the share. The actual deleted-file guard
    /// lives in the temp-file copy step the caller performs (NP-8.6, NP-14);
    /// a failed copy returns silently and the sheet does not present. The
    /// caller is responsible for nil-URL handling via this gate (NPC-12).
    static func canPresentShare(for fileURL: URL?) -> Bool {
        fileURL != nil
    }
}
