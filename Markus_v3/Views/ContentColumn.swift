import SwiftUI

/// Shared content-column layout decision (ipad-expansion-13, design
/// Component B). Pure function of horizontal size class + available width;
/// returns the resolved usable column width and gutters.
///
/// The cap is a **maximum, not a fixed width** (C-B.3): when the available
/// width is at or below `maxContentWidth`, the column uses the full available
/// width and no gutters appear. In the compact horizontal size class the cap
/// never engages (FM-5).
enum ContentColumnLayout {

    /// Shared maximum content width applied to both editor surfaces in the
    /// regular horizontal size class. ~700pt sits in the focused-writing band
    /// (Pages, iA Writer, Bear), wide enough for comfortable prose lines and
    /// narrow enough to keep saccades short on a full-screen iPad.
    static let maxContentWidth: CGFloat = 700

    struct Resolved: Equatable {
        let usableWidth: CGFloat
        let leadingGutter: CGFloat
        let trailingGutter: CGFloat
        let isCentered: Bool
    }

    /// Resolves the column layout for `availableWidth` under the given size
    /// class. Used by both the unit tests (asserting the layout decision
    /// directly) and the live `ContentColumnModifier` (which applies the
    /// resulting frame in SwiftUI).
    static func resolve(sizeClass: UserInterfaceSizeClass?,
                        availableWidth: CGFloat) -> Resolved {
        switch sizeClass {
        case .regular:
            let usable = min(availableWidth, maxContentWidth)
            let totalGutter = max(0, availableWidth - usable)
            let side = totalGutter / 2
            return Resolved(usableWidth: usable,
                            leadingGutter: side,
                            trailingGutter: side,
                            isCentered: totalGutter > 0)
        default:
            // FM-5 — compact never caps.
            return Resolved(usableWidth: availableWidth,
                            leadingGutter: 0,
                            trailingGutter: 0,
                            isCentered: false)
        }
    }
}

/// View modifier that applies the shared content column to a view. Used
/// identically by both editor surfaces (raw editor + rendered preview), so
/// they draw from one shared maximum width and the same horizontal position
/// (C-B.1, FM-8). The treatment is presentation-only — it touches neither
/// scroll state nor save flow (S-7).
struct ContentColumnModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        let isRegular = horizontalSizeClass == .regular
        // The inner frame caps the column width; `accessibilityElement(
        // children: .contain)` makes the capped region itself a discoverable
        // container so XCUITest's `ContentColumn` lookup finds the column's
        // frame rather than the first text child within it. The outer
        // expander centers the column when the available width exceeds the
        // cap, and is a no-op below it.
        content
            .frame(maxWidth: isRegular ? ContentColumnLayout.maxContentWidth : .infinity,
                   alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ContentColumn")
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

extension View {
    /// Apply the shared, size-class-aware content column to a view.
    func contentColumn() -> some View {
        modifier(ContentColumnModifier())
    }
}
