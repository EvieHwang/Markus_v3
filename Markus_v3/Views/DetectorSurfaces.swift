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
                Button("Keep Theirs") { detector.resolveConflict(.keepTheirs) }
                    .accessibilityIdentifier("ConflictKeepTheirs")
                Button("Discard Mine", role: .destructive) { detector.resolveConflict(.discardMine) }
                    .accessibilityIdentifier("ConflictDiscardMine")
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
                Button("Dismiss") { detector.dismissDeletionBanner() }
                    .accessibilityIdentifier("DeletionBannerDismiss")
            }
            .padding()
            .background(.thinMaterial)
        }
    }
}
