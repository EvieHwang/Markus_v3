import SwiftUI
import UIKit

struct DocumentView: View {
    @ObservedObject var document: MarkdownDocument
    let fileURL: URL?

    @State private var mode: DocumentMode = .rendered
    @State private var didInitMode = false
    @State private var activeAlert: ActiveAlert?
    @State private var toast: String?
    @State private var coordinator: AutosaveCoordinator
    @State private var saveStatusObserver = SaveStatusObserver()
    @StateObject private var rawScrollState = RawEditorScrollState()
    @State private var pendingRawAnchor: ScrollAnchor?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.undoManager) private var undoManager

    private static let largeFileByteThreshold = 500 * 1024

    init(configuration: ReferenceFileDocumentConfiguration<MarkdownDocument>) {
        self.init(document: configuration.document, fileURL: configuration.fileURL)
    }

    init(document: MarkdownDocument, fileURL: URL? = nil) {
        self.document = document
        self.fileURL = fileURL
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
                    RenderedView(text: document.text, onTap: { switchTo(.rendered, target: .raw) })
                case .raw:
                    RawEditorView(
                        document: document,
                        coordinator: coordinator,
                        scrollState: rawScrollState,
                        pendingScrollAnchor: $pendingRawAnchor
                    )
                }
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
                mode = document.initialByteSize >= Self.largeFileByteThreshold ? .raw : .rendered
                didInitMode = true
            }
            document.undoManager = undoManager
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                triggerSave()
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
        if mode == .raw {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
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
        fileURL?.deletingPathExtension().lastPathComponent ?? ""
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
