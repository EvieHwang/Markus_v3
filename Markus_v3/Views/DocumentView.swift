import SwiftUI
import UIKit

struct DocumentView: View {
    @ObservedObject var document: MarkdownDocument
    let fileURL: URL?
    let detector: ChangeDetector?
    let onBack: (() -> Void)?
    /// T-004 (save-bridge-hardening-9) — per-document router that surfaces
    /// bridge write failures into `activeAlert` with the DC-10–DC-15 lifecycle
    /// (single-alert coalescing, background latch, conflict precedence).
    let saveFailedRouter: SaveFailedAlertRouter?
    /// ipad-expansion-13 — shared action handles wired from the host's
    /// `EditorKeyCommandHostingController`. `DocumentView` installs the
    /// `toggleMode` and `saveNow` closures on appear (S-2) so the ⌘P / ⌘S
    /// key commands route through the *existing* transition / save flows
    /// rather than reimplementing them.
    let editorActions: EditorActions?

    @State private var mode: DocumentMode = .rendered
    @State private var didInitMode = false
    @State private var focusRawOnFirstAppear: Bool = false
    @State private var activeAlert: ActiveAlert?
    @State private var toast: String?
    @State private var coordinator: AutosaveCoordinator
    @State private var saveStatusObserver = SaveStatusObserver()
    @StateObject private var rawScrollState = RawEditorScrollState()
    @State private var pendingRawAnchor: ScrollAnchor?
    @State private var pendingRenderedAnchor: ScrollAnchor?
    @State private var currentDisplayURL: URL?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.undoManager) private var undoManager

    static let largeFileByteThreshold = 500 * 1024

    init(configuration: ReferenceFileDocumentConfiguration<MarkdownDocument>) {
        self.init(document: configuration.document, fileURL: configuration.fileURL)
    }

    init(document: MarkdownDocument,
         fileURL: URL? = nil,
         detector: ChangeDetector? = nil,
         onBack: (() -> Void)? = nil,
         saveFailedRouter: SaveFailedAlertRouter? = nil,
         editorActions: EditorActions? = nil) {
        self.document = document
        self.fileURL = fileURL
        self.detector = detector
        self.onBack = onBack
        self.saveFailedRouter = saveFailedRouter
        self.editorActions = editorActions
        let doc = document
        self._coordinator = State(wrappedValue: AutosaveCoordinator(onIdle: { [weak doc] in
            doc?.markDirty()
        }))
    }

    /// DC-4 — content-based initial-mode rule. Pure function of content:
    /// empty content (zero text) → `.raw` (caller should also bring up the
    /// keyboard); content at or above `largeFileByteThreshold` → `.raw`;
    /// otherwise `.rendered`. Used by `.onAppear` and exposed as a static
    /// helper so the rule can be unit-tested at the seam itself.
    static func initialMode(forContent text: String, byteSize: Int) -> DocumentMode {
        if text.isEmpty || byteSize == 0 { return .raw }
        if byteSize >= largeFileByteThreshold { return .raw }
        return .rendered
    }

    /// DC-4 — file-based convenience. Resolves the file's bytes from disk
    /// and delegates to `initialMode(forContent:byteSize:)`. If the file
    /// cannot be read, defaults to `.rendered` (the historical fallback
    /// when no signal is available).
    static func initialMode(forFile url: URL) -> DocumentMode {
        let data = (try? Data(contentsOf: url)) ?? Data()
        let text = String(data: data, encoding: .utf8) ?? ""
        return initialMode(forContent: text, byteSize: data.count)
    }

    var body: some View {
        Group {
            if saveStatusObserver.isDownloadingFromiCloud {
                DocumentLoadingView()
            } else {
                switch mode {
                case .rendered:
                    RenderedView(
                        // open-path-hardening-10 DC-3 — render-time BOM
                        // suppression. Buffer keeps the BOM for byte-identical
                        // save round-trip; only the display surface drops it.
                        text: document.displayText,
                        onTap: { fractionalY in
                            pendingRawAnchor = ScrollAnchor(fractionalY: fractionalY ?? 0)
                            switchTo(.rendered, target: .raw)
                        },
                        pendingScrollAnchor: $pendingRenderedAnchor,
                        onSwipeToRaw: { switchToRawFromSwipe() }
                    )
                case .raw:
                    RawEditorView(
                        document: document,
                        coordinator: coordinator,
                        scrollState: rawScrollState,
                        pendingScrollAnchor: $pendingRawAnchor,
                        focusOnAppear: focusRawOnFirstAppear,
                        onSwipeToRendered: { switchToRenderedFromSwipe() },
                        // NP-5: mid-screen L→R on raw goes back to file browser,
                        // matching the system edge-pan dismiss + back-button paths.
                        onSwipeToBrowser: { onBack?() }
                    )
                }
            }
        }
        .overlay(alignment: .top) { debugInjectionBar }
        .overlay {
            if let detector {
                DetectorSurfaces(detector: detector, document: document)
            }
        }
        // ipad-expansion-13 — register ⌘P / ⌘W / ⌘S as SwiftUI keyboard
        // shortcuts so the OS reliably delivers chords to the editor session
        // (the responder-chain reach through `EditorKeyCommandHostingController`
        // is brittle when nothing in the SwiftUI tree is first responder; the
        // SwiftUI shortcut handler installs itself on the chain regardless).
        // Each shortcut routes to the same `editorActions` closures the
        // UIKit `keyCommands` route to, so both mechanisms invoke the same
        // existing flow (FM-1). The hidden buttons add no visible chrome
        // (zero-size, no opacity) — the only user-visible effect is the
        // discoverability overlay carrying their titles.
        .background(editorKeyboardShortcuts)
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        // NP-9.2 / NP-9.5: navigation bar uses the standard .bar material so it
        // blurs the content scrolling beneath it (HIG semantic). Visibility is
        // pinned to .visible so the material is drawn even when scroll is at the
        // top edge (where SwiftUI would otherwise hide the bar background).
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(.bar, for: .navigationBar)
        .toast($toast)
        .alert(
            alertTitle,
            isPresented: alertPresented,
            presenting: activeAlert
        ) { alert in
            alertActions(for: alert)
        } message: { alert in
            Text(alertMessage(for: alert))
        }
        .onAppear {
            if !didInitMode {
                // DC-4 — content-based initial mode. Empty content lands in
                // raw mode with the keyboard up (matching Notes/Pages new-doc
                // behavior); large content lands in raw without auto-focus;
                // otherwise rendered.
                let resolved = Self.initialMode(forContent: document.text,
                                                byteSize: document.initialByteSize)
                mode = resolved
                focusRawOnFirstAppear = (resolved == .raw)
                    && (document.text.isEmpty || document.initialByteSize == 0)
                didInitMode = true
            }
            document.undoManager = undoManager
            startDetectorIfNeeded()
            // ipad-expansion-13 — wire ⌘P / ⌘S to the existing toggle and
            // save flows (S-2). Closures are invoked by
            // `EditorKeyCommandHostingController` when the chord arrives;
            // they route through `switchTo` / the eye-button effect /
            // `triggerSave` — never a second implementation (FM-1).
            installEditorActions()
            // DC-13 (save-bridge-hardening-9) — view is alive; promote any
            // failure latched while no view was visible.
            saveFailedRouter?.viewBecameActive()
            // DC-14 — initialize conflict precedence from the current detector
            // surface so a save-failed observed during onAppear does not
            // pre-empt a conflict sheet already on screen.
            saveFailedRouter?.setConflictPresented(detector?.activeSurface != nil)
        }
        .onDisappear {
            detector?.stop()
            saveFailedRouter?.viewBecameInactive()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                triggerSave()
                saveFailedRouter?.viewBecameInactive()
            } else if newPhase == .active {
                // DC-23 — recover a latched-but-surface-less outcome on return.
                detector?.reconcileOnForeground()
                // DC-13 — promote any failure latched while backgrounded.
                saveFailedRouter?.viewBecameActive()
            }
        }
        .onChange(of: saveStatusObserver.lastSaveError) { _, err in
            if let err {
                // DC-15 / NR-7 — single-alert state model absorbs the duplicate
                // if the bridge route already surfaced an alert for the same
                // underlying failure (both producers funnel into activeAlert).
                activeAlert = .saveFailed(err)
            }
        }
        .onChange(of: detector?.activeSurface) { _, surface in
            // DC-14 — keep the router informed so a presented conflict sheet
            // or deletion banner outranks any incoming save-failed alert.
            saveFailedRouter?.setConflictPresented(surface != nil)
        }
        .onChange(of: saveFailedRouter?.pendingError as NSError?) { _, _ in
            if let err = saveFailedRouter?.pendingError {
                // DC-10 — route bridge failures into the existing alert path.
                activeAlert = .saveFailed(.saveFailed(underlying: err))
            } else if case .saveFailed = activeAlert {
                // Router cleared (success / dismissed) — clear our reflection too.
                activeAlert = nil
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if let onBack {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    triggerSave()
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Back")
                .accessibilityIdentifier("Back")
            }
        }
        if mode == .raw {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    pendingRenderedAnchor = ScrollAnchor(fractionalY: rawScrollState.currentFractionalY)
                    triggerSave()
                    mode = .rendered
                    postModeAnnouncement(for: .rendered)
                } label: {
                    Image(systemName: "eye")
                }
                .accessibilityLabel("Show rendered")
            }
        }
        // T-008 / NP-8.1, NP-8.7, NPC-11: share button is present only in
        // rendered mode and uses the square.and.arrow.up SF Symbol. Tap is
        // gated by DocumentViewShareConfig.canPresentShare(...) so a missing
        // or nil URL is a no-op (NP-8.6, NP-14, NPC-12).
        if DocumentViewShareConfig.shareButtonVisible(mode: mode) {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presentShareSheet()
                } label: {
                    Image(systemName: DocumentViewShareConfig.shareButtonSFSymbol)
                }
                .accessibilityLabel("Share")
                .accessibilityIdentifier("Share")
            }
        }
    }

    /// Tap handler for the share button. Presents `UIActivityViewController`
    /// imperatively from the top view controller with the original document
    /// URL as the activity item, and keeps the file's security scope active
    /// for the lifetime of the activity controller. Sharing the original URL
    /// (rather than a copy in the app's tmp directory) lets share extensions
    /// resolve the file through its real file-provider domain — copying to
    /// tmp first produces a blank share sheet because LaunchServices cannot
    /// fetch metadata for files in the app sandbox. Nil URL is rejected by
    /// the config gate (NPC-12). Unsaved buffer edits are unaffected —
    /// extensions read the last-saved disk file (NP-8.4 / NP-8.5). If the
    /// file has been deleted, presentation still attempts and the OS surfaces
    /// the standard "couldn't load" error rather than crashing (NP-8.6 / NP-14).
    private func presentShareSheet() {
        guard DocumentViewShareConfig.canPresentShare(for: fileURL),
              let url = fileURL,
              let presenter = Self.topPresentedViewController() else { return }

        let scoped = url.startAccessingSecurityScopedResource()
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            if scoped { url.stopAccessingSecurityScopedResource() }
        }

        // iPad popover anchor — sourceView is required even if we don't have
        // an exact rect; the system places the popover sensibly given a view.
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX,
                                        y: 0,
                                        width: 1,
                                        height: 1)
            popover.permittedArrowDirections = [.up]
        }

        presenter.present(activityVC, animated: true)
    }

    /// Walks the active scene's window hierarchy to the top-most presented
    /// view controller. Used so `UIActivityViewController` is presented from
    /// the editor, not from inside a SwiftUI sheet's hosting context (which
    /// in iOS 18+ produces a blank activity sheet for file-provider URLs).
    private static func topPresentedViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first
        guard var top = window?.rootViewController else { return nil }
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    /// NP-4 / NPC-7: R→L swipe on raw editor → rendered mode. Triggers save
    /// (preserves unsaved edits) and seeds the rendered scroll anchor from the
    /// raw editor's current scroll fraction, matching the eye-button path.
    private func switchToRenderedFromSwipe() {
        pendingRenderedAnchor = ScrollAnchor(fractionalY: rawScrollState.currentFractionalY)
        triggerSave()
        mode = .rendered
        postModeAnnouncement(for: .rendered)
    }

    /// NP-6: L→R swipe on rendered view → raw mode. Same switch logic as the
    /// tap-to-edit path; no save is triggered (rendered mode does not edit).
    private func switchToRawFromSwipe() {
        switchTo(.rendered, target: .raw)
    }

    private var displayName: String {
        // DC-19/BR-8.3 — track the detector's followed location so a rename
        // propagates to the title; fall back to the opened URL.
        (currentDisplayURL ?? fileURL)?.deletingPathExtension().lastPathComponent ?? ""
    }

    /// Test-only deterministic external-change injectors, present only under the
    /// `-uitest-open-seed-file` UI-test marker (see ExternalChangeUITests). Routed
    /// through the live detector so they exercise the real classify→apply path.
    @ViewBuilder
    private var debugInjectionBar: some View {
        if ProcessInfo.processInfo.arguments.contains("-uitest-open-seed-file"), let detector {
            HStack(spacing: 1) {
                Button("ic") { detector.injectExternalChange("EXTERNAL DIVERGENT CONTENT\n") }
                    .accessibilityIdentifier("DebugInjectExternalChange")
                Button("id") { detector.injectExternalChange(document.text) }
                    .accessibilityIdentifier("DebugInjectIdenticalExternalChange")
                Button("kt") { detector.injectExternalChange("EXTERNAL-KNOWN-MARKER\n") }
                    .accessibilityIdentifier("DebugInjectExternalChangeKnownText")
                Button("iu") { detector.injectInvalidUTF8() }
                    .accessibilityIdentifier("DebugInjectInvalidUtf8")
            }
            .font(.caption2)
            .buttonStyle(.bordered)
        }
    }

    private var alertPresented: Binding<Bool> {
        Binding(
            get: { activeAlert != nil },
            set: { if !$0 { activeAlert = nil } }
        )
    }

    private var alertTitle: String {
        switch activeAlert {
        case .saveFailed:           return "Couldn't save"
        case .invalidEncoding:      return "Couldn't open"
        case .iCloudDownloadFailed: return "Couldn't download"
        // open-path-hardening-10 — these surfaces normally fire on
        // BrowserHostController (DC-6a) before a DocumentView exists, but
        // ActiveAlert is a single enum and Swift requires exhaustive
        // switching. Titles are sensible defaults in case of routing drift.
        case .permissionDenied:     return "Couldn't open"
        case .fileMovedOrRemoved:   return "Couldn't open"
        case .couldNotReadFile:     return "Couldn't open"
        case .tooLarge:             return "Couldn't open"
        case .none:                 return ""
        }
    }

    private func alertMessage(for alert: ActiveAlert) -> String {
        switch alert {
        case let .saveFailed(error):
            // BR-1.2 (save-bridge-hardening-9) — include the underlying error's
            // localized description so the user has something actionable to
            // recognize (e.g. file path, permission text). Falls back to the
            // generic line alone if the underlying error provides no message.
            let base = "Your edits are still in memory. You can copy them to the clipboard."
            let underlying = underlyingDescription(for: error)
            if let underlying, !underlying.isEmpty {
                return "\(underlying)\n\n\(base)"
            }
            return base
        case .invalidEncoding:
            return "This file isn't valid UTF-8 text."
        case .iCloudDownloadFailed:
            return "The file couldn't be downloaded from iCloud."
        case .permissionDenied, .fileMovedOrRemoved, .couldNotReadFile, .tooLarge:
            // Open-path surfaces normally fire on BrowserHostController
            // (DC-6a); included here for exhaustiveness with shared copy.
            return OpenPathAlertCopy.message(for: alert)
        }
    }

    private func underlyingDescription(for error: DocumentError) -> String? {
        if case let .saveFailed(underlying) = error {
            let description = (underlying as NSError).localizedDescription
            // SaveStatusObserver synthesizes an empty NSError on UIDocument
            // save errors; suppress its placeholder so the generic line is
            // shown unchanged.
            if description.isEmpty || description == "The operation couldn’t be completed. (UIDocument.savingError error 0.)" {
                return nil
            }
            return description
        }
        return nil
    }

    @ViewBuilder
    private func alertActions(for alert: ActiveAlert) -> some View {
        switch alert {
        case .saveFailed:
            Button("Copy contents to clipboard") { copyContentsToClipboard() }
            Button("Dismiss", role: .cancel) {
                activeAlert = nil
                // BR-1.3 / DC-10 — close the surface; router clears its
                // pending state but does NOT retry, queue, or clear dirty.
                saveFailedRouter?.dismiss()
            }
        case .invalidEncoding, .iCloudDownloadFailed,
             .permissionDenied, .fileMovedOrRemoved,
             .couldNotReadFile, .tooLarge:
            Button("OK", role: .cancel) { activeAlert = nil }
        }
    }

    private func switchTo(_ from: DocumentMode, target: DocumentMode) {
        if from == .raw && target == .rendered {
            triggerSave()
        }
        mode = target
        postModeAnnouncement(for: target)
    }

    /// AC-5.1 / AC-5.2 / AC-5.4: post a VoiceOver announcement when the mode
    /// changes due to a user action. Posted directly at each triggering call
    /// site (this helper, the toolbar handler, `switchToRenderedFromSwipe`)
    /// rather than in an `.onChange(of: mode)` observer, so initial-mode
    /// assignment on `onAppear` cannot trigger an announcement (AC-5.5, F-001).
    private func postModeAnnouncement(for target: DocumentMode) {
        let argument: String
        switch target {
        case .raw:
            argument = String(localized: "Editing mode",
                              comment: "VoiceOver announcement when switching to raw edit mode")
        case .rendered:
            argument = String(localized: "Preview mode",
                              comment: "VoiceOver announcement when switching to rendered preview mode")
        }
        UIAccessibility.post(notification: .announcement, argument: argument)
    }

    private func triggerSave() {
        document.markDirty()
    }

    /// ipad-expansion-13 — wire the ⌘P / ⌘S handles into the *existing*
    /// transition and save flows. ⌘P consults the current `mode` and runs
    /// the same effect the screen would: rendered→raw is the tap-to-edit
    /// path (`switchTo(.rendered, target: .raw)`, which seeds the raw anchor
    /// and posts "Editing mode"); raw→rendered is the eye-button path (seed
    /// the rendered anchor from the raw scroll fraction, trigger a save,
    /// set `mode = .rendered`, post "Preview mode"). ⌘S routes through
    /// `triggerSave()`. The host owns `closeEditor` via `onBack` already.
    /// All three closures invoke existing entry points, never a parallel
    /// implementation (FM-1, FM-9).
    private func installEditorActions() {
        editorActions?.toggleMode = {
            performToggleMode()
        }
        editorActions?.saveNow = {
            triggerSave()
        }
    }

    /// Shared toggle effect invoked by both the `EditorActions.toggleMode`
    /// closure (UIKit chord delivery via `EditorKeyCommandHostingController`)
    /// and the SwiftUI `.keyboardShortcut("p", modifiers: .command)` button
    /// in `editorKeyboardShortcuts`. Routes through the existing `switchTo`
    /// / eye-button effect, never a parallel transition.
    private func performToggleMode() {
        switch mode {
        case .rendered:
            pendingRawAnchor = ScrollAnchor(fractionalY: 0)
            switchTo(.rendered, target: .raw)
        case .raw:
            pendingRenderedAnchor = ScrollAnchor(fractionalY: rawScrollState.currentFractionalY)
            triggerSave()
            mode = .rendered
            postModeAnnouncement(for: .rendered)
        }
    }

    /// ipad-expansion-13 — hidden buttons that install ⌘P / ⌘W / ⌘S as
    /// SwiftUI keyboard shortcuts. SwiftUI hooks each shortcut into the
    /// responder chain so the OS reliably routes the chord to the active
    /// editor session, even when nothing is first responder (the UIKit
    /// `keyCommands` reach through the hosting controller is brittle in
    /// that case). The buttons are size-zero / opacity-zero / hit-test
    /// disabled, so they add no visible chrome (FM-4) — the only
    /// user-visible effect is each chord performing its action and the
    /// discoverability overlay carrying the action titles.
    @ViewBuilder
    private var editorKeyboardShortcuts: some View {
        ZStack {
            Button("Toggle Preview") { performToggleMode() }
                .keyboardShortcut("p", modifiers: .command)
            Button("Close") { onBack?() }
                .keyboardShortcut("w", modifiers: .command)
            Button("Save") { triggerSave() }
                .keyboardShortcut("s", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func startDetectorIfNeeded() {
        guard let detector else { return }
        // DC-7 — feed the detector the iCloud busy signal so it suppresses
        // classification while a sync is in flight, without delegating the
        // collision decision to the observer (DC-3).
        detector.isSyncInFlight = { [weak obs = saveStatusObserver] in
            obs?.isDownloadingFromiCloud ?? false
        }
        detector.onInvalidEncoding = { activeAlert = .invalidEncoding }
        currentDisplayURL = detector.displayURL
        detector.onDisplayURLChange = { url in currentDisplayURL = url }
        detector.start()
        handleLaunchInjections(ProcessInfo.processInfo.arguments, detector)
    }

    /// Deterministic UI-test injections applied once the detector is live, mirroring
    /// the resume-and-create seeding convention (see ExternalChangeUITests).
    private func handleLaunchInjections(_ args: [String], _ detector: ChangeDetector) {
        if let content = value(after: "-uitest-external-change", in: args) {
            detector.injectExternalChange(content)
        }
        if let name = value(after: "-uitest-external-rename", in: args) {
            detector.injectExternalRename(to: name)
        }
        if args.contains("-uitest-external-delete") {
            detector.injectExternalDelete()
        }
        if args.contains("-uitest-external-move-reappear") {
            // A delete-then-reappear within the window resolves as a move (BR-9.5):
            // no banner. Modeled by a direct move injection — the file remains
            // resolvable at the new location, so presence-first yields `moved`.
            detector.injectExternalRename(to: "Reappeared.md")
        }
        // -uitest-inject-invalid-utf8 is driven by the DebugInjectInvalidUtf8 button
        // in-session (firing it at launch would pop the alert before the editor opens).
        // -uitest-external-change-other-file is intentionally a no-op for the open
        // document: a change to a non-open file produces no UI (BR-18).
    }

    private func value(after flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    private func copyContentsToClipboard() {
        UIPasteboard.general.string = document.text
        UIAccessibility.post(
            notification: .announcement,
            argument: NSLocalizedString("Copied", comment: "VoiceOver announcement after Copy contents to clipboard")
        )
        toast = "Copied"
        activeAlert = nil
        // BR-1.3 / DC-10 — copying is an alternative dismissal path; the
        // router clears its pending state but does NOT retry or clear dirty.
        saveFailedRouter?.dismiss()
    }
}
