import SwiftUI
import UIKit
import MarkdownUI

/// Builds the `MarkdownUI.Theme` applied to `RenderedView`.
///
/// Body text uses the current `UIFont.preferredFont(forTextStyle: .body)`
/// point size so the rendered text scales with the user's Dynamic Type
/// preference (NP-2.1 / NP-2.2 / NPC-2). Headings use em-relative sizes so
/// they scale with the same base.
///
/// The theme is constructed at body-build time inside `RenderedView` (which
/// reads `@Environment(\.dynamicTypeSize)`), so a Dynamic Type change in
/// Settings re-renders the view with the new size on next appearance.
enum MarkdownThemeFactory {

    /// The body font that the theme's text style targets. Exposed for tests so
    /// `RenderedViewTypographyProbe` can verify the contract without inspecting
    /// the SwiftUI view tree.
    static func bodyFont() -> UIFont {
        UIFont.preferredFont(forTextStyle: .body)
    }

    /// The expected effective heading font at the given level (1 = largest).
    /// Mirrors the em factors used in `makeTheme()`. Exposed for tests.
    static func headingFont(level: Int) -> UIFont {
        let baseSize = bodyFont().pointSize
        let factor: CGFloat
        switch level {
        case 1: factor = 2.0
        case 2: factor = 1.5
        case 3: factor = 1.25
        case 4: factor = 1.0
        case 5: factor = 0.875
        case 6: factor = 0.85
        default: factor = 1.0
        }
        return UIFont.systemFont(ofSize: baseSize * factor, weight: .semibold)
    }

    /// The Markdown theme applied to `RenderedView`'s `Markdown(...)` call.
    static func makeTheme() -> Theme {
        let baseSize = bodyFont().pointSize
        return Theme()
            .text {
                FontProperties(family: .system(), size: baseSize)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.85))
            }
            .strong {
                FontWeight(.semibold)
            }
            .emphasis {
                FontStyle(.italic)
            }
            .heading1 { configuration in
                configuration.label
                    .markdownMargin(top: 24, bottom: 16)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(2.0))
                    }
            }
            .heading2 { configuration in
                configuration.label
                    .markdownMargin(top: 24, bottom: 16)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.5))
                    }
            }
            .heading3 { configuration in
                configuration.label
                    .markdownMargin(top: 24, bottom: 16)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.25))
                    }
            }
            .heading4 { configuration in
                configuration.label
                    .markdownMargin(top: 24, bottom: 16)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                    }
            }
            .heading5 { configuration in
                configuration.label
                    .markdownMargin(top: 24, bottom: 16)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(0.875))
                    }
            }
            .heading6 { configuration in
                configuration.label
                    .markdownMargin(top: 24, bottom: 16)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(0.85))
                    }
            }
    }
}
