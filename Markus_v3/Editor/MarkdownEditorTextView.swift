import UIKit

final class MarkdownEditorTextView: UITextView {

    private var dynamicTypeObserver: NSObjectProtocol?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configureTraits()
        configureAppearance()
        registerDynamicTypeObserver()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureTraits()
        configureAppearance()
        registerDynamicTypeObserver()
    }

    deinit {
        if let token = dynamicTypeObserver {
            NotificationCenter.default.removeObserver(token)
        }
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
        // Floor of 1pt (AC-3.6) keeps WCAG 1.4.4 compliance unconditional
        // for any current or future Dynamic Type category.
        let rawSize = UIFont.preferredFont(forTextStyle: .body).pointSize - 2
        let size = max(1, rawSize)
        let monoFont = UIFont(name: "SFMono-Regular", size: size)
            ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        font = monoFont
        typingAttributes[.font] = monoFont
    }

    private func registerDynamicTypeObserver() {
        dynamicTypeObserver = NotificationCenter.default.addObserver(
            forName: UIContentSizeCategory.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.configureAppearance()
        }
    }
}
