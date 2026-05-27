import Foundation
import UIKit

/// Resume-vs-browser decision at scene activation (design C2 / DC-3, DC-4).
///
/// Called from `SceneDelegate.scene(_:willConnectTo:options:)` *before* the
/// browser is made the visible top view controller. If `LastFileStore`
/// resolves a reachable last-opened file, we present that file's editor as
/// the scene's first content via `BrowserHostController.presentDocument`
/// with `animated: false`, so the browser is never the visible top screen
/// on a successful resume.
///
/// If no reference resolves (first-ever launch, stale bookmark,
/// unreachable file), the branch does nothing — the browser is the
/// natural landing screen (DC-4). No error UI is shown either way.
///
/// Also handles deterministic UI-test launch state via `-uitest-*`
/// launch arguments so XCUITest can seed the store before the resume
/// decision runs.
enum LaunchResumeBranch {

    static let resetArg = "-uitest-reset-last-file"
    static let staleArg = "-uitest-stale-last-file"
    static let seedArg = "-uitest-seed-last-file"
    /// external-change-5: open a freshly-seeded sample as the open document so the
    /// external-change UI tests have a known file behind the editor.
    static let openSeedArg = "-uitest-open-seed-file"

    /// Apply UI-test launch overrides to `LastFileStore` if any are
    /// present in `arguments`. Idempotent; safe to call on every scene
    /// activation.
    static func applyTestOverrides(_ arguments: [String], store: LastFileStore = LastFileStore()) {
        if arguments.contains(resetArg) {
            UserDefaults.standard.removeObject(forKey: LastFileStore.defaultBookmarkKey)
            UserDefaults.standard.removeObject(forKey: LastFileStore.defaultPathKey)
            // Also remove any seed file the previous test left behind so
            // collision-naming tests start clean.
            removeSeededSample()
        }
        if arguments.contains(staleArg) {
            // Plant a bookmark Data value that won't resolve, plus a
            // recorded path that does not exist on disk. Both halves of
            // the resolve check fail closed (DC-4 / BR-5 / BR-19).
            UserDefaults.standard.set(Data([0xDE, 0xAD, 0xBE, 0xEF]), forKey: LastFileStore.defaultBookmarkKey)
            UserDefaults.standard.set("/var/empty/never-exists.md", forKey: LastFileStore.defaultPathKey)
        }
        if arguments.contains(seedArg) || arguments.contains(openSeedArg) {
            // Reset any stale store/seed first so the open file is deterministic.
            if arguments.contains(openSeedArg) {
                removeSeededSample()
            }
            seedSampleAndRecord(store: store)
        }
    }

    /// Decide whether to present a resumed file as the scene's first
    /// content. Returns true if a file was presented (browser will be
    /// covered); false if the browser should be the landing screen.
    @MainActor
    @discardableResult
    static func resume(into host: BrowserHostController,
                       store: LastFileStore = LastFileStore()) -> Bool {
        guard let url = store.resolveLastOpened() else { return false }
        host.presentDocument(at: url, animated: false)
        return true
    }

    // MARK: - UI-test seeding helpers

    private static let seededSampleName = "sample.md"
    private static let seededSampleBody = "# Resumed sample\n\nThis file is the seed for resume UI tests.\n"

    private static func seedSampleAndRecord(store: LastFileStore) {
        guard let docs = try? LocalDocumentsFallback.documentsDirectory() else { return }
        let url = docs.appendingPathComponent(seededSampleName)
        try? seededSampleBody.write(to: url, atomically: true, encoding: .utf8)
        store.recordLastOpened(url)
    }

    private static func removeSeededSample() {
        guard let docs = try? LocalDocumentsFallback.documentsDirectory() else { return }
        let url = docs.appendingPathComponent(seededSampleName)
        try? FileManager.default.removeItem(at: url)
    }
}
