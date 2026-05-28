import SwiftUI
import UIKit

struct DocumentView: View {
    @ObservedObject var document: MarkdownDocument
    let fileURL: URL?
    let detector: ChangeDetector?
    let onBack: (() -> Void)?

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
         onBack: (() -> Void)? = nil) {
        self.document = document
        self.fileURL = fileURL
        self.detector = detector
        self.onBack = onBack
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
                        text: document.text,
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
        }
        .onDisappear {
            detector?.stop()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                triggerSave()
            } else if newPhase == .active {
                // DC-23 — recover a latched-but-surface-less outcome on return.
                detector?.reconcileOnForeground()
            }
        }
        .onChange(of: saveStatusObserver.lastSaveError) { _, err in
            if let err {
                activeAlert = .saveFailed(err)
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
        case .none:                 return ""
        }
    }

    private func alertMessage(for alert: ActiveAlert) -> String {
        switch alert {
        case .saveFailed:
            return "Your edits are still in memory. You can copy them to the clipboard."
        case .invalidEncoding:
            return "This file isn't valid UTF-8 text."
        case .iCloudDownloadFailed:
            return "The file couldn't be downloaded from iCloud."
        }
    }

    @ViewBuilder
    private func alertActions(for alert: ActiveAlert) -> some View {
        switch alert {
        case .saveFailed:
            Button("Copy contents to clipboard") { copyContentsToClipboard() }
            Button("Dismiss", role: .cancel) { activeAlert = nil }
        case .invalidEncoding, .iCloudDownloadFailed:
            Button("OK", role: .cancel) { activeAlert = nil }
        }
    }

    private func switchTo(_ from: DocumentMode, target: DocumentMode) {
        if from == .raw && target == .rendered {
            triggerSave()
        }
        mode = target
    }

    private func triggerSave() {
        document.markDirty()
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
    }
}
