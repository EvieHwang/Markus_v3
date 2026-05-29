import Combine
import Foundation

/// The owned change detector (design C1, BR-10). Created by the host beside the
/// save bridge for the lifetime of one presented document; exactly one is live at
/// a time, observing only the open document (BR-18, OOS-3). It is the single
/// authority on "what is happening to the open file on disk":
///
/// - coordinated, never-torn reads (DC-2) via `FilePresenterShim` + `NSFileCoordinator`,
/// - settle-window + in-flight-sync suppression (DC-6/DC-7/DC-8) via `SettleGate`,
/// - presence-first classification into one of four outcomes (DC-4) via `ChangeClassifier`,
/// - apply-edge re-validation against the live buffer (DC-21) via `ApplyEdgeRevalidation`,
/// - save-back suspension keyed to classification (DC-22) via `SaveSuspensionLatch`,
/// - move/deletion presence disambiguation (DC-16),
/// - the absorb path (silent adoption preserving the editing surface, DC-12).
///
/// It publishes the surface state the editor renders (conflict sheet / deletion
/// banner, Wave 4) and the live display URL (rename → title, DC-19). It never
/// decides UI directly: it emits a classified outcome and the editor maps outcomes
/// to surfaces.
@MainActor
final class ChangeDetector: ObservableObject {

    /// The surface the editor should present, derived from the latched outcome.
    enum Surface: Equatable {
        case conflict(diskContent: String)
        case deletion
    }

    /// The followed location; updated on a rename/move (DC-19). Drives the title.
    @Published private(set) var displayURL: URL
    /// The currently-presented surface, or nil for none (absorb / quiescent).
    @Published var activeSurface: Surface?

    private let document: MarkdownDocument
    private var settleGate: SettleGate
    private let settleEnabled: Bool
    private let disambiguationSeconds: TimeInterval
    private var latch = SaveSuspensionLatch()
    private let clock: @Sendable () -> TimeInterval

    /// DC-7 — bound to `SaveStatusObserver`'s busy state; suppresses classification
    /// while a sync is in flight. The detector consumes this as a settle input but
    /// never delegates the collision decision to it (DC-3).
    var isSyncInFlight: @MainActor () -> Bool = { false }

    /// Bound by the host to the save bridge: write the buffer to the followed
    /// location now (the single deliberate write for Keep Mine, DC-13/BR-5).
    var requestImmediateWrite: (@MainActor () -> Void)?

    /// Bound by the host to retarget the save bridge + resume reference when the
    /// followed location changes (DC-19): `(newURL)`.
    var onRetarget: (@MainActor (URL) -> Void)?

    /// BR-13 — invalid-UTF-8 external content reuses the existing alert path rather
    /// than a conflict sheet. T-010 binds this to `ActiveAlert.invalidEncoding`.
    var onInvalidEncoding: (@MainActor () -> Void)?

    /// DC-19/BR-8.3 — the editor binds this to update the displayed title when a
    /// rename retargets the followed location. (`displayURL` is also @Published.)
    var onDisplayURLChange: (@MainActor (URL) -> Void)?

    private var presenter: FilePresenterShim?
    private var pendingSettleReeval: Task<Void, Never>?
    private var pendingDeletionDisambiguation: Task<Void, Never>?

    init(document: MarkdownDocument,
         url: URL,
         settleWindowSeconds: TimeInterval = 2.0,
         disambiguationSeconds: TimeInterval = 2.0,
         settleEnabled: Bool = true,
         clock: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }) {
        self.document = document
        self.displayURL = url
        self.settleGate = SettleGate(windowSeconds: settleWindowSeconds)
        self.disambiguationSeconds = disambiguationSeconds
        self.settleEnabled = settleEnabled
        self.clock = clock
        // DC-6 trigger 1 — opening/presenting opens the settle window.
        self.settleGate.noteTrigger(.opened, at: clock())
    }

    /// DC-22 — whether save-back is currently permitted (consulted by the bridge).
    var allowsSaveBack: Bool { latch.allowsSaveBack }

    /// True when an outcome is latched but no surface is presented — the condition
    /// the foreground reconciler (DC-23, T-010) recovers from.
    var hasLatchedSurfacelessOutcome: Bool {
        latch.isLatchedUnresolved && activeSurface == nil
    }

    // MARK: - Lifecycle

    func start() {
        // resume-and-detector-hardening-11 DC-7/DC-8: perform an initial
        // coordinated read of displayURL and seed lastKnownDiskContent BEFORE
        // registering the presenter, so no handler body can ever observe
        // placeholder initial state. On read failure (file missing, coordination
        // error, invalid UTF-8), leave the host-seeded prior in place — start()
        // does not throw or raise activeSurface; the next live callback
        // re-evaluates against whatever the host seeded.
        if let initial = coordinatedRead(displayURL) {
            document.lastKnownDiskContent = initial
        }

        let shim = FilePresenterShim(url: displayURL)
        shim.onChange = { [weak self] in
            Task { @MainActor in self?.handleDidChange() }
        }
        shim.onMove = { [weak self] newURL in
            Task { @MainActor in self?.handleDidMove(to: newURL) }
        }
        shim.onDelete = { [weak self] in
            Task { @MainActor in self?.handleDidDelete() }
        }
        presenter = shim
        shim.register()
    }

    func stop() {
        pendingSettleReeval?.cancel()
        pendingDeletionDisambiguation?.cancel()
        presenter?.unregister()
        presenter = nil
    }

    // MARK: - Settle triggers (DC-6)

    /// DC-6 trigger 3 — a local save completed: reset last-known-disk and re-open
    /// the settle window so the sync echo of our own write is suppressed.
    func noteSaveCompleted(writtenContent: String) {
        document.lastKnownDiskContent = writtenContent
        settleGate.noteTrigger(.saveCompleted, at: clock())
    }

    /// DC-6 trigger 2 — a deferred-write create first persisted to disk.
    func noteFirstPersist(content: String) {
        document.lastKnownDiskContent = content
        settleGate.noteTrigger(.created, at: clock())
    }

    // MARK: - Live filesystem events

    private func handleDidChange() {
        // DC-5 — quiescent while a choice is pending; a later change updates the
        // content to compare on resolution but does not stack a second surface.
        guard !latch.isLatchedUnresolved else { return }

        guard FileManager.default.fileExists(atPath: displayURL.path) else {
            handleDidDelete()
            return
        }

        if isSuppressedNow() {
            scheduleSettleReeval()           // DC-8 — delay, never discard
            return
        }

        guard let disk = coordinatedRead(displayURL) else {
            // nil → unreadable bytes. Distinguish invalid-UTF-8 (BR-13) from a
            // transient read miss: if bytes exist but don't decode, route to the
            // invalid-encoding alert; otherwise ignore (next event re-evaluates).
            if let data = rawBytes(displayURL), String(data: data, encoding: .utf8) == nil {
                onInvalidEncoding?()
            }
            return
        }
        applySameLocation(diskContent: disk)
    }

    private func handleDidMove(to newURL: URL) {
        pendingDeletionDisambiguation?.cancel()   // a move resolves a pending "gone"
        guard !latch.isLatchedUnresolved else {
            // A surface is up; still retarget the followed location silently.
            retarget(to: newURL)
            return
        }
        let disk = coordinatedRead(newURL) ?? document.lastKnownDiskContent
        let outcome = ChangeClassifier.classify(
            presenceSameLocation: false,
            movedLocation: newURL,
            isAbsent: false,
            onDiskContent: disk,
            buffer: document.text,
            lastKnownDisk: document.lastKnownDiskContent
        )
        retarget(to: newURL)
        switch outcome {
        case .moved:
            // BR-8.1 — a move alone is neither a sheet nor a banner.
            break
        case .collision:
            // DC-20 — a move carrying a material change against a dirty buffer is gated.
            latchCollision(diskContent: disk)
        case .absorb, .deleted:
            break
        }
    }

    private func handleDidDelete() {
        guard !latch.isLatchedUnresolved else { return }
        // DC-16 — do not present a deletion immediately; wait the disambiguation
        // interval to see whether the file reappears as a move.
        pendingDeletionDisambiguation?.cancel()
        let interval = settleEnabled ? disambiguationSeconds : 0
        pendingDeletionDisambiguation = Task { @MainActor [weak self] in
            guard let self else { return }
            if interval > 0 {
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { return }
            }
            // Still absent (a move would have cancelled this task) → deleted.
            if !FileManager.default.fileExists(atPath: self.displayURL.path) {
                self.latchDeletion()
            }
        }
    }

    // MARK: - Apply edge (DC-21)

    private func applySameLocation(diskContent: String) {
        // DC-21 — re-derive against the LIVE buffer at the instant of application.
        let outcome = ApplyEdgeRevalidation.reDerive(
            readTimeBuffer: document.text,
            liveBuffer: document.text,
            settledDiskContent: diskContent,
            lastKnownDisk: document.lastKnownDiskContent
        )
        switch outcome {
        case .absorb:
            // DC-12 — adopt the new content, reset last-known-disk; the editor's
            // surface (mode/cursor) is untouched because only `text` changes.
            if !ContentEqualityGate.equal(document.text, diskContent) {
                document.text = diskContent
            }
            document.lastKnownDiskContent = diskContent
        case .collision:
            latchCollision(diskContent: diskContent)
        case .moved, .deleted:
            break   // not reachable for a same-location read
        }
    }

    private func latchCollision(diskContent: String) {
        latch.classify(.collision)          // DC-22 — suspend from classification
        latch.presentSurface()
        activeSurface = .conflict(diskContent: diskContent)
    }

    private func latchDeletion() {
        latch.classify(.deleted)            // DC-22 — suspend recreate at vanished path
        latch.presentSurface()
        activeSurface = .deletion
    }

    private func retarget(to newURL: URL) {
        displayURL = newURL                 // DC-19 — title tracks the new name
        onDisplayURLChange?(newURL)         // editor title (BR-8.3)
        onRetarget?(newURL)                 // save bridge + resume reference
        // Re-register the presenter at the new location.
        presenter?.unregister()
        let shim = FilePresenterShim(url: newURL)
        shim.onChange = { [weak self] in Task { @MainActor in self?.handleDidChange() } }
        shim.onMove = { [weak self] u in Task { @MainActor in self?.handleDidMove(to: u) } }
        shim.onDelete = { [weak self] in Task { @MainActor in self?.handleDidDelete() } }
        presenter = shim
        shim.register()
    }

    // MARK: - Resolution (DC-13, Wave 4 calls these)

    /// BR-5/6/7 — resolve a pending collision. Keep Mine writes the buffer; Keep
    /// Theirs / Discard Mine adopt disk with no clobbering write.
    func resolveConflict(_ option: ConflictResolution.Option) {
        guard case let .conflict(disk) = activeSurface else { return }
        let r = ConflictResolution.apply(option, buffer: document.text, onDisk: disk)
        document.text = r.newBufferContent
        latch.resolveByUser()               // DC-22 — lift before the deliberate write
        activeSurface = nil
        if let written = r.contentWrittenToDisk {
            document.lastKnownDiskContent = written
            settleGate.noteTrigger(.saveCompleted, at: clock())
            requestImmediateWrite?()        // Keep Mine: single deliberate write
        } else {
            document.lastKnownDiskContent = disk
            settleGate.noteTrigger(.saveCompleted, at: clock())
        }
    }

    /// BR-9.6 — user dismisses the deletion banner without Save As; buffer preserved.
    func dismissDeletionBanner() {
        guard activeSurface == .deletion else { return }
        latch.resolveByUser()
        activeSurface = nil
    }

    /// BR-9.4 — Save As retargets to a new location and continues the session.
    func completeSaveAs(to newURL: URL) {
        retarget(to: newURL)
        document.lastKnownDiskContent = document.text
        latch.resolveByUser()
        activeSurface = nil
        settleGate.noteTrigger(.opened, at: clock())
        requestImmediateWrite?()
    }

    // MARK: - Foreground reconciliation (DC-23, T-010)

    /// DC-23 — re-validate a latched-but-surface-less outcome against current
    /// settled disk + live buffer and either re-present the surface or recoverably
    /// lift suspension. Total: never leaves a stuck-suspended state.
    func reconcileOnForeground() {
        guard latch.isLatchedUnresolved, activeSurface == nil else { return }
        let absent = !FileManager.default.fileExists(atPath: displayURL.path)
        let disk = absent ? nil : coordinatedRead(displayURL)
        let decision = ForegroundReconciler.reconcile(
            latchedOutcome: absent ? .deleted : .collision,
            settledDiskContent: disk,
            liveBuffer: document.text,
            lastKnownDisk: document.lastKnownDiskContent,
            fileReappearedAt: nil
        )
        switch decision {
        case .rePresent:
            // DC-19 (save-bridge-hardening-9) / NR-6: never refresh
            // lastKnownDiskContent on re-present — silently agreeing with disk
            // would defeat the user's pending three-option choice (BR-3.6).
            activeSurface = absent ? .deletion : .conflict(diskContent: disk ?? "")
        case .lift:
            // DC-16 / BR-3.1 (save-bridge-hardening-9): refresh
            // lastKnownDiskContent to the settled bytes that justified the lift
            // BEFORE lifting suspension. Order matters: if suspension lifts
            // first, a debounced save could fire against a stale reference and
            // overwrite a fresher-but-equal disk state the user never observed.
            // DC-18 / BR-3.4: never mutate document.text — only the
            // lastKnownDiskContent reference changes; cursor/scroll are
            // preserved. DC-20 / BR-10: if the coordinated read returned nil
            // (read failed) we do not synthesize a refresh against a stale
            // reference; existing reconciler logic already guarded the lift
            // decision itself.
            if let disk, !absent {
                document.lastKnownDiskContent = disk
            }
            latch.resolveByUser()
            activeSurface = nil
        }
    }

    // MARK: - Test injection (deterministic UI fixtures)

    /// Simulate a settled same-location external write by landing the bytes on disk
    /// and routing them through the real change path (UI tests / debug menu).
    func injectExternalChange(_ content: String) {
        try? Data(content.utf8).write(to: displayURL, options: [.atomic])
        handleDidChange()
    }

    /// Simulate a rename/move to a sibling name within the test container.
    func injectExternalRename(to newName: String) {
        let newURL = displayURL.deletingLastPathComponent().appendingPathComponent(newName)
        try? FileManager.default.moveItem(at: displayURL, to: newURL)
        handleDidMove(to: newURL)
    }

    /// Simulate a deletion of the open document.
    func injectExternalDelete() {
        try? FileManager.default.removeItem(at: displayURL)
        handleDidDelete()
    }

    /// Simulate invalid-UTF-8 external content (reuses the alert path, BR-13).
    func injectInvalidUTF8() {
        try? Data([0xFF, 0xFE, 0xFF]).write(to: displayURL, options: [.atomic])
        handleDidChange()
    }

    // MARK: - Helpers

    private func isSuppressedNow() -> Bool {
        guard settleEnabled else { return false }
        return settleGate.isSuppressed(at: clock(), syncInFlight: isSyncInFlight())
    }

    private func scheduleSettleReeval() {
        pendingSettleReeval?.cancel()
        pendingSettleReeval = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.settleGate.windowSeconds))
            if Task.isCancelled { return }
            self.handleDidChange()           // DC-8 — re-evaluate after settle
        }
    }

    private func coordinatedRead(_ url: URL) -> String? {
        guard let data = coordinatedReadData(url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func coordinatedReadData(_ url: URL) -> Data? {
        var result: Data?
        var coordError: NSError?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordError) { readURL in
            let scoped = readURL.startAccessingSecurityScopedResource()
            defer { if scoped { readURL.stopAccessingSecurityScopedResource() } }
            result = try? Data(contentsOf: readURL)
        }
        return result
    }

    private func rawBytes(_ url: URL) -> Data? {
        coordinatedReadData(url)
    }
}
