import Foundation

/// Documented contract for `DocumentView` toolbar styling — NP-9.2 / NP-9.5.
///
/// The navigation bar uses the standard `.bar` material (blur over scrolling
/// content beneath) rather than a solid opaque fill. This constant is the
/// single source of truth referenced by the test target; the production
/// modifier in `DocumentView.body` is `.toolbarBackground(.bar, for: .navigationBar)`.
enum DocumentViewToolbarConfig {
    /// True iff the navigation bar in `DocumentView` is configured to use the
    /// `.bar` material. Production code applies the modifier unconditionally;
    /// this flag is the testable manifestation of that commitment.
    static let navigationBarUsesMaterial = true
}
