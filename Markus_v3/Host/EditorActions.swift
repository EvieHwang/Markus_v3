import Foundation

/// Editor-session-scoped action handles wired between SwiftUI `DocumentView`,
/// the UIKit host (`BrowserHostController`), and the hardware-keyboard
/// shortcut provider (`EditorKeyCommandHostingController`) — see
/// ipad-expansion-13, design Component A.
///
/// Each closure is a *trigger onto an existing action*, never a second
/// implementation (FM-1). `DocumentView` owns `toggleMode` and `saveNow`
/// (S-2); the host owns `closeEditor` (S-3). The presence/absence of an
/// installed closure mirrors the editor session lifetime: closures are wired
/// when the editor is presented and discarded when it is dismissed, so at the
/// browser the provider is structurally inert (S-1).
final class EditorActions {

    /// Toggle raw ↔ rendered using the *existing* DocumentView transition for
    /// the current mode (tap-to-edit for rendered→raw; eye-button /
    /// switchToRenderedFromSwipe for raw→rendered). Set by `DocumentView` on
    /// appear; remains `nil` if no editor is presented.
    var toggleMode: (() -> Void)?

    /// Invoke the existing save flow (`triggerSave()` → `document.markDirty()`).
    /// Adds no new save mechanism (FM-1, FM-9). Set by `DocumentView` on appear.
    var saveNow: (() -> Void)?

    /// Run the existing `onBack` flow → `BrowserHostController.dismissPresentedEditor()`
    /// (synchronous save → detector stop → session teardown → dismiss). Set by
    /// the host when it presents an editor session.
    var closeEditor: (() -> Void)?
}
