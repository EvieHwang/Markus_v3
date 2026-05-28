import SwiftUI
import UniformTypeIdentifiers

/// Maps the change detector's published surface state to the two user-visible
/// surfaces (design §Conflict & lifecycle UI):
/// - the modal three-option conflict sheet (DC-14/DC-15, T-008), and
/// - the non-modal deletion banner with Save As (DC-16/DC-17, T-009).
///
/// Rendered as a transparent overlay over the editor so it observes the detector
/// without restructuring `DocumentView`. Save-back is already suspended from
/// classification by the latch (DC-22), so nothing overwrites disk while a choice
/// is pending; a non-user dismissal never resolves the outcome (DC-15) — recovery
/// is the foreground reconciler (DC-23).
struct DetectorSurfaces: View {
    @ObservedObject var detector: ChangeDetector
    @ObservedObject var document: MarkdownDocument

    @State private var showSaveAs = false

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .overlay(alignment: .bottom) { deletionBanner }
            .sheet(isPresented: conflictPresented) { conflictSheet }
            .fileExporter(
                isPresented: $showSaveAs,
                document: document,
                contentType: .plainText,
                defaultFilename: detector.displayURL.deletingPathExtension().lastPathComponent
            ) { result in
                if case let .success(url) = result {
                    detector.completeSaveAs(to: url)   // BR-9.4 — continue at new location
                    // AC-4.9: banner is removed; move VoiceOver focus off the
                    // now-invisible controls.
                    UIAccessibility.post(notification: .layoutChanged, argument: nil)
                }
            }
    }

    // MARK: - Conflict sheet (DC-14, BR-4)

    private var conflictPresented: Binding<Bool> {
        Binding(
            get: {
                if case .conflict = detector.activeSurface { return true }
                return false
            },
            set: { _ in /* dismissal is by explicit choice only (DC-15) */ }
        )
    }

    @ViewBuilder
    private var conflictSheet: some View {
        VStack(spacing: 20) {
            Text("This file changed on another device")
                .font(.headline)
            Text("Choose which version to keep. There is no automatic merge.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 12) {
                Button("Keep Mine") { detector.resolveConflict(.keepMine) }
                    .accessibilityIdentifier("ConflictKeepMine")
                    .accessibilityLabel(String(localized: "Keep My Version",
                                               comment: "VoiceOver label for conflict sheet Keep Mine button"))
                Button("Keep Theirs") { detector.resolveConflict(.keepTheirs) }
                    .accessibilityIdentifier("ConflictKeepTheirs")
                    .accessibilityLabel(String(localized: "Keep Their Version",
                                               comment: "VoiceOver label for conflict sheet Keep Theirs button"))
                Button("Discard Mine", role: .destructive) { detector.resolveConflict(.discardMine) }
                    .accessibilityIdentifier("ConflictDiscardMine")
                    .accessibilityLabel(String(localized: "Discard My Changes",
                                               comment: "VoiceOver label for conflict sheet Discard Mine button"))
                    .accessibilityHint(String(localized: "Your local edits cannot be recovered after this action.",
                                              comment: "VoiceOver hint for irreversible Discard Mine action"))
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        // BR-4.3 — modal enough that neither side is silently overwritten while
        // the choice is pending; only the three buttons resolve it.
        .interactiveDismissDisabled(true)
    }

    // MARK: - Deletion banner (DC-16/DC-17, BR-9)

    @ViewBuilder
    private var deletionBanner: some View {
        if detector.activeSurface == .deletion {
            HStack(spacing: 12) {
                Text("This file was deleted on disk")
                    .font(.subheadline)
                Spacer()
                Button("Save As") { showSaveAs = true }
                    .accessibilityIdentifier("DeletionBannerSaveAs")
                    .accessibilityLabel(String(localized: "Save to New Location",
                                               comment: "VoiceOver label for deletion banner Save As button"))
                Button("Dismiss") {
                    detector.dismissDeletionBanner()
                    // AC-4.9: move VoiceOver focus off the now-invisible banner.
                    UIAccessibility.post(notification: .layoutChanged, argument: nil)
                }
                .accessibilityIdentifier("DeletionBannerDismiss")
                .accessibilityLabel(String(localized: "Dismiss file deleted notice",
                                           comment: "VoiceOver label for deletion banner Dismiss button"))
            }
            .padding()
            .background(.thinMaterial)
        }
    }
}
