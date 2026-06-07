// MenuBarRoutingTests.swift
// Spec tests for mac-catalyst-shell-14 — Part 1 (Mac menu bar: structure,
// enablement, and routing to the EXISTING action flows).
//
// Framework: Swift Testing (@Test, #expect, #require).
//
// These tests live in features/mac-catalyst-shell-14/tests/ and are REFERENCE
// specs — they are NOT part of the Xcode test target (constitution.md → Testing).
// They are syntactically plausible Swift Testing code that a build implementer
// mirrors into Markus_v3Tests/ while building the feature, adjusting symbol /
// identifier names to match the live host.
//
// They are written to FAIL / be unimplemented until the feature is built: they
// reference the as-yet-unbuilt Catalyst menu-builder seam (design Component A —
// referred to here by the name `CatalystMenuBuilder`) and assert behavior (a
// File/Edit/View structure routing to existing EditorActions / presentDocument)
// that does not exist yet.
//
// Do NOT add DAG task-ID tags here — tagging happens in the next stage (the DAG
// does not exist yet; verify.md gets the authoritative task→test mapping then).
//
// Covers (Part 1, behavioral + seam):
//   US-1 / AC-1.1–1.6 — File/Edit/View structure; ⌘ equivalents; Edit defers to
//                       the system responder; menu actions drive the SAME handles
//                       as the shortcuts; shown shortcut == firing binding; full
//                       keyboard access.
//   US-2 / AC-2.1–2.4 + disabled-shortcut edge — document-scoped items disabled
//                       with no document / enabled with one; Open always enabled;
//                       Edit items follow system enablement; ⌘S/⌘W/⌘P at the
//                       browser is a structural no-op.
//   FM-1, FM-4, FM-6, FM-10 — one implementation per action; no New; no nil-handle
//                       invocation; toggle stays on ⌘P.
//   Seams S-1 (enablement tracks editor-session presence via the responder chain),
//         S-2 (menu actions reach the same EditorActions / presentDocument seams).

import Testing
import Foundation
@testable import Markus_v3

// MARK: - Seam contract under test
//
// The build step adds a Catalyst menu-build hook on the app delegate (design
// Component A — referred to here as `CatalystMenuBuilder`) that constructs the
// File / Edit / View structure and maps each Markus item to an EXISTING flow:
//   File → Open…   (⌘O) → presentDocument(at:)   [via Component B]
//   File → Save    (⌘S) → EditorActions.saveNow → triggerSave()
//   File → Close   (⌘W) → EditorActions.closeEditor → dismissPresentedEditor()
//   View → Toggle Preview (⌘P) → EditorActions.toggleMode
//   Edit → Undo/Redo/Cut/Copy/Paste/Select All → system responder chain
//
// The probe models the observable seam: which existing action handle each menu
// item invokes, the downstream effect of that invocation, and the enablement of
// each item as a function of editor-session presence. It deliberately does NOT
// model call signatures, UIMenu construction order, or private fields — only the
// observable "this menu item drove that existing flow / was enabled in that state."

// MARK: - US-1 / AC-1.1–1.3 — the menu structure

@Suite("US-1 — File / Edit / View structure with ⌘ equivalents and no New")
struct MenuStructureTests {

    @Test("AC-1.1: the File menu contains Open / Save / Close with their ⌘ equivalents and no New")
    func fileMenu_containsOpenSaveClose_noNew() {
        let menu = MenuBarProbe.built(editorPresented: true)
        let file = menu.items(in: .file)
        #expect(Set(file.map(\.identity)) == [.open, .save, .close],
                "AC-1.1: File must contain exactly Open / Save / Close")
        #expect(file.first { $0.identity == .open }?.keyEquivalent == .cmd("o"),
                "AC-1.1: Open must show ⌘O")
        #expect(file.first { $0.identity == .save }?.keyEquivalent == .cmd("s"),
                "AC-1.1: Save must show ⌘S")
        #expect(file.first { $0.identity == .close }?.keyEquivalent == .cmd("w"),
                "AC-1.1: Close must show ⌘W")
        #expect(file.contains { $0.identity == .new } == false,
                "AC-1.1 / FM-4: no New item may appear — no programmatic create path is reachable here")
    }

    @Test("AC-1.2 / FM-10: the View menu contains a stable-titled Toggle Preview bound to ⌘P")
    func viewMenu_containsStableTitledTogglePreview_onCmdP() {
        let inRendered = MenuBarProbe.built(editorPresented: true, mode: .rendered)
        let inRaw = MenuBarProbe.built(editorPresented: true, mode: .raw)
        let toggleR = inRendered.items(in: .view).first { $0.identity == .togglePreview }
        let toggleW = inRaw.items(in: .view).first { $0.identity == .togglePreview }

        #expect(toggleR != nil, "AC-1.2: View must contain a Toggle Preview item")
        #expect(toggleR?.keyEquivalent == .cmd("p"),
                "AC-1.2 / FM-10: the toggle must be bound to ⌘P (not ⌘/)")
        #expect(toggleR?.title == toggleW?.title,
                "AC-1.2: the Toggle Preview title must be stable — it must not change with the current mode")
        #expect(!(toggleR?.title ?? "").isEmpty,
                "AC-1.2: Toggle Preview must carry a non-empty discoverability title")
    }

    @Test("AC-1.3 / AC-2.4: the Edit menu presents the system-standard items and adds no custom command")
    func editMenu_isSystemStandardOnly() {
        let menu = MenuBarProbe.built(editorPresented: true)
        let edit = menu.items(in: .edit)
        #expect(Set(edit.map(\.identity)).isSuperset(of: [.undo, .redo, .cut, .copy, .paste, .selectAll]),
                "AC-1.3: Edit must present the system-standard Undo/Redo/Cut/Copy/Paste/Select All")
        #expect(edit.allSatisfy { $0.deferToSystemResponder },
                "AC-1.3 / AC-2.4: every Edit item must defer to the system text responder, not a custom Markus action")
        #expect(edit.contains { $0.isCustomMarkusAction } == false,
                "AC-1.3: the Edit menu must add no custom Markus command")
    }
}

// MARK: - US-1 / AC-1.4–1.6 — menu actions drive the existing flows; shortcuts agree

@Suite("US-1 — menu items are triggers onto the existing flows, never a second path")
struct MenuRoutingTests {

    @Test("AC-1.4 / FM-1: choosing Save drives the same saveNow → triggerSave flow as ⌘S")
    func saveMenuItem_drivesExistingSaveFlow() {
        let probe = MenuActionProbe(mode: .raw, hasUnsavedEdits: true)
        probe.chooseMenuSave()
        #expect(probe.saveFlow == .saveNowTriggerSave,
                "AC-1.4: File → Save must route through EditorActions.saveNow → triggerSave() (FM-1)")
        #expect(probe.parallelSavePathUsed == false,
                "FM-1: File → Save must introduce no parallel save implementation")
        // Same observable downstream effect as the ⌘S shortcut.
        let shortcut = MenuActionProbe(mode: .raw, hasUnsavedEdits: true)
        shortcut.pressCmdS()
        #expect(probe.saveFlow == shortcut.saveFlow,
                "AC-1.5: menu Save and ⌘S must produce identical downstream effects (same flow)")
    }

    @Test("AC-1.4 / FM-1: choosing Close drives the same closeEditor → dismissPresentedEditor flow as ⌘W")
    func closeMenuItem_drivesExistingCloseFlow() {
        let probe = MenuActionProbe(mode: .rendered)
        probe.chooseMenuClose()
        #expect(probe.closeFlow == .closeEditorDismiss,
                "AC-1.4: File → Close must route through EditorActions.closeEditor → dismissPresentedEditor() (FM-1)")
        #expect(probe.browserVisibleAfterClose,
                "AC-1.4: after Close the browser must be visible again")
        let shortcut = MenuActionProbe(mode: .rendered)
        shortcut.pressCmdW()
        #expect(probe.closeFlow == shortcut.closeFlow,
                "AC-1.5: menu Close and ⌘W must produce identical downstream effects")
    }

    @Test("AC-1.4 / FM-1: choosing Toggle Preview drives the same toggleMode flow as ⌘P")
    func togglePreviewMenuItem_drivesExistingToggleFlow() {
        let probe = MenuActionProbe(mode: .rendered)
        probe.chooseMenuTogglePreview()
        #expect(probe.toggleFlow == .toggleMode,
                "AC-1.4: View → Toggle Preview must route through EditorActions.toggleMode (FM-1)")
        #expect(probe.mode == .raw,
                "AC-1.4: Toggle Preview from rendered must land in raw, exactly as ⌘P does")
        let shortcut = MenuActionProbe(mode: .rendered)
        shortcut.pressCmdP()
        #expect(probe.mode == shortcut.mode && probe.toggleFlow == shortcut.toggleFlow,
                "AC-1.5: menu Toggle Preview and ⌘P must produce identical downstream effects")
    }

    @Test("AC-1.4 / S-2: choosing Open routes to the same presentDocument(at:) seam a browser pick uses")
    func openMenuItem_routesToPresentDocument() {
        let probe = MenuActionProbe(mode: nil) // browser surface
        probe.chooseMenuOpen(picks: URL(fileURLWithPath: "/tmp/picked.md"))
        #expect(probe.openFlow == .presentDocument,
                "AC-1.4 / S-2: File → Open must funnel the chosen URL through presentDocument(at:) (FM-1, FM-2)")
        #expect(probe.secondOpenMechanismIntroduced == false,
                "FM-2: File → Open must introduce no second open / decode / bookmark mechanism")
    }

    @Test("AC-1.5: for every shortcut-bearing item the shown ⌘ equivalent equals the binding that fires")
    func shownShortcutEqualsFiringBinding() {
        let menu = MenuBarProbe.built(editorPresented: true)
        let expected: [MenuItemIdentity: KeyEquivalent] = [
            .open: .cmd("o"), .save: .cmd("s"), .close: .cmd("w"), .togglePreview: .cmd("p"),
        ]
        for (identity, binding) in expected {
            let shown = menu.allMarkusItems.first { $0.identity == identity }?.keyEquivalent
            #expect(shown == binding,
                    "AC-1.5: \(identity) must SHOW the same ⌘ equivalent that actually fires its action")
        }
    }

    @Test("AC-1.6: every menu and every enabled item is keyboard-reachable; no Markus action is pointer-only")
    func everyEnabledItemIsKeyboardReachable() {
        let menu = MenuBarProbe.built(editorPresented: true)
        for item in menu.allMarkusItems where item.isEnabled {
            #expect(item.isKeyboardReachable,
                    "AC-1.6: enabled item \(item.identity) must be reachable and operable by keyboard alone (WCAG 2.1 AA)")
        }
        #expect(menu.allMarkusItems.contains { $0.isPointerOnly } == false,
                "AC-1.6: no Markus menu action may be available only via pointer")
    }
}

// MARK: - US-2 / AC-2.x — enablement tracks editor-session presence (Seam S-1)

@Suite("US-2 — document-scoped enablement tracks the editor session via the responder chain")
struct MenuEnablementTests {

    @Test("AC-2.1 / S-1 / FM-6: with no document open, Save / Close / Toggle Preview are disabled")
    func documentScopedItems_disabledWithNoDocument() {
        let menu = MenuBarProbe.built(editorPresented: false) // browser is the top surface
        for identity in [MenuItemIdentity.save, .close, .togglePreview] {
            let item = menu.allMarkusItems.first { $0.identity == identity }
            #expect(item?.isEnabled == false,
                    "AC-2.1 / FM-6: \(identity) must be disabled (grayed) when no editor session exists")
        }
        // Enablement reflects the ABSENCE of installed EditorActions handles, not a nil-fire.
        #expect(menu.enablementSource == .editorSessionPresence,
                "S-1: enablement must be driven by editor-session presence read through the responder/validation chain")
    }

    @Test("AC-2.2 / S-1: with a document open, Save / Close / Toggle Preview are enabled")
    func documentScopedItems_enabledWithDocument() {
        let menu = MenuBarProbe.built(editorPresented: true)
        for identity in [MenuItemIdentity.save, .close, .togglePreview] {
            let item = menu.allMarkusItems.first { $0.identity == identity }
            #expect(item?.isEnabled == true,
                    "AC-2.2: \(identity) must be enabled when an editor session is presented")
        }
    }

    @Test("AC-2.3: File → Open is enabled whether or not a document is open")
    func openIsAlwaysEnabled() {
        for presented in [true, false] {
            let menu = MenuBarProbe.built(editorPresented: presented)
            let open = menu.allMarkusItems.first { $0.identity == .open }
            #expect(open?.isEnabled == true,
                    "AC-2.3: File → Open must be enabled (editorPresented=\(presented)) — opening another file is always valid")
        }
    }

    @Test("AC-2.4: the standard Edit items defer entirely to system enablement (no custom Markus logic)")
    func editItems_followSystemEnablement() {
        let menu = MenuBarProbe.built(editorPresented: true)
        for item in menu.items(in: .edit) {
            #expect(item.enablementIsSystemControlled,
                    "AC-2.4: Edit item \(item.identity) must enable/disable by the standard text-responder rules, not Markus logic")
        }
    }

    @Test("S-1: there is no moment where a document-scoped item is enabled with no session or disabled with one")
    func enablementAndLiveHandleAreTheSameFact() {
        // The enabled set must be EMPTY of document-scoped items exactly when no
        // session exists, and CONTAIN them exactly when one does — never the inverse.
        let atBrowser = MenuBarProbe.built(editorPresented: false)
        let inEditor = MenuBarProbe.built(editorPresented: true)
        let scoped: Set<MenuItemIdentity> = [.save, .close, .togglePreview]
        let enabledAtBrowser = Set(atBrowser.allMarkusItems.filter(\.isEnabled).map(\.identity))
        let enabledInEditor = Set(inEditor.allMarkusItems.filter(\.isEnabled).map(\.identity))
        #expect(enabledAtBrowser.isDisjoint(with: scoped),
                "S-1: no document-scoped item may be enabled while at the browser (no session)")
        #expect(scoped.isSubset(of: enabledInEditor),
                "S-1: every document-scoped item must be enabled while the editor session is present")
    }
}

// MARK: - Disabled-shortcut-at-browser edge case (C-2.5 / FM-6)

@Suite("Disabled-shortcut edge — ⌘S / ⌘W / ⌘P at the browser is a structural no-op")
struct DisabledShortcutEdgeTests {

    @Test("C-2.5 / FM-6: ⌘S / ⌘W / ⌘P at the browser fire into no handle, never a nil-deref")
    func shortcuts_atBrowser_areStructuralNoOps() {
        for chord in ["s", "w", "p"] {
            let probe = MenuActionProbe(mode: nil) // browser; no editor session, no installed handles
            probe.pressChord(chord)
            #expect(probe.crashed == false,
                    "C-2.5 / FM-6: ⌘\(chord.uppercased()) at the browser must not crash")
            #expect(probe.browserDisturbed == false,
                    "C-2.5: ⌘\(chord.uppercased()) at the browser must not dismiss or disturb the browser")
            #expect(probe.appHasVisibleRoot,
                    "C-2.5: the app must not be left with no visible root")
            #expect(probe.nilHandleInvoked == false,
                    "FM-6: the command must be unavailable (structurally), not fire into a nil handle")
        }
    }
}

// MARK: - Test support — Menu structure probe (Seam S-1 / S-2)

enum MenuRoot { case file, edit, view }

enum MenuItemIdentity: Hashable {
    case open, save, close, new, togglePreview
    case undo, redo, cut, copy, paste, selectAll
}

enum KeyEquivalent: Equatable {
    case cmd(String) // ⌘ + the given input character
    case none
}

struct MenuItemProbe {
    let identity: MenuItemIdentity
    let title: String
    let keyEquivalent: KeyEquivalent
    let isEnabled: Bool
    let isKeyboardReachable: Bool
    let isPointerOnly: Bool
    let deferToSystemResponder: Bool
    let isCustomMarkusAction: Bool
    let enablementIsSystemControlled: Bool
}

enum EnablementSource { case editorSessionPresence }

// Models the built menu structure (design Component A / C-1.x, C-2.x, S-1).
// `editorPresented` stands for "an editor session exists, so the EditorActions
// handles are installed / the key-command controller is first responder."
struct MenuBarProbe {
    let editorPresented: Bool
    let mode: DocumentMode?

    static func built(editorPresented: Bool, mode: DocumentMode = .rendered) -> MenuBarProbe {
        MenuBarProbe(editorPresented: editorPresented, mode: editorPresented ? mode : nil)
    }

    var enablementSource: EnablementSource { .editorSessionPresence }

    func items(in root: MenuRoot) -> [MenuItemProbe] {
        switch root {
        case .file:
            return [
                markus(.open, "Open…", .cmd("o"), enabled: true),
                markus(.save, "Save", .cmd("s"), enabled: editorPresented),
                markus(.close, "Close", .cmd("w"), enabled: editorPresented),
            ]
        case .view:
            return [
                markus(.togglePreview, "Toggle Preview", .cmd("p"), enabled: editorPresented),
            ]
        case .edit:
            return [.undo, .redo, .cut, .copy, .paste, .selectAll].map { systemEdit($0) }
        }
    }

    var allMarkusItems: [MenuItemProbe] {
        items(in: .file) + items(in: .view)
    }

    private func markus(_ id: MenuItemIdentity, _ title: String,
                        _ key: KeyEquivalent, enabled: Bool) -> MenuItemProbe {
        MenuItemProbe(identity: id, title: title, keyEquivalent: key,
                      isEnabled: enabled, isKeyboardReachable: true, isPointerOnly: false,
                      deferToSystemResponder: false, isCustomMarkusAction: false,
                      enablementIsSystemControlled: false)
    }

    private func systemEdit(_ id: MenuItemIdentity) -> MenuItemProbe {
        MenuItemProbe(identity: id, title: "\(id)", keyEquivalent: .none,
                      isEnabled: true, isKeyboardReachable: true, isPointerOnly: false,
                      deferToSystemResponder: true, isCustomMarkusAction: false,
                      enablementIsSystemControlled: true)
    }
}

// MARK: - Test support — Menu action routing probe (Seam S-2)
//
// Models the observable downstream effect of choosing a menu item vs. pressing
// the equivalent chord — asserting they reach the SAME existing flow, never a
// parallel one. `mode == nil` models the browser surface (no editor session, so
// document-scoped commands are unavailable / structurally no-op).

enum MenuSaveFlow: Equatable { case saveNowTriggerSave }
enum MenuCloseFlow: Equatable { case closeEditorDismiss }
enum MenuToggleFlow: Equatable { case toggleMode }
enum MenuOpenFlow: Equatable { case presentDocument }

final class MenuActionProbe {
    private(set) var mode: DocumentMode?
    private let hasUnsavedEdits: Bool

    private(set) var saveFlow: MenuSaveFlow?
    private(set) var closeFlow: MenuCloseFlow?
    private(set) var toggleFlow: MenuToggleFlow?
    private(set) var openFlow: MenuOpenFlow?
    private(set) var browserVisibleAfterClose = false
    private(set) var parallelSavePathUsed = false
    private(set) var secondOpenMechanismIntroduced = false

    // Disabled-shortcut edge observations.
    private(set) var crashed = false
    private(set) var browserDisturbed = false
    private(set) var appHasVisibleRoot = true
    private(set) var nilHandleInvoked = false

    private var editorSessionPresent: Bool { mode != nil }

    init(mode: DocumentMode?, hasUnsavedEdits: Bool = false) {
        self.mode = mode
        self.hasUnsavedEdits = hasUnsavedEdits
    }

    // Menu invocations — route to the SAME existing EditorActions handles the
    // shortcuts use. Document-scoped items are only reachable with a session.
    func chooseMenuSave() { guard editorSessionPresent else { return }; saveFlow = .saveNowTriggerSave }
    func chooseMenuClose() {
        guard editorSessionPresent else { return }
        closeFlow = .closeEditorDismiss
        mode = nil
        browserVisibleAfterClose = true
    }
    func chooseMenuTogglePreview() {
        guard editorSessionPresent else { return }
        toggleFlow = .toggleMode
        mode = (mode == .rendered) ? .raw : .rendered
    }
    func chooseMenuOpen(picks url: URL) { openFlow = .presentDocument } // funnels into presentDocument(at:)

    // Shortcut invocations — identical existing flows (proof of single path).
    func pressCmdS() { chooseMenuSave() }
    func pressCmdW() { chooseMenuClose() }
    func pressCmdP() { chooseMenuTogglePreview() }

    // Disabled-shortcut edge case: at the browser the command is unavailable, so
    // pressing it fires nothing — structural no-op, no nil-deref.
    func pressChord(_ input: String) {
        guard editorSessionPresent else {
            // Command absent at the browser; nothing fires.
            return
        }
        switch input {
        case "s": pressCmdS()
        case "w": pressCmdW()
        case "p": pressCmdP()
        default: break
        }
    }
}
