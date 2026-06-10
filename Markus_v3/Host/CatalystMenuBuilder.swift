#if targetEnvironment(macCatalyst)
import UIKit

/// Mac Catalyst menu-bar construction (mac-catalyst-shell-14, design
/// Component A). Called from `AppDelegate.buildMenu(with:)` to reshape the
/// default Catalyst menu structure into the three Markus menus:
///
///     File  → Open… ⌘O,  Save ⌘S,  Close ⌘W      (no New)
///     Edit  → system-standard Undo / Redo / Cut / Copy / Paste / Select All
///     View  → Toggle Preview ⌘P  (stable title; not ⌘/)
///
/// Each Markus item is a UICommand/UIKeyCommand whose action selector resolves
/// on the responder chain. Enablement is therefore *structural* (S-1): when the
/// responder that implements the selector is in the chain, the item is enabled;
/// otherwise the system grays it out. The seam selectors match the existing
/// `EditorKeyCommandHostingController` handlers (`handleSave` / `handleClose` /
/// `handleTogglePreview`) and a new `BrowserHostController.handleFileOpenMenu(_:)`
/// for File → Open, so menu invocation and ⌘-chord invocation reach the same
/// handles (FM-1, S-2).
enum CatalystMenuBuilder {

    /// Selectors targeted by the menu items. String-keyed because the
    /// generic-typed `EditorKeyCommandHostingController<Content>` cannot be
    /// referenced in a top-level `#selector(...)` expression without binding a
    /// content type; the Obj-C runtime resolves by selector name.
    static let openSelector = Selector(("handleFileOpenMenu:"))
    static let saveSelector = Selector(("handleSave"))
    static let closeSelector = Selector(("handleClose"))
    static let togglePreviewSelector = Selector(("handleTogglePreview"))

    /// Apply the Markus menu reshape onto the given builder. Called from
    /// `AppDelegate.buildMenu(with:)`.
    static func build(with builder: UIMenuBuilder) {
        // Only the system menu builder owns the menu bar.
        guard builder.system == .main else { return }

        // Strip menus that Markus's shape declares out of scope (Format,
        // New Scene, Open Recent).
        builder.remove(menu: .format)
        builder.remove(menu: .newScene)
        builder.remove(menu: .openRecent)

        // File menu — Open…, Save, Close (no New).
        let openCommand = UIKeyCommand(title: "Open…",
                                       action: openSelector,
                                       input: "o",
                                       modifierFlags: .command)
        let saveCommand = UIKeyCommand(title: "Save",
                                       action: saveSelector,
                                       input: "s",
                                       modifierFlags: .command)
        let closeCommand = UIKeyCommand(title: "Close",
                                        action: closeSelector,
                                        input: "w",
                                        modifierFlags: .command)
        let fileMenu = UIMenu(title: "File",
                              image: nil,
                              identifier: .file,
                              options: [],
                              children: [openCommand, saveCommand, closeCommand])
        builder.replace(menu: .file, with: fileMenu)

        // View menu — Toggle Preview (stable title; ⌘P).
        let togglePreviewCommand = UIKeyCommand(title: "Toggle Preview",
                                                action: togglePreviewSelector,
                                                input: "p",
                                                modifierFlags: .command)
        let viewMenu = UIMenu(title: "View",
                              image: nil,
                              identifier: .view,
                              options: [],
                              children: [togglePreviewCommand])
        builder.replace(menu: .view, with: viewMenu)

        // The Edit menu is intentionally left at the system default — Undo,
        // Redo, Cut, Copy, Paste, Select All — deferring entirely to the text
        // responder (AC-1.3, AC-2.4, C-1.3).
    }
}
#endif
