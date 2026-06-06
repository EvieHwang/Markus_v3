import SwiftUI
import UIKit

/// `UIHostingController` subclass that vends the three hardware-keyboard
/// commands (⌘P / ⌘W / ⌘S) for the presented editor session — see
/// ipad-expansion-13, design Component A.
///
/// The controller sits **above the raw `UITextView`** on the responder chain
/// inside the presented editor, so the OS chain-walk finds a matching ⌘-chord
/// here before the text view treats it as input (S-4 / FM-3). A plain
/// `UITextView` binds none of ⌘P/⌘W/⌘S as editing actions, so the chain
/// reaches this controller naturally.
///
/// Lifetime is bound to the editor session (S-1): the host constructs an
/// instance when presenting the editor and discards it on dismiss. At the
/// browser (no editor presented) the editor commands are structurally absent,
/// making the ⌘W browser edge case a no-op by construction.
///
/// The controller is *only* a router: it holds no mode/save/close logic. Each
/// command invokes the matching closure on `EditorActions`, which routes to
/// the existing DocumentView or host action (FM-1).
final class EditorKeyCommandHostingController<Content: View>: UIHostingController<Content> {

    /// Shared action handles wired by the host and `DocumentView`. Held
    /// strongly so the closures' captured state survives for the editor
    /// session's lifetime.
    let actions: EditorActions

    init(rootView: Content, actions: EditorActions) {
        self.actions = actions
        super.init(rootView: rootView)
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported for EditorKeyCommandHostingController")
    }

    /// Required for `keyCommands` to be consulted while no other responder is
    /// first responder (e.g. on initial appearance in rendered mode). The text
    /// view, when it becomes first responder, sits *below* this controller on
    /// the chain — the OS still walks up here for ⌘-chord matches.
    override var canBecomeFirstResponder: Bool { true }

    /// Become first responder every time the editor reappears so the OS
    /// starts the ⌘-chord chain walk at *this* controller rather than at
    /// the window's rootViewController (the browser host). Without this,
    /// an editor presented with nothing focused leaves chord delivery at
    /// the root VC — which vends no editor commands — so ⌘P/⌘W/⌘S would
    /// silently no-op until the text view took focus.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        _ = becomeFirstResponder()
    }

    /// The three commands the editor session vends (C-A.6 / AC-5.1).
    /// Returned as a freshly-built array each access so the system observes
    /// stable identities per `UIKeyCommand`.
    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(title: "Toggle Preview",
                         action: #selector(handleTogglePreview),
                         input: "p",
                         modifierFlags: .command),
            UIKeyCommand(title: "Close",
                         action: #selector(handleClose),
                         input: "w",
                         modifierFlags: .command),
            UIKeyCommand(title: "Save",
                         action: #selector(handleSave),
                         input: "s",
                         modifierFlags: .command),
        ]
    }

    @objc func handleTogglePreview() { actions.toggleMode?() }
    @objc func handleClose() { actions.closeEditor?() }
    @objc func handleSave() { actions.saveNow?() }
}
