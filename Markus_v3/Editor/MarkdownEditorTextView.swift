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
        // SF Mono at a fixed prose size (NP-1.2 / OOS-2: exempt from Dynamic Type).
        // Named font keeps the SF Mono guarantee explicit; the system-monospace
        // fallback is the documented contract when the named face cannot be loaded.
        let size: CGFloat = 17
        let monoFont = UIFont(name: "SFMono-Regular", size: size)
            ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        font = monoFont
        typingAttributes[.font] = monoFont
    }
}
