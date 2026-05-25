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
        let bodySize = UIFont.preferredFont(forTextStyle: .body).pointSize
        font = UIFont.monospacedSystemFont(ofSize: bodySize, weight: .regular)
    }
}
