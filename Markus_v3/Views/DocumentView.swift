import SwiftUI
import UIKit

struct DocumentView: View {
    @ObservedObject var document: MarkdownDocument
    let fileURL: URL?
    let initialMode: DocumentMode?
    let focusEditorOnAppear: Bool
    let detector: ChangeDetector?
    let onBack: (() -> Void)?

    @State private var mode: DocumentMode = .rendered
    @State private var didInitMode = false
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

    private static let largeFileByteThreshold = 500 * 1024

    init(configuration: ReferenceFileDocumentConfiguration<MarkdownDocument>) {
        self.init(document: configuration.document, fileURL: configuration.fileURL)
    }

    init(document: MarkdownDocument,
         fileURL: URL? = nil,
         initialMode: DocumentMode? = nil,
         focusEditorOnAppear: Bool = false,
         detector: ChangeDetector? = nil,
         onBack: (() -> Void)? = nil) {
        self.document = document
        self.fileURL = fileURL
        self.initialMode = initialMode
        self.focusEditorOnAppear = focusEditorOnAppear
        self.detector = detector
        self.onBack = onBack
        let doc = document
        self._coordinator = State(wrappedValue: AutosaveCoordinator(onIdle: { [weak doc] in
            doc?.markDirty()
        }))
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
                        pendingScrollAnchor: $pendingRenderedAnchor
                    )
                case .raw:
                    RawEditorView(
                        document: document,
                        coordinator: coordinator,
                        scrollState: rawScrollState,
                        pendingScrollAnchor: $pendingRawAnchor,
                        focusOnAppear: focusEditorOnAppear
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
                if let initialMode {
                    mode = initialMode
                } else {
                    mode = document.initialByteSize >= Self.largeFileByteThreshold ? .raw : .rendered
                }
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
