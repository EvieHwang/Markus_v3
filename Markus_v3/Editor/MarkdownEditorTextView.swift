import UIKit

final class MarkdownEditorTextView: UITextView {

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configureTraits()
        configureAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureTraits()
        configureAppearance()
    }

    private func configureTraits() {
        smartQuotesType = .no
        smartDashesType = .no
        spellCheckingType = .yes
        autocorrectionType = .yes
    }

    private func configureAppearance() {
        // SF Mono sized 2pt smaller than the body Dynamic Type size:
        // SF Mono's fixed-width cells make it visually heavier than SF Pro at
        // equal point sizes, so stepping it down compensates and the editor
        // reads at roughly the same density as the rendered view.
        let size = UIFont.preferredFont(forTextStyle: .body).pointSize - 2
        let monoFont = UIFont(name: "SFMono-Regular", size: size)
            ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        font = monoFont
        typingAttributes[.font] = monoFont
    }
}
